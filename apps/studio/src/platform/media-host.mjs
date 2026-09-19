// Runtime values only; fetching, decoding and resource ownership live in MoonBit.
import { ALL_FORMATS, BlobSource, Input, CanvasSink, AudioBufferSink } from 'mediabunny';
export const mediaRuntime = () => ({ ALL_FORMATS, BlobSource, Input, CanvasSink });
export const audioRuntime = () => ({ AudioBufferSink });
