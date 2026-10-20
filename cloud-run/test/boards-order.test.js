import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {boardsHandler} from '../src/boards.js';

const id = () => randomUUID();

function fakePool(owned) {
  const calls = [];
  const db = {
    async query(sql, params = []) {
      calls.push({sql, params});
      if (/SELECT id FROM public\.board_workplaces WHERE owner_id/.test(sql)) return {rows: owned.map(i => ({id: i}))};
      if (/count\(\*\)/.test(sql)) return {rows: [{count: 0}]};
      return {rows: []};
    },
    release() {},
  };
  return {pool: {connect: async () => db}, calls};
}

async function call(pool, body) {
  const reply = {code(status) { this.status = status; return this; }, send(payload) { this.payload = payload; return payload; }};
  const result = await boardsHandler(pool)({body, userProfile: {id: id()}, log: {error() {}}}, reply);
  return {status: reply.status ?? 200, body: reply.payload ?? result};
}

test('boards are reordered by listing every board once, in the new order', async () => {
  const [a, b, c] = [id(), id(), id()];
  const {pool, calls} = fakePool([a, b, c]);
  const ok = await call(pool, {action: 'reorderWorkplaces', ids: [c, a, b]});
  assert.deepEqual([ok.status, ok.body], [200, {saved: true}]);
  const update = calls.find(x => /UPDATE public\.board_workplaces w SET position/.test(x.sql));
  assert.deepEqual(update.params[0], [c, a, b]);
  assert.ok(calls.some(x => x.sql === 'COMMIT'));
});

test('a reorder that misses, repeats or invents a board is refused and writes nothing', async () => {
  const [a, b, c] = [id(), id(), id()];
  for (const ids of [[a, b], [a, b, b], [a, b, id()], [a, b, c, id()], 'x', null, [], {}]) {
    const {pool, calls} = fakePool([a, b, c]);
    const r = await call(pool, {action: 'reorderWorkplaces', ids});
    assert.equal(r.status, 400, JSON.stringify(ids));
    assert.equal(calls.some(x => /UPDATE public/.test(x.sql)), false);
    assert.ok(calls.some(x => x.sql === 'ROLLBACK'));
  }
});

test('a user with no boards can reorder the empty list', async () => {
  const {pool} = fakePool([]);
  assert.equal((await call(pool, {action: 'reorderWorkplaces', ids: []})).status, 200);
});

test('boards are listed in their saved order and new boards go last', async () => {
  const {pool, calls} = fakePool([]);
  await call(pool, {action: 'listWorkplaces'});
  assert.match(calls.find(x => /SELECT id,name FROM public\.board_workplaces/.test(x.sql)).sql, /ORDER BY position,created_at,id/);
  await call(pool, {action: 'createWorkplace', name: 'New'});
  assert.match(calls.find(x => /INSERT INTO public\.board_workplaces/.test(x.sql)).sql, /COALESCE\(MAX\(position\),0\)\+1/);
});
