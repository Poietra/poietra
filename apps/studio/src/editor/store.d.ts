import type { Keyframe } from "../../shared/scene-types";
import * as Y from 'yjs';
import { WebsocketProvider } from 'y-websocket';
import { IndexeddbPersistence } from 'y-indexeddb';
import type { Change } from '../../shared/document';
import { type AnimationTiming, type PropertyChannel, type AnimationTrack, type Composition, type ObjectKind, type ObjectState, type Project, type Scene, type SceneObject } from '../../shared/model';
import { applyProposal, type EditProposal } from '../../shared/ai';
import { RoomChat } from '../../shared/chat';
import type { ImageAsset } from '../../shared/images';
import type { AudioTrack, MediaAsset, MediaPlayback } from '../../shared/media';
import type { ObjectClipboard } from '../../shared/clipboard';
import { EditorUndoManager } from './undo';
export interface Peer {
    clientId: number;
    name: string;
    color: string;
    sceneId?: string;
    compositionId?: string;
    selectedIds?: string[];
    cursor?: {
        x: number;
        y: number;
    } | null;
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
export declare const currentRoom: () => string;
export declare class EditorStore {
    readonly roomId: string;
    readonly doc: Y.Doc;
    readonly chat: RoomChat;
    readonly chatAuthorId: string;
    readonly provider: WebsocketProvider;
    readonly persistence: IndexeddbPersistence;
    readonly undoManager: EditorUndoManager;
    readonly color: string;
    userName: string;
    get runtime(): {
        Y: typeof Y;
        colors: string[];
        applyProposal: typeof applyProposal;
        RoomChat: new (doc: Y.Doc) => RoomChat;
        EditorUndoManager: typeof EditorUndoManager;
        WebsocketProvider: typeof WebsocketProvider;
        IndexeddbPersistence: typeof IndexeddbPersistence;
    };
    constructor(roomId: string);
    subscribe: (listener: () => void) => (() => void);
    snapshot: () => EditorSnapshot;
    retryConnection: () => void;
    setName(name: string): undefined;
    presence(state: Partial<Peer>): undefined;
    beginGesture(): undefined;
    endGesture(): undefined;
    get lastUndoPreservedObjects(): number;
    get lastUndoPreservedAudioTracks(): number;
    get lastUndoPreservedCompositions(): number;
    get lastUndoPreservedDurations(): number;
    undo(): number;
    redo(): number;
    rollbackGesture(item: object): boolean;
    edit(changes: Change[], separate?: boolean): undefined;
    project(): Project;
    scene(id: string): Scene;
    setProjectName(name: string): undefined;
    setScene(sceneId: string, patch: Partial<Pick<Scene, 'name' | 'background'>>): undefined;
    setObject(sceneId: string, id: string, patch: Partial<SceneObject>): undefined;
    updateState(sceneId: string, compositionId: string, objectId: string, patch: Partial<ObjectState>, separate?: boolean): undefined;
    translate(sceneId: string, compositionId: string, starts: Record<string, {
        x: number;
        y: number;
    }>, dx: number, dy: number): undefined;
    addObject(sceneId: string, compositionId: string, kind: ObjectKind, patch?: Partial<ObjectState>, image?: ImageAsset, imageName?: string): string;
    addMedia(sceneId: string, compositionId: string, asset: MediaAsset, kind: 'audio' | 'video', name: string, start?: number, point?: {
        x: number;
        y: number;
    }): {
        objectId?: string;
        audioTrackId?: string;
    };
    setAudioTrack(sceneId: string, id: string, patch: Partial<Pick<AudioTrack, 'name' | 'start' | 'offset' | 'duration' | 'volume' | 'muted'>>, separate?: boolean): undefined;
    removeAudioTrack(sceneId: string, id: string): undefined;
    setVideoPlayback(sceneId: string, id: string, patch: Partial<MediaPlayback>, separate?: boolean): undefined;
    addScene(): string;
    addComposition(sceneId: string): string;
    setComposition(sceneId: string, id: string, patch: Partial<Pick<Composition, 'name' | 'duration'>>): undefined;
    setTransitionDuration(sceneId: string, id: string, duration: number): undefined;
    setKeyframe(sceneId: string, transitionId: string, objectId: string, id: string, patch: Partial<Keyframe> | null, separate?: boolean): undefined;
    setParent(sceneId: string, objectId: string, parentId: string | null): undefined;
    setAnchor(sceneId: string, compositionId: string, objectId: string, x: number, y: number): undefined;
    setTrack(sceneId: string, transitionId: string, objectId: string, patch: Partial<AnimationTrack>, separate?: boolean): undefined;
    setPropertyTiming(sceneId: string, transitionId: string, objectId: string, channel: PropertyChannel, timing: AnimationTiming | null, separate?: boolean): undefined;
    linkedIds(sceneId: string, selected: string[]): string[];
    link(sceneId: string, ids: string[]): undefined;
    unlink(sceneId: string, ids: string[]): undefined;
    hide(sceneId: string, compositionId: string, ids: string[]): undefined;
    duplicate(sceneId: string, compositionId: string, ids: string[]): string[];
    paste(sceneId: string, compositionId: string, clipboard: ObjectClipboard, offset?: number): string[];
    applyProposal(proposal: EditProposal): undefined;
}
