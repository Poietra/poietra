import { resolveLocale as resolve } from '../../../_build/js/release/build/site_boundary/site_boundary.js';
export type Locale = 'en' | 'ja';
export const resolveLocale = resolve as (preferences?: { query?: string | null; stored?: string | null; languages?: readonly string[] }) => Locale;
