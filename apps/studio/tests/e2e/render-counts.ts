import type { Page } from '@playwright/test';

// Test-only instrumentation of pinned MoonBit output. Count actual function
// invocations, including StrictMode/retries, without shipping diagnostics.
const components = ['studio', 'sidebar', 'inspector', 'timeline', 'stage', 'assistant__panel', 'studio__dialogs', 'studio__main', 'scene__tabs', 'media__timeline'];
declare global { interface Window { renderCounts: Record<string, number> } }

export async function countEditorRenders(page: Page) {
  await page.route('**/_build/js/release/build/ui/ui.js*', async route => {
    const response = await route.fetch();
    let source = await response.text();
    for (const name of components) {
      const pattern = new RegExp('(function _M0FP37poietra7poietra2ui[0-9]+' + name + '\\([^)]*\\) \\{)');
      if (!pattern.test(source)) throw new Error('Missing render probe: ' + name);
      source = source.replace(pattern, '$1\n globalThis.renderCounts ??= {}; globalThis.renderCounts["' + name + '"] = (globalThis.renderCounts["' + name + '"] || 0) + 1;');
    }
    await route.fulfill({ response, body: source });
  });
}
