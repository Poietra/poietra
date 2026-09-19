import type { Change } from './document';
import type { ObjectState, Scene, SceneObject } from './model';
import * as moon from '../../../_build/js/release/build/boundary/boundary.js';
export const OBJECT_CLIPBOARD_PREFIX = 'POIETRA_OBJECTS_V1\n';
export const OBJECT_CLIPBOARD_MIME = 'application/x-poietra-objects+json';
export interface ObjectClipboard { objects: SceneObject[]; states: Record<string, ObjectState> }
export const copyObjects: (scene: Scene, compositionId: string, ids: string[]) => ObjectClipboard = moon.copyObjects;
export const serializeObjects: (clipboard: ObjectClipboard) => string = moon.serializeObjects;
export const parseObjects: (text: string) => ObjectClipboard | null = moon.parseObjects;
export const pasteObjectChanges: (scene: Scene, compositionId: string, clipboard: ObjectClipboard, offset?: number) => { ids: string[]; changes: Change[] } = moon.pasteObjectChanges;
