import * as shell from "../../../_build/js/release/build/site_shell/site_shell.js";
export { resolveLocale } from "../shared/locale.js";
export const getLocale = shell.getLocale;
export const applyPageLanguage = shell.applyPageLanguage;
export const pageCopy = { en: shell.pageCopy('en'), ja: shell.pageCopy('ja') };
