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
  pad_folders: [{id: 'f1', name: 'Work notes', parent_id: null}, {id: 'f2', name: 'Recipes', parent_id: 'f1'}],
  pads: [
    {id: 'd1', name: 'Shopping list', description: '', kind: 'notepad', folder_id: 'f2', doc: {version: 1, text: 'buy oat milk and bread'}},
    {id: 'd2', name: 'Floor plan', description: 'the house', kind: 'pad', folder_id: null, doc: {version: 1, elements: []}},
  ],
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

test('search finds documents and folders, including the text inside notepads', async () => {
  const note = (await run({query: 'oat milk'})).results;
  assert.equal(note.length, 1);
  assert.deepEqual([note[0].type, note[0].page, note[0].id, note[0].parentId], ['Notepad', 'Documents', 'd1', 'f2']);
  assert.equal(note[0].parent, 'Work notes / Recipes');
  assert.equal(note[0].description, 'buy oat milk and bread', 'the start of the note shows as the description');
  assert.equal('searchBody' in note[0], false, 'whole notes are not sent back');
  const pad = (await run({query: 'house'})).results;
  assert.deepEqual(pad.map(r => [r.type, r.id, r.parentId]), [['Dynamic Pad', 'd2', null]]);
  const folders = (await run({query: 'recipes'})).results;
  assert.deepEqual(folders.map(r => [r.type, r.id, r.parentId]), [['Folder', 'f2', 'f2'], ['Notepad', 'd1', 'f2']]);
  assert.equal(folders[0].parent, 'Work notes');
  assert.equal((await run({query: 'shopping'})).results[0].title, 'Shopping list');
});

test('search still works when the document tables are missing', async () => {
  const missing = Object.assign(new Error('relation does not exist'), {code: '42P01'});
  const partial = {query: async sql => {
    if (/public\.pad/.test(sql)) throw missing;
    return pool.query(sql);
  }};
  const reply = {code: c => ({send: b => ({code: c, body: b})})};
  const result = await searchHandler(partial)({body: {query: 'launch'}, userProfile: {id: 'u'}, log: {error() {}}}, reply);
  assert.equal(result.total, 2);
  const other = Object.assign(new Error('boom'), {code: 'XX000'});
  const broken = {query: async sql => { if (/public\.pads/.test(sql)) throw other; return pool.query(sql); }};
  assert.equal((await searchHandler(broken)({body: {query: 'launch'}, userProfile: {id: 'u'}, log: {error() {}}}, reply)).code, 503);
});
