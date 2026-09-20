import { createRoot } from 'react-dom/client';
import { StrictMode } from 'react';
import '@fontsource/inter/400.css';
import '@fontsource/noto-sans-jp/400.css';
import '../../../src/styles.css';
import { App } from '../../../src/App';
import { EditorStore, currentRoom } from '../../../src/editor/store';
import { loadKernel } from '../../../src/engine/kernel';
import { compositionFrame } from '../../../src/engine/evaluate';
import type { ObjectState } from '../../../shared/model';
import * as renderer from '../../../src/engine/renderer';
import { drawSvgFrame } from '../../../src/engine/exporting/rasterize';
import type { PainterContract } from '../../../src/engine/painter-contract';

const heldRenders = new Set<() => void>();
const probe = {
  delay: 35, failNext: false, creations: 0, disposals: 0, active: 0, maximumConcurrentPerInstance: 0,
  svgCalls: 0, preparations: 0, preparationError: false,
  message(content: string) {
    store.chat.append({ id: crypto.randomUUID(), role: 'user', content, authorId: 'peer-probe', authorName: 'Peer', color: '#123456', createdAt: Date.now(), scope: { sceneId: 'scene-1', selection: { kind: 'composition', id: 'comp-1' }, selectedIds: [], label: 'Composition 1' } });
  },
  updateCircle(patch: Partial<ObjectState>) { store.updateState('scene-1', 'comp-1', 'circle', patch); },
  renameCircle(name: string) { store.setObject('scene-1', 'circle', { name }); },
  updateEquation(text: string, composition = 'comp-1') { store.updateState('scene-1', composition, 'equation', { text }); },
  renameComposition(name: string) { store.setComposition('scene-1', 'comp-1', { name }); },
  duration(duration: number) { store.setComposition('scene-1', 'comp-1', { duration }); },
  replaceImage(src: string) {
    const object = Object.values(store.scene('scene-1').objects).find(object => object.kind === 'image')!;
    store.setObject('scene-1', object.id, { image: { ...object.image!, src } });
  },
  referenceSvg() {
    const scene = store.scene('scene-1');
    return renderer.frameToSvg(compositionFrame(scene, scene.compositions['comp-1']), { idPrefix: 'reference', hitVideo: true });
  },
  hold: false,
  release() { probe.hold = false; for (const resume of heldRenders) resume(); heldRenders.clear(); },
  renders: [] as { instance: number; x: number | null; finished: boolean; aborted: boolean }[],
  async positions(values: number[]) {
    for (const x of values) {
      store.updateState('scene-1', 'comp-1', 'circle', { x });
      await new Promise<void>(resolve => requestAnimationFrame(() => resolve()));
    }
  },
  async cursors(count: number) {
    for (let index = 0; index < count; index++) {
      store.presence({ cursor: { x: index * 10, y: 100 } });
      await new Promise<void>(resolve => requestAnimationFrame(() => resolve()));
    }
  },
};
const observedRenderer = {
  ...renderer,
  prepareScene(...args: Parameters<typeof renderer.prepareScene>) {
    probe.preparations++;
    if (probe.preparationError) return Promise.reject(new Error('Simulated resource failure'));
    return renderer.prepareScene(...args);
  },
  frameToSvg(...args: Parameters<typeof renderer.frameToSvg>) {
    probe.svgCalls++;
    return renderer.frameToSvg(...args);
  },
  frameToSvgView(...args: Parameters<typeof renderer.frameToSvgView>) {
    probe.svgCalls++;
    return renderer.frameToSvgView(...args);
  },
};
const factory: PainterContract['createFramePainter'] = async canvas => {
  const instance = ++probe.creations;
  let disposed = false, activeRenders = 0;
  return {
    backend: 'canvas2d',
    async render(frame, options) {
      const record = { instance, x: frame.objects.find(item => item.object.id === 'circle')?.state.x ?? null, finished: false, aborted: false };
      probe.renders.push(record); probe.active++; activeRenders++;
      probe.maximumConcurrentPerInstance = Math.max(probe.maximumConcurrentPerInstance, activeRenders);
      const width = canvas.width, height = canvas.height;
      try {
        if (probe.hold) await new Promise<void>(resolve => heldRenders.add(resolve));
        // Deliberately finish the delay after dispose: stale renders must never publish.
        await new Promise(resolve => setTimeout(resolve, probe.delay));
        if (options?.signal?.aborted) { record.aborted = true; throw new DOMException('Canceled', 'AbortError'); }
        if (probe.failNext) { probe.failNext = false; throw new Error('Simulated painter failure'); }
        await drawSvgFrame(renderer.frameToSvg(frame), canvas.getContext('2d')!, width, height, frame.width, frame.height, frame.background, options?.signal);
        record.finished = true;
      } finally { probe.active--; activeRenders--; }
    },
    dispose() { if (!disposed) { disposed = true; probe.disposals++; } },
  };
};
const store = new EditorStore(currentRoom());
const kernel = await loadKernel();
declare global { interface Window { painterPreview: typeof probe } }
window.painterPreview = probe;
createRoot(document.getElementById('root')!).render(<StrictMode><App store={store} kernel={kernel} renderer={observedRenderer} exporter={null} createFramePainter={factory}/></StrictMode>);
