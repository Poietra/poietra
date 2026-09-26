import { StrictMode, useState } from 'react';
import { createRoot } from 'react-dom/client';
import '../../../src/styles.css';
import { ExportDialog } from '../../../src/ui/ExportDialog';
import { makeDemoProject } from '../../../shared/demo';
import type { Project, Scene } from '../../../shared/model';
import type { ExportCapabilities, ExporterContract, ExportOptions, ExportResult } from '../../../src/engine/render-contract';
import type { MotionKernel } from '../../../src/engine/kernel';

const capabilities: { resolve(value: ExportCapabilities): void; reject(error: Error): void }[] = [];
const exports: { scene: Scene; project?: Project; options: ExportOptions; resolve(value: ExportResult): void; reject(error: Error): void }[] = [];
const projectMode = new URLSearchParams(location.search).has('project');
let clones = 0;
const nativeClone = globalThis.structuredClone;
globalThis.structuredClone = (...args) => { clones++; return nativeClone(...args); };
const exporter: ExporterContract = {
  getExportCapabilities: () => new Promise((resolve, reject) => capabilities.push({ resolve, reject })),
  exportScene: (scene, _kernel, options) => new Promise((resolve, reject) => exports.push({ scene, options, resolve, reject })),
};
if (projectMode) exporter.exportProject = (project, _kernel, options) => new Promise((resolve, reject) => exports.push({ project, scene: project.scenes[project.sceneOrder[0]], options, resolve, reject }));
const kernel = {} as MotionKernel; // The explicit exporter stub never evaluates frames.
const probe = {
  open() {}, close() {}, unmount() {},
  changeSource(_width: number, _height: number, _sceneName: string, _projectName: string) {},
  capabilities(index: number, value: ExportCapabilities) { capabilities[index].resolve(value); },
  capabilityError(index: number) { capabilities[index].reject(new Error('Capability check failed')); },
  progress(index: number, value: number) { exports[index].options.onProgress?.(value); },
  finish(index: number) { const { options } = exports[index]; exports[index].resolve({ blob: new Blob(['explicit-exporter-stub'], { type: 'video/mp4' }), mimeType: 'video/mp4', extension: options.format, codec: 'stub', width: options.width!, height: options.height!, durationMs: 3400 }); },
  fail(index: number) { exports[index].reject(new Error('Encoder interrupted')); },
  mutateCaptured(index: number) {
    const input = exports[index]; input.scene.name = 'Exporter changed scene'; input.scene.width = 50;
    for (const composition of Object.values(input.scene.compositions)) composition.duration = 9000;
    if (input.project) input.project.name = 'Exporter changed project';
  },
  state() { return { clones, capabilities: capabilities.length, exports: exports.map(({ scene, project, options }) => ({ scene, project, format: options.format, width: options.width, height: options.height, fps: options.fps, aborted: options.signal?.aborted })) }; },
};
declare global { interface Window { exportDialogProbe: typeof probe } }
window.exportDialogProbe = probe;
function Fixture() {
  const [open, setOpen] = useState(false); const [mounted, setMounted] = useState(true);
  const [project, setProject] = useState(() => {
    const project = makeDemoProject(); project.name = 'Original project';
    if (projectMode) {
      const second = structuredClone(project.scenes['scene-1']); second.id = 'scene-2'; second.name = 'Second';
      project.scenes['scene-2'] = second; project.sceneOrder.push('scene-2');
    }
    return project;
  });
  const scene = project.scenes['scene-1'], name = project.name;
  probe.open = () => setOpen(true); probe.close = () => setOpen(false); probe.unmount = () => setMounted(false);
  probe.changeSource = (width, height, sceneName, projectName) => setProject(previous => ({ ...previous, name: projectName, scenes: { ...previous.scenes, 'scene-1': { ...previous.scenes['scene-1'], width, height, name: sceneName } } }));
  return <>{mounted && <ExportDialog open={open} onOpenChange={setOpen} exporter={exporter} scene={scene} project={projectMode ? project : undefined} kernel={kernel} name={name}/>}</>;
}
createRoot(document.getElementById('root')!).render(<StrictMode><Fixture/></StrictMode>);
