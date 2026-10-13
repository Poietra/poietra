import { makeDemoProject } from '../../shared/demo';
import { defaultState } from '../../shared/model';

// Ordinary poses exceed the 2 MiB echo queue without oversized leaves.
export function largeImportProject() {
  const project = makeDemoProject(), scene = project.scenes['scene-1'];
  project.name = 'Large imported project';
  scene.objects = {}; scene.compositions = {}; scene.compositionOrder = []; scene.transitions = {};
  for (let i = 0; i < 500; i++) scene.objects[`o${i}`] = { id: `o${i}`, name: `Object ${i}`, kind: 'circle', order: i, groupId: null, locked: false };
  for (let c = 0; c < 12; c++) {
    const id = `c${c}`; scene.compositionOrder.push(id);
    scene.compositions[id] = { id, name: `Composition ${c}`, accent: '#123456', duration: 1000,
      states: Object.fromEntries(Object.keys(scene.objects).map((oid, i) => [oid, defaultState('circle', {
        x: 25 + (i % 25) * 48 + c, y: 25 + Math.floor(i / 25) * 32, width: 20, height: 20,
      })])) };
  }
  return project;
}
