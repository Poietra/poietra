import { startPage } from "../../../_build/js/release/build/site_shell/site_shell.js";
import "./entry.css";
// Keep separate dynamic entries so Vite owns each branch's CSS preload graph.
startPage({
    loadEditor: () => import("./editor/bootstrap.js"),
    loadKernelModule: () => import("./engine/kernel.js"),
    loadHome: () => import("./home.js"),
});
