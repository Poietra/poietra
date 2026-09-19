import type { Keyframe } from "./scene-types";
import type { z } from 'zod';
import { type Change } from './document';
import type { ObjectKind, Project } from './model';
import type { ImageAsset } from './images';
import * as Y from 'yjs';
import type { Bezier, CubicBezierEasing, PropertyChannel, AnimationTiming } from './model';
type ObjectFields = {
    compositionId: string;
    name: string;
    x: number;
    y: number;
    width: number;
    height: number;
    fill: string;
    text: string;
    fontSize: number;
};
type ShapeKind = Exclude<ObjectKind, 'image' | 'video'>;
export interface GenerateImageOperation {
    action: 'generateImage';
    ref: string;
    compositionId: string;
    name: string;
    prompt: string;
    size: 'square' | 'landscape' | 'portrait';
    transparent: boolean;
    x: number;
    y: number;
    width: number;
}
export interface CreateImageOperation {
    action: 'createImage';
    ref: string;
    compositionId: string;
    name: string;
    x: number;
    y: number;
    width: number;
    height: number;
    image: ImageAsset;
}
export type ProposalOperation = {
    action: 'setState';
    compositionId: string;
    objectId: string;
    property: typeof stateProperties[number];
    value: number | string | boolean;
} | {
    action: 'setTrack';
    transitionId: string;
    objectId: string;
    property: 'type' | 'start' | 'duration' | 'easing' | 'order';
    value: number | string | CubicBezierEasing;
} | {
    action: 'setParent';
    objectId: string;
    parentId: string | null;
} | {
    action: 'setAnchor';
    objectId: string;
    compositionId: string;
    x: number;
    y: number;
} | {
    action: 'setKeyframe';
    transitionId: string;
    objectId: string;
    keyframeId: string;
    keyframe: Keyframe | null;
} | {
    action: 'setPropertyTiming';
    transitionId: string;
    objectId: string;
    channel: PropertyChannel;
    timing: AnimationTiming | null;
} | {
    action: 'setMotionPath';
    transitionId: string;
    objectId: string;
    path: Bezier | null;
} | {
    action: 'setShapePath';
    compositionId: string;
    objectId: string;
    path: Bezier;
} | {
    action: 'setCompositionDuration';
    compositionId: string;
    duration: number;
} | {
    action: 'setTransitionDuration';
    transitionId: string;
    duration: number;
} | ({
    action: 'addObject';
    kind: Exclude<ShapeKind, 'path'>;
} & ObjectFields) | ({
    action: 'createObject';
    ref: string;
    kind: ShapeKind;
} & ObjectFields) | {
    action: 'appendComposition';
    ref: string;
    transitionRef: string;
    name: string;
    duration: number;
    transitionDuration: number;
} | GenerateImageOperation;
declare const stateProperties: readonly ['x', 'y', 'width', 'height', 'rotation', 'opacity', 'visible', 'fill', 'stroke', 'strokeWidth', 'text', 'fontSize', 'cornerRadius', 'effect', 'anchorX', 'anchorY', 'scaleX', 'scaleY', 'shear'];
export declare const GENERATED_IMAGE_SIZES: {
    readonly square: {
        readonly width: 1024;
        readonly height: 1024;
    };
    readonly landscape: {
        readonly width: 1536;
        readonly height: 1024;
    };
    readonly portrait: {
        readonly width: 1024;
        readonly height: 1536;
    };
};
export declare const MAX_GENERATED_IMAGES = 2;
export declare const EditProposalSchema: z.ZodType<{
    message: string;
    operations: ProposalOperation[];
}>;
/** compileProposal input: model operations whose generateImage requests have become createImage. */
export interface CompilableProposal {
    message: string;
    operations: Array<ProposalOperation | CreateImageOperation>;
}
export declare const placeholderImage: (size: GenerateImageOperation['size']) => ImageAsset;
export declare const withGeneratedImages: (raw: z.infer<typeof EditProposalSchema>, asset: (operation: GenerateImageOperation) => ImageAsset | undefined) => CompilableProposal;
export interface ProposalGuard {
    path: string[];
    expected: unknown;
    existed: boolean;
    parentIdentity?: string;
}
export type GuardedChange = Change & ProposalGuard;
export interface EditScope {
    selectedIds: string[];
    compositionId: string | null;
    transitionId: string | null;
}
export interface CompositionAppend {
    sceneId: string;
    compositionIds: string[];
    orderIdentity: string;
}
export interface EditProposal {
    id: string;
    message: string;
    changes: GuardedChange[];
    count: number;
    guards?: ProposalGuard[];
    compositionAppends?: CompositionAppend[];
}
export declare const validateStateValue: (property: string, value: unknown, kind?: ObjectKind) => void;
export declare function validateProposalForApply(doc: Y.Doc, proposal: EditProposal): void;
export declare function applyProposal(doc: Y.Doc, proposal: EditProposal, origin?: unknown): void;
export declare function compileProposal(doc: Y.Doc, project: Project, sceneId: string, raw: CompilableProposal, _scope?: EditScope): EditProposal;
export {};
