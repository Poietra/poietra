import type { Locale } from './locale';
export interface PublicPagePlan {
    kind: 'home' | 'editor' | 'developers';
    locale: Locale;
    assetPath: string;
    contentType: string;
    headers: Record<string, string>;
}
export declare const prefersMarkdown: (accept: string | null) => boolean;
export declare const publicPagePlan: (url: URL, headers: Headers) => PublicPagePlan | null;
export declare const fetchPublicPage: (request: Request, fetchAsset: (request: Request) => Promise<Response>) => Promise<Response | null>;
