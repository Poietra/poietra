import { openEditor as open } from '../../../../_build/js/release/build/site_shell/site_shell.js';
import type { Root } from 'react-dom/client';
import '@fontsource/inter/400.css';
import '@fontsource/inter/500.css';
import '@fontsource/inter/600.css';
import '@fontsource/noto-sans-jp/400.css';
import { App } from '../App';
import { EditorStore, currentRoom } from './store';
import type { MotionKernel } from '../engine/kernel';
import * as renderer from '../engine/renderer';
import * as exporter from '../engine/export';
import { createFramePainter } from '../engine/painter';
import '../styles.css';

export function openEditor(root: Root, kernel: MotionKernel) {
  open(root, kernel, { EditorStore, currentRoom, App, renderer, exporter, createFramePainter });
}
