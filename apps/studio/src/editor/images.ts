import * as media from '../../../../_build/js/release/build/browser_media/browser_media.js';
import * as projects from '../../../../_build/js/release/build/browser_projects/browser_projects.js';
import { blobDataUrl, imageBlob } from '../engine/rendering/image-source';
import type { Project, SceneObject } from '../../shared/model';
import { mediaBlob, prepareMedia, uploadMedia } from './media';

export const IMAGE_FILE_LIMIT = 20 * 1024 * 1024;
export const IMAGE_ACCEPT = 'image/png,image/jpeg,image/webp';
export const normalizeImage: (file: File) => Promise<{ blob: Blob; width: number; height: number }> = media.normalizeImage;
export const uploadImage: (room: string, blob: Blob, signal?: AbortSignal) => Promise<string> = media.uploadImage;

// Explicit I/O boundary; asset validation, ownership and batch publication live in MoonBit.
const io = { blobDataUrl, imageBlob, mediaBlob, prepareMedia, uploadMedia, uploadImage };
export const portableProject = (project: Project, signal?: AbortSignal): Promise<Project> => projects.portableProject(project, signal, io);
export const storeProjectImages = (project: Project, room: string, signal?: AbortSignal): Promise<Project> => projects.storeProjectImages(project, room, signal, io);
export const rehostImageAssets = (objects: SceneObject[], room: string, signal?: AbortSignal): Promise<void> => projects.rehostImageAssets(objects, room, signal, io);
