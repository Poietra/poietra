import { makeDemoProject } from '../shared/demo';
import { defaultState, defaultTrack, type Project } from '../shared/model';

export function geometryProject(): Project {
  const project = makeDemoProject(); project.version = 5;
  const scene = project.scenes['scene-1'];
  scene.objects = { diagram: { id: 'diagram', name: 'Mathematical diagram', kind: 'geometry', order: 0, groupId: null, locked: false } };
  for (const composition of Object.values(scene.compositions)) composition.states = { diagram: defaultState('geometry') };
  for (const transition of Object.values(scene.transitions)) transition.tracks = { diagram: defaultTrack('diagram', { duration: transition.duration, easing: 'linear' }) };
  return project;
}
