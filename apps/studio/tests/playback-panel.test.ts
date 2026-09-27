import { createElement } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { expect, it } from 'vitest';
import { makeDemoProject } from '../shared/demo';
import { sceneSegments } from '../shared/model';
import { PlaybackPanel } from '../src/ui/PlaybackPanel';

it('the public native playback panel accepts every segment kind and an empty selection', () => {
  const scene = makeDemoProject().scenes['scene-1'];
  const segments = sceneSegments(scene);
  const render = (segment: typeof segments[number] | undefined) => renderToStaticMarkup(createElement(PlaybackPanel, { scene, segment, playhead: 1300, onEdit: () => {} }));
  expect(render(undefined)).toContain(scene.name);
  expect(render(segments[0])).toContain(scene.compositions[segments[0].id].name);
  expect(render(segments[1])).toContain('Composition 1 → Composition 2');
  expect(render(segments[2])).toContain(scene.compositions[segments[2].id].name);
  expect(render(segments[1])).toContain('1,300 ms');
});
