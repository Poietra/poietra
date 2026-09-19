// Runtime values that MoonBit consumes through typed React bindings.
// Layout, event handling, and component state live in moonbit/ui.
import { Tooltip } from '@base-ui/react/tooltip';
import { Dialog } from '@base-ui/react/dialog';
import { Popover } from '@base-ui/react/popover';
import { Tabs } from '@base-ui/react/tabs';
import { Menu } from '@base-ui/react/menu';
import * as Y from 'yjs';
import { X, Clapperboard, PencilLine, Check, LockKeyhole, MousePointer2, Move, AlertTriangle, RefreshCw, ArrowLeft, ArrowRight, ChartNoAxesColumnIncreasing, Copy, MoreHorizontal, Pencil, Plus, Trash2, Sparkles, LoaderCircle, RotateCcw, Download, Play, Pause } from 'lucide-react';
import { clsx } from 'clsx';
import { twMerge } from 'tailwind-merge';

const icons = { X, Clapperboard, PencilLine, Check, LockKeyhole, MousePointer2, Move, AlertTriangle, RefreshCw, ArrowLeft, ArrowRight, ChartNoAxesColumnIncreasing, Copy, MoreHorizontal, Pencil, Plus, Trash2, Sparkles, LoaderCircle, RotateCcw, Download, Play, Pause };
const libraries = { Tooltip, Dialog, Popover, Tabs, Menu };
export const iconComponent = name => icons[name];
export const uiComponent = (library, name) => libraries[library][name];
export const classNames = values => twMerge(clsx(values));
export const sharedRuntime = () => Y;
