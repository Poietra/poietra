import { describe, expect, it } from 'vitest';
import { makeDemoProject } from '../shared/demo';
import { defaultState, defaultTrack } from '../shared/model';
import { parseProjectFile } from '../shared/project-file';
import * as Y from 'yjs';
import * as encoding from 'lib0/encoding';
import * as decoding from 'lib0/decoding';
import * as sync from 'y-protocols/sync';
import { ensureSceneAnimationTracks, ensureSceneAudioTracks, initializeDocument, readProject } from '../shared/document';
import { createProjectMessages } from '../src/editor/projects';
import { boundedUtf8Size } from '../../../_build/js/release/build/boundary/boundary.js';

describe('project file import', () => {
  it('counts UTF-8 with bounded scratch memory across surrogate and buffer boundaries', () => {
    for (const text of ['', '日本語', '\ud800', '\udc00', 'a'.repeat(65535) + '😀終', '日'.repeat(30000) + '😀', 'x'.repeat(65534) + '😀' + 'x'.repeat(70000)]) {
      const bytes = new TextEncoder().encode(text).length;
      for (const limit of [0, 1, 65536, 128 * 1024 * 1024]) expect(boundedUtf8Size(text, limit)).toBe(Math.min(bytes, limit + 1));
    }
  });
  it('strips unknown data while preserving explicit inherited timings and independent nested states', () => {
    const project = makeDemoProject();
    project.scenes['scene-1'].transitions['transition-1'].tracks.circle.positionTiming = null;
    const source = { ...project, extra: '😀'.repeat(40000) };
    const parsed = parseProjectFile(JSON.stringify(source));
    expect(parsed).toEqual(project);
    parsed.scenes['scene-1'].compositions['comp-1'].states.circle.path.c1.x = 987;
    expect(parsed.scenes['scene-1'].compositions['comp-2'].states.circle.path.c1.x).not.toBe(987);
    expect(project.scenes['scene-1'].compositions['comp-1'].states.circle.path.c1.x).not.toBe(987);
  });
  it('normalizes every owned record while retaining optional nulls and independent parse results', () => {
    const expected = makeDemoProject(), scene = expected.scenes['scene-1'];
    scene.objects.circle.parentId = null;
    scene.transitions['transition-1'].tracks.circle.positionTiming = null;
    const input = structuredClone(expected), source = input.scenes['scene-1'];
    for (const value of [input, source, source.objects.circle, source.compositions['comp-1'],
      source.compositions['comp-1'].states.circle, source.compositions['comp-1'].states.circle.path,
      source.compositions['comp-1'].states.circle.path.c1, source.transitions['transition-1'],
      source.transitions['transition-1'].tracks.circle]) Object.assign(value, { extra: { ignored: ['日本語😀', 1] } });
    const text = JSON.stringify(input), first = parseProjectFile(text), second = parseProjectFile(text);
    expect(first).toEqual(expected); expect(second).toEqual(expected);
    first.sceneOrder.push('another');
    first.scenes['scene-1'].compositions['comp-1'].states.circle.path.c1.x = 987;
    expect(second).toEqual(expected);
    expect(JSON.stringify(input)).toBe(text);
  });
  it.each(['__proto__', 'constructor', 'prototype'])('rejects a reserved %s key even inside an unknown subtree', key => {
    const input = { ...makeDemoProject(), extra: JSON.parse(`{"${key}": {"value": 1}}`) };
    expect(() => parseProjectFile(JSON.stringify(input))).toThrow('JSON');
  });
  it.each([
    ['__proto__', '\\u005f_proto__'], ['constructor', '\\u0063onstructor'], ['prototype', '\\u0070rototype'],
  ])('checks decoded %s keys inside ignored nested arrays', (key, escaped) => {
    const text = JSON.stringify(makeDemoProject());
    const withExtra = text.slice(0, -1) + `,"extra":[null,1,"safe",[[{"${escaped}":true}]]]}`;
    expect(() => JSON.parse(withExtra, (name, value) => {
      if (name === key) throw new Error('Reserved key');
      return value;
    })).toThrow('Reserved key');
    expect(() => parseProjectFile(withExtra)).toThrow('JSON');
  });
  it('allows reserved words in values and ignores overwritten JSON subtrees', () => {
    const expected = makeDemoProject(); expected.name = 'constructor';
    const text = JSON.stringify(expected);
    const withExtra = text.slice(0, -1) + ',"extra":{"prototype":1},"extra":["__proto__",{"prototype-value":"constructor"}]}';
    expect(() => JSON.parse(withExtra, (key, value) => {
      if (['__proto__', 'constructor', 'prototype'].includes(key)) throw new Error('Reserved key');
      return value;
    })).not.toThrow();
    expect(parseProjectFile(withExtra)).toEqual(expected);
  });
  it('keeps custom easing strict even when other record fields can be stripped', () => {
    const input = makeDemoProject();
    input.scenes['scene-1'].transitions['transition-1'].tracks.circle.easing = {
      type: 'cubicBezier', x1: .2, y1: 0, x2: .8, y2: 1, extra: true,
    } as never;
    expect(() => parseProjectFile(JSON.stringify(input))).toThrow('形式');
  });
  it('round-trips editable geometry, timing and expressions', () => {
    const project = makeDemoProject();
    expect(parseProjectFile(JSON.stringify(project))).toEqual(project);
  });
  it('rejects dangling composition references before opening a room', () => {
    const project = makeDemoProject();
    project.scenes['scene-1'].transitions['transition-1'].toId = 'missing';
    expect(() => parseProjectFile(JSON.stringify(project))).toThrow('参照');
  });
  it('rejects an animation exceeding the transition and duplicate ordered IDs', () => {
    const project = makeDemoProject();
    project.scenes['scene-1'].transitions['transition-1'].tracks.circle.start = 400;
    expect(() => parseProjectFile(JSON.stringify(project))).toThrow('時間');
    project.scenes['scene-1'].transitions['transition-1'].tracks.circle.start = 0;
    project.sceneOrder.push('scene-1');
    expect(() => parseProjectFile(JSON.stringify(project))).toThrow('参照');
  });
  it('rejects nonfinite geometry and reserved object keys', () => {
    const project = makeDemoProject();
    project.scenes['scene-1'].compositions['comp-1'].states.circle.x = Infinity;
    expect(() => parseProjectFile(JSON.stringify(project))).toThrow('形式');
    expect(() => parseProjectFile(JSON.stringify(makeDemoProject()).replaceAll('circle', '__proto__'))).toThrow('形式');
  });
  it('round-trips the full font and stroke range allowed by AI edits', () => {
    const project = makeDemoProject();
    const state = project.scenes['scene-1'].compositions['comp-1'].states.circle;
    state.fontSize = 0; state.strokeWidth = 10000;
    expect(parseProjectFile(JSON.stringify(project))).toEqual(project);
    state.fontSize = 10000;
    expect(parseProjectFile(JSON.stringify(project))).toEqual(project);
  });

  it('prepares a replacement without mutating the source and delivers it with the standard sync protocol', () => {
    const source = new Y.Doc(); initializeDocument(source, makeDemoProject());
    const project = makeDemoProject(); project.name = 'Restored';
    const messages = createProjectMessages(source, project);
    expect(readProject(source)!.name).toBe('A little motion');
    applyMessages(source, messages.updateMessages);
    expect(readProject(source)).toEqual(project);
    const request = decoding.createDecoder(messages.syncMessage);
    expect(decoding.readVarUint(request)).toBe(0);
    expect(sync.readSyncMessage(request, encoding.createEncoder(), source, 'test')).toBe(sync.messageYjsSyncStep1);
    source.destroy();
  });

  it('opens a valid project above 2 MiB in compact bounded messages that reconstruct it', () => {
    const empty = new Y.Doc();
    expect(createProjectMessages(empty, makeDemoProject()).updateMessages).toHaveLength(1);
    empty.destroy();
    const source = new Y.Doc(); initializeDocument(source, makeDemoProject());
    const project = parseProjectFile(JSON.stringify(largeProject()));
    const messages = createProjectMessages(source, project);
    expect(messages.updateMessages.length).toBeGreaterThan(1);
    expect(messages.updateMessages.length).toBeLessThan(100);
    expect(messages.updateMessages.reduce((total, message) => total + message.byteLength, 0)).toBeGreaterThan(2 * 1048576);
    for (const message of messages.updateMessages) expect(message.byteLength).toBeLessThanOrEqual(1048576);
    expect(readProject(source)).toEqual(makeDemoProject());
    applyMessages(source, messages.updateMessages);
    expect(readProject(source)).toEqual(project);
    source.destroy();
  });
  it('preserves authored tracks and 2,000 keyframes when the room initializes after every import message', () => {
    const source = new Y.Doc(), server = new Y.Doc();
    source.clientID = 1;
    // A deterministic winner for defaults inserted concurrently with the staged import.
    server.clientID = 0xffffffff;
    initializeDocument(source, makeDemoProject());
    ensureSceneAudioTracks(source); ensureSceneAnimationTracks(source);
    Y.applyUpdate(server, Y.encodeStateAsUpdate(source));
    const input = largeProject(2, 2); input.version = 2;
    const tracks = input.scenes['scene-1'].transitions.t1.tracks;
    for (const objectId of ['o0', 'o1']) tracks[objectId] = defaultTrack(objectId, {
      type: 'write', start: 25, duration: 200, easing: 'easeOut',
      keyframes: Object.fromEntries(Array.from({ length: 1000 }, (_, i) => [
        `point-${i}`.padEnd(64, 'x'),
        { property: 'x' as const, at: (i + 1) / 1001, value: i, easing: 'linear' as const },
      ])),
    });
    const project = parseProjectFile(JSON.stringify(input));
    const { updateMessages } = createProjectMessages(source, project);
    expect(updateMessages.length).toBeGreaterThan(1);
    for (const [index, message] of updateMessages.entries()) {
      applyMessages(server, [message]);
      ensureSceneAudioTracks(server); ensureSceneAnimationTracks(server);
      if (index < updateMessages.length - 1) expect(readProject(server)).toBeNull();
    }
    expect(readProject(server)!.scenes['scene-1'].transitions.t1.tracks).toEqual(tracks);
    source.destroy(); server.destroy();
  });
  it('creates the same shared structure in parts as a single conversion, including legacy track keyframes', () => {
    const project = largeProject();
    // A legacy track without keyframes that is itself larger than one staging transaction.
    (project.scenes['scene-1'].transitions.t1.tracks as Record<string, unknown>).o0 = { objectId: 'o0', type: 'move', start: 0, duration: 250, easing: 'linear', order: 'together', path: null, extra: 'x'.repeat(300000) };
    const parts = new Y.Doc(), whole = new Y.Doc();
    applyMessages(parts, createProjectMessages(new Y.Doc(), project).updateMessages);
    initializeDocument(whole, project);
    const track = ['scenes', 'scene-1', 'transitions', 't1', 'tracks', 'o0'].reduce((map: any, key) => map.get(key), parts.getMap('project') as any);
    expect(track.get('keyframes')).toBeInstanceOf(Y.Map);
    expect(track.get('extra')).toHaveLength(300000);
    expect(shape(parts.getMap('project'))).toEqual(shape(whole.getMap('project')));
    parts.destroy(); whole.destroy();
  });
  it('rejects a single value that cannot fit one message before mutating or sending the project', () => {
    const source = new Y.Doc(); initializeDocument(source, makeDemoProject());
    const project = makeDemoProject();
    project.scenes['scene-1'].compositions['comp-1'].states.equation.text = 'a'.repeat(2 * 1024 * 1024);
    expect(() => createProjectMessages(source, project)).toThrow('1 MB');
    expect(readProject(source)).toEqual(makeDemoProject());
    source.destroy();
  });
});

