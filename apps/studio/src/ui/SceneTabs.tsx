import type { ReactElement } from 'react';
import type { Project } from '../../shared/model';
import type { EditorStore } from '../editor/store';
import { SceneTabs as MoonSceneTabs } from '../../../../_build/js/release/build/ui/ui.js';
import './SceneTabs.css';

interface Props { project: Project; sceneId: string; onChange: (id: string) => void; onNew: () => void; store: EditorStore; notify: (message: string) => void }
export const SceneTabs = MoonSceneTabs as (props: Props) => ReactElement;
