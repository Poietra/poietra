import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { Boundary } from '../../../src/ui/Boundary';
import { Home } from '../../../../../_build/js/release/build/browser_site/browser_site.js';
import '../../../src/entry.css';
import '../../../src/ui/LandingPage.css';

const root = createRoot(document.getElementById('root')!);
const pending: Array<{ signal: AbortSignal; resolve(url: URL): void; reject(error: Error): void }> = [];
const runtime = {
  loadProjects: async () => ({ createProjectRoom: (_project: unknown, signal: AbortSignal) => new Promise<URL>((resolve, reject) => pending.push({ signal, resolve, reject })) }),
  loadSamples: async () => ({ makeBlankScene: (id: string) => ({ id }), makeDemoProject: () => ({ version: 1 }) }),
};
const probe = {
  pending,
  unmount() { root.unmount(); },
  finish(index: number) { pending[index].resolve(new URL('/?room=stale-room-123456789', location.href)); },
  fail(index: number) { pending[index].reject(new Error('Old response')); },
};
(window as unknown as { siteProbe: typeof probe }).siteProbe = probe;
function Crash(): never { throw new Error('Injected render failure'); }
root.render(<StrictMode><Boundary>{location.search.includes('failure') ? <Crash/> : <Home initialLocale="en" runtime={runtime}/>}</Boundary></StrictMode>);
