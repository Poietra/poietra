import { expect, it } from 'vitest';
import { makeDemoProject } from '../shared/demo';
import { defaultState, sceneDuration, sceneSegments } from '../shared/model';

const unused = () => { throw new Error('Unrelated timeline data was read'); };

it('visual segments do not read objects, audio or Composition states', () => {
  const scene = makeDemoProject().scenes['scene-1'];
  const expected = sceneSegments(scene);
  Object.defineProperty(scene, 'objects', { get: unused });
  Object.defineProperty(scene, 'audioTracks', { get: unused });
  for (const composition of Object.values(scene.compositions)) Object.defineProperty(composition, 'states', { get: unused });
  expect(sceneSegments(scene)).toEqual(expected);
});

it('duration reads clip timing and visibility without reading media or appearance', () => {
  const scene = makeDemoProject().scenes['scene-1'];
  scene.objects.video = { id: 'video', name: 'Video', kind: 'video', groupId: null, order: 5, locked: false, playback: { start: 200, offset: 0, duration: 7000 } };
  Object.defineProperty(scene.objects.video, 'media', { get: unused });
  Object.defineProperty(scene.objects.circle, 'playback', { get: unused });
  const state = defaultState('video');
  Object.defineProperty(state, 'x', { get: unused });
  scene.compositions['comp-2'].states.video = state;
  expect(sceneDuration(scene)).toBe(7200);
  state.visible = false;
  expect(sceneDuration(scene)).toBe(3400);
  scene.audioTracks = { audio: { id: 'audio', name: 'Audio', asset: { src: '', mime: 'audio/wav', duration: 10000, hasAudio: true, waveform: [] }, start: 500, offset: 0, duration: 8000, volume: 0, muted: true } };
  Object.defineProperty(scene.audioTracks.audio, 'asset', { get: unused });
  expect(sceneDuration(scene)).toBe(8500);
  scene.audioTracks.audio.duration = 1000;
  expect(sceneDuration(scene)).toBe(3400);
});

it('video visibility in a retained Composition still extends duration without changing visual order', () => {
  const scene = makeDemoProject().scenes['scene-1'];
  const parts = sceneSegments(scene);
  scene.objects.video = { id: 'video', name: 'Video', kind: 'video', groupId: null, order: 5, locked: false, playback: { start: 200, offset: 0, duration: 7000 } };
  scene.compositions.retained = { ...scene.compositions['comp-1'], id: 'retained', deleted: true, states: { video: defaultState('video') } };
  expect(sceneSegments(scene)).toEqual(parts);
  expect(sceneDuration(scene)).toBe(7200);
  scene.compositions.retained.states.video.visible = false;
  expect(sceneDuration(scene)).toBe(3400);
});

it('duration keeps invalid-number propagation at an unvalidated caller boundary', () => {
  const scene = makeDemoProject().scenes['scene-1'];
  scene.compositions['comp-1'].duration = NaN;
  expect(sceneDuration(scene)).toBeNaN();
  scene.compositions['comp-1'].duration = Infinity;
  expect(sceneDuration(scene)).toBe(Infinity);
});
