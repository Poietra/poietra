import * as media from "../../../../_build/js/release/build/browser_media/browser_media.js";
import * as projects from "../../../../_build/js/release/build/browser_projects/browser_projects.js";
import { blobDataUrl, imageBlob } from "../engine/rendering/image-source.js";
import { mediaBlob, prepareMedia, uploadMedia } from "./media.js";
export const IMAGE_FILE_LIMIT = 20 * 1024 * 1024;
export const IMAGE_ACCEPT = 'image/png,image/jpeg,image/webp';
export const normalizeImage = media.normalizeImage;
export const uploadImage = media.uploadImage;
// Explicit I/O boundary; asset validation, ownership and batch publication live in MoonBit.
const io = { blobDataUrl, imageBlob, mediaBlob, prepareMedia, uploadMedia, uploadImage };
export const portableProject = (project, signal) => projects.portableProject(project, signal, io);
export const storeProjectImages = (project, room, signal) => projects.storeProjectImages(project, room, signal, io);
export const rehostImageAssets = (objects, room, signal) => projects.rehostImageAssets(objects, room, signal, io);
