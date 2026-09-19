import type { ReactElement } from 'react';
import './OperationFeedback.css';
export interface OperationStatus {
    label: string;
    detail?: string;
    kind: 'active' | 'complete' | 'cancelled' | 'locked' | 'idle';
}
export declare const useOperationFeedback: (scope: string) => {
    feedback: OperationStatus | null;
    report: (status: OperationStatus | null) => void;
};
export declare const OperationFeedback: (props: {
    status: OperationStatus | null;
    className?: string;
}) => ReactElement;
