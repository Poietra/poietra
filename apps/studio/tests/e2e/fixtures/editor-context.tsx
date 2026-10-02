import { StrictMode, useRef, useState } from 'react';
import { createRoot } from 'react-dom/client';
import { EditorContext, useEditor, type EditorContextValue } from '../../../src/editor/context';
import { Tooltip } from '@base-ui/react/tooltip';
import { makeDemoProject } from '../../../shared/demo';
import type { Easing, Selection } from '../../../shared/model';
import { loadKernel } from '../../../src/engine/kernel';
import * as renderer from '../../../src/engine/renderer';
import { GroupControls } from '../../../src/ui/GroupInspector';
import { Timeline } from '../../../src/ui/Timeline';
import { EasingEditor } from '../../../src/ui/EasingEditor';
import { PropertyTimingInspector } from '../../../src/ui/PropertyTimingInspector';
import '../../../src/styles.css';

const kernel = await loadKernel();

function Probe() {
  const editor = useEditor(), previous = useRef(editor);
  const [local, setLocal] = useState(0);
  const stable = previous.current === editor;
  previous.current = editor;
  return <><output>{editor.playhead}:{editor.peers[0].name}</output><button onClick={() => setLocal(local + 1)}>Local render</button><span data-testid="stable">{String(stable)}</span></>;
}
function Fixture() {
  const [context, setContext] = useState(() => ({
    playhead: 125, peers: [{ clientId: 7, name: 'Alice' }],
    // An externally supplied Context is authoritative; do not replace its
    // values by reaching into a different store's snapshot.
    store: { snapshot() { throw new Error('Unexpected store subscription'); } },
  }) as unknown as EditorContextValue);
  return <EditorContext.Provider value={context}><Probe/><button onClick={() => setContext({ ...context, playhead: 375, peers: [{ ...context.peers[0], name: 'Bob' }] })}>Update context</button></EditorContext.Provider>;
}
// Real exported panels must also work under an external provider, including
// native callback arguments and replacement callbacks after a provider update.
function PanelsFixture() {
  const [scene] = useState(() => {
    const project = makeDemoProject(), scene = project.scenes[project.sceneOrder[0]];
    scene.objects.circle.groupId = scene.objects.sigmoid.groupId = 'fixture-group';
    return scene;
  });
  const [selection, setSelection] = useState<Selection>({ kind: 'composition', id: 'comp-1' });
  const [selectedIds, setSelectedIds] = useState(['circle']);
  const [playhead, setPlayhead] = useState(125);
  const [generation, setGeneration] = useState(1);
  const [command, setCommand] = useState('');
  const record = (name: string, ...args: unknown[]) => setCommand(JSON.stringify([generation, name, ...args]));
  const [store] = useState(() => ({
    snapshot() { throw new Error('External panels must not subscribe to the editor store'); },
  }) as unknown as EditorContextValue['store']);
  const context: EditorContextValue = {
    store, scene, kernel, renderer, selection, selectedIds, playhead, peers: [],
    compositionId: selection.kind === 'composition' ? selection.id : scene.transitions[selection.id].toId,
    tool: 'select', playing: false, previewScope: 'scene', pathEditing: false,
    select(value) { record('select', value); setSelection(value); },
    setSelectedIds(value) { record('objects', value); setSelectedIds(value); },
    seek(time, scope) { record('seek', time, scope); setPlayhead(time); },
    play(scope) { record('play', scope); },
    appendComposition() { record('append'); },
    requestTextEdit(object, composition) { record('text', object, composition); },
    setTool(tool) { record('tool', tool); },
    setPathEditing(editing) { record('path', editing); },
    notify(message) { record('notify', message); },
  };
  return <Tooltip.Provider><EditorContext.Provider value={context}>
    <GroupControls/><Timeline zoom={1} setZoom={() => {}}/>
    <output data-testid="command">{command}</output>
    <button onClick={() => setGeneration(generation + 1)}>Replace callbacks</button>
  </EditorContext.Provider></Tooltip.Provider>;
}
function AnimationFixture() {
  const [project] = useState(() => {
    const project = makeDemoProject();
    const track = project.scenes['scene-1'].transitions['transition-1'].tracks.circle;
    track.positionTiming = { start: 100, duration: 500, easing: 'linear' };
    track.keyframes = {};
    // Exported UI must accept the immutable snapshots used by the real store.
    function freeze(value: unknown) {
      if (value && typeof value === 'object') {
        Object.values(value).forEach(freeze);
        Object.freeze(value);
      }
    }
    freeze(project);
    return project;
  });
  const current = useRef(project);
  const [command, setCommand] = useState('');
  const [curve, setCurve] = useState<Easing>('linear');
  const currentCurve = useRef<Easing>(curve);
  const [generation, setGeneration] = useState(1);
  const [store] = useState(() => ({
    project() { return current.current; },
    snapshot() { throw new Error('External animation panels must not subscribe to the store'); },
    setPropertyTiming(...args: Parameters<EditorContextValue['store']['setPropertyTiming']>) {
      setCommand(JSON.stringify(['timing', ...args]));
    },
  }) as unknown as EditorContextValue['store']);
  const scene = project.scenes['scene-1'], transition = scene.transitions['transition-1'];
  const unexpected = () => { throw new Error('Unexpected editor action from an animation control'); };
  const context: EditorContextValue = {
    store, scene, kernel, renderer, selection: { kind: 'transition', id: transition.id },
    compositionId: transition.toId, selectedIds: ['circle'], playhead: 0, peers: [],
    tool: 'select', playing: false, previewScope: 'scene', pathEditing: false,
    select: unexpected, appendComposition: unexpected, requestTextEdit: unexpected,
    setSelectedIds: unexpected, setTool: unexpected, setPathEditing: unexpected,
    seek: unexpected, play: unexpected,
    notify(message: string) { throw new Error(message); },
  };
  return <EditorContext.Provider value={context}>
    <EasingEditor value={curve} getValue={() => currentCurve.current} label="External easing" onChange={(value, separate) => {
      setCommand(JSON.stringify([generation, 'curve', value, separate ?? 'default']));
      currentCurve.current = value;
      setCurve(value);
    }}/>
    <PropertyTimingInspector object={scene.objects.circle} transition={transition} track={transition.tracks.circle}/>
    <output data-testid="command">{command}</output>
    <button onClick={() => setGeneration(generation + 1)}>Replace callbacks</button>
    <button onClick={() => { currentCurve.current = { type: 'cubicBezier', x1: .65, y1: .3, x2: .7, y2: .9 }; }}>Peer curve before render</button>
    <button onClick={() => {
      const next = structuredClone(project);
      next.scenes['scene-1'].transitions['transition-1'].tracks.circle.positionTiming = { start: 200, duration: 300, easing: 'easeIn' };
      current.current = next;
    }}>Peer timing before render</button>
    <button onClick={() => { current.current = { ...project, scenes: {}, sceneOrder: [] }; }}>Remove target before render</button>
  </EditorContext.Provider>;
}
const params = new URLSearchParams(location.search);
createRoot(document.getElementById('root')!).render(<StrictMode>{params.has('animation') ? <AnimationFixture/> : params.has('panels') ? <PanelsFixture/> : <Fixture/>}</StrictMode>);
