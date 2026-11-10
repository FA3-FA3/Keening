import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {boardsHandler} from '../src/boards.js';
import {scheduleHandler} from '../src/schedule.js';
import {addUser, call, makeDb} from './helpers/pglite.js';

// What the desktop app sends after working without a connection: its copy of a
// board or of the schedule replaces the one on the server.

const board = () => {
  const column = randomUUID(), tag = randomUUID();
  return {
    columns: [{id: column, name: 'To do', color: '#2E7D5B', archived: false, created_at: '2026-01-01T00:00:00.000Z', updated_at: '2026-01-01T00:00:00.000Z'}],
    tags: [{id: tag, name: 'Urgent', color: '#DC2626'}],
    tasks: [{id: randomUUID(), column_id: column, title: 'Written offline', description: 'd', color: null, tag_ids: [tag], completed: false, archived: false, created_at: '2026-01-01T00:00:00.000Z', updated_at: '2026-01-01T00:00:00.000Z'}],
  };
};

test('a board made offline is added, and one changed offline replaces the server one', async () => {
  const {pool} = await makeDb();
  const owner = await addUser(pool, 'owner');
  const boards = boardsHandler(pool);
  const send = (body, who = owner) => call(boards, body, who);

  const id = randomUUID();
  const made = await send({action: 'syncWorkplace', id, name: 'Offline board', board: board()});
  assert.equal(made.status, 200);
  assert.deepEqual(made.body.workplace, {id, name: 'Offline board'});
  assert.equal((await send({action: 'listWorkplaces'})).body.workplaces.length, 1);
  const got = (await send({action: 'getBoard', workplaceId: id})).body;
  assert.equal(got.tasks[0].title, 'Written offline');
  assert.equal(got.tasks[0].tags[0].name, 'Urgent');

  // Changed on the server meanwhile; the offline copy wins.
  const server = (await send({action: 'createTaskColumn', workplaceId: id, name: 'Elsewhere'})).body.column;
  const local = board();
  const again = await send({action: 'syncWorkplace', id, name: 'Renamed offline', board: local});
  assert.equal(again.status, 200);
  const after = (await send({action: 'getBoard', workplaceId: id})).body;
  assert.deepEqual(after.columns.map(c => c.id), [local.columns[0].id]);
  assert.ok(!after.columns.some(c => c.id === server.id));
  assert.equal((await send({action: 'listWorkplaces'})).body.workplaces[0].name, 'Renamed offline');
  assert.equal((await send({action: 'listWorkplaces'})).body.workplaces.length, 1);
});

test('syncing a board is checked like any other change', async () => {
  const {pool} = await makeDb();
  const owner = await addUser(pool, 'owner');
  const other = await addUser(pool, 'other');
  const boards = boardsHandler(pool);
  const send = (body, who = owner) => call(boards, body, who);
  const id = randomUUID();
  for (const bad of [
    {id: 'nope', name: 'x', board: board()},
    {id, name: '', board: board()},
    {id, name: 'x', board: null},
    {id, name: 'x', board: {columns: [], tags: [], tasks: 'no'}},
    {id, name: 'x', board: {...board(), tasks: [{...board().tasks[0], column_id: randomUUID()}]}},
    {id, name: 'x', board: {...board(), columns: [{...board().columns[0], color: 'red'}]}},
    {id, name: 'x', board: {...board(), tasks: [{...board().tasks[0], title: ''}]}},
  ]) {
    assert.equal((await send({action: 'syncWorkplace', ...bad})).status, 400, JSON.stringify(bad).slice(0, 80));
  }
  assert.equal((await send({action: 'listWorkplaces'})).body.workplaces.length, 0);
  // Somebody else's board cannot be overwritten.
  await send({action: 'syncWorkplace', id, name: 'Mine', board: board()});
  const stolen = await send({action: 'syncWorkplace', id, name: 'Theirs', board: board()}, other);
  assert.equal(stolen.status, 404);
  assert.equal((await send({action: 'listWorkplaces'})).body.workplaces[0].name, 'Mine');
});

test('the whole schedule can be read, and replaced after working offline', async () => {
  const {pool} = await makeDb();
  const owner = await addUser(pool, 'owner');
  const other = await addUser(pool, 'other');
  const schedule = scheduleHandler(pool);
  const send = (body, who = owner) => call(schedule, body, who);

  await send({action: 'saveBlock', date: '2026-09-30', title: 'On the server', start: '09:00', end: '10:00', color: '#D97706'});
  const all = (await send({action: 'getAll'})).body;
  assert.equal(all.blocks.length, 1);

  const group = {id: randomUUID(), name: 'Work'};
  const row = {id: randomUUID(), group_id: group.id, name: 'Me'};
  const tag = {id: randomUUID(), name: 'Gym', color: '#2563EB'};
  const blocks = [
    {id: randomUUID(), date: '2026-10-01', start: '08:00', end: '09:00', title: 'Offline A', note: '', color: '#2563EB', tagId: tag.id, location: ''},
    {id: randomUUID(), date: '2026-10-02', start: '10:00', end: '24:00', title: 'Offline B', note: 'n', color: '#6B7280', location: 'Home'},
  ];
  const put = await send({action: 'putAll', data: {groups: [group], rows: [row], blocks, tagDefinitions: [tag], tags: {}}});
  assert.equal(put.status, 200);
  const now = (await send({action: 'getAll'})).body;
  assert.deepEqual(now.blocks.map(b => b.title), ['Offline A', 'Offline B']);
  assert.deepEqual(now.groups, [group]);
  assert.deepEqual(now.tagDefinitions, [tag]);
  // The week view reads it too.
  const week = (await send({action: 'getWeek', startDate: '2026-09-28'})).body;
  assert.equal(week.blocks.length, 2);
  // Isolated by owner.
  assert.equal((await send({action: 'getAll'}, other)).body.blocks.length, 0);
});

test('a bad schedule is refused and changes nothing', async () => {
  const {pool} = await makeDb();
  const owner = await addUser(pool, 'owner');
  const schedule = scheduleHandler(pool);
  const send = body => call(schedule, body, owner);
  await send({action: 'saveBlock', date: '2026-09-30', title: 'Keep', start: '09:00', end: '10:00', color: '#D97706'});
  const ok = {groups: [], rows: [], blocks: [], tagDefinitions: [], tags: {}};
  const block = {id: randomUUID(), date: '2026-10-01', start: '08:00', end: '09:00', title: 'x', color: '#2563EB'};
  for (const data of [
    null,
    {...ok, blocks: 'no'},
    {...ok, blocks: [{...block, start: '25:00'}]},
    {...ok, blocks: [{...block, end: '07:00'}]},
    {...ok, blocks: [{...block, color: 'bad'}]},
    {...ok, blocks: [block, block]},
    {...ok, rows: [{id: randomUUID(), group_id: randomUUID(), name: 'orphan'}]},
    {...ok, blocks: Array.from({length: 5001}, () => ({...block, id: randomUUID()}))},
  ]) {
    assert.equal((await send({action: 'putAll', data})).status, 400, JSON.stringify(data)?.slice(0, 80));
  }
  assert.equal((await send({action: 'getAll'})).body.blocks.length, 1);
});
