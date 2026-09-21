import assert from 'node:assert/strict';

// Reuse against the production Node server and local workerd after build:web.
// No JavaScript, accounts, room reads or WebSocket connections are needed.
const origin = process.env.POIETRA_TEST_URL ?? 'http://127.0.0.1:5188';
const request = (path, headers = {}, method = 'GET') => fetch(new URL(path, origin), { method, headers, redirect: 'manual' });
async function page(path, language, headers = {}) {
  const response = await request(path, headers);
  assert.equal(response.status, 200, `${path}: expected direct HTML without redirect`);
  assert.match(response.headers.get('Content-Type') ?? '', /^text\/html/);
  assert.equal(response.headers.get('Content-Language'), language);
  assert.match(response.headers.get('Vary') ?? '', /Accept-Language/);
  assert.match(response.headers.get('Vary') ?? '', /Accept(?:,|$)/);
  const html = await response.text();
  assert.match(html, new RegExp(`<html[^>]*lang=["']${language}["']`));
  assert.match(html, /<h1\b/);
  assert.match(html, language === 'ja' ? /共有リンク/ : /shared link/i);
  assert.match(html, /rel=["']canonical["']/);
  assert.doesNotMatch(html, /<div id=["']root["']><\/div>/);
  assert.doesNotMatch(response.headers.get('X-Robots-Tag') ?? '', /noindex/);
  return html;
}

await page('/', 'en', { 'Accept-Language': 'en-US' });
await page('/', 'ja', { 'Accept-Language': 'ja-JP, en;q=0.8' });
await page('/?lang=en', 'en', { 'Accept-Language': 'ja-JP' });
await page('/?lang=ja', 'ja', { 'Accept-Language': 'en-US' });
await page('/ja/', 'ja', { 'Accept-Language': 'en-US' });
await page('/index.html?lang=ja', 'ja');
console.log('PASS: raw HTML contains localized homepage content and metadata');

for (const [path, language] of [['/', 'en'], ['/?lang=ja', 'ja'], ['/ja/', 'ja']]) {
  const response = await request(path, { Accept: 'text/markdown' });
  assert.equal(response.status, 200);
  assert.match(response.headers.get('Content-Type') ?? '', /^text\/markdown/);
  assert.equal(response.headers.get('Content-Language'), language);
  const markdown = await response.text();
  assert.match(markdown, /^# /m);
  assert.doesNotMatch(markdown, /<html/);
}
for (const Accept of ['text/markdown;q=0, text/html', 'text/markdown;q=0.2,text/html;q=0.9', '*/*']) {
  assert.match((await request('/', { Accept })).headers.get('Content-Type') ?? '', /^text\/html/);
}
console.log('PASS: explicit Markdown negotiation and HTML quality/exclusions');

for (const [path, language] of [['/developers', 'en'], ['/developers/', 'en'], ['/developers/index.html?lang=ja', 'ja'], ['/ja/developers/', 'ja']]) {
  const response = await request(path);
  assert.equal(response.status, 200, path);
  assert.equal(response.headers.get('Content-Language'), language);
  assert.match(response.headers.get('Content-Type') ?? '', /^text\/html/);
  assert.match(response.headers.get('Link') ?? '', /\/openapi\.json.*service-desc/);
  const html = await response.text();
  assert.match(html, /<h1\b/);
  assert.match(html, /hello\.poietra\.json/);
  assert.doesNotMatch(html, /<script[^>]*\bsrc=/);
  const head = await request(path, {}, 'HEAD');
  assert.equal(head.status, 200); assert.equal(await head.text(), '');
}
for (const [path, language, headers] of [
  ['/developers/', 'ja', { Accept: 'text/markdown', 'Accept-Language': 'ja' }],
  ['/developers/index.md', 'en', { Accept: 'text/html' }],
  ['/ja/developers/index.md', 'ja', { Accept: 'text/html' }],
]) {
  const response = await request(path, headers);
  assert.equal(response.status, 200, path);
  assert.equal(response.headers.get('Content-Language'), language);
  assert.match(response.headers.get('Content-Type') ?? '', /^text\/markdown/);
  assert.match(response.headers.get('Vary') ?? '', /Accept/);
  const markdown = await response.text();
  assert.match(markdown, /poietra:\/\/docs\/project-schema/);
  assert.doesNotMatch(markdown, /<html/);
  const etag = response.headers.get('ETag');
  if (etag) {
    const cached = await request(path, { ...headers, 'If-None-Match': etag });
    assert.equal(cached.status, 304); assert.equal(await cached.text(), '');
    assert.equal(cached.headers.get('Content-Language'), language);
  }
}
for (const path of ['/openapi.json', '/schemas/project.json', '/examples/hello.poietra.json', '/developers/mcp-config.json']) {
  const response = await request(path);
  assert.equal(response.status, 200, path);
  assert.match(response.headers.get('Content-Type') ?? '', /application\/(?:schema\+)?json/);
  assert.ok(await response.json());
  // Static Assets applies _headers; the local Node host has no cross-origin deployment.
  if (process.env.POIETRA_TEST_STATIC_HEADERS === '1') {
    assert.equal(response.headers.get('Access-Control-Allow-Origin'), '*');
    assert.equal(response.headers.get('X-Content-Type-Options'), 'nosniff');
  }
}
assert.equal((await request('/developers/not-a-page')).status, 404);
console.log('PASS: developer HTML/Markdown, HEAD/cache validators and machine-readable contracts');

for (const path of ['/?room=seo-untouched-room-123456', '/?projects=1', '/?auth_error=denied', '/studio', '/studio/', '/studio/index.html', '/index.html?room=seo-untouched-room-123456', '/ja/?room=seo-untouched-room-123456']) {
  const response = await request(path, { Accept: 'text/markdown' });
  assert.equal(response.status, 200, path);
  assert.equal(response.headers.get('Location'), null, path);
  assert.match(response.headers.get('Content-Type') ?? '', /^text\/html/);
  assert.match(response.headers.get('X-Robots-Tag') ?? '', /noindex/);
  assert.match(response.headers.get('Cache-Control') ?? '', /no-store/);
  const html = await response.text();
  assert.doesNotMatch(html, /class=["'][^"']*landing-page/);
  assert.match(html, /name=["']robots["'][^>]*noindex/);
}
console.log('PASS: all shared/editor/callback routes stay HTML and noindex without redirects');

const head = await request('/?lang=ja', {}, 'HEAD');
assert.equal(head.status, 200); assert.equal(head.headers.get('Content-Language'), 'ja'); assert.equal(await head.text(), '');
const missing = await request('/this-route-does-not-exist-seo-check');
assert.equal(missing.status, 404);
const robots = await request('/robots.txt'); assert.equal(robots.status, 200); assert.match(robots.headers.get('Content-Type') ?? '', /^text\/plain/);
const sitemap = await request('/sitemap.xml'); assert.equal(sitemap.status, 200); assert.match(sitemap.headers.get('Content-Type') ?? '', /(?:application|text)\/xml/);
assert.doesNotMatch(await sitemap.text(), /room=|projects=|auth_error=|\/studio/);
console.log('PASS: HEAD, real 404 and public-only crawl discovery files');
