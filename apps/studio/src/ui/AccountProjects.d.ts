import type { ComponentType, ReactNode } from 'react';
export declare const AccountProjects: ComponentType<{
    open: boolean;
    roomId: string;
    name: string;
    synced: boolean;
    busy: boolean;
    onOpenChange: (open: boolean) => void;
    children: (content: ReactNode) => ReactNode;
}>;
