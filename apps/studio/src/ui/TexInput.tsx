import type { ComponentType, TextareaHTMLAttributes } from 'react';
import { TexTextarea as MoonTexTextarea } from '../../../../_build/js/release/build/ui/ui.js';
import './TexInput.css';

type Props = Omit<TextareaHTMLAttributes<HTMLTextAreaElement>, 'value' | 'onChange'> & { value: string; onChange: (value: string) => void };
export const TexTextarea: ComponentType<Props> = MoonTexTextarea;
