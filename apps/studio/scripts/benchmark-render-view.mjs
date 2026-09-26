// Public JS render boundary only; no DOM, resource loading or GPU work.
import { frameToSvg, frameToSvgView } from '../../../_build/js/release/build/boundary/boundary.js';
import { defaultState } from '../shared/model.js';

const resources = {
  getEquation: () => null,
  measureText: () => { throw new Error('This fixture has no text'); },
  preparedImage: () => null,
  embeddedFontStyles: () => '',
};
const options = { idPrefix: 'render-bench', hitVideo: true };
const results = [];
let checksum = 0;
function measure(callback) {
  const run = () => {
    const start = performance.now();
    for (let index = 0; index < 100; index++) callback(index);
    return (performance.now() - start) / 100;
  };
  run(); run();
  const samples = Array.from({ length: 7 }, run);
  return { median: [...samples].sort((a, b) => a - b)[3], samples };
}
for (const objects of [100, 500]) for (const variant of ['circles', 'mixed + glow']) {
  const kinds = variant === 'circles' ? ['circle'] : ['circle', 'rectangle', 'path', 'arrow', 'numberline'];
  const frame = { width: 1280, height: 720, background: '#08090b', objects: Array.from({ length: objects }, (_, index) => {
    const kind = kinds[index % kinds.length];
    return { object: { id: `object-${index}`, kind },
      state: defaultState(kind, { x: index % 25 * 48, y: Math.floor(index / 25) * 32, width: 20, height: 20, fill: '#123456', stroke: '#abcdef', strokeWidth: 2,
        effect: variant !== 'circles' && index % 10 === 0 ? 'glow' : 'none',
      }), writeProgress: .75, order: 'together',
    };
  }) };
  const view = measure(index => {
    frame.objects[0].state.x = index;
    const value = frameToSvgView(frame, options, resources);
    checksum += value.objects[0].transform.length + value.objects.at(-1).body.length;
  });
  const svg = measure(index => {
    frame.objects[0].state.x = index;
    checksum += frameToSvg(frame, options, resources).length;
  });
  results.push({ objects, variant, msPerView: view.median, msPerSvg: svg.median,
    samples: { msPerView: view.samples, msPerSvg: svg.samples },
  });
}
console.log(JSON.stringify({ scope: 'Public native frame to SVG view/markup, including typed decoding and rendering. Markup is the unchanged control path. No DOM, React, resources, media, GPU or encoding.',
  iterations: '2 warmup + 7 measured batches of 100 frames per scenario and method', results, checksum,
}, null, 2));
