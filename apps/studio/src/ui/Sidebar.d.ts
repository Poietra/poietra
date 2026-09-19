import type { ComponentType } from 'react';
import type { ObjectKind } from '../../shared/model';
import './groups.css';
export declare const ObjectIcon: ComponentType<{
    kind: ObjectKind;
    size?: number;
}>;
export declare const Sidebar: ComponentType<{
    onNewScene: () => void;
}>;
