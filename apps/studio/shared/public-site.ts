import type { Locale } from './locale';
import * as moon from '../../../_build/js/release/build/http_runtime/http_runtime.js';

export interface PublicPagePlan {
  kind: 'home' | 'editor';
  locale: Locale;
  assetPath: string;
  contentType: string;
  headers: Record<string, string>;
}

export const prefersMarkdown: (accept: string | null) => boolean = moon.prefersMarkdown;
export const publicPagePlan: (url: URL, headers: Headers) => PublicPagePlan | null = moon.publicPagePlan;
export const fetchPublicPage: (request: Request, fetchAsset: (request: Request) => Promise<Response>) => Promise<Response | null> = moon.fetchPublicPage;
