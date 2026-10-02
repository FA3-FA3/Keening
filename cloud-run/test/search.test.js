import test from 'node:test';
import assert from 'node:assert/strict';
import {searchHandler} from '../src/search.js';

const rows = {
  gantt_calendars: [{id: 'g1', name: 'Plan'}],
  gantt_items: [{id: 'p1', calendar_id: 'g1', title: 'Launch phase', description: 'ship it', date: '2026-09-01', parent: 'Plan'}],
  calendar_events: [{id: 'e1', calendar_id: 'c1', title: 'Dentist', location: 'Town', date: '2026-09-02', tag_id: 't1'}],
  board_workplaces: [{id: 'w1', name: 'Work', board: {columns: [{id: 'col1', name: 'To do'}], tasks: [{id: 'k1', title: 'Launch email', column_id: 'col1', tag_ids: ['x']}], tags: [{id: 'x', name: 'urgent'}]}}],
  schedules: [{data: {blocks: [{id: 's1', title: 'Study', start: '09:00', end: '10:00', tagId: 'tg'}], tagDefinitions: [{id: 'tg', name: 'uni'}]}}],
  calendar_tags: [{tags: [{id: 't1', name: 'health'}]}],
};
const pool = {query: async sql => ({rows: rows[sql.match(/public\.(\w+)/)[1]]})};
const run = async body => {
  let sent;
  const reply = {code: c => ({send: b => (sent = {code: c, body: b})})};
  const result = await searchHandler(pool)({body, userProfile: {id: 'u'}, log: {error() {}}}, reply);
  return sent ?? result;
};

test('search rejects empty, oversized and invalid-offset queries', async () => {
  for (const body of [{}, {query: '  '}, {query: 'a'.repeat(201)}, {query: 'a', offset: -1}, {query: 'a', offset: 1.5}])
    assert.equal((await run(body)).code, 400);
});

test('search spans pages, matches every term, tags and parents, and ranks title hits first', async () => {
  const r = await run({query: 'launch'});
  assert.equal(r.total, 2);
  assert.deepEqual(r.results.map(i => i.type).sort(), ['Phase', 'Task']);
  assert.equal((await run({query: 'urgent'})).results[0].id, 'k1');
  assert.equal((await run({query: 'health dentist'})).results[0].id, 'e1');
  assert.equal((await run({query: 'uni'})).results[0].time, '09:00–10:00');
  assert.equal((await run({query: 'launch zzz'})).total, 0);
});

test('search paginates in pages of 50', async () => {
  assert.equal((await run({query: 'launch', offset: 1})).results.length, 1);
});
