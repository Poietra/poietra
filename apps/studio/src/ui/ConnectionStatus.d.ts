import type { ReactElement } from 'react';
import type { EditorSnapshot } from '../editor/store';
import './ConnectionStatus.css';
export declare const connectionPresentation: (snapshot: Pick<EditorSnapshot, 'status' | 'synced' | 'project' | 'localPersistence' | 'connectionIssue'>) => {
    live: boolean;
    label: string;
    description: string;
    storage: string;
};
export declare const ConnectionStatus: (props: {
    snapshot: EditorSnapshot;
    onRetry: () => void;
    expanded?: boolean;
}) => ReactElement;
