import type { ButtonHTMLAttributes, ReactElement, ReactNode } from 'react';
import * as moonbit from '../../../../_build/js/release/build/ui/ui.js';

// React's runtime is external; component layout, hooks and event handling are MoonBit.
const bind = <Props,>(component: (props: unknown) => unknown) => component as (props: Props) => ReactElement;
export const IconButton = bind<ButtonHTMLAttributes<HTMLButtonElement> & { label: string; active?: boolean }>(moonbit.IconButton);
export const Field = bind<{ label: string; children: ReactNode; className?: string }>(moonbit.Field);
export const NumberInput = bind<{ value: number; onChange: (value: number) => void; label: string; suffix?: string; min?: number; max?: number; step?: number }>(moonbit.NumberInput);
export const Modal = bind<{ open: boolean; onOpenChange: (open: boolean) => void; title: string; description?: string; children: ReactNode; className?: string }>(moonbit.Modal);
export const Section = bind<{ title: string; children: ReactNode; action?: ReactNode }>(moonbit.Section);
