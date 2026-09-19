// Read-only differential oracle: shared HTTP policy at 198004b.
import { resolveLocale, type Locale } from '../../shared/locale.js';

export interface PublicPagePlan {
  kind: 'home' | 'editor';
  locale: Locale;
  assetPath: string;
  contentType: string;
  headers: Record<string, string>;
}

function weightedValues(header: string | null): Array<{ value: string; quality: number }> {
  return (header ?? '').split(',').map(part => {
    const [value, ...parameters] = part.trim().split(';');
    const qualityParameter = parameters.map(parameter => parameter.trim()).find(parameter => /^q\s*=/i.test(parameter));
    const rawQuality = qualityParameter?.slice(qualityParameter.indexOf('=') + 1).trim();
    const quality = rawQuality === undefined ? 1 : /^(?:0(?:\.\d{0,3})?|1(?:\.0{0,3})?)$/.test(rawQuality) ? Number(rawQuality) : 0;
    return { value: value.toLowerCase(), quality };
  }).filter(entry => entry.value);
}

/** Markdown is opt-in. An explicit exclusion beats a less-specific wildcard. */
export function prefersMarkdown(accept: string | null): boolean {
  const values = weightedValues(accept);
  const markdown = values.find(entry => entry.value === 'text/markdown')?.quality ?? 0;
  const html = ['text/html', 'text/*', '*/*'].map(value => values.find(entry => entry.value === value)?.quality).find(quality => quality !== undefined) ?? 0;
  return markdown > 0 && markdown >= html;
}

/** Public entry routes only: assets, API endpoints and unknown paths pass through. */
export function publicPagePlan(url: URL, headers: Headers): PublicPagePlan | null {
  if (!['/', '/index.html', '/ja', '/ja/', '/ja/index.html', '/studio', '/studio/', '/studio/index.html'].includes(url.pathname)) return null;
  const editor = url.pathname.startsWith('/studio') || ['room', 'projects', 'auth_error'].some(key => url.searchParams.has(key));
  if (editor) return {
    kind: 'editor', locale: 'ja', assetPath: '/studio/index.html', contentType: 'text/html; charset=utf-8',
    headers: { 'X-Robots-Tag': 'noindex, nofollow', 'Cache-Control': 'private, no-store' },
  };
  const languages = weightedValues(headers.get('Accept-Language')).filter(entry => entry.quality > 0).sort((a, b) => b.quality - a.quality).map(entry => entry.value);
  const query = url.searchParams.get('lang');
  const locale = resolveLocale({ query: query === 'en' || query === 'ja' ? query : url.pathname.startsWith('/ja') ? 'ja' : null, languages });
  const markdown = prefersMarkdown(headers.get('Accept'));
  return {
    kind: 'home', locale,
    assetPath: `${locale === 'ja' ? '/ja' : ''}/index.${markdown ? 'md' : 'html'}`,
    contentType: `${markdown ? 'text/markdown' : 'text/html'}; charset=utf-8`,
    headers: { 'Content-Language': locale, Vary: 'Accept, Accept-Language', 'Cache-Control': 'public, max-age=0, must-revalidate' },
  };
}


export type ByteRange = { start: number; end: number };
/** Single RFC byte range. Multiple/invalid/unsatisfiable ranges return null (416). */
export function mediaByteRange(header: string, size: number): ByteRange | null {
  const match = /^bytes=(\d*)-(\d*)$/i.exec(header.trim());
  if (!match || !size || !match[1] && !match[2]) return null;
  if (!match[1]) {
    const length = Number(match[2]);
    return Number.isSafeInteger(length) && length > 0 ? { start: Math.max(0, size - length), end: size - 1 } : null;
  }
  const start = Number(match[1]), end = match[2] ? Number(match[2]) : size - 1;
  return Number.isSafeInteger(start) && Number.isSafeInteger(end) && start >= 0 && start < size && end >= start ? { start, end: Math.min(size - 1, end) } : null;
}
export const mediaHeaders = (mime: string, digest: string) => ({
  'Content-Type': mime, 'Accept-Ranges': 'bytes', ETag: `"${digest}"`,
  'Cache-Control': 'private, max-age=31536000, immutable', 'X-Content-Type-Options': 'nosniff',
  'Content-Security-Policy': "default-src 'none'", 'Cross-Origin-Resource-Policy': 'same-origin',
});

/** The two storage backends share precisely the same HTTP range semantics. */
export function mediaResponsePlan(request: { range: string | null; ifRange: string | null; ifNoneMatch: string | null }, metadata: { size: number; mime: string }, digest: string): { status: number; headers: Record<string, string>; range?: ByteRange } {
  const headers: Record<string, string> = mediaHeaders(metadata.mime, digest);
  if (request.ifNoneMatch?.split(',').some(value => value.trim().replace(/^W\//, '') === headers.ETag || value.trim() === '*')) return { status: 304, headers };
  let range: ByteRange = { start: 0, end: metadata.size - 1 }, status = 200;
  if (request.range && /^bytes=/i.test(request.range.trim()) && (!request.ifRange || request.ifRange === headers.ETag)) {
    const requested = mediaByteRange(request.range, metadata.size);
    if (!requested) return { status: 416, headers: { ...headers, 'Content-Range': `bytes */${metadata.size}`, 'Content-Length': '0' } };
    range = requested; status = 206;
    headers['Content-Range'] = `bytes ${range.start}-${range.end}/${metadata.size}`;
  }
  headers['Content-Length'] = String(range.end - range.start + 1);
  return { status, headers, range };
}
