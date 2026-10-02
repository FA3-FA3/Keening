import test from 'node:test';
import assert from 'node:assert/strict';
import {scheduleHandler} from '../src/schedule.js';

function run(body, blocks = []) {
  let saved;
  const data = {groups: [], rows: [], blocks, tagDefinitions: []};
  const db = {
    release() {},
    query: async (sql, params) => {
      if (sql.startsWith('SELECT data')) return {rows: [{data}]};
      if (sql.startsWith('UPDATE')) saved = JSON.parse(params[0]);
      return {rows: []};
    },
  };
  let sent;
  const reply = {code: c => ({send: b => (sent = {code: c, body: b})})};
  return scheduleHandler({connect: async () => db})(
    {body: {action: 'saveBlock', title: 'Gym', start: '09:00', end: '10:00', date: '2026-09-30', ...body}, userProfile: {id: 'u'}, log: {error() {}}},
    reply,
  ).then(r => ({r, sent, saved}));
}

test('recurring session creates one session per extra date, ignoring duplicates and the main date', async () => {
  const {r, saved} = await run({repeatDates: ['2026-10-01', '2026-10-01', '2026-09-30', '2026-10-05']});
  assert.equal(r.created, 3);
  assert.deepEqual(saved.blocks.map(b => b.date).sort(), ['2026-09-30', '2026-10-01', '2026-10-05']);
  assert.equal(new Set(saved.blocks.map(b => b.id)).size, 3);
  assert.ok(saved.blocks.every(b => b.title === 'Gym'));
});

test('repeat dates are validated and ignored when editing', async () => {
  assert.equal((await run({repeatDates: ['nope']})).sent.code, 400);
  assert.equal((await run({repeatDates: 'x'})).sent.code, 400);
  assert.equal((await run({repeatDates: Array.from({length: 366}, (_, i) => `2027-01-${String(i % 28 + 1).padStart(2, '0')}`)})).sent.code, 400);
  const existing = [{id: 'b1', date: '2026-09-30', start: '09:00', end: '10:00', title: 'Gym', color: '#D97706'}];
  const {saved} = await run({blockId: 'b1', repeatDates: ['2026-10-01']}, existing);
  assert.equal(saved.blocks.length, 1);
});
