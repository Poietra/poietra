import * as Y from "yjs";
import * as moonbit from "../../../_build/js/release/build/boundary/boundary.js";
export const LOCAL_ORIGIN = 'poietra-local';
// Runtime binding only. Projection, parent migration, atomic preparation and
// snapshot invalidation are implemented in MoonBit.
export const toShared = (value) => moonbit.toShared(value, Y);
export const initializeDocument = (doc, project) => moonbit.initializeDocument(doc, project, Y);
export const ensureSceneAudioTracks = (doc) => moonbit.ensureSceneAudioTracks(doc, Y);
export const ensureSceneAnimationTracks = (doc) => moonbit.ensureSceneAnimationTracks(doc, Y);
/** Immutable snapshot. Clone before editing outside the shared command API. */
export const readProject = (doc) => moonbit.readProject(doc, Y);
export const getShared = (doc, path) => moonbit.getShared(doc, path, Y);
export const getValue = (doc, path) => moonbit.getValue(doc, path, Y);
export const applyChanges = (doc, changes, origin = LOCAL_ORIGIN) => moonbit.applyChanges(doc, changes, origin, Y);
export const changesFor = (base, values) => moonbit.changesFor(base, values);
