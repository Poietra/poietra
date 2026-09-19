import type { ComponentType } from 'react';
import type { Easing } from '../../shared/model';
import './EasingEditor.css';
export interface EasingEditorProps {
    value: Easing | undefined;
    onChange: (value: Easing, separate?: boolean) => void;
    /** Read after input blur, so a drag starts from the latest committed curve. */
    getValue?: () => Easing | undefined;
    label: string;
    disabled?: boolean;
    disabledReason?: string;
}
export declare const EasingEditor: ComponentType<EasingEditorProps>;
