import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {ganttHandler} from '../src/gantt.js';
import {padsHandler} from '../src/pads.js';
import {boardsHandler} from '../src/boards.js';
import {projectsHandler} from '../src/projects.js';
import {addUser, call, makeDb} from './helpers/pglite.js';

// What the desktop app sends after working without a connection: calendars,
// Gantt calendars and projects it holds replace the server's.

const item = (title, extra = {}) => ({
  id: randomUUID(), title, description: '', start_date: '2026-10-01', end_date: '2026-10-03', completed: false, prerequisite_id: null, ...extra,
});

test('a calendar made offline is added with its events, and a changed one is replaced', async () => {
  const {pool} = await makeDb();
  const owner = await addUser(pool, 'owner');
  const calendar = ganttHandler(pool, 'calendar');
  const send = (body, who = owner) => call(calendar, body, who);

  const id = randomUUID();
  const first = item('Dentist', {start_time: '09:00', end_time: '10:00', location: ' Clinic '});
  const second = item('Follow up', {prerequisite_id: first.id});
  const made = await send({action: 'syncCalendar', calendar_id: id, name: 'Offline calendar', color: '#2563EB', items: [first, second]});
  assert.equal(made.status, 200, JSON.stringify(made.body));
  const listed = (await send({action: 'listCalendars'})).body.calendars;
  assert.deepEqual(listed.map(c => [c.id, c.name, c.color]), [[id, 'Offline calendar', '#2563EB']]);
  const items = (await send({action: 'listItems', calendar_id: id})).body.items;
  assert.deepEqual(items.map(i => i.title), ['Dentist', 'Follow up']);
  assert.equal(items[0].start_time, '09:00');
  assert.equal(items[0].location, 'Clinic');
  assert.equal(items[1].prerequisite_id, first.id);

  // Changed on the server meanwhile; the offline copy wins.
  await send({action: 'saveItem', calendar_id: id, title: 'Added elsewhere', start_date: '2026-10-05', completed: false});
  const third = item('Only offline');
  const again = await send({action: 'syncCalendar', calendar_id: id, name: 'Renamed offline', color: '#DC2626', items: [{...first, title: 'Dentist (moved)'}, third]});
  assert.equal(again.status, 200);
  const after = (await send({action: 'listItems', calendar_id: id})).body.items;
  assert.deepEqual(after.map(i => i.title), ['Dentist (moved)', 'Only offline']);
  assert.equal(after[0].id, first.id, 'an item that stays keeps its id');
  assert.equal((await send({action: 'listCalendars'})).body.calendars[0].name, 'Renamed offline');
});

test('syncing a calendar is checked like any other change', async () => {
  const {pool} = await makeDb();
  const owner = await addUser(pool, 'owner');
  const other = await addUser(pool, 'other');
  const calendar = ganttHandler(pool, 'calendar');
  const send = (body, who = owner) => call(calendar, body, who);
  const id = randomUUID();
  const base = {action: 'syncCalendar', calendar_id: id, name: 'Cal', color: '#2563EB', items: []};
  const a = item('A'), b = item('B');
  for (const bad of [
    {...base, calendar_id: 'nope'},
    {...base, name: ''},
    {...base, color: 'red'},
    {...base, items: 'no'},
    {...base, items: [{...a, title: ''}]},
    {...base, items: [{...a, completed: 'yes'}]},
    {...base, items: [{...a, end_date: '2026-09-01'}]},
    {...base, items: [{...a, start_time: '10:00', end_time: '09:00'}]},
    {...base, items: [{...a, tag_id: 'not-a-tag'}]},
    {...base, items: [{...a, prerequisite_id: randomUUID()}]},
    {...base, items: [{...a, prerequisite_id: b.id}, {...b, prerequisite_id: a.id}]},
    {...base, items: [a, a]},
  ]) {
    assert.equal((await send(bad)).status, 400, JSON.stringify(bad).slice(0, 120));
  }
  assert.equal((await send({action: 'listCalendars'})).body.calendars.length, 0);
  await send(base);
  const stolen = await send({...base, name: 'Theirs'}, other);
  assert.equal(stolen.status, 404);
  assert.equal((await send({action: 'listCalendars'})).body.calendars[0].name, 'Cal');
});

