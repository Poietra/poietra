import type { ButtonHTMLAttributes, ReactElement, ReactNode } from 'react';
export declare const IconButton: (props: ButtonHTMLAttributes<HTMLButtonElement> & {
    label: string;
    active?: boolean;
}) => ReactElement;
export declare const Field: (props: {
    label: string;
    children: ReactNode;
    className?: string;
}) => ReactElement;
export declare const NumberInput: (props: {
    value: number;
    onChange: (value: number) => void;
    label: string;
    suffix?: string;
    min?: number;
    max?: number;
    step?: number;
}) => ReactElement;
export declare const Modal: (props: {
    open: boolean;
    onOpenChange: (open: boolean) => void;
    title: string;
    description?: string;
    children: ReactNode;
    className?: string;
}) => ReactElement;
export declare const Section: (props: {
    title: string;
    children: ReactNode;
    action?: ReactNode;
}) => ReactElement;
