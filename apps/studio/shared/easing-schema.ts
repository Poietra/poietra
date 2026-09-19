import type { z } from 'zod';
import type { CubicBezierEasing, Easing } from './model';
import { cubicEasingSchema, easingSchema } from '../../../_build/js/release/build/schemas/schemas.js';
export const CubicBezierEasingSchema = cubicEasingSchema() as z.ZodType<CubicBezierEasing>;
export const EasingSchema = easingSchema() as z.ZodType<Easing>;
