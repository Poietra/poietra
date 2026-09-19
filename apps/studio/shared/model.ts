import type { ImageAsset } from './images';
import type { AudioTrack, MediaAsset, MediaPlayback } from './media';
import type { Easing, PresetEasing } from './easing';
import * as moonbit from '../../../_build/js/release/build/boundary/boundary.js';
export { DEFAULT_CUSTOM_EASING, isValidEasing, easingsEqual, type PresetEasing, type CubicBezierEasing, type Easing } from './easing';
export type ObjectKind = 'circle' | 'rectangle' | 'text' | 'equation' | 'path' | 'arrow' | 'numberline' | 'image' | 'video';
export type AnimationKind = 'move' | 'write' | 'fade' | 'grow' | 'none';
export type Point = { x: number; y: number };
export type Bezier = { c1: Point; c2: Point };

export interface SceneObject {
  id: string;
  name: string;
  kind: ObjectKind;
  order: number;
  groupId: string | null;
  locked: boolean;
  image?: ImageAsset;
  media?: MediaAsset;
  playback?: MediaPlayback;
}

export interface ObjectState {
  x: number;
  y: number;
  width: number;
  height: number;
  rotation: number;
  opacity: number;
  visible: boolean;
  fill: string;
  stroke: string;
  strokeWidth: number;
  text: string;
  fontSize: number;
  cornerRadius: number;
  effect: 'none' | 'glow';
  path: Bezier;
}

export interface Composition {
  id: string;
  name: string;
  duration: number;
  accent: string;
  states: Record<string, ObjectState>;
  /** Internal CRDT metadata; readProject omits these from the editable/saved view. */
  deleted?: boolean;
  incomingTransitionId?: string;
}

export const PROPERTY_CHANNELS = ['position', 'opacity', 'size', 'rotation', 'fill', 'stroke', 'strokeWidth', 'fontSize', 'cornerRadius', 'path', 'reveal'] as const;
export type PropertyChannel = typeof PROPERTY_CHANNELS[number];
export type PropertyTimingKey = `${PropertyChannel}Timing`;
export interface AnimationTiming { start: number; duration: number; easing: Easing }
export const PROPERTY_CHANNEL_LABELS: Record<PropertyChannel, string> = { position: 'Position', opacity: 'Opacity', size: 'Size', rotation: 'Rotation', fill: 'Fill', stroke: 'Stroke', strokeWidth: 'Stroke width', fontSize: 'Font size', cornerRadius: 'Corner radius', path: 'Shape path', reveal: 'Reveal' };
export const propertyTimingKey = (channel: PropertyChannel): PropertyTimingKey => moonbit.propertyTimingKey(channel) as PropertyTimingKey;

export interface AnimationTrack extends Partial<Record<PropertyTimingKey, AnimationTiming | null>> {
  /** A materialized automatic track still follows its Transition's base timing. */
  implicit?: boolean;
  objectId: string;
  type: AnimationKind;
  start: number;
  duration: number;
  easing: Easing;
  order: 'together' | 'sequential';
  path: Bezier | null;
}

export interface Transition {
  id: string;
  fromId: string;
  toId: string;
  duration: number;
  tracks: Record<string, AnimationTrack>;
}

export interface Scene {
  id: string;
  name: string;
  width: number;
  height: number;
  background: string;
  objects: Record<string, SceneObject>;
  compositionOrder: string[];
  compositions: Record<string, Composition>;
  transitions: Record<string, Transition>;
  audioTracks?: Record<string, AudioTrack>;
  /** Internal CRDT tombstone; readProject omits it from the editable/saved view. */
  deleted?: boolean;
}

export interface Project {
  version: 1;
  name: string;
  sceneOrder: string[];
  scenes: Record<string, Scene>;
}

export type Selection = { kind: 'composition' | 'transition'; id: string };
export type Segment = { kind: Selection['kind']; id: string; start: number; duration: number };

export const COLORS = ['#d7d8e4', '#67c4d9', '#f4ce55', '#b5d396', '#ef8078', '#d5a3bd', '#8a8fe9', '#ffffff'];
export const KINDS: Record<ObjectKind, string> = { circle: 'Circle', rectangle: 'Rectangle', text: 'Text', equation: 'Equation', path: 'Path', arrow: 'Arrow', numberline: 'Number line', image: 'Image', video: 'Video' };
export const EASINGS: Record<PresetEasing, string> = { linear: 'Linear', easeInOut: 'Ease in out', easeIn: 'Ease in', easeOut: 'Ease out' };
export const ANIMATIONS: Record<AnimationKind, string> = { move: 'Move', write: 'Write', fade: 'Fade', grow: 'Grow', none: 'Cut' };

// Typed host signatures for MoonBit's document and timeline implementation.
export const newId = (prefix = 'obj'): string => moonbit.newId(prefix);
export const defaultState: (kind: ObjectKind, overrides?: Partial<ObjectState>) => ObjectState = moonbit.defaultState;
export const defaultTrack: (objectId: string, overrides?: Partial<AnimationTrack>) => AnimationTrack = moonbit.defaultTrack;
export const getPropertyTiming: (track: AnimationTrack, channel: PropertyChannel) => AnimationTiming = moonbit.getPropertyTiming;
export const hasPropertyTiming: (track: AnimationTrack, channel: PropertyChannel) => boolean = moonbit.hasPropertyTiming;
export const resolveTrack: (track: AnimationTrack | undefined, objectId: string, duration: number) => AnimationTrack = moonbit.resolveTrack;
export const implicitTracks: (objectIds: string[], duration: number) => Record<string, AnimationTrack> = moonbit.implicitTracks;
export const trackTimingEnd = (track: AnimationTrack, includeBase = true): number => moonbit.trackTimingEnd(track, includeBase);
export const validateAnimationTiming: (timing: AnimationTiming, duration: number) => void = moonbit.validateAnimationTiming;
export const validateAnimationTrack: (track: AnimationTrack, duration: number) => void = moonbit.validateAnimationTrack;
export const sceneSegments: (scene: Scene) => Segment[] = moonbit.sceneSegments;
export const sceneDuration: (scene: Scene) => number = moonbit.sceneDuration;
export const orderedObjects: (scene: Scene) => SceneObject[] = moonbit.orderedObjects;
export const stateFor: (scene: Scene, compositionId: string, objectId: string) => ObjectState | undefined = moonbit.stateFor;
export const clamp: (value: number, min: number, max: number) => number = moonbit.clamp;
export const ms: (value: number) => string = moonbit.formatMilliseconds;
