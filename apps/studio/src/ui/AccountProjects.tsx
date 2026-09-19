import type { ComponentType, ReactNode } from 'react';
import { AccountProjects as MoonAccountProjects } from '../../../../_build/js/release/build/ui/ui.js';
export const AccountProjects: ComponentType<{ open: boolean; roomId: string; name: string; synced: boolean; busy: boolean; onOpenChange: (open: boolean) => void; children: (content: ReactNode) => ReactNode }> = MoonAccountProjects;
