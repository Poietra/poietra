import type { ComponentType, ReactNode } from 'react';
import { boundaryComponent } from '../../../../_build/js/release/build/site_shell/site_shell.js';
export const Boundary = boundaryComponent() as ComponentType<{ children: ReactNode }>;
