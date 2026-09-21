import { renderProjectFile } from '../index.mjs';
import { project, addImage, addAudio, addObject } from './fixtures.mjs';
import { decodeVideo } from './decode.mjs';
const p = project(); addImage(p); addAudio(p);
addObject(p, 'text', 'text', { x: 160, y: 30, text: '日本語 Poietra', fontSize: 20 });
addObject(p, 'math', 'equation', { x: 160, y: 140, text: 'x^2', fontSize: 24 });
const result = await renderProjectFile(JSON.stringify(p), { format: 'mp4' });
const decoded = await decodeVideo(result.bytes);
console.log(JSON.stringify({ format: result.format, frames: result.frames, audioCodec: result.audioCodec, decodedFrames: decoded.frames.length }));
