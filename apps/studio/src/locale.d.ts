import type { Locale } from '../shared/locale';
export { resolveLocale, type Locale } from '../shared/locale';
export declare const getLocale: () => Locale;
export declare const applyPageLanguage: (locale: Locale) => void;
type PageCopy = Record<'description' | 'loadError' | 'retryHint' | 'retry' | 'projectError', string>;
export declare const pageCopy: Record<Locale, PageCopy>;
