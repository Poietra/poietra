import { defaultState } from '../../../_build/js/release/build/boundary/boundary.js';
import { PNG } from 'pngjs';

export function project() {
  const state = x => defaultState('rectangle', { x, y: 90, width: 24, height: 24, cornerRadius: 0, strokeWidth: 0, fill: '#ffffff' });
  return { version: 2, name: 'Headless fixture', sceneOrder: ['scene'], scenes: { scene: {
    id: 'scene', name: 'Scene', width: 320, height: 180, background: '#000000',
    objects: { box: { id: 'box', name: 'Box', kind: 'rectangle', order: 0, groupId: null, locked: false } },
    compositionOrder: ['a', 'b'],
    compositions: {
      a: { id: 'a', name: 'A', duration: 200, accent: '#ffffff', states: { box: state(60) } },
      b: { id: 'b', name: 'B', duration: 220, accent: '#ffffff', states: { box: state(260) } },
    },
    transitions: { transition: { id: 'transition', fromId: 'a', toId: 'b', duration: 400, tracks: {
      box: { objectId: 'box', type: 'move', start: 0, duration: 400, easing: 'linear', order: 'together', path: null,
        keyframes: { middle: { property: 'x', at: 0.5, value: 100, easing: 'linear' } } },
    } } }, audioTracks: {},
  } } };
}

export function addObject(p, id, kind, values) {
  const scene = p.scenes.scene;
  scene.objects[id] = { id, name: id, kind, order: Object.keys(scene.objects).length, groupId: null, locked: false };
  for (const c of Object.values(scene.compositions)) c.states[id] = defaultState(kind, values);
}

export function addImage(p) {
  const png = new PNG({ width: 8, height: 8 });
  for (let i = 0; i < png.data.length; i += 4) { png.data[i] = 255; png.data[i + 1] = 128; png.data[i + 3] = 255; }
  addObject(p, 'image', 'image', { x: 290, y: 30, width: 24, height: 24, strokeWidth: 0, cornerRadius: 0 });
  p.scenes.scene.objects.image.image = { src: `data:image/png;base64,${PNG.sync.write(png).toString('base64')}`, width: 8, height: 8 };
}

export function wav(rate = 44100, duration = 1) {
  const n = Math.floor(rate * duration), b = Buffer.alloc(44 + n * 4);
  b.write('RIFF'); b.writeUInt32LE(b.length - 8, 4); b.write('WAVEfmt ', 8);
  b.writeUInt32LE(16, 16); b.writeUInt16LE(1, 20); b.writeUInt16LE(2, 22);
  b.writeUInt32LE(rate, 24); b.writeUInt32LE(rate * 4, 28); b.writeUInt16LE(4, 32); b.writeUInt16LE(16, 34);
  b.write('data', 36); b.writeUInt32LE(n * 4, 40);
  for (let i = 0; i < n; i++) {
    b.writeInt16LE(Math.round(Math.sin(i / rate * 440 * Math.PI * 2) * 12000), 44 + i * 4);
    b.writeInt16LE(Math.round(Math.sin(i / rate * 880 * Math.PI * 2) * 6000), 46 + i * 4);
  }
  return b;
}

export function addAudio(p) {
  const track = { id: 'tone', name: 'Tone', start: 200, offset: 137, duration: 400, volume: 0.5, muted: false,
    asset: { src: `data:audio/wav;base64,${wav().toString('base64')}`, mime: 'audio/wav', duration: 1000, hasAudio: true } };
  p.scenes.scene.audioTracks.tone = track;
  p.scenes.scene.audioTracks.muted = { ...structuredClone(track), id: 'muted', volume: 1, muted: true };
}
