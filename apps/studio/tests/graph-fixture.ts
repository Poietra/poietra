import { makeDemoProject } from '../shared/demo';
import { defaultState, defaultTrack } from '../shared/model';

export function graphProject() {
  const project = makeDemoProject(); project.version = 4;
  const scene = project.scenes['scene-1'];
  scene.objects = { graph: { id: 'graph', name: 'Function graph', kind: 'graph', order: 0, groupId: null, locked: false } };
  for (const composition of Object.values(scene.compositions)) composition.states = { graph: defaultState('graph') };
  for (const transition of Object.values(scene.transitions)) transition.tracks = { graph: defaultTrack('graph', { duration: transition.duration, easing: 'linear' }) };
  return project;
}
