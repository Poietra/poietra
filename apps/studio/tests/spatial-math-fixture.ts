import { makeDemoProject } from '../shared/demo';
import { defaultState, defaultTrack, type Project } from '../shared/model';

export function spatialMathProject(kind: 'network' | 'surface'): Project {
  const project = makeDemoProject(); project.version = 6;
  const scene = project.scenes['scene-1'];
  scene.objects = { diagram: { id: 'diagram', name: kind === 'network' ? 'Network diagram' : '3D surface', kind, order: 0, groupId: null, locked: false } };
  for (const composition of Object.values(scene.compositions)) composition.states = { diagram: defaultState(kind) };
  for (const transition of Object.values(scene.transitions)) transition.tracks = { diagram: defaultTrack('diagram', { duration: transition.duration, easing: 'linear' }) };
  return project;
}
