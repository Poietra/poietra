import { renderToString } from 'react-dom/server';
import { homeTree } from './home';
import { pageCopy, type Locale } from './locale';
import { renderMarkdown as markdown } from '../../../_build/js/release/build/browser_site/browser_site.js';
export function renderHome(locale: Locale) {
  return { html: renderToString(homeTree(locale)), description: pageCopy[locale].description };
}
export const renderMarkdown = markdown as (locale: Locale) => string;
