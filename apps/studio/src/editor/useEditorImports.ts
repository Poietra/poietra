import type { RefObject } from 'react';
import type { ImportProgress } from './media';
import { useEditorImports as moonUseEditorImports } from '../../../../_build/js/release/build/ui/ui.js';

type Request = { sceneId: string; compositionId: string; controller: AbortController };
type ImportFiles = (files: File[], point?: { x: number; y: number }) => Promise<void>;
type Imports = {
  imageRequest: RefObject<Request | null>;
  mediaRequest: RefObject<Request | null>;
  importingImage: boolean;
  setImportingImage: (value: boolean) => void;
  mediaImport: (ImportProgress & { name: string; index: number; count: number }) | null;
  importError: string;
  setImportError: (value: string) => void;
  importImages: ImportFiles;
  importMediaFiles: ImportFiles;
  importFiles: ImportFiles;
  cancel: () => void;
};

export const useEditorImports: (input: Record<string, unknown>) => Imports = moonUseEditorImports;
