import type { Context, ElementType } from 'react';
import type { ClassValue } from 'clsx';
import type { EditorContextValue } from '../editor/context';
import type * as Y from 'yjs';

export const editorContext: Context<EditorContextValue | null>;
export function editorContextRuntime(): typeof editorContext;
export function iconComponent(name: string): ElementType;
export function uiComponent(library: string, name: string): unknown;
export function classNames(values: ClassValue[]): string;
export function sharedRuntime(): typeof Y;
