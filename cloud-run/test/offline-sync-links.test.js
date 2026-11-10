import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {linksHandler} from '../src/links.js';
import {ganttHandler} from '../src/gantt.js';
import {boardsHandler} from '../src/boards.js';
import {scheduleHandler} from '../src/schedule.js';
import {padsHandler} from '../src/pads.js';
import {addUser, call, makeDb} from './helpers/pglite.js';

// Links made without a connection, and calendar events saved on a computer that
// had no copy of the schedule.

async function world(pool, owner) {
  const boards = boardsHandler(pool), calendar = ganttHandler(pool, 'calendar'), gantt = ganttHandler(pool);
  const pads = padsHandler(pool), schedule = scheduleHandler(pool);
  const board = (await call(boards, {action: 'createWorkplace', name: 'Plan'}, owner)).body.workplace;
  const column = (await call(boards, {action: 'createTaskColumn', workplaceId: board.id, name: 'To do'}, owner)).body.column;
  const task = (await call(boards, {action: 'createOrgTask', workplaceId: board.id, columnId: column.id, title: 'Ship'}, owner)).body.task;
  const cal = (await call(calendar, {action: 'createCalendar', name: 'Cal'}, owner)).body.calendar;
  await call(calendar, {action: 'saveItem', calendar_id: cal.id, title: 'Dentist', completed: false, start_date: '2026-10-01'}, owner);
  const calEvent = (await call(calendar, {action: 'listItems', calendar_id: cal.id}, owner)).body.items[0];
  const doc = (await call(pads, {action: 'createPad', name: 'Roadmap', kind: 'gantt'}, owner)).body.pad;
  await call(gantt, {action: 'saveItem', calendar_id: doc.id, title: 'Design', completed: false, start_date: '2026-10-01', end_date: '2026-10-02'}, owner);
  const phase = (await call(gantt, {action: 'listItems', calendar_id: doc.id}, owner)).body.items[0];
  await call(schedule, {action: 'saveBlock', date: '2026-10-01', title: 'Session', start: '09:00', end: '10:00'}, owner);
  const session = (await call(schedule, {action: 'getAll'}, owner)).body.blocks[0];
  return {board, column, task, calEvent, phase, session};
}

test('links can be read all at once and sent back', async () => {
  const {pool} = await makeDb();
  const owner = await addUser(pool, 'owner');
  const links = linksHandler(pool);
  const send = (body, who = owner) => call(links, body, who);
  const w = await world(pool, owner);
  const t = {workplaceId: w.board.id, taskId: w.task.id};

  assert.equal((await send({action: 'link', source: 'event', targetType: 'task', eventId: w.phase.id, ...t})).status, 200);
  assert.equal((await send({action: 'link', source: 'calendar', targetType: 'task', calendarEventId: w.calEvent.id, ...t})).status, 200);
  assert.equal((await send({action: 'link', source: 'calendar', targetType: 'event', calendarEventId: w.calEvent.id, eventId: w.phase.id})).status, 200);
  assert.equal((await send({action: 'link', source: 'session', targetType: 'task', sessionId: w.session.id, ...t})).status, 200);
  assert.equal((await send({action: 'link', source: 'event', targetType: 'panel', eventId: w.phase.id, workplaceId: w.board.id, panelId: w.column.id})).status, 200);

  const all = (await send({action: 'listAll'})).body;
  assert.equal(all.eventTask.length, 1);
  assert.equal(all.calendarTask.length, 1);
  assert.equal(all.calendarGantt.length, 1);
  assert.equal(all.session.length, 1);
  assert.equal(all.eventPanel.length, 1);

  // Take a link away and add another, offline; the whole set is sent.
  const next = {...all, eventTask: [], calendarGantt: [], calendarPanel: [{calendar_event_id: w.calEvent.id, workplace_id: w.board.id, panel_id: w.column.id}]};
  const sent = await send({action: 'syncLinks', links: next});
  assert.equal(sent.status, 200, JSON.stringify(sent.body));
  const after = (await send({action: 'listAll'})).body;
  assert.equal(after.eventTask.length, 0);
  assert.equal(after.calendarGantt.length, 0);
  assert.equal(after.calendarTask.length, 1);
  assert.equal(after.calendarPanel.length, 1);
  assert.equal(after.session.length, 1);
  assert.equal(after.eventPanel.length, 1, 'kept because it was sent');
  // The normal list agrees.
  const options = (await send({action: 'list', source: 'event', eventId: w.phase.id})).body.options;
  assert.equal(options.find(o => o.target_type === 'task').linked, false);
});

