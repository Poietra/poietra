import { StrictMode, useRef, useState } from 'react';
import { createRoot } from 'react-dom/client';
import { EditorContext, useEditor, type EditorContextValue } from '../../../src/editor/context';

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
createRoot(document.getElementById('root')!).render(<StrictMode><Fixture/></StrictMode>);
