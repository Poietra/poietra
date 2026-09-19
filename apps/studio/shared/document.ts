import * as Y from 'yjs';
import type { Project } from './model';
import * as moonbit from '../../../_build/js/release/build/boundary/boundary.js';

export type Path = (string | number)[];
export type Change = { path: string[]; value: unknown };
export const LOCAL_ORIGIN = 'poietra-local';

// Runtime binding only. Projection, parent migration, atomic preparation and
// snapshot invalidation are implemented in MoonBit.
export const toShared = (value: unknown): unknown => moonbit.toShared(value, Y);
export const initializeDocument = (doc: Y.Doc, project: Project): void => moonbit.initializeDocument(doc, project, Y);
export const ensureSceneAudioTracks = (doc: Y.Doc): boolean => moonbit.ensureSceneAudioTracks(doc, Y);
export const ensureSceneAnimationTracks = (doc: Y.Doc): boolean => moonbit.ensureSceneAnimationTracks(doc, Y);
/** Immutable snapshot. Clone before editing outside the shared command API. */
export const readProject = (doc: Y.Doc): Project | null => moonbit.readProject(doc, Y);
export const getShared = (doc: Y.Doc, path: string[]): unknown => moonbit.getShared(doc, path, Y);
export const getValue = (doc: Y.Doc, path: string[]): unknown => moonbit.getValue(doc, path, Y);
export const applyChanges = (doc: Y.Doc, changes: Change[], origin: unknown = LOCAL_ORIGIN): void => moonbit.applyChanges(doc, changes, origin, Y);
export const changesFor = (base: string[], values: object): Change[] => moonbit.changesFor(base, values);
