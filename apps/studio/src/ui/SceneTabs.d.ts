import type { ReactElement } from 'react';
import type { Project } from '../../shared/model';
import type { EditorStore } from '../editor/store';
import './SceneTabs.css';
interface Props {
    project: Project;
    sceneId: string;
    onChange: (id: string) => void;
    onNew: () => void;
    store: EditorStore;
    notify: (message: string) => void;
}
export declare const SceneTabs: (props: Props) => ReactElement;
export {};
