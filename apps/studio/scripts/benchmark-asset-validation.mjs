// Portable asset validation and snapshot preparation, with no decoders or network.
import assert from 'node:assert/strict';
import { performance } from 'node:perf_hooks';
import { makeDemoProject } from '../shared/demo.js';
import { defaultState } from '../shared/model.js';
import { parseProjectFile } from '../shared/project-file.js';
import { portableProject } from '../../../_build/js/release/build/browser_projects/browser_projects.js';

const median = values => [...values].sort((a, b) => a - b)[values.length >> 1];
const results = []; let checksum = 0;
const cases = [
  { sourceCharacters: 0, references: 32, unique: false },
  { sourceCharacters: 1048576, references: 1, unique: false },
  { sourceCharacters: 1048576, references: 16, unique: false },
  { sourceCharacters: 65536, references: 16, unique: true },
];
for (const kind of ['image', 'audio']) for (const dimensions of cases) {
  const { sourceCharacters, references, unique } = dimensions;
  const project = makeDemoProject(), scene = project.scenes['scene-1'], expectedSources = [];
  scene.audioTracks = {};
  for (let index = 0; index < references; index++) {
    const token = unique ? index.toString(16).padStart(64, '0') : 'a'.repeat(64);
    const source = sourceCharacters ? `data:${kind === 'image' ? 'image/png' : 'audio/wav'};base64,` + token + 'A'.repeat(sourceCharacters - token.length)
      : `/api/rooms/${'a'.repeat(32)}/${kind === 'image' ? 'images' : 'media'}/${token}`;
    expectedSources.push(source);
    const id = `asset-${index}`;
    if (kind === 'image') {
      scene.objects[id] = { id, name: id, kind: 'image', order: index + 100, locked: false, groupId: null, image: { src: source, width: 1, height: 1 } };
      for (const composition of Object.values(scene.compositions)) composition.states[id] = defaultState('image');
    } else {
      scene.audioTracks[id] = { id, name: id, start: 0, offset: 0, duration: 500, volume: .5, muted: false,
        asset: { src: source, mime: 'audio/wav', duration: 1000, hasAudio: true, waveform: Array(160).fill(.5) } };
    }
  }
  const text = JSON.stringify(project), embedded = `data:${kind === 'image' ? 'image/png' : 'audio/wav'};base64,AAAA`;
  let reads = 0;
  const io = { imageBlob: async () => { reads++; return new Blob(['x'], { type: 'image/png' }); }, mediaBlob: async () => { reads++; return new Blob(['x'], { type: 'audio/wav' }); }, blobDataUrl: async () => embedded };
  const sources = value => kind === 'image' ? Object.values(value.scenes['scene-1'].objects).filter(object => object.image).map(object => object.image.src)
    : Object.values(value.scenes['scene-1'].audioTracks).map(track => track.asset.src);
  for (const operation of ['parse', 'portable']) {
    let latest;
    const run = async () => { latest = operation === 'parse' ? parseProjectFile(text) : await portableProject(project, undefined, io); checksum++; };
    await run();
    assert.deepEqual(sources(latest), expectedSources.map(source => operation === 'portable' && !sourceCharacters ? embedded : source));
    assert.deepEqual(sources(project), expectedSources);
    assert.equal(reads, operation === 'portable' && !sourceCharacters ? new Set(expectedSources).size : 0);
    const iterations = 3;
    const batch = async () => { const start = performance.now(); for (let index = 0; index < iterations; index++) await run(); return (performance.now() - start) / iterations; };
    await batch(); await batch(); const samples = [];
    for (let index = 0; index < 7; index++) samples.push(await batch());
    results.push({ kind, ...dimensions, operation, jsonBytes: Buffer.byteLength(text), iterations, msPerOperation: median(samples), samples: { msPerOperation: samples } });
    reads = 0;
  }
}
console.log(JSON.stringify({ scope: 'Public portable-file parsing and portableProject capture, size checks, metadata validation and source deduplication. Embedded sizes are base64 characters; payloads exercise validation, not decoding. Room URL I/O is stubbed to one tiny Blob per unique source. No browser, codec, disk or network; JSON.stringify for parse input is outside timing, portableProject internal stringify/copy is included.', iterations: 'One assertion call, two warmup + seven measured batches of three operations per case.', results, checksum }, null, 2));
