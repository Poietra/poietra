import { openEditor as open } from "../../../../_build/js/release/build/site_shell/site_shell.js";
import "@fontsource/inter/400.css";
import "@fontsource/inter/500.css";
import "@fontsource/inter/600.css";
import "@fontsource/noto-sans-jp/400.css";
import { App } from "../App.js";
import { EditorStore, currentRoom } from "./store.js";
import * as renderer from "../engine/renderer.js";
import * as exporter from "../engine/export.js";
import { createFramePainter } from "../engine/painter.js";
import "../styles.css";
export function openEditor(root, kernel) {
    open(root, kernel, { EditorStore, currentRoom, App, renderer, exporter, createFramePainter });
}
