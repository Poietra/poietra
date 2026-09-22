import { describe, expect, test } from 'vitest';
import * as encoding from 'lib0/encoding';
import * as decoding from 'lib0/decoding';
import { presenceMessage, readPresenceUpdate, type Presence } from '../worker/presence';
import { presenceMessages } from '../../../_build/js/release/build/server_presence/server_presence.js';

function update(entries: { clientId: number; clock: number; state: unknown }[]) {
  const encoder = encoding.createEncoder();
  encoding.writeVarUint(encoder, entries.length);
  for (const entry of entries) {
    encoding.writeVarUint(encoder, entry.clientId);
    encoding.writeVarUint(encoder, entry.clock);
    encoding.writeVarString(encoder, JSON.stringify(entry.state));
  }
  return encoding.toUint8Array(encoder);
}

const state = { user: { name: 'Alice', color: '#abcdef' }, editor: { selectedIds: [], cursor: null } };

function readPackets(packets: Uint8Array[]) {
  const entries: Array<{ clientId: number; clock: number; state: unknown }> = [];
  for (const packet of packets) {
    expect(packet.byteLength).toBeLessThanOrEqual(16000);
    const outer = decoding.createDecoder(packet);
    expect(decoding.readVarUint(outer)).toBe(1);
    const inner = decoding.createDecoder(decoding.readVarUint8Array(outer));
    const count = decoding.readVarUint(inner); expect(count).toBeLessThanOrEqual(100);
    for (let i = 0; i < count; i++) entries.push({ clientId: decoding.readVarUint(inner), clock: decoding.readVarUint(inner), state: JSON.parse(decoding.readVarString(inner)) });
    expect(inner.pos).toBe(inner.arr.byteLength); expect(outer.pos).toBe(outer.arr.byteLength);
  }
  return entries;
}

describe('hibernatable presence', () => {
  test('packs ordinary cursor bursts into one packet while preserving the stock awareness format', () => {
    const entries = Array.from({ length: 64 }, (_, i) => ({ clientId: 2 ** 32 + i, clock: 2 ** 32 + 73, state: { ...state, editor: { sceneId: 'scene-1', compositionId: 'comp-1', selectedIds: [`load-${i}`], cursor: { x: i, y: i } } } }));
    const packets = presenceMessages(entries);
    expect(packets).toHaveLength(1);
    expect(readPackets(packets)).toEqual(entries);
  });

  test('splits large Unicode rosters by encoded bytes and short removal rosters by entry count', () => {
    const entries = Array.from({ length: 500 }, (_, i) => ({ clientId: 2 ** 32 + i, clock: Number.MAX_SAFE_INTEGER, state: {
      user: { name: '制作'.repeat(20), color: '#abcdef' },
      editor: { sceneId: '場面'.repeat(40), compositionId: '状態'.repeat(40), selectedIds: Array.from({ length: 12 }, (_, j) => `${j}${'図形'.repeat(39)}`), cursor: null },
    } }));
    expect(readPackets(presenceMessages(entries))).toEqual(entries);
    const removals = entries.map(entry => ({ ...entry, state: null }));
    expect(readPackets(presenceMessages(removals))).toEqual(removals);
    expect(presenceMessages([])).toEqual([]);
  });

  test('keeps safe-integer client IDs and clocks without 32-bit truncation', () => {
    for (const clientId of [2 ** 31 + 17, 2 ** 32 + 29, Number.MAX_SAFE_INTEGER]) {
      const clock = 2 ** 32 + 73;
      const present = readPresenceUpdate(update([{ clientId, clock, state }]), null)!;
      expect(present).toMatchObject({ clientId, clock });
      expect(readPresenceUpdate(update([{ clientId, clock: clock - 1, state: null }]), present)).toBe(present);
      const decoder = decoding.createDecoder(presenceMessage([present]));
      expect(decoding.readVarUint(decoder)).toBe(1);
      expect(readPresenceUpdate(decoding.readVarUint8Array(decoder), null)).toEqual(present);
    }
  });

  test('rejects oversized, excessive and truncated messages before accepting presence', () => {
    expect(() => readPresenceUpdate(new Uint8Array(16385), null)).toThrow('large');
    const excessive = encoding.createEncoder(); encoding.writeVarUint(excessive, 101);
    expect(() => readPresenceUpdate(encoding.toUint8Array(excessive), null)).toThrow('many');
    const bytes = update([{ clientId: 71, clock: 3, state }]);
    expect(() => readPresenceUpdate(bytes.subarray(0, bytes.length - 2), null)).toThrow();
    expect(readPresenceUpdate(update([{ clientId: 71, clock: 3, state: null }]), null)).toBeNull();
  });

  test('replayed clocks cannot resurrect a removal or replace a newer state', () => {
    const present = readPresenceUpdate(update([{ clientId: 7, clock: 3, state }]), null)!;
    const removed = readPresenceUpdate(update([{ clientId: 7, clock: 3, state: null }]), present)!;
    expect(removed.state).toBeNull();
    expect(readPresenceUpdate(update([{ clientId: 7, clock: 3, state }]), removed)).toBe(removed);
    expect(readPresenceUpdate(update([{ clientId: 7, clock: 2, state }]), present)).toBe(present);
    expect(readPresenceUpdate(update([{ clientId: 7, clock: 4, state }]), removed)!.state?.user.name).toBe('Alice');
  });

  test('one socket cannot publish or remove another client’s presence', () => {
    const present = readPresenceUpdate(update([{ clientId: 7, clock: 3, state }]), null)!;
    expect(readPresenceUpdate(update([{ clientId: 8, clock: 999, state: null }]), present)).toBe(present);
    expect(readPresenceUpdate(update([{ clientId: 8, clock: 999, state }]), present)).toBe(present);
  });

  test('bounded attachments roundtrip with unicode names and large selections', () => {
    const entry = readPresenceUpdate(update([{ clientId: 7, clock: 3, state: {
      user: { name: '制作'.repeat(100), color: 'red' },
      editor: { selectedIds: Array.from({ length: 20 }, () => '図形'.repeat(100)), cursor: { x: 1e12, y: -1e12 } },
    } }]), null)!;
    expect(entry.state?.user.name.length).toBe(40);
    expect(entry.state?.editor.selectedIds).toHaveLength(12);
    expect(entry.state?.editor.cursor).toEqual({ x: 10000, y: -10000 });
    expect(new TextEncoder().encode(JSON.stringify(entry)).byteLength).toBeLessThan(16384);
    const decoder = decoding.createDecoder(presenceMessage([entry]));
    expect(decoding.readVarUint(decoder)).toBe(1);
    expect(readPresenceUpdate(decoding.readVarUint8Array(decoder), null)).toEqual(entry satisfies Presence);
  });
});
