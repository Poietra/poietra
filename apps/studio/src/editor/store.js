import * as commands from "../../../../_build/js/release/build/browser_editor/browser_editor.js";
import * as Y from "yjs";
import { WebsocketProvider } from "y-websocket";
import { IndexeddbPersistence } from "y-indexeddb";
import { COLORS } from "../../shared/model.js";
import { applyProposal } from "../../shared/ai.js";
import { RoomChat } from "../../shared/chat.js";
import { EditorUndoManager } from "./undo.js";
const runtime = { Y, colors: COLORS, applyProposal, RoomChat, EditorUndoManager, WebsocketProvider, IndexeddbPersistence };
const subscribe = commands.subscribe;
export const currentRoom = commands.currentRoom;
// Constructor/prototype signatures adapt existing consumers and tests to the
// MoonBit-owned session and typed command plans. Native dependencies stay injectable.
export class EditorStore {
    roomId;
    get runtime() { return runtime; }
    constructor(roomId) {
        this.roomId = roomId;
        commands.createStore(this, roomId);
    }
    subscribe = (listener) => subscribe(this, listener);
    snapshot = () => commands.snapshot(this);
    retryConnection = () => commands.retryConnection(this);
    setName(name) { return commands.setName(this, name); }
    presence(state) { return commands.presence(this, state); }
    beginGesture() { return commands.beginGesture(this); }
    endGesture() { return commands.endGesture(this); }
    get lastUndoPreservedObjects() { return this.undoManager.lastUndoPreservedObjects; }
    get lastUndoPreservedAudioTracks() { return this.undoManager.lastUndoPreservedAudioTracks; }
    get lastUndoPreservedCompositions() { return this.undoManager.lastUndoPreservedCompositions; }
    get lastUndoPreservedDurations() { return this.undoManager.lastUndoPreservedDurations; }
    undo() { return commands.undoEdit(this); }
    redo() { return commands.redoEdit(this); }
    rollbackGesture(item) { return commands.rollbackGesture(this, item); }
    edit(changes, separate = true) { return commands.editBatch(this, changes, separate); }
    project() { return commands.project(this); }
    scene(id) { return commands.scene(this, id); }
    setProjectName(name) { return commands.setProjectName(this, name); }
    setScene(sceneId, patch) { return commands.setScene(this, sceneId, patch); }
    setObject(sceneId, id, patch) { return commands.setObject(this, sceneId, id, patch); }
    updateState(sceneId, compositionId, objectId, patch, separate = true) { return commands.updateState(this, sceneId, compositionId, objectId, patch, separate); }
    translate(sceneId, compositionId, starts, dx, dy) { return commands.translate(this, sceneId, compositionId, starts, dx, dy); }
    addObject(sceneId, compositionId, kind, patch = {}, image, imageName) { return commands.addObject(this, sceneId, compositionId, kind, patch, image, imageName); }
    addMedia(sceneId, compositionId, asset, kind, name, start = 0, point) { return commands.addMedia(this, sceneId, compositionId, asset, kind, name, start, point); }
    setAudioTrack(sceneId, id, patch, separate = true) { return commands.setAudioTrack(this, sceneId, id, patch, separate); }
    removeAudioTrack(sceneId, id) { return commands.removeAudioTrack(this, sceneId, id); }
    setVideoPlayback(sceneId, id, patch, separate = true) { return commands.setVideoPlayback(this, sceneId, id, patch, separate); }
    addScene() { return commands.addScene(this); }
    addComposition(sceneId) { return commands.addComposition(this, sceneId); }
    setComposition(sceneId, id, patch) { return commands.setComposition(this, sceneId, id, patch); }
    setTransitionDuration(sceneId, id, duration) { return commands.setTransitionDuration(this, sceneId, id, duration); }
    setKeyframe(sceneId, transitionId, objectId, id, patch, separate = true) { return commands.setKeyframe(this, sceneId, transitionId, objectId, id, patch, separate); }
    setParent(sceneId, objectId, parentId) { return commands.setParent(this, sceneId, objectId, parentId); }
    setAnchor(sceneId, compositionId, objectId, x, y) { return commands.setAnchor(this, sceneId, compositionId, objectId, x, y); }
    setTrack(sceneId, transitionId, objectId, patch, separate = true) { return commands.setTrack(this, sceneId, transitionId, objectId, patch, separate); }
    setPropertyTiming(sceneId, transitionId, objectId, channel, timing, separate = true) { return commands.setPropertyTiming(this, sceneId, transitionId, objectId, channel, timing, separate); }
    linkedIds(sceneId, selected) { return commands.linkedIds(this, sceneId, selected); }
    link(sceneId, ids) { return commands.link(this, sceneId, ids); }
    unlink(sceneId, ids) { return commands.unlink(this, sceneId, ids); }
    hide(sceneId, compositionId, ids) { return commands.hide(this, sceneId, compositionId, ids); }
    duplicate(sceneId, compositionId, ids) { return commands.duplicate(this, sceneId, compositionId, ids); }
    paste(sceneId, compositionId, clipboard, offset = 24) { return commands.paste(this, sceneId, compositionId, clipboard, offset); }
    applyProposal(proposal) { return commands.applyProposal(this, proposal); }
}
