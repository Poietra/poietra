import type { Context } from 'react';
import { editorContext } from '../platform/ui-host.mjs';
import { useEditor as moonUseEditor } from '../../../../_build/js/release/build/ui/ui.js';
import type { ObjectKind, Scene, Selection } from '../../shared/model';
import type { MotionKernel } from '../engine/kernel';
import type { RendererContract } from '../engine/render-contract';
import type { PainterContract } from '../engine/painter-contract';
import type { EditorStore, Peer } from './store';

export type Tool = 'select' | ObjectKind;
export interface EditorContextValue {
  store: EditorStore;
  scene: Scene;
  selection: Selection;
  select: (selection: Selection) => void;
  appendComposition: () => void;
  requestTextEdit: (objectId: string, compositionId: string) => void;
  compositionId: string;
  selectedIds: string[];
  setSelectedIds: (ids: string[]) => void;
  tool: Tool;
  setTool: (tool: Tool) => void;
  kernel: MotionKernel;
  renderer: RendererContract;
  createFramePainter?: PainterContract['createFramePainter'];
  playhead: number;
  seek: (time: number, scope?: 'scene' | 'transition') => void;
  viewingPlayback?: boolean;
  playing: boolean;
  play: (scope?: 'scene' | 'transition') => void;
  previewScope: 'scene' | 'transition';
  pathEditing: boolean;
  setPathEditing: (editing: boolean) => void;
  peers: Peer[];
  notify: (message: string) => void;
}
export const EditorContext: Context<EditorContextValue | null> = editorContext;
export const useEditor: () => EditorContextValue = moonUseEditor;
