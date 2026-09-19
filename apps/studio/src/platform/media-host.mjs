// Native package loading only. Policy, decoding and resource ownership live in MoonBit.
// Import on the first media operation so empty projects do not load codecs/parsers.
let runtime;
const load = () => runtime ??= import('mediabunny').catch(error => { runtime = undefined; throw error; });
export const mediaRuntime = load;
export const audioRuntime = load;
export const videoProbeRuntime = load;
export const encoderRuntime = load;
export const audioEncoderRuntime = load;
