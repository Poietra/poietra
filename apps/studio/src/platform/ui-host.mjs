// Runtime values that MoonBit consumes through typed React bindings.
// Layout, event handling, and component state live in moonbit/ui.
import { Tooltip } from '@base-ui/react/tooltip';
import { Dialog } from '@base-ui/react/dialog';
import { Popover } from '@base-ui/react/popover';
import { X, Clapperboard, PencilLine, Check, LockKeyhole, MousePointer2, Move, AlertTriangle, RefreshCw } from 'lucide-react';
import { clsx } from 'clsx';
import { twMerge } from 'tailwind-merge';

const icons = { X, Clapperboard, PencilLine, Check, LockKeyhole, MousePointer2, Move, AlertTriangle, RefreshCw };
const libraries = { Tooltip, Dialog, Popover };
export const iconComponent = name => icons[name];
export const uiComponent = (library, name) => libraries[library][name];
export const classNames = values => twMerge(clsx(values));
