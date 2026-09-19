export type Locale = 'en' | 'ja';
export declare const resolveLocale: (preferences?: {
    query?: string | null;
    stored?: string | null;
    languages?: readonly string[];
}) => Locale;
