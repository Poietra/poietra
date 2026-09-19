import * as shell from '../../../_build/js/release/build/site_shell/site_shell.js';
export const isEditorLocation = shell.isEditorLocation as (url: URL) => boolean;
export const lastRoom = shell.lastRoom as () => string | null;
export const roomLink = shell.roomLink as (room: string) => string;
