import type { Selection } from '../../shared/model';
export interface ProposalTarget {
    selection: Selection;
    objectIds: string[];
    label: string;
    created?: boolean;
}
export { proposalTargets } from '../../../../_build/js/release/build/boundary/boundary.js';
