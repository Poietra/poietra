// Runtime values only; fetching, decoding and resource ownership live in MoonBit.
import { ALL_FORMATS, BlobSource, Input, CanvasSink, AudioBufferSink,
  AudioBufferSource, canEncodeAudio, canEncodeVideo, BufferTarget, CanvasSource, Mp4OutputFormat, Output, WebMOutputFormat } from 'mediabunny';
export const mediaRuntime = () => ({ ALL_FORMATS, BlobSource, Input, CanvasSink });
export const audioRuntime = () => ({ AudioBufferSink });
export const videoProbeRuntime = () => ({ canEncodeVideo });
export const encoderRuntime = () => ({ BufferTarget, CanvasSource, Mp4OutputFormat, Output, WebMOutputFormat });
export const audioEncoderRuntime = () => ({ AudioBufferSource, canEncodeAudio });
