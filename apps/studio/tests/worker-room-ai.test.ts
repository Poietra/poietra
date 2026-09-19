import { DatabaseSync } from 'node:sqlite';
import { afterEach, expect, test, vi } from 'vitest';
import * as Y from 'yjs';
import * as sync from 'y-protocols/sync';
import { aiRuntime } from '../server/ai';
import { projectRoomClass } from '../../../_build/js/release/build/worker_room/worker_room.js';

const databases: DatabaseSync[] = [];
afterEach(() => { for (const db of databases.splice(0)) db.close(); vi.restoreAllMocks(); });
function fixture() {
  const database = new DatabaseSync(':memory:'); databases.push(database);
  const sql = { exec(query: string, ...parameters: never[]) {
    const rows = database.prepare(query).all(...parameters);
    return { toArray: () => rows, [Symbol.iterator]: () => rows[Symbol.iterator]() };
  } };
  const ctx = { storage: { sql, transactionSync<T>(run: () => T) {
    database.exec('BEGIN');
    try { const result = run(); database.exec('COMMIT'); return result; }
    catch (error) { database.exec('ROLLBACK'); throw error; }
  } } };
  const pending: Array<{ resolve: (value: unknown) => void; reject: (error: Error) => void }> = [];
  const createEditProposal = vi.fn(() => new Promise((resolve, reject) => pending.push({ resolve, reject })));
  const Room = projectRoomClass({ Y, sync, ai: aiRuntime, createEditProposal });
  const env = { OPENAI_API_KEY: 'test-key-never-sent', OPENAI_MODEL: 'test-model' };
  const lock = () => database.prepare('SELECT request_id, until_ms FROM ai_lock WHERE id=1').get();
  return { room: new Room(ctx, env), restore: () => new Room(ctx, env), pending, createEditProposal, lock };
}
const input = { roomId: 'worker-ai-lock-room', sceneId: 'scene-1', compositionId: 'comp-1', transitionId: null, selectedIds: [], prompt: 'hello' };
const proposal = { id: 'test', message: 'ok', changes: [], count: 0 };

test('an in-flight AI lock survives a restored room and an old owner cannot release its successor', async () => {
  let time = 1_000_000; vi.spyOn(Date, 'now').mockImplementation(() => time);
  const { room, restore, pending, createEditProposal, lock } = fixture();
  const first = room.propose(input);
  expect(createEditProposal).toHaveBeenCalledTimes(1);
  const original = lock();
  expect(original?.until_ms).toBe(time + 180_000);
  const restored = restore();
  expect((await restored.propose(input)).status).toBe(429);
  expect(createEditProposal).toHaveBeenCalledTimes(1);
  time += 180_001;
  const second = restored.propose(input);
  const successor = lock();
  expect(successor?.request_id).not.toBe(original?.request_id);
  pending[0].resolve(proposal);
  expect(await first).toEqual({ status: 200, body: proposal });
  expect(lock()).toEqual(successor);
  pending[1].resolve(proposal);
  expect(await second).toEqual({ status: 200, body: proposal });
  expect(lock()).toBeUndefined();
});

test('a failed AI request releases its durable lock and allows another request', async () => {
  const { room, pending, lock, createEditProposal } = fixture();
  const first = room.propose(input);
  pending[0].reject(new Error('provider unavailable'));
  expect(await first).toEqual({ status: 400, body: { error: 'provider unavailable' } });
  expect(lock()).toBeUndefined();
  const next = room.propose(input);
  expect(createEditProposal).toHaveBeenCalledTimes(2);
  pending[1].resolve(proposal);
  expect((await next).status).toBe(200);
});
