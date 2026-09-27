import { makeDemoProject } from '../shared/demo';
import { defaultState } from '../shared/model';

export function clippingProject() {
  const p = makeDemoProject(); p.version = 3;
  const s = p.scenes['scene-1'];
  Object.assign(s, { width: 200, height: 160, background: '#000000', audioTracks: {} });
  s.objects = {
    frame: { id: 'frame', name: 'Clipping frame', kind: 'rectangle', order: 0, groupId: null, locked: false, clipChildren: true },
    child: { id: 'child', name: 'Clipped child', kind: 'rectangle', order: 1, groupId: null, locked: false, parentId: 'frame' },
  };
  for (const c of Object.values(s.compositions)) c.states = {
    frame: defaultState('rectangle', { x: 100, y: 80, width: 80, height: 80, visible: false, opacity: 0 }),
    child: defaultState('rectangle', { x: 0, y: 0, width: 160, height: 160, fill: '#ffffff', strokeWidth: 0 }),
  };
  for (const t of Object.values(s.transitions)) t.tracks = {};
  return p;
}
