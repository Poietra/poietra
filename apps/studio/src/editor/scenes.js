import * as Y from "yjs";
import * as moonbit from "../../../../_build/js/release/build/boundary/boundary.js";
export const renameScene = (doc, sceneId, name) => moonbit.renameScene(doc, sceneId, name, Y);
export const duplicateScene = (doc, sceneId) => moonbit.duplicateScene(doc, sceneId, Y);
export const deleteScene = (doc, sceneId) => moonbit.deleteScene(doc, sceneId, Y);
export const moveScene = (doc, sceneId, direction) => moonbit.moveScene(doc, sceneId, direction, Y);
