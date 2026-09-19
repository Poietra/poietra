import { renderToString } from "react-dom/server";
import { homeTree } from "./home.js";
import { pageCopy } from "./locale.js";
import { renderMarkdown as markdown } from "../../../_build/js/release/build/browser_site/browser_site.js";
export function renderHome(locale) {
    return { html: renderToString(homeTree(locale)), description: pageCopy[locale].description };
}
export const renderMarkdown = markdown;
