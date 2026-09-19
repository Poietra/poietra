import * as commands from '../../../../_build/js/release/build/browser_editor/browser_editor.js';
import * as Y from 'yjs';
import { WebsocketProvider } from 'y-websocket';
import { IndexeddbPersistence } from 'y-indexeddb';
import type { Change } from '../../shared/document';
import { COLORS, type AnimationTiming, type PropertyChannel, type AnimationTrack, type Composition, type ObjectKind, type ObjectState, type Project, type Scene, type SceneObject } from '../../shared/model';
import { applyProposal, type EditProposal } from '../../shared/ai';
import { RoomChat } from '../../shared/chat';
import type { ImageAsset } from '../../shared/images';
import type { AudioTrack, MediaAsset, MediaPlayback } from '../../shared/media';
import type { ObjectClipboard } from '../../shared/clipboard';
import { EditorUndoManager } from './undo';

const runtime = { Y, colors: COLORS, applyProposal, RoomChat, EditorUndoManager, WebsocketProvider, IndexeddbPersistence };
const subscribe = commands.subscribe as (store: EditorStore, listener: () => void) => () => void;

export interface Peer {
  clientId: number;
  name: string;
  color: string;
  sceneId?: string;
  compositionId?: string;
  selectedIds?: string[];
  cursor?: { x: number; y: number } | null;
}
export interface EditorSnapshot {
  project: Project | null;
  status: 'connecting' | 'connected' | 'disconnected';
  synced: boolean;
  localPersistence: 'loading' | 'ready' | 'unavailable';
  connectionIssue: string | null;
  peers: Peer[];
  canUndo: boolean;
  canRedo: boolean;
}

export const currentRoom: () => string = commands.currentRoom;

// Constructor/prototype signatures adapt existing consumers and tests to the
// MoonBit-owned session and typed command plans. Native dependencies stay injectable.
export class EditorStore {
  declare readonly doc: Y.Doc;
  declare readonly chat: RoomChat;
  declare readonly chatAuthorId: string;
  declare readonly provider: WebsocketProvider;
  declare readonly persistence: IndexeddbPersistence;
  declare readonly undoManager: EditorUndoManager;
  declare readonly color: string;
  declare userName: string;
  get runtime() { return runtime; }
  constructor(readonly roomId: string) { commands.createStore(this, roomId); }
  subscribe = (listener: () => void): (() => void) => subscribe(this, listener);
  snapshot = (): EditorSnapshot => commands.snapshot(this);
  retryConnection = (): void => commands.retryConnection(this);
  setName(name: string) { return commands.setName(this, name); }
  presence(state: Partial<Peer>) { return commands.presence(this, state); }
  beginGesture() { return commands.beginGesture(this); }
  endGesture() { return commands.endGesture(this); }
  get lastUndoPreservedObjects() { return this.undoManager.lastUndoPreservedObjects; }
  get lastUndoPreservedAudioTracks() { return this.undoManager.lastUndoPreservedAudioTracks; }
  get lastUndoPreservedCompositions() { return this.undoManager.lastUndoPreservedCompositions; }
  get lastUndoPreservedDurations() { return this.undoManager.lastUndoPreservedDurations; }
  undo(): number { return commands.undoEdit(this); }
  redo(): number { return commands.redoEdit(this); }
  rollbackGesture(item: object): boolean { return commands.rollbackGesture(this, item); }
  edit(changes: Change[], separate = true) { return commands.editBatch(this, changes, separate); }
  project(): Project { return commands.project(this); }
  scene(id: string): Scene { return commands.scene(this, id); }
  setProjectName(name: string) { return commands.setProjectName(this, name); }
  setScene(sceneId: string, patch: Partial<Pick<Scene, 'name' | 'background'>>) { return commands.setScene(this, sceneId, patch); }
  setObject(sceneId: string, id: string, patch: Partial<SceneObject>) { return commands.setObject(this, sceneId, id, patch); }
  updateState(sceneId: string, compositionId: string, objectId: string, patch: Partial<ObjectState>, separate = true) { return commands.updateState(this, sceneId, compositionId, objectId, patch, separate); }
  translate(sceneId: string, compositionId: string, starts: Record<string, { x: number; y: number }>, dx: number, dy: number) { return commands.translate(this, sceneId, compositionId, starts, dx, dy); }
  addObject(sceneId: string, compositionId: string, kind: ObjectKind, patch: Partial<ObjectState> = {}, image?: ImageAsset, imageName?: string): string { return commands.addObject(this, sceneId, compositionId, kind, patch, image, imageName); }
  addMedia(sceneId: string, compositionId: string, asset: MediaAsset, kind: 'audio' | 'video', name: string, start = 0, point?: { x: number; y: number }): { objectId?: string; audioTrackId?: string } { return commands.addMedia(this, sceneId, compositionId, asset, kind, name, start, point); }
  setAudioTrack(sceneId: string, id: string, patch: Partial<Pick<AudioTrack, 'name' | 'start' | 'offset' | 'duration' | 'volume' | 'muted'>>, separate = true) { return commands.setAudioTrack(this, sceneId, id, patch, separate); }
  removeAudioTrack(sceneId: string, id: string) { return commands.removeAudioTrack(this, sceneId, id); }
  setVideoPlayback(sceneId: string, id: string, patch: Partial<MediaPlayback>, separate = true) { return commands.setVideoPlayback(this, sceneId, id, patch, separate); }
  addScene(): string { return commands.addScene(this); }
  addComposition(sceneId: string): string { return commands.addComposition(this, sceneId); }
  setComposition(sceneId: string, id: string, patch: Partial<Pick<Composition, 'name' | 'duration'>>) { return commands.setComposition(this, sceneId, id, patch); }
  setTransitionDuration(sceneId: string, id: string, duration: number) { return commands.setTransitionDuration(this, sceneId, id, duration); }
  setTrack(sceneId: string, transitionId: string, objectId: string, patch: Partial<AnimationTrack>, separate = true) { return commands.setTrack(this, sceneId, transitionId, objectId, patch, separate); }
  setPropertyTiming(sceneId: string, transitionId: string, objectId: string, channel: PropertyChannel, timing: AnimationTiming | null, separate = true) { return commands.setPropertyTiming(this, sceneId, transitionId, objectId, channel, timing, separate); }
  linkedIds(sceneId: string, selected: string[]): string[] { return commands.linkedIds(this, sceneId, selected); }
  link(sceneId: string, ids: string[]) { return commands.link(this, sceneId, ids); }
  unlink(sceneId: string, ids: string[]) { return commands.unlink(this, sceneId, ids); }
  hide(sceneId: string, compositionId: string, ids: string[]) { return commands.hide(this, sceneId, compositionId, ids); }
  duplicate(sceneId: string, compositionId: string, ids: string[]): string[] { return commands.duplicate(this, sceneId, compositionId, ids); }
  paste(sceneId: string, compositionId: string, clipboard: ObjectClipboard, offset = 24): string[] { return commands.paste(this, sceneId, compositionId, clipboard, offset); }
  applyProposal(proposal: EditProposal) { return commands.applyProposal(this, proposal); }
}
