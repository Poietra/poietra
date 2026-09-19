import { expect, it } from 'vitest';
import * as model from '../shared/model';
import * as original from './oracle/model';
import { makeDemoProject } from '../shared/demo';

it('preserves model defaults and property timing across all object/animation kinds', () => {
  for (const kind of Object.keys(model.KINDS) as model.ObjectKind[]) {
    expect(model.defaultState(kind)).toEqual(original.defaultState(kind));
    expect(model.defaultState(kind, { x: -12, fill: '#abcdef' })).toEqual(original.defaultState(kind, { x: -12, fill: '#abcdef' }));
  }
  for (const type of Object.keys(model.ANIMATIONS) as model.AnimationKind[]) {
    const track = original.defaultTrack('o', { type });
    expect(model.defaultTrack('o', { type })).toEqual(track);
    for (const channel of model.PROPERTY_CHANNELS) {
      const key = model.propertyTimingKey(channel);
      track[key] = { start: 15, duration: 20, easing: 'linear' };
      expect(model.getPropertyTiming(track, channel)).toEqual(original.getPropertyTiming(track, channel));
      expect(model.trackTimingEnd(track)).toBe(original.trackTimingEnd(track));
    }
  }
});

it('preserves validation and invalid-number propagation instead of silently normalizing data', () => {
  const values = [undefined, null, false, 0, '', 'linear', 'easeIn', 'unknown', [], {}, model.DEFAULT_CUSTOM_EASING,
    { ...model.DEFAULT_CUSTOM_EASING, extra: true }, { ...model.DEFAULT_CUSTOM_EASING, x1: NaN }, { ...model.DEFAULT_CUSTOM_EASING, x1: Infinity }, { ...model.DEFAULT_CUSTOM_EASING, x1: '0.1' }, { ...model.DEFAULT_CUSTOM_EASING, y2: -0.1 }];
  for (const value of values) expect(model.isValidEasing(value)).toBe(original.isValidEasing(value));
  for (const value of [NaN, Infinity, -Infinity, -1, -0, 0, 800, 801]) {
    const track = original.defaultTrack('o', { start: value, opacityTiming: { start: 5, duration: 10, easing: 'linear' } });
    expect(model.trackTimingEnd(track)).toBe(original.trackTimingEnd(track));
    const result = (validate: typeof model.validateAnimationTrack) => { try { validate(track, 800); return 'ok'; } catch (error) { return (error as Error).message; } };
    expect(result(model.validateAnimationTrack)).toBe(result(original.validateAnimationTrack));
    for (const low of [0, -0, NaN]) for (const high of [1, NaN]) expect(model.clamp(value, low, high)).toBe(original.clamp(value, low, high));
  }
});

it('matches structural schedules and media extents without decoding state payloads', () => {
  for (const duration of [0, 100, NaN, Infinity]) {
    const scene = makeDemoProject().scenes['scene-1'];
    scene.compositions['comp-1'].duration = duration;
    scene.compositionOrder.push('missing');
    expect(model.sceneSegments(scene)).toEqual(original.sceneSegments(scene));
    expect(model.sceneDuration(scene)).toBe(original.sceneDuration(scene));
  }
});
