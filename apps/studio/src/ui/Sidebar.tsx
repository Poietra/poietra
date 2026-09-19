import type { ComponentType } from 'react';
import type { ObjectKind } from '../../shared/model';
import { Sidebar as MoonSidebar, ObjectIcon as MoonObjectIcon } from '../../../../_build/js/release/build/ui/ui.js';
import './groups.css';

export const ObjectIcon: ComponentType<{ kind: ObjectKind; size?: number }> = MoonObjectIcon;
export const Sidebar: ComponentType<{ onNewScene: () => void }> = MoonSidebar;