function applyMessages(doc: Y.Doc, messages: Uint8Array[]) {
  for (const message of messages) {
    const decoder = decoding.createDecoder(message);
    expect(decoding.readVarUint(decoder)).toBe(0);
    sync.readSyncMessage(decoder, encoding.createEncoder(), doc, 'test');
  }
}

// Nested shared maps and arrays versus plain leaves, independent of item order.
function shape(value: unknown): unknown {
  if (value instanceof Y.Map) return { map: Object.fromEntries([...value.keys()].sort().map(key => [key, shape(value.get(key))])) };
  if (value instanceof Y.Array) return { array: value.toArray().map(shape) };
  return value;
}

// Valid authored text content exceeds 2 MiB without any single oversized value.
function largeProject(objects = 500, compositions = 6) {
  const project = makeDemoProject(), scene = project.scenes['scene-1'];
  scene.objects = {}; scene.compositions = {}; scene.compositionOrder = []; scene.transitions = {};
  for (let i = 0; i < objects; i++) scene.objects[`o${i}`] = { id: `o${i}`, name: `Object ${i}`, kind: 'text', order: i, groupId: null, locked: false };
  for (let c = 0; c < compositions; c++) {
    const id = `c${c}`; scene.compositionOrder.push(id);
    scene.compositions[id] = { id, name: `Composition ${c}`, accent: '#123456', duration: 1000,
      states: Object.fromEntries(Object.keys(scene.objects).map((oid, i) => [oid, defaultState('text', {
        x: 25 + (i % 25) * 48 + c, y: 25 + Math.floor(i / 25) * 32, width: 20, height: 20, text: 'a'.repeat(400),
      })])) };
    if (c) scene.transitions[`t${c}`] = { id: `t${c}`, fromId: `c${c - 1}`, toId: id, duration: 250, tracks: {} };
  }
  return project;
}
