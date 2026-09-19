// Runtime values only; fetching, decoding and resource ownership live in MoonBit.
import { ALL_FORMATS, BlobSource, Input, CanvasSink } from 'mediabunny';
export const mediaRuntime = () => ({ ALL_FORMATS, BlobSource, Input, CanvasSink });
