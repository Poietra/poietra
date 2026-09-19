import type { Locale } from './locale';
import * as moon from '../../../_build/js/release/build/browser_site/browser_site.js';
import './home-fonts.css';
import './ui/LandingPage.css';
const runtime = {
  loadProjects: () => import('./editor/projects'),
  loadSamples: () => import('../shared/demo'),
};
export const Home = (props: { initialLocale?: Locale }) => moon.Home({ ...props, runtime });
export const homeTree = (initialLocale?: Locale) => moon.homeTree(initialLocale, runtime);
export function openHome(container: HTMLElement) { moon.openHome(container, runtime); }
