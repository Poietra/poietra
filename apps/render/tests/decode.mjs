import { Input, BufferSource, ALL_FORMATS, EncodedPacketSink } from 'mediabunny';
import TinyH264 from 'tinyh264/lib/TinyH264.js';
import TinyH264Decoder from 'tinyh264/lib/TinyH264Decoder.js';
import { MPEGDecoder } from 'mpg123-decoder';

const annexB = nals => Buffer.concat(nals.flatMap(nal => [Buffer.from([0, 0, 0, 1]), nal]));

export async function decodeVideo(bytes) {
  // tinyh264's WASM loader expects a worker location; no DOM/browser is needed.
  const previous = globalThis.self;
  globalThis.self = { location: { href: 'file:///tinyh264/' } };
  let module;
  try { module = await TinyH264(); } finally { if (previous === undefined) delete globalThis.self; else globalThis.self = previous; }
  const input = new Input({ source: new BufferSource(bytes), formats: ALL_FORMATS });
  const frames = [];
  const decoder = new TinyH264Decoder(module, (pixels, width, height) => { frames.push({ pixels, width, height }); });
  try {
    const track = await input.getPrimaryVideoTrack(), config = await track.getDecoderConfig();
    const description = Buffer.from(config.description), nals = []; let offset = 6;
    for (let i = 0; i < (description[5] & 31); i++) { const n = description.readUInt16BE(offset); offset += 2; nals.push(description.subarray(offset, offset + n)); offset += n; }
    for (let i = 0, count = description[offset++]; i < count; i++) { const n = description.readUInt16BE(offset); offset += 2; nals.push(description.subarray(offset, offset + n)); offset += n; }
    decoder.decode(annexB(nals));
    const packets = [];
    for await (const packet of new EncodedPacketSink(track).packets()) {
      packets.push(packet);
      const data = Buffer.from(packet.data), nals = [];
      for (let i = 0; i < data.length;) { const n = data.readUInt32BE(i); i += 4; nals.push(data.subarray(i, i + n)); i += n; }
      const au = annexB(nals);
      if (au.length > 1024 * 1024) throw new Error('Test decoder access unit exceeds its fixed buffer.');
      decoder.decode(au);
    }
    return { frames, packets, config, duration: await input.computeDuration() };
  } finally { decoder.release(); module._free(decoder._decBuffer); input.dispose(); }
}

export async function decodeAudio(bytes) {
  const input = new Input({ source: new BufferSource(bytes), formats: ALL_FORMATS });
  const decoder = new MPEGDecoder({ enableGapless: false });
  try {
    await decoder.ready;
    const track = await input.getPrimaryAudioTrack(), packets = [];
    for await (const packet of new EncodedPacketSink(track).packets()) packets.push(packet);
    const decoded = decoder.decodeFrames(packets.map(packet => packet.data));
    return { ...decoded, timestamp: packets[0].timestamp, duration: await input.computeDuration(), packets };
  } finally { decoder.free(); input.dispose(); }
}
