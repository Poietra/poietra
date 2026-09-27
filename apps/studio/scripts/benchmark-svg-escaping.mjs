// UTF-16 escaping and public SVG output; no DOM, decoding or GPU.
import assert from 'node:assert/strict';
import { svgEscape, frameToSvgView, frameToSvg } from '../../../_build/js/release/build/boundary/boundary.js';
import { defaultState } from '../shared/model.js';

const entities = { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&apos;' };
const reference = value => value.toWellFormed().replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f\ufffe\uffff]/g, '').replace(/[&<>"']/g, value => entities[value]);
const results = []; let checksum = 0;
function measure(dimensions, callback, iterations) {
  const batch = () => { const start = performance.now(); for (let i = 0; i < iterations; i++) checksum += callback(); return (performance.now() - start) / iterations; };
  batch(); batch(); const samples = Array.from({ length: 7 }, batch);
  results.push({ ...dimensions, iterations, msPerOperation: [...samples].sort((a, b) => a - b)[3], samples: { msPerOperation: samples } });
}
for (const [name, input, iterations] of [
  ['short ASCII', 'object-0123456789abcdef', 10000],
  ['multilingual', '日本語α😀'.repeat(2000), 100],
  ['embedded source', 'data:image/png;base64,' + 'A'.repeat(1048576), 3],
  ['mixed escaping', '日本語<&\"\'😀\ud800\u0000end>'.repeat(1000), 50],
]) {
  assert.equal(svgEscape(input), reference(input));
  measure({ operation: 'escape', name, codeUnits: input.length }, () => svgEscape(input).length, iterations);
}
const resources = { getEquation: () => null, measureText: () => { throw new Error('No text'); }, preparedImage: source => source, embeddedFontStyles: () => '' };
for (const [objects, sourceCharacters] of [[1, 1048576], [16, 65536]]) {
  const source = 'data:image/png;base64,' + 'A'.repeat(sourceCharacters);
  const frame = { width: 1280, height: 720, background: '#08090b', objects: Array.from({ length: objects }, (_, i) => ({ object: { id: `image-${i}`, kind: 'image', image: { src: source, width: 256, height: 256 } }, state: defaultState('image', { x: i * 40, y: 80 }), writeProgress: 1, order: 'together' })) };
  const options = { idPrefix: 'escape-bench' };
  const view = frameToSvgView(frame, options, resources);
  assert.ok(view.objects[0].body.includes(`href="${source}"`));
  for (const operation of ['view', 'svg']) measure({ operation, name: 'embedded images', objects, sourceCharacters }, () => {
    frame.objects[0].state.x += 1;
    const value = operation === 'view' ? frameToSvgView(frame, options, resources) : frameToSvg(frame, options, resources);
    return operation === 'view' ? value.objects.at(-1).body.length : value.length;
  }, 3);
}
console.log(JSON.stringify({ scope: 'UTF-16 XML escaping and public SVG view/serialization with embedded source strings. Image bytes exercise markup only, without decoding. Native inputs are read each call; movement changes every frame. No browser, React, resource fetch, GPU or encoding; no peak-memory measurement.', iterations: 'Two warmup + seven measured batches; per-case iteration counts are included.', results, checksum }, null, 2));
