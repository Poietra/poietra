import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import type { AudioTrack } from '../shared/media';

const runtime = vi.hoisted(() => ({ Input: vi.fn(), BlobSource: vi.fn(), CanvasSink: vi.fn(), AudioBufferSink: vi.fn(), ALL_FORMATS: [] }));
vi.mock('mediabunny', () => runtime);

class PcmBuffer {
  readonly data: Float32Array[];
  readonly sampleRate: number;
  readonly length: number;
  readonly numberOfChannels: number;
  constructor(options: { length: number; sampleRate: number; numberOfChannels: number }) {
    this.length = options.length; this.sampleRate = options.sampleRate; this.numberOfChannels = options.numberOfChannels;
    this.data = Array.from({ length: this.numberOfChannels }, () => new Float32Array(this.length));
  }
  getChannelData(channel: number) { return this.data[channel]; }
}
type Packet = { timestamp: number; duration: number; buffer: PcmBuffer };
type Input = { dispose: ReturnType<typeof vi.fn>; getPrimaryAudioTrack: ReturnType<typeof vi.fn> };
const source = (digit = 'b') => `/api/rooms/${'a'.repeat(16)}/media/${digit.repeat(64)}`;
const clip = (patch: Partial<AudioTrack> = {}): AudioTrack => ({ id: 'audio', name: 'Sound', start: 0, offset: 0, duration: 1000,
  volume: .75, muted: false, asset: { src: source(), mime: 'audio/wav', duration: 5000, hasAudio: true }, ...patch });
function deferred<T>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>(yes => { resolve = yes; });
  return { promise, resolve };
}
function packets(rate: number, channels: number): Packet[] {
  // Deliberate packet gap and unequal final packet expose boundary errors.
  return [0, .017, .055, .091, .137].map((timestamp, packet) => {
    const length = Math.round((packet === 0 ? .017 : .026) * rate);
    const buffer = new PcmBuffer({ length, sampleRate: rate, numberOfChannels: channels });
    for (let channel = 0; channel < channels; channel++) for (let i = 0; i < length; i++) {
      buffer.data[channel][i] = Math.sin((i + 71 * packet) * (.12 + channel * .07)) * .97;
    }
    return { timestamp, duration: length / rate, buffer };
  });
}
function equalPcm(actual: PcmBuffer, expected: AudioBuffer) {
  for (let channel = 0; channel < 2; channel++) {
    const actualBits = new Uint32Array(actual.getChannelData(channel).buffer);
    const expectedBits = new Uint32Array(expected.getChannelData(channel).buffer);
    expect(actualBits).toEqual(expectedBits);
  }
}

