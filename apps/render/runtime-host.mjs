// Host interop only: bundled fonts, SVG rasterization and standalone WASM codecs.
// Project validation, time evaluation, resource selection and mixing are MoonBit.
import { readFile, readdir } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { setImmediate } from 'node:timers/promises';
import { Resvg, initWasm } from '@resvg/resvg-wasm';
import { svgPathProperties } from 'svg-path-properties';
import HME from 'h264-mp4-encoder';
import {
  Input, BufferSource, ALL_FORMATS, AudioSampleSink, AudioSample, AudioSampleSource,
  Output, BufferTarget, Mp3OutputFormat, Mp4OutputFormat,
  EncodedPacketSink, EncodedVideoPacketSource, EncodedAudioPacketSource,
} from 'mediabunny';
import { registerMp3Encoder } from '@mediabunny/mp3-encoder';
import { requiredFontFaces } from '../../_build/js/release/build/headless_render/headless_render.js';
import { loadMathRuntime } from '../studio/src/platform/render-host.mjs';

const wasmReady = initWasm(readFile(fileURLToPath(import.meta.resolve('@resvg/resvg-wasm/index_bg.wasm'))));
registerMp3Encoder();

const escapeXml = text => text.replace(/[&<>"']/g, ch => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&apos;' })[ch]);

// resvg 0.34 does not implement SVG2 pathLength. Convert the normalized dash
// units emitted by Poietra into native geometry units, including MathJax glyphs.
export function normalizePathLengths(svg, cache = new Map()) {
  return svg.replace(/<(path|rect|ellipse|circle|line|polygon|polyline)\b[^>]*\bpathLength="1"[^>]*\/?\s*>/g, (tag, kind) => {
    const a = Object.fromEntries([...tag.matchAll(/([\w-]+)="([^"]*)"/g)].map(m => [m[1], m[2]]));
    const n = key => Number(a[key] ?? 0);
    const key = JSON.stringify([kind, a.d, a.width, a.height, a.rx, a.ry, a.r, a.x1, a.y1, a.x2, a.y2, a.points]);
    let length = cache.get(key);
    if (length === undefined) {
      if (kind === 'path') length = new svgPathProperties(a.d).getTotalLength();
      else if (kind === 'line') length = Math.hypot(n('x2') - n('x1'), n('y2') - n('y1'));
      else if (kind === 'circle') length = 2 * Math.PI * n('r');
      else if (kind === 'ellipse') {
        // Use the same elliptic-arc integration as arbitrary SVG paths.
        length = new svgPathProperties(`M${n('rx')} 0 A${n('rx')} ${n('ry')} 0 1 0 ${-n('rx')} 0 A${n('rx')} ${n('ry')} 0 1 0 ${n('rx')} 0`).getTotalLength();
      } else if (kind === 'rect') {
        const r = Math.min(n('rx'), n('width') / 2, n('height') / 2);
        length = 2 * (n('width') + n('height') - 4 * r) + 2 * Math.PI * r;
      } else {
        const points = a.points.trim().split(/[\s,]+/).map(Number);
        let path = `M${points[0]} ${points[1]}`;
        for (let i = 2; i < points.length; i += 2) path += `L${points[i]} ${points[i + 1]}`;
        length = new svgPathProperties(path + (kind === 'polygon' ? 'Z' : '')).getTotalLength();
      }
      if (!Number.isFinite(length)) throw new Error('Invalid SVG path length.');
      // Animated geometry can change every frame; keep the cache bounded.
      if (cache.size >= 4096) cache.clear();
      cache.set(key, length);
    }
    return tag.replace(/\s+pathLength="1"/, '')
      .replace(/stroke-dasharray="[^"]*"/, `stroke-dasharray="${length}"`)
      .replace(/stroke-dashoffset="([^"]*)"/, (_, value) => `stroke-dashoffset="${Number(value) * length}"`);
  });
}

function embeddedBytes(source) {
  const comma = source.indexOf(',');
  const body = source.slice(comma + 1);
  if (comma < 0 || !source.slice(0, comma).endsWith(';base64') || !/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(body)) {
    throw new Error('Invalid embedded base64 asset.');
  }
  return Buffer.from(body, 'base64');
}

function imageSize(bytes, mime) {
  if (mime === 'image/png') {
    if (bytes.length < 33 || !bytes.subarray(0, 8).equals(Buffer.from([137,80,78,71,13,10,26,10])) || bytes.toString('ascii',12,16) !== 'IHDR') throw new Error('Invalid PNG asset.');
    return [bytes.readUInt32BE(16), bytes.readUInt32BE(20)];
  }
  if (bytes.length < 4 || bytes.readUInt16BE(0) !== 0xffd8) throw new Error('Invalid JPEG asset.');
  let offset = 2;
  while (offset + 4 <= bytes.length) {
    if (bytes[offset++] !== 0xff) break;
    while (bytes[offset] === 0xff) offset++;
    const marker = bytes[offset++];
    if (marker === 0xd9 || marker === 0xda) break;
    if (marker === 0x01 || (marker >= 0xd0 && marker <= 0xd7)) continue;
    if (offset + 2 > bytes.length) break;
    const size = bytes.readUInt16BE(offset);
    if (size < 2 || offset + size > bytes.length) break;
    if ([0xc0,0xc1,0xc2,0xc3,0xc5,0xc6,0xc7,0xc9,0xca,0xcb,0xcd,0xce,0xcf].includes(marker) && size >= 7) {
      return [bytes.readUInt16BE(offset + 5), bytes.readUInt16BE(offset + 3)];
    }
    offset += size;
  }
  throw new Error('Invalid JPEG dimensions.');
}

export async function createHost({ format, signal, onProgress } = {}) {
  await wasmReady;
  let fontBuffers = [], styles = '';
  const metrics = new Map(), lengths = new Map(), audioInputs = new Map();
  const check = () => signal?.throwIfAborted();
  const fontOptions = () => ({ fontBuffers, defaultFontFamily: 'Inter', sansSerifFamily: 'Inter' });
  const nativeSvg = svg => normalizePathLengths(svg, lengths)
    .replaceAll("'Poietra Inter'", "'Inter'").replaceAll("'Poietra Noto Sans JP'", "'Noto Sans JP'");
  const raster = (svg, png) => {
    check();
    const tree = new Resvg(nativeSvg(svg), { font: fontOptions() });
    try {
      const image = tree.render();
      try { return png ? image.asPng() : image.pixels; }
      finally { image.free(); }
    } finally { tree.free(); }
  };
  return {
    loadMathRuntime,
    async prepare(sources, images) {
      check();
      const inter = fileURLToPath(import.meta.resolve('@fontsource/inter/files/inter-latin-400-normal.woff2'));
      const cssPath = fileURLToPath(import.meta.resolve('@fontsource/noto-sans-jp/400.css'));
      const directory = join(dirname(cssPath), 'files');
      const files = Object.fromEntries((await readdir(directory)).map(name => [name, join(directory, name)]));
      const faces = requiredFontFaces(inter, await readFile(cssPath, 'utf8'), files, sources);
      fontBuffers = await Promise.all(faces.map(face => readFile(face.url)));
      if (format === 'svg') styles = '<defs><style>' + faces.map((face, i) =>
        `@font-face{font-family:'${face.family}';font-weight:400;src:url(data:font/woff2;base64,${fontBuffers[i].toString('base64')}) format('woff2');${face.unicodeRange ? `unicode-range:${face.unicodeRange};` : ''}}`
      ).join('') + '</style></defs>';
      let decodedPixels = 0;
      for (const source of images) {
        const mime = source.slice(5, source.indexOf(';'));
        const [width, height] = imageSize(embeddedBytes(source), mime);
        if (!width || !height || width > 8192 || height > 8192 || width * height > 16777216) throw new Error('An image exceeds the 16 megapixel decode limit.');
        decodedPixels += width * height;
        if (decodedPixels > 16777216) throw new Error('Embedded images exceed the total 16 megapixel decode limit.');
        const probe = new Resvg(`<svg xmlns="http://www.w3.org/2000/svg" width="1" height="1"><image href="${source}" width="1" height="1"/></svg>`, { font: { fontBuffers: [] } });
        try { if (!probe.toString().includes('<image')) throw new Error('The embedded image could not be decoded.'); }
        finally { probe.free(); }
      }
      check();
    },
    fontStyles: () => styles,
    measureLine(line, size) {
      const key = `${size}\0${line}`;
      if (metrics.has(key)) return metrics.get(key);
      const tree = new Resvg(`<svg xmlns="http://www.w3.org/2000/svg" width="1" height="1"><text x="0" y="0" text-anchor="middle" xml:space="preserve" font-family="Inter, Noto Sans JP, sans-serif" font-size="${size}">${escapeXml(line)}</text></svg>`, { font: fontOptions() });
      try {
        const box = tree.getBBox();
        try {
          const value = box ? { left: -box.x, right: box.x + box.width, ascent: -box.y, descent: box.y + box.height } : { left: 0, right: 0, ascent: 0, descent: 0 };
          if (metrics.size >= 4096) metrics.clear();
          metrics.set(key, value);
          return value;
        } finally { box?.free(); }
      } finally { tree.free(); }
    },
    svgBytes: svg => new TextEncoder().encode(svg),
    png: svg => raster(svg, true),
    rgba: svg => raster(svg, false),
    async readAudio(source, start, end) {
      check();
      let asset = audioInputs.get(source);
      if (!asset) {
        const input = new Input({ source: new BufferSource(embeddedBytes(source)), formats: ALL_FORMATS });
        try {
          const track = await input.getPrimaryAudioTrack();
          const codec = await track?.getCodec();
          if (!codec?.startsWith('pcm-')) throw new Error('Headless audio decoding currently requires PCM WAV.');
          if (await track.getNumberOfChannels() > 2 || await track.getSampleRate() > 192000) throw new Error('Audio inputs must be mono/stereo at 192 kHz or less.');
          asset = { input, sink: new AudioSampleSink(track) };
          audioInputs.set(source, asset);
        } catch (error) { input.dispose(); throw error; }
      }
      const packets = [];
      for await (const sample of asset.sink.samples(start, end)) {
        try {
          check();
          const left = new Float32Array(sample.numberOfFrames), right = new Float32Array(sample.numberOfFrames);
          sample.copyTo(left, { format: 'f32-planar', planeIndex: 0 });
          sample.copyTo(right, { format: 'f32-planar', planeIndex: Math.min(1, sample.numberOfChannels - 1) });
          packets.push({ timestamp: sample.timestamp, duration: sample.duration, sampleRate: sample.sampleRate, left, right });
        } finally { sample.close(); }
      }
      return packets;
    },
    createEncoder: options => createEncoder(options, check),
    async progress(value) { check(); onProgress?.(value); await setImmediate(); check(); },
    dispose() { for (const asset of audioInputs.values()) asset.input.dispose(); audioInputs.clear(); metrics.clear(); lengths.clear(); fontBuffers = []; },
  };
}

async function createEncoder(options, check) {
  const encoder = await HME.createH264MP4Encoder();
  let audioOutput, audioSource, audioTarget, closed = false, finished = false;
  const dispose = async () => {
    if (closed) return;
    closed = true;
    try { if (audioOutput && !finished) await audioOutput.cancel(); }
    finally {
      audioSource?.close();
      const filename = encoder.outputFilename;
      encoder.delete();
      try { encoder.FS.unlink(filename); } catch { /* No completed file on cancellation. */ }
    }
  };
  try {
    check();
    encoder.width = options.width; encoder.height = options.height; encoder.frameRate = options.fps;
    encoder.speed = 5; encoder.quantizationParameter = 24; encoder.groupOfPictures = options.fps * 2;
    encoder.initialize();
    if (options.audio) {
      audioTarget = new BufferTarget();
      audioOutput = new Output({ target: audioTarget, format: new Mp3OutputFormat() });
      audioSource = new AudioSampleSource({ codec: 'mp3', bitrate: 192000 });
      audioOutput.addAudioTrack(audioSource);
      await audioOutput.start();
    }
    return {
      addVideo(pixels) { check(); encoder.addFrameRgba(pixels); },
      async addAudio(left, right, timestamp) {
        check();
        const data = new Float32Array(left.length + right.length); data.set(left); data.set(right, left.length);
        const sample = new AudioSample({ data, format: 'f32-planar', numberOfChannels: 2, sampleRate: 48000, timestamp });
        try { await audioSource.add(sample); } finally { sample.close(); }
      },
      async finish() {
        check(); encoder.finalize();
        if (audioOutput) await audioOutput.finalize();
        finished = true;
        check();
        return remux(encoder.FS.readFile(encoder.outputFilename), audioTarget?.buffer, options, check);
      },
      dispose,
    };
  } catch (error) { await dispose(); throw error; }
}

// Packet copy, not a second encode. This also preserves a partial final frame.
async function remux(videoBytes, audioBytes, options, check) {
  const inputs = [], target = new BufferTarget();
  const output = new Output({ target, format: new Mp4OutputFormat({ fastStart: 'in-memory' }) });
  let completed = false;
  try {
    const video = new Input({ source: new BufferSource(videoBytes), formats: ALL_FORMATS }); inputs.push(video);
    const videoTrack = await video.getPrimaryVideoTrack();
    const source = new EncodedVideoPacketSource('avc'); output.addVideoTrack(source);
    let audioTrack, audioSource;
    if (audioBytes) {
      const audio = new Input({ source: new BufferSource(audioBytes), formats: ALL_FORMATS }); inputs.push(audio);
      audioTrack = await audio.getPrimaryAudioTrack();
      audioSource = new EncodedAudioPacketSource('mp3'); output.addAudioTrack(audioSource);
    }
    await output.start();
    const config = await videoTrack.getDecoderConfig();
    let index = 0;
    for await (const packet of new EncodedPacketSink(videoTrack).packets(undefined, undefined, { verifyKeyPackets: true })) {
      check();
      const timestamp = index++ / options.fps;
      await source.add(packet.clone({ timestamp, duration: Math.min(1 / options.fps, options.durationMs / 1000 - timestamp) }), { decoderConfig: config });
    }
    source.close();
    if (audioTrack) {
      const config = await audioTrack.getDecoderConfig();
      for await (const packet of new EncodedPacketSink(audioTrack).packets()) {
        check();
        // Pinned LAME 3.100 adds 576 encoder + 529 synthesis samples. The
        // extension disables its gapless tag, so keep priming as negative time
        // in the MP4 edit list and trim flush padding to the authored duration.
        // An independent mpg123 decode regression checks both timing and gain.
        const timestamp = packet.timestamp - 1105 / 48000;
        const duration = Math.min(packet.duration, options.durationMs / 1000 - timestamp);
        if (duration <= 0) break;
        await audioSource.add(packet.clone({ timestamp, duration }), { decoderConfig: config });
      }
      audioSource.close();
    }
    await output.finalize(); completed = true;
    return new Uint8Array(target.buffer);
  } finally {
    try { if (!completed) await output.cancel(); }
    finally { for (const input of inputs) input.dispose(); }
  }
}