test('links to things that are gone, or not valid, are handled', async () => {
  const {pool} = await makeDb();
  const owner = await addUser(pool, 'owner');
  const other = await addUser(pool, 'other');
  const links = linksHandler(pool);
  const send = (body, who = owner) => call(links, body, who);
  const w = await world(pool, owner);
  const gone = randomUUID();
  const given = {
    eventTask: [{event_id: w.phase.id, workplace_id: w.board.id, task_id: w.task.id}, {event_id: gone, workplace_id: w.board.id, task_id: w.task.id}, {event_id: w.phase.id, workplace_id: w.board.id, task_id: gone}],
    session: [{session_id: w.session.id, calendar_event_id: w.calEvent.id}, {session_id: gone, calendar_event_id: w.calEvent.id}],
  };
  const done = await send({action: 'syncLinks', links: given});
  assert.equal(done.status, 200);
  assert.equal(done.body.linked, 2, 'only the links to things that exist');
  for (const bad of [
    null,
    {eventTask: 'no'},
    {eventTask: [{event_id: 'x', workplace_id: w.board.id, task_id: w.task.id}]},
    {session: [{session_id: w.session.id}]},
    {session: [{session_id: w.session.id, event_id: w.phase.id, calendar_event_id: w.calEvent.id}]},
    {session: [{session_id: w.session.id, workplace_id: w.board.id}]},
  ]) {
    assert.equal((await send({action: 'syncLinks', links: bad})).status, 400, JSON.stringify(bad));
  }
  assert.equal((await send({action: 'listAll'})).body.eventTask.length, 1, 'a refused set changes nothing');
  // Isolated by owner: someone else cannot use these.
  const theirs = await send({action: 'syncLinks', links: given}, other);
  assert.equal(theirs.status, 200);
  assert.equal(theirs.body.linked, 0);
  assert.equal((await send({action: 'listAll'})).body.eventTask.length, 1);
});

test('events saved offline get their sessions made when they are sent', async () => {
  const {pool} = await makeDb();
  const owner = await addUser(pool, 'owner');
  const calendar = ganttHandler(pool, 'calendar');
  const schedule = scheduleHandler(pool);
  const id = randomUUID();
  const timed = {id: randomUUID(), title: 'Conference', description: 'notes', start_date: '2026-10-01', end_date: '2026-10-03', completed: false, prerequisite_id: null, start_time: '09:00', end_time: '17:00', location: 'Hall'};
  const plain = {id: randomUUID(), title: 'No times', description: '', start_date: '2026-10-05', end_date: '2026-10-05', completed: false, prerequisite_id: null};
  const sent = await call(calendar, {action: 'syncCalendar', calendar_id: id, name: 'Cal', color: '#2563EB', items: [timed, plain], session_events: [timed.id, plain.id, randomUUID()]}, owner);
  assert.equal(sent.status, 200, JSON.stringify(sent.body));
  const blocks = (await call(schedule, {action: 'getAll'}, owner)).body.blocks;
  assert.deepEqual(blocks.map(b => b.date), ['2026-10-01', '2026-10-02', '2026-10-03']);
  assert.ok(blocks.every(b => b.calendarEventId === timed.id && b.title === 'Conference' && b.start === '09:00' && b.location === 'Hall'));
  // Without the list, no sessions are touched.
  const again = await call(calendar, {action: 'syncCalendar', calendar_id: id, name: 'Cal', color: '#2563EB', items: [{...timed, title: 'Renamed'}, plain]}, owner);
  assert.equal(again.status, 200);
  assert.equal((await call(schedule, {action: 'getAll'}, owner)).body.blocks[0].title, 'Conference');
  // Taking the times away removes the sessions when listed.
  await call(calendar, {action: 'syncCalendar', calendar_id: id, name: 'Cal', color: '#2563EB', items: [{...timed, start_time: null, end_time: null}, plain], session_events: [timed.id]}, owner);
  assert.equal((await call(schedule, {action: 'getAll'}, owner)).body.blocks.length, 0);
});
