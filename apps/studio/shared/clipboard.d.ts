import type { Change } from './document';
import type { ObjectState, Scene, SceneObject } from './model';
export declare const OBJECT_CLIPBOARD_PREFIX = "POIETRA_OBJECTS_V1\n";
export declare const OBJECT_CLIPBOARD_MIME = "application/x-poietra-objects+json";
export interface ObjectClipboard {
    objects: SceneObject[];
    states: Record<string, ObjectState>;
}
export declare const copyObjects: (scene: Scene, compositionId: string, ids: string[]) => ObjectClipboard;
export declare const serializeObjects: (clipboard: ObjectClipboard) => string;
export declare const parseObjects: (text: string) => ObjectClipboard | null;
export declare const pasteObjectChanges: (scene: Scene, compositionId: string, clipboard: ObjectClipboard, offset?: number) => {
    ids: string[];
    changes: Change[];
};
