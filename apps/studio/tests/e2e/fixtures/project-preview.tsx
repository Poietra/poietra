import { StrictMode, useState } from 'react';
import { createRoot } from 'react-dom/client';
import '../../../src/styles.css';
import { ProjectPreview } from '../../../src/ui/ProjectPreview';
import { makeBlankScene } from '../../../shared/demo';
import { defaultState, type Project, type Scene } from '../../../shared/model';
import { loadKernel } from '../../../src/engine/kernel';
import * as renderer from '../../../src/engine/renderer';
import { createFramePainter } from '../../../src/engine/painter';
import type { RendererContract } from '../../../src/engine/render-contract';
import type { PainterContract } from '../../../src/engine/painter-contract';

const mode = new URLSearchParams(location.search).get('mode') || 'canvas';
const waiting = new Set<() => void>();
const probe = {
  svg: 0, views: 0, frames: 0, painters: 0, hold: false, failFrame: false,
  addVideo() {}, close() {},
  release() { probe.hold = false; for (const next of waiting) next(); waiting.clear(); },
};
const measuredRenderer: RendererContract = {
  ...renderer,
  frameToSvg(...args) { probe.svg++; return renderer.frameToSvg(...args); },
  frameToSvgView(...args) {
    probe.views++;
    const view = renderer.frameToSvgView(...args);
    for (const object of view.objects) Object.freeze(object);
    return Object.freeze(view);
  },
  async prepareFrame(frame) {
    probe.frames++;
    if (probe.hold) await new Promise<void>(resolve => waiting.add(resolve));
    // Deliberately ignore cancellation to test the preview owner's late suppression.
    if (probe.failFrame) throw new Error('Simulated video preparation failure');
    for (const object of frame.objects) if (object.object.kind === 'video') {
      const canvas = document.createElement('canvas'); canvas.width = 16; canvas.height = 16;
      const context = canvas.getContext('2d')!; context.fillStyle = (object.videoTimeMs ?? 0) < 200 ? '#0000ff' : '#00ff00'; context.fillRect(0, 0, 16, 16);
      object.videoFrame = canvas.toDataURL();
    }
  },
};
if (mode === 'legacy') delete measuredRenderer.frameToSvgView;
const factory: PainterContract['createFramePainter'] | undefined = mode === 'svg' || mode === 'legacy' ? undefined : async canvas => {
  probe.painters++;
  if (mode === 'fail') throw new Error('Simulated unavailable painter');
  return createFramePainter(canvas);
};
function scene(id: string, color: string): Scene {
  const value = makeBlankScene(id, id); value.width = 320; value.height = 180;
  const a = value.compositionOrder[0], b = `${id}-end`;
  value.compositions[a].duration = 100;
  value.objects.box = { id: 'box', name: 'Box', kind: 'rectangle', order: 0, locked: false, groupId: null };
  value.compositions[a].states.box = defaultState('rectangle', { x: 80, y: 90, width: 50, height: 50, fill: color, strokeWidth: 0 });
  value.compositions[b] = { ...value.compositions[a], id: b, name: b, states: { box: { ...value.compositions[a].states.box, x: 240 } } };
  value.compositionOrder.push(b); value.transitions.t = { id: 't', fromId: a, toId: b, duration: 800, tracks: {} };
  return value;
}
const initial: Project = { version: 1, name: 'Preview fixture', sceneOrder: ['first', 'second'], scenes: { first: scene('first', '#ff0000'), second: scene('second', '#00ffff') } };
initial.scenes.second.width = 180; initial.scenes.second.height = 320;
const kernel = await loadKernel();
declare global { interface Window { projectPreviewProbe: typeof probe } }
window.projectPreviewProbe = probe;
function Fixture() {
  const [project, setProject] = useState(initial), [open, setOpen] = useState(true);
  probe.close = () => setOpen(false);
  probe.addVideo = () => setProject(previous => {
    const next = structuredClone(previous), first = next.scenes.first;
    first.objects.clip = { id: 'clip', name: 'Clip', kind: 'video', order: 1, locked: false, groupId: null,
      media: { src: 'data:video/mp4;base64,AAAA', mime: 'video/mp4', duration: 1000, hasAudio: false, width: 16, height: 16 },
      playback: { start: 0, offset: 0, duration: 1000 } };
    for (const composition of Object.values(first.compositions)) composition.states.clip = defaultState('video', { x: 160, y: 90, width: 64, height: 64 });
    return next;
  });
  return <ProjectPreview open={open} onOpenChange={setOpen} project={project} renderer={measuredRenderer} kernel={kernel} createFramePainter={factory} onEdit={() => {}}/>;
}
createRoot(document.getElementById('root')!).render(<StrictMode><Fixture/></StrictMode>);
