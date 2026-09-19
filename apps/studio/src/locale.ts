import * as shell from '../../../_build/js/release/build/site_shell/site_shell.js';
import type { Locale } from '../shared/locale';
export { resolveLocale, type Locale } from '../shared/locale';
export const getLocale = shell.getLocale as () => Locale;
export const applyPageLanguage = shell.applyPageLanguage as (locale: Locale) => void;
type PageCopy = Record<'description' | 'loadError' | 'retryHint' | 'retry' | 'projectError', string>;
export const pageCopy: Record<Locale, PageCopy> = { en: shell.pageCopy('en'), ja: shell.pageCopy('ja') };
