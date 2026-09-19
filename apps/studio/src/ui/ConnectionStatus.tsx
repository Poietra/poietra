import type { ReactElement } from 'react';
import type { EditorSnapshot } from '../editor/store';
import * as moonbit from '../../../../_build/js/release/build/ui/ui.js';
import './ConnectionStatus.css';

export const connectionPresentation: (snapshot: Pick<EditorSnapshot, 'status' | 'synced' | 'project' | 'localPersistence' | 'connectionIssue'>) => { live: boolean; label: string; description: string; storage: string } = moonbit.connectionPresentation;
export const ConnectionStatus = moonbit.ConnectionStatus as (props: { snapshot: EditorSnapshot; onRetry: () => void; expanded?: boolean }) => ReactElement;
