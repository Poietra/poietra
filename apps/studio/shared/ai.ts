import * as proposals from '../../../_build/js/release/build/proposals/proposals.js';
import type { z } from 'zod';
import { LOCAL_ORIGIN, type Change } from './document';
import type { ObjectKind, Project } from './model';
import type { ImageAsset } from './images';
import * as Y from 'yjs';

// Runtime schemas are constructed by MoonBit with mizchi's typed Zod bindings.
import * as schemas from '../../../_build/js/release/build/schemas/schemas.js';
import type { Bezier, CubicBezierEasing, PropertyChannel, AnimationTiming } from './model';
type ObjectFields = { compositionId: string; name: string; x: number; y: number; width: number; height: number; fill: string; text: string; fontSize: number };
type ShapeKind = Exclude<ObjectKind, 'image' | 'video'>;
export interface GenerateImageOperation { action: 'generateImage'; ref: string; compositionId: string; name: string; prompt: string; size: 'square' | 'landscape' | 'portrait'; transparent: boolean; x: number; y: number; width: number }
export interface CreateImageOperation { action: 'createImage'; ref: string; compositionId: string; name: string; x: number; y: number; width: number; height: number; image: ImageAsset }
export type ProposalOperation =
  | { action: 'setState'; compositionId: string; objectId: string; property: typeof stateProperties[number]; value: number | string | boolean }
  | { action: 'setTrack'; transitionId: string; objectId: string; property: 'type' | 'start' | 'duration' | 'easing' | 'order'; value: number | string | CubicBezierEasing }
  | { action: 'setPropertyTiming'; transitionId: string; objectId: string; channel: PropertyChannel; timing: AnimationTiming | null }
  | { action: 'setMotionPath'; transitionId: string; objectId: string; path: Bezier | null }
  | { action: 'setShapePath'; compositionId: string; objectId: string; path: Bezier }
  | { action: 'setCompositionDuration'; compositionId: string; duration: number }
  | { action: 'setTransitionDuration'; transitionId: string; duration: number }
  | ({ action: 'addObject'; kind: Exclude<ShapeKind, 'path'> } & ObjectFields)
  | ({ action: 'createObject'; ref: string; kind: ShapeKind } & ObjectFields)
  | { action: 'appendComposition'; ref: string; transitionRef: string; name: string; duration: number; transitionDuration: number }
  | GenerateImageOperation;
const stateProperties = ['x', 'y', 'width', 'height', 'rotation', 'opacity', 'visible', 'fill', 'stroke', 'strokeWidth', 'text', 'fontSize', 'cornerRadius', 'effect'] as const;
export const GENERATED_IMAGE_SIZES = { square: { width: 1024, height: 1024 }, landscape: { width: 1536, height: 1024 }, portrait: { width: 1024, height: 1536 } } as const;
export const MAX_GENERATED_IMAGES = 2;
export const EditProposalSchema = schemas.editProposalSchema() as z.ZodType<{ message: string; operations: ProposalOperation[] }>;
/** compileProposal input: model operations whose generateImage requests have become createImage. */
export interface CompilableProposal { message: string; operations: Array<ProposalOperation | CreateImageOperation> }

export const placeholderImage = proposals.placeholderImage as (size: GenerateImageOperation['size']) => ImageAsset;
export const withGeneratedImages = proposals.withGeneratedImages as (raw: z.infer<typeof EditProposalSchema>, asset: (operation: GenerateImageOperation) => ImageAsset | undefined) => CompilableProposal;

export interface ProposalGuard { path: string[]; expected: unknown; existed: boolean; parentIdentity?: string }
export type GuardedChange = Change & ProposalGuard;
export interface EditScope { selectedIds: string[]; compositionId: string | null; transitionId: string | null }
export interface CompositionAppend { sceneId: string; compositionIds: string[]; orderIdentity: string }
export interface EditProposal { id: string; message: string; changes: GuardedChange[]; count: number; guards?: ProposalGuard[]; compositionAppends?: CompositionAppend[] }

export const validateStateValue = proposals.validateStateValue as (property: string, value: unknown, kind?: ObjectKind) => void;
export function validateProposalForApply(doc: Y.Doc, proposal: EditProposal): void { proposals.validateProposalForApply(doc, proposal, Y); }
export function applyProposal(doc: Y.Doc, proposal: EditProposal, origin: unknown = LOCAL_ORIGIN): void { proposals.applyProposal(doc, proposal, origin, Y); }
export function compileProposal(doc: Y.Doc, project: Project, sceneId: string, raw: CompilableProposal, _scope?: EditScope): EditProposal {
  return proposals.compileProposal(doc, project, sceneId, raw, Y);
}
