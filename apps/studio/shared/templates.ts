import type { Project } from './model';
import { makeCalculusProject as calculus } from '../../../_build/js/release/build/boundary/boundary.js';
export const makeCalculusProject: () => Project = calculus;
