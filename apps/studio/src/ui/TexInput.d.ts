import type { ComponentType, TextareaHTMLAttributes } from 'react';
import './TexInput.css';
type Props = Omit<TextareaHTMLAttributes<HTMLTextAreaElement>, 'value' | 'onChange'> & {
    value: string;
    onChange: (value: string) => void;
};
export declare const TexTextarea: ComponentType<Props>;
export {};
