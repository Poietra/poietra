import type { Project, Scene } from './model';
import { makeBlankScene as blank, makeDemoProject as demo } from '../../../_build/js/release/build/boundary/boundary.js';
export const makeBlankScene: (id: string, name: string) => Scene = blank;
export const makeDemoProject: () => Project = demo;
