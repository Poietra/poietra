import { expect, test } from '@playwright/test';

test('developer pages are readable without JS on desktop and mobile and never open editor services', async ({ browser }, info) => {
  const context = await browser.newContext({ javaScriptEnabled: false, locale: 'en-US' });
  const page = await context.newPage();
  const privateRequests: string[] = [], scripts: string[] = [];
  page.on('request', request => {
    const path = new URL(request.url()).pathname;
    if (/^\/(api|sync)\//.test(path)) privateRequests.push(path);
    if (request.resourceType() === 'script') scripts.push(path);
  });
  try {
    for (const [path, lang, title] of [
      ['/developers/?lang=en', 'en', 'Your agent.In motion.'],
      ['/ja/developers/', 'ja', 'エージェントから、動画をつくる。'],
    ] as const) {
      for (const width of [1440, 390]) {
        await page.setViewportSize({ width, height: 1000 });
        const response = await page.goto(path);
        expect(response?.status()).toBe(200);
        await expect(page.locator('html')).toHaveAttribute('lang', lang);
        await expect(page.getByRole('heading', { level: 1 })).toHaveText(title);
        await expect(page.locator('link[rel="service-desc"]')).toHaveAttribute('href', '/openapi.json');
        await expect(page.getByRole('link', { name: /OpenAPI JSON/ })).toBeVisible();
        await expect(page.getByRole('link', { name: 'hello.poietra.json', exact: true })).toHaveAttribute('href', '/examples/hello.poietra.json');
        const overflow = await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
        expect(overflow).toBeLessThanOrEqual(1);
        await page.screenshot({ path: info.outputPath('developers-' + lang + '-' + width + '.png'), fullPage: true });
      }
    }
    expect(privateRequests).toEqual([]); expect(scripts).toEqual([]);
  } finally { await context.close(); }
});

test('agent discovery returns Markdown, OpenAPI, schema and a usable starter file', async ({ request }) => {
  const markdown = await request.get('/developers/', { headers: { Accept: 'text/markdown', 'Accept-Language': 'ja' } });
  expect(markdown.status()).toBe(200);
  expect(markdown.headers()['content-type']).toContain('text/markdown');
  expect(markdown.headers().vary).toContain('Accept');
  expect(markdown.headers().link).toContain('/openapi.json');
  const text = await markdown.text();
  expect(text).toContain('poietra://docs/project-schema');
  expect(text).toContain('ローカル');
  expect(text).not.toContain('<html');
  const spec = await (await request.get('/openapi.json')).json();
  expect(spec.openapi).toBe('3.1.1');
  expect(spec.servers[0].url).toBe('http://127.0.0.1:8799');
  expect(spec.paths['/render'].post.requestBody.content['application/json'].schema.$ref).toContain('Project');
  expect((await (await request.get('/schemas/project.json')).json()).$defs.SceneObject).toBeTruthy();
  const example = await (await request.get('/examples/hello.poietra.json')).json();
  expect(example.version).toBe(2); expect(example.sceneOrder).toEqual(['hello']);
  const config = await (await request.get('/developers/mcp-config.json')).json();
  expect(config.mcpServers.poietra.args[0]).toContain('/apps/render/mcp.mjs');
  expect(await (await request.get('/llms.txt')).text()).toContain('https://poietra.com/openapi.json');
  expect(await (await request.get('/sitemap.xml')).text()).toContain('https://poietra.com/developers/');
  expect((await request.get('/developers/not-a-page')).status()).toBe(404);
});
