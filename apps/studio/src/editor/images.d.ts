import type { Project, SceneObject } from '../../shared/model';
export declare const IMAGE_FILE_LIMIT: number;
export declare const IMAGE_ACCEPT = "image/png,image/jpeg,image/webp";
export declare const normalizeImage: (file: File) => Promise<{
    blob: Blob;
    width: number;
    height: number;
}>;
export declare const uploadImage: (room: string, blob: Blob, signal?: AbortSignal) => Promise<string>;
export declare const portableProject: (project: Project, signal?: AbortSignal) => Promise<Project>;
export declare const storeProjectImages: (project: Project, room: string, signal?: AbortSignal) => Promise<Project>;
export declare const rehostImageAssets: (objects: SceneObject[], room: string, signal?: AbortSignal) => Promise<void>;