test('a Gantt calendar is synced after its document, and not made without one', async () => {
  const {pool} = await makeDb();
  const owner = await addUser(pool, 'owner');
  const pads = padsHandler(pool);
  const gantt = ganttHandler(pool);
  const phase = item('Design', {kind: 'event'});
  const missing = await call(gantt, {action: 'syncCalendar', calendar_id: randomUUID(), name: 'Gone', color: '#2563EB', items: []}, owner);
  assert.equal(missing.status, 404);
  const doc = (await call(pads, {action: 'createPad', name: 'Roadmap', kind: 'gantt'}, owner)).body.pad;
  const done = await call(gantt, {action: 'syncCalendar', calendar_id: doc.id, name: 'Roadmap', color: '#DC2626', items: [phase, item('Build', {prerequisite_id: phase.id})]}, owner);
  assert.equal(done.status, 200, JSON.stringify(done.body));
  const calendars = (await call(gantt, {action: 'listCalendars'}, owner)).body.calendars;
  assert.deepEqual(calendars.map(c => [c.id, c.color]), [[doc.id, '#DC2626']]);
  const items = (await call(gantt, {action: 'listItems', calendar_id: doc.id}, owner)).body.items;
  assert.deepEqual(items.map(i => i.title), ['Design', 'Build']);
});

test('a project made offline is added with its links, and a changed one is replaced', async () => {
  const {pool} = await makeDb();
  const owner = await addUser(pool, 'owner');
  const projects = projectsHandler(pool);
  const boards = boardsHandler(pool);
  const send = (body, who = owner) => call(projects, body, who);
  const board = (await call(boards, {action: 'createWorkplace', name: 'Plan'}, owner)).body.workplace;

  const id = randomUUID();
  const made = await send({action: 'syncProject', project: {id, name: 'Offline project', description: 'd', color: '#dc2626'}, links: [{kind: 'board', id: board.id}, {kind: 'board', id: randomUUID()}]});
  assert.equal(made.status, 200, JSON.stringify(made.body));
  assert.equal(made.body.linked, 1, 'a link to something that is gone is left out');
  const listed = (await send({action: 'listProjects'})).body.projects;
  assert.equal(listed[0].id, id);
  assert.equal(listed[0].color, '#DC2626');
  assert.equal(listed[0].counts.board, 1);

  await send({action: 'unlinkItem', projectId: id, kind: 'board', targetId: board.id});
  const again = await send({action: 'syncProject', project: {id, name: 'Renamed', description: '', color: '#2563EB'}, links: [{kind: 'board', id: board.id}]});
  assert.equal(again.status, 200);
  const shown = (await send({action: 'getProject', projectId: id})).body;
  assert.equal(shown.project.name, 'Renamed');
  assert.equal(shown.boards.length, 1);
});

test('syncing a project is checked like any other change', async () => {
  const {pool} = await makeDb();
  const owner = await addUser(pool, 'owner');
  const other = await addUser(pool, 'other');
  const projects = projectsHandler(pool);
  const send = (body, who = owner) => call(projects, body, who);
  const id = randomUUID();
  for (const bad of [
    {project: null, links: []},
    {project: {id: 'x', name: 'a'}, links: []},
    {project: {id, name: ''}, links: []},
    {project: {id, name: 'a', color: 'red'}, links: []},
    {project: {id, name: 'a'}, links: 'no'},
    {project: {id, name: 'a'}, links: [{kind: 'nope', id: randomUUID()}]},
  ]) {
    assert.equal((await send({action: 'syncProject', ...bad})).status, 400, JSON.stringify(bad));
  }
  await send({action: 'syncProject', project: {id, name: 'Mine'}, links: []});
  assert.equal((await send({action: 'syncProject', project: {id, name: 'Theirs'}, links: []}, other)).status, 404);
  assert.equal((await send({action: 'listProjects'})).body.projects[0].name, 'Mine');
});
