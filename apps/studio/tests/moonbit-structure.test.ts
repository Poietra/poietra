import { expect, it } from 'vitest';
import { makeDemoProject } from '../shared/demo';
import { projectStructureView, sceneStructureView } from '../shared/structure-view';
import * as original from './oracle/structure-view';
import type { Composition, Transition } from '../shared/model';

it('preserves the original tombstone projection across concurrent retained structures', () => {
  let seed = 0x5eed;
  const random = (limit: number) => { seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0; return seed % limit; };
  const ids = ['a', 'aa', 'b', 'z', 'é', '😀', '\uffff'];
  for (let run = 0; run < 200; run++) {
    const project = makeDemoProject(), scene = project.scenes['scene-1'];
    const base = scene.compositions['comp-1'];
    scene.compositions = {};
    scene.transitions = {};
    scene.compositionOrder = Array.from({ length: 10 }, () => ids[random(ids.length)]);
    for (const id of ids) if (random(5)) {
      const composition: Composition = { ...base, id, deleted: random(2) === 0 };
      if (random(2)) composition.incomingTransitionId = ids[random(ids.length)];
      scene.compositions[id] = composition;
    }
    for (const id of ids) if (random(4)) {
      const link: Transition = { id, fromId: ids[random(ids.length)], toId: ids[random(ids.length)], duration: random(100), tracks: {} };
      scene.transitions[id] = link;
    }
    project.scenes.other = { ...scene, id: 'other', deleted: random(2) === 0 };
    scene.deleted = random(2) === 0;
    project.sceneOrder = ['missing', 'other', 'scene-1', 'other'];
    expect(sceneStructureView(scene)).toEqual(original.sceneStructureView(scene));
    expect(projectStructureView(project)).toEqual(original.projectStructureView(project));
  }
});
