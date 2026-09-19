import type { ComponentType } from 'react';
import type { Easing } from '../../shared/model';
import { EasingEditor as MoonEasingEditor } from '../../../../_build/js/release/build/ui/ui.js';
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

export const EasingEditor: ComponentType<EasingEditorProps> = MoonEasingEditor;
