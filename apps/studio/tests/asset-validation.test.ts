import { expect, it } from 'vitest';
import { makeDemoProject } from '../shared/demo';
import { defaultState, type Project } from '../shared/model';
import { parseProjectFile } from '../shared/project-file';
import { portableProject } from '../../../_build/js/release/build/browser_projects/browser_projects.js';

const imageSource = 'data:image/png;base64,' + 'A'.repeat(65536);
const audioSource = 'data:audio/wav;base64,' + 'A'.repeat(65536);
function project(kind: 'image' | 'audio'): Project {
  const value = makeDemoProject(), scene = value.scenes['scene-1'];
  scene.audioTracks = {};
  for (const id of ['first', 'second']) {
    if (kind === 'image') {
      scene.objects[id] = { id, name: id, kind: 'image', order: 10, groupId: null, locked: false, image: { src: imageSource, width: 1, height: 1 } };
      for (const composition of Object.values(scene.compositions)) composition.states[id] = defaultState('image');
    } else {
      scene.audioTracks[id] = { id, name: id, start: 0, offset: 0, duration: 500, volume: .5, muted: false, asset: { src: audioSource, mime: 'audio/wav', duration: 1000, hasAudio: true, waveform: [.1, .2] } };
    }
  }
  return value;
}
const read = (value: Project) => parseProjectFile(JSON.stringify(value));
const noIo = new Proxy({}, { get() { throw new Error('Unexpected I/O before validation'); } });

it('shared source strings preserve independent image metadata and audio waveforms', async () => {
  const images = project('image'), imageScene = images.scenes['scene-1'];
  imageScene.objects.second.image!.width = 2;
  expect(read(images)).toEqual(images);
  await expect(portableProject(images, undefined, noIo)).rejects.toThrow('サイズ情報');
  const audio = project('audio'), audioScene = audio.scenes['scene-1'];
  audioScene.audioTracks!.second.asset.waveform = [.8, .9];
  const parsed = read(audio), portable = await portableProject(audio, undefined, noIo);
  expect(parsed).toEqual(audio); expect(portable).toEqual(audio);
  parsed.scenes['scene-1'].audioTracks!.second.asset.waveform![0] = 0;
  expect(parsed.scenes['scene-1'].audioTracks!.first.asset.waveform).toEqual([.1, .2]);
  expect(audioScene.audioTracks!.second.asset.waveform).toEqual([.8, .9]);
});

for (const patch of [{ width: 0 }, { width: 2049 }, { height: 1.5 }, { src: audioSource }, { src: imageSource + '?' }]) {
  it(`checks every image reference after a shared source was validated: ${Object.keys(patch)[0]}=${String(Object.values(patch)[0]).slice(0, 24)}`, async () => {
    const value = project('image');
    Object.assign(value.scenes['scene-1'].objects.second.image!, patch);
    expect(() => read(value)).toThrow('形式');
    await expect(portableProject(value, undefined, noIo)).rejects.toThrow('画像の参照');
  });
}

for (const patch of [{ duration: 0 }, { width: 0 }, { height: 8193 }, { mime: 'audio/mpeg' }, { waveform: [-.1] }, { waveform: Array(161).fill(.5) }, { src: imageSource }, { src: audioSource + '?' }]) {
  it(`checks every audio reference after a shared source was validated: ${Object.keys(patch)[0]}=${String(Object.values(patch)[0]).slice(0, 24)}`, async () => {
    const value = project('audio');
    Object.assign(value.scenes['scene-1'].audioTracks!.second.asset, patch);
    expect(() => read(value)).toThrow('形式');
    await expect(portableProject(value, undefined, noIo)).rejects.toThrow('音声・動画の参照');
  });
}

it('new calls read changed native metadata and embedded source tails afresh', async () => {
  const value = project('audio'), second = value.scenes['scene-1'].audioTracks!.second.asset;
  await expect(portableProject(value, undefined, noIo)).resolves.toEqual(value);
  expect(read(value)).toEqual(value);
  second.waveform![0] = 2;
  await expect(portableProject(value, undefined, noIo)).rejects.toThrow('音声・動画の参照');
  expect(() => read(value)).toThrow('形式');
  second.waveform![0] = .5; second.src += '!';
  await expect(portableProject(value, undefined, noIo)).rejects.toThrow('音声・動画の参照');
  expect(() => read(value)).toThrow('形式');
});

it('shared media source validation does not bypass clip duration or audio requirements', () => {
  for (const change of ['duration', 'hasAudio']) {
    const value = project('audio'), track = value.scenes['scene-1'].audioTracks!.second;
    if (change === 'duration') track.duration = 1002;
    else track.asset.hasAudio = false;
    expect(() => read(value)).toThrow('形式');
  }
});
