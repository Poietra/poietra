import * as moon from "../../../_build/js/release/build/browser_site/browser_site.js";
import "./home-fonts.css";
import "./ui/LandingPage.css";
const runtime = {
    loadProjects: () => import("./editor/projects.js"),
    loadSamples: () => import("../shared/demo.js"),
};
export const Home = (props) => moon.Home({ ...props, runtime });
export const homeTree = (initialLocale) => moon.homeTree(initialLocale, runtime);
export function openHome(container) { moon.openHome(container, runtime); }