describe('MoonBit audio packet mixer', () => {
  let moon: typeof import('../../../_build/js/release/build/browser_media/browser_media.js');
  let Oracle: typeof import('./oracle/audio').AudioMixer;
  let available: Packet[];
  let inputs: Input[];
  let iterators: Array<{ next: ReturnType<typeof vi.fn>; return: ReturnType<typeof vi.fn> }>;
  let track: { canDecode: ReturnType<typeof vi.fn> };
  let fetcher: ReturnType<typeof vi.fn>;

  beforeEach(async () => {
    vi.resetModules(); vi.clearAllMocks(); inputs = []; iterators = []; available = packets(44100, 2);
    track = { canDecode: vi.fn().mockResolvedValue(true) };
    runtime.Input.mockImplementation(function () {
      const input = { dispose: vi.fn(), getPrimaryAudioTrack: vi.fn().mockResolvedValue(track) };
      inputs.push(input); return input;
    });
    runtime.BlobSource.mockImplementation(function (blob: Blob) { return { blob }; });
    runtime.AudioBufferSink.mockImplementation(function () { return { buffers: (start: number, end: number) => {
      const selected = available.filter(sample => sample.timestamp + sample.duration > start && sample.timestamp < end);
      let index = 0;
      const iterator = { next: vi.fn(async () => index < selected.length ? { done: false, value: selected[index++] } : { done: true }),
        return: vi.fn().mockResolvedValue({ done: true }) };
      iterators.push(iterator); return iterator;
    } }; });
    fetcher = vi.fn().mockImplementation(() => Promise.resolve(new Response(new Uint8Array([1]), { headers: { 'Content-Type': 'audio/wav' } })));
    vi.stubGlobal('fetch', fetcher); vi.stubGlobal('AudioBuffer', PcmBuffer);
    moon = await import('../../../_build/js/release/build/browser_media/browser_media.js');
    Oracle = (await import('./oracle/audio')).AudioMixer;
  });
  afterEach(() => { vi.unstubAllGlobals(); vi.restoreAllMocks(); });

  for (const rate of [16000, 44100, 48000]) for (const channels of [1, 2]) {
    it(`matches original Float32 samples at ${rate} Hz/${channels} channels with gaps, trims and overlap`, async () => {
      available = packets(rate, channels);
      for (const shift of [0, 3599.987]) {
        const tracks = [clip({ start: shift * 1000 + 13.1, offset: 2.35, duration: 151.2, volume: .83 }),
          clip({ id: 'overlap', start: shift * 1000 + 25.7, offset: 33.9, duration: 124.45, volume: .96 })];
        const original = new Oracle(tracks), mixer = moon.createAudioMixer(tracks, undefined);
        let cursor = shift;
        for (const frames of [1, 227, 911, 2491, 4519, 327]) {
          equalPcm(await mixer.mix(cursor, frames), await original.mix(cursor, frames));
          cursor += frames / 48000;
        }
        mixer.dispose(); original.dispose();
      }
    });
  }

  it('preserves filtering order and shares one input while keeping independent track iterators', async () => {
    const a = clip(), b = clip({ id: 'b', offset: 17 });
    expect(moon.audibleTracks({ a, quiet: clip({ volume: 0 }), b, muted: clip({ muted: true }), empty: clip({ duration: 0 }) })).toEqual([a, b]);
    const mixer = moon.createAudioMixer([a, b], undefined);
    await Promise.all([mixer.prepare(), mixer.prepare()]);
    await mixer.mix(0, 100);
    expect(fetcher).toHaveBeenCalledOnce(); expect(inputs).toHaveLength(1);
    expect(iterators).toHaveLength(2);
    mixer.dispose(); mixer.dispose();
    expect(inputs[0].dispose).toHaveBeenCalledOnce();
    for (const iterator of iterators) expect(iterator.return).toHaveBeenCalledOnce();
  });

  it('serializes concurrent chunks and rejects backwards seeks without corrupting the next chunk', async () => {
    const wait = deferred<unknown>();
    const next = vi.fn().mockImplementationOnce(() => wait.promise).mockResolvedValue({ done: true });
    runtime.AudioBufferSink.mockImplementation(function () { return { buffers: () => ({ next, return: vi.fn().mockResolvedValue({ done: true }) }) }; });
    const mixer = moon.createAudioMixer([clip()], undefined);
    const first = mixer.mix(0, 240), second = mixer.mix(.005, 240);
    await vi.waitFor(() => expect(next).toHaveBeenCalledOnce());
    wait.resolve({ done: false, value: available[0] });
    const [a, b] = await Promise.all([first, second]);
    expect(a.getChannelData(0)[1]).not.toBe(b.getChannelData(0)[1]);
    expect(next).toHaveBeenCalledOnce();
    await expect(mixer.mix(0, 240)).rejects.toThrow('シーク');
    await expect(mixer.mix(.01, 240)).resolves.toHaveProperty('length', 240);
    mixer.dispose();
  });

  it('releases the input during metadata discovery and cancels queued chunks', async () => {
    const wait = deferred<unknown>();
    runtime.Input.mockImplementationOnce(function () {
      const input = { dispose: vi.fn(), getPrimaryAudioTrack: vi.fn(() => wait.promise) };
      inputs.push(input); return input;
    });
    const controller = new AbortController(), mixer = moon.createAudioMixer([clip()], controller.signal);
    const results = Promise.allSettled([mixer.mix(0, 240), mixer.mix(.005, 240)]);
    await vi.waitFor(() => expect(inputs[0]?.getPrimaryAudioTrack).toHaveBeenCalledOnce());
    controller.abort(); expect(inputs[0].dispose).toHaveBeenCalledOnce();
    wait.resolve(track);
    for (const result of await results) expect(result).toMatchObject({ status: 'rejected', reason: { name: 'AbortError' } });
    mixer.dispose(); expect(inputs[0].dispose).toHaveBeenCalledOnce();
  });

  it('releases every partial input after preparation fails and retries from a clean state', async () => {
    track.canDecode.mockResolvedValueOnce(true).mockResolvedValueOnce(false);
    const mixer = moon.createAudioMixer([clip(), clip({ asset: { ...clip().asset, src: source('c') } })], undefined);
    await expect(mixer.prepare()).rejects.toThrow('コーデック');
    expect(inputs).toHaveLength(2);
    expect(inputs.every(input => input.dispose.mock.calls.length === 1)).toBe(true);
    await mixer.prepare(); await mixer.mix(0, 100);
    expect(inputs).toHaveLength(4);
    mixer.dispose(); expect(inputs.every(input => input.dispose.mock.calls.length === 1)).toBe(true);
  });
});
