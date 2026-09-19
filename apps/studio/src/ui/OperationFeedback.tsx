import type { ReactElement } from 'react';
import * as moonbit from '../../../../_build/js/release/build/ui/ui.js';
import './OperationFeedback.css';

export interface OperationStatus {
  label: string;
  detail?: string;
  kind: 'active' | 'complete' | 'cancelled' | 'locked' | 'idle';
}
export const useOperationFeedback: (scope: string) => { feedback: OperationStatus | null; report: (status: OperationStatus | null) => void } = moonbit.useOperationFeedback;
export const OperationFeedback = moonbit.OperationFeedback as (props: { status: OperationStatus | null; className?: string }) => ReactElement;
