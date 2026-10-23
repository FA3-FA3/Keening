import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { makeDb, migrateFrom, addUser, call } from './helpers/pglite.js';
import { padsHandler, KINDS } from '../src/pads.js';
import { ganttHandler } from '../src/gantt.js';
import { projectsHandler } from '../src/projects.js';
import { searchHandler } from '../src/search.js';

test('Gantt is one of the document types', () => {
  assert.ok(KINDS.includes('gantt'));
});

test('existing Gantt calendars become documents at the top level, once', async () => {
  const { pg, pool } = await makeDb(21);
  const owner = await addUser(pool, 'ann');
  const other = await addUser(pool, 'bob');
  const mk = async (who, name) => (await pool.query("INSERT INTO public.gantt_calendars(owner_id,name,color) VALUES($1,$2,'#2563EB') RETURNING id", [who, name])).rows[0].id;
  const a = await mk(owner, 'Launch'), b = await mk(owner, 'Hiring'), c = await mk(other, 'Bob plan');
  await pool.query("INSERT INTO public.gantt_items(calendar_id,kind,title,start_date,end_date) VALUES($1,'event','Design','2026-01-01','2026-01-05')", [a]);
  const project = (await pool.query("INSERT INTO public.projects(owner_id,name) VALUES($1,'P') RETURNING id", [owner])).rows[0].id;
  await pool.query("INSERT INTO public.project_links(project_id,owner_id,kind,target_id) VALUES($1,$2,'gantt',$3)", [project, owner, a]);
  // An ordinary document with a folder, to be left alone.
  const folder = (await pool.query("INSERT INTO public.pad_folders(owner_id,name) VALUES($1,'Docs') RETURNING id", [owner])).rows[0].id;
  await pool.query("INSERT INTO public.pads(owner_id,name,kind,folder_id) VALUES($1,'Notes','notepad',$2)", [owner, folder]);

  await migrateFrom(pg, 21);
  const docs = (await pool.query("SELECT id,owner_id,name,kind,folder_id,doc FROM public.pads WHERE kind='gantt' ORDER BY name")).rows;
  assert.deepEqual(docs.map(d => d.name), ['Bob plan', 'Hiring', 'Launch']);
  assert.deepEqual(new Set(docs.map(d => d.id)), new Set([a, b, c]), 'a calendar and its document share an id');
  assert.ok(docs.every(d => d.folder_id === null), 'in the default directory');
  assert.equal(docs.find(d => d.id === c).owner_id, other);
  assert.deepEqual(docs[0].doc, { version: 1 });
  // Nothing else changed.
  assert.equal((await pool.query('SELECT count(*)::int AS n FROM public.gantt_calendars')).rows[0].n, 3);
  assert.equal((await pool.query('SELECT count(*)::int AS n FROM public.gantt_items')).rows[0].n, 1);
  assert.equal((await pool.query('SELECT count(*)::int AS n FROM public.project_links')).rows[0].n, 1);
  const notes = (await pool.query("SELECT folder_id FROM public.pads WHERE name='Notes'")).rows[0];
  assert.equal(notes.folder_id, folder);
  assert.equal((await pool.query("SELECT color FROM public.gantt_calendars WHERE id=$1", [a])).rows[0].color, '#2563EB');

  // Running it again changes nothing.
  await migrateFrom(pg, 21);
  assert.equal((await pool.query("SELECT count(*)::int AS n FROM public.pads WHERE kind='gantt'")).rows[0].n, 3);
  assert.equal((await pool.query('SELECT count(*)::int AS n FROM public.gantt_calendars')).rows[0].n, 3);
});

test('Gantt calendars live as documents, through the documents and Gantt routes', async () => {
  const { pool } = await makeDb();
  const owner = await addUser(pool, 'ann');
  const other = await addUser(pool, 'bob');
  const pads = padsHandler(pool), gantt = ganttHandler(pool), projects = projectsHandler(pool), search = searchHandler(pool);
  const P = (who, body) => call(pads, body, who);
  const G = (who, body) => call(gantt, body, who);

  // Creating a Gantt document makes its calendar, with the same id and name.
  let r = await P(owner, { action: 'createPad', name: 'Roadmap', kind: 'gantt', description: 'Q1' });
  assert.equal(r.status, 200);
  const id = r.body.pad.id;
  assert.equal(r.body.pad.kind, 'gantt');
  assert.equal(r.body.pad.folder_id, null);
  let cals = (await G(owner, { action: 'listCalendars' })).body.calendars;
  assert.deepEqual(cals.map(c => [c.id, c.name]), [[id, 'Roadmap']]);
  assert.equal((await G(other, { action: 'listCalendars' })).body.calendars.length, 0);

  // Its phases work as before.
  r = await G(owner, { action: 'saveItem', calendar_id: id, title: 'Design', start_date: '2026-02-01', end_date: '2026-02-10', completed: false });
  assert.equal(r.status, 200);
  assert.equal((await G(owner, { action: 'listItems', calendar_id: id })).body.items.length, 1);
  assert.equal((await G(other, { action: 'listItems', calendar_id: id })).status, 404);

  // Renaming the document renames the calendar (both ways round).
  assert.equal((await P(owner, { action: 'updatePad', padId: id, name: 'Roadmap 2026' })).status, 200);
  assert.equal((await G(owner, { action: 'listCalendars' })).body.calendars[0].name, 'Roadmap 2026');
  assert.equal((await G(owner, { action: 'renameCalendar', calendar_id: id, name: 'Plan' })).status, 200);
  assert.equal((await pool.query('SELECT name FROM public.pads WHERE id=$1', [id])).rows[0].name, 'Plan');
  assert.equal((await P(owner, { action: 'renamePad', padId: id, name: 'Plan B' })).status, 200);
  assert.equal((await G(owner, { action: 'listCalendars' })).body.calendars[0].name, 'Plan B');

  // A calendar made through the Gantt route is a document too.
  r = await G(owner, { action: 'createCalendar', name: 'Hiring', color: '#7C3AED' });
  assert.equal(r.status, 200);
  assert.equal(r.body.calendar.color, '#7C3AED');
  const second = r.body.calendar.id;
  const listed = (await P(owner, { action: 'listPads' })).body.pads;
  assert.deepEqual(listed.filter(p => p.kind === 'gantt').map(p => p.name).sort(), ['Hiring', 'Plan B']);
  assert.equal(listed.find(p => p.id === second).folder_id, null);

  // It can move into a folder like any document, and nothing breaks.
  const folder = (await P(owner, { action: 'createFolder', name: 'Plans' })).body.folder;
  assert.equal((await P(owner, { action: 'movePad', padId: id, folderId: folder.id })).body.pad.folder_id, folder.id);
  assert.equal((await G(owner, { action: 'listItems', calendar_id: id })).body.items.length, 1);

  // It has no content of its own to save, and no pictures.
  assert.equal((await P(owner, { action: 'savePad', padId: id, doc: { version: 1 } })).status, 400);
  assert.equal((await P(owner, { action: 'uploadImage', padId: id, image: 'AAAA' })).status, 400);
  const got = (await P(owner, { action: 'getPad', padId: id })).body.pad;
  assert.equal(got.kind, 'gantt');

  // Projects list it as a calendar, not as a document; search finds it once.
  const link = (await call(projects, { action: 'listLinkable' }, owner)).body;
  assert.deepEqual(link.gantt.map(c => c.id).sort(), [id, second].sort());
  assert.equal(link.document.filter(d => d.kind === 'gantt').length, 0);
  const found = (await call(search, { query: 'Plan B' }, owner)).body.results.filter(x => x.title === 'Plan B');
  assert.equal(found.length, 1);
  assert.equal(found[0].page, 'Gantt');
  assert.equal(found[0].parentId, id);

  // Deleting the document deletes the calendar, its phases and its project link.
  const project = (await call(projects, { action: 'createProject', name: 'Q1' }, owner)).body.project.id;
  await call(projects, { action: 'linkItems', projectId: project, items: [{ kind: 'gantt', id }] }, owner);
  assert.equal((await pool.query('SELECT count(*)::int AS n FROM public.project_links WHERE target_id=$1', [id])).rows[0].n, 1);
  assert.equal((await P(other, { action: 'deletePad', padId: id })).status, 404);
  assert.equal((await P(owner, { action: 'deletePad', padId: id })).status, 200);
  assert.equal((await pool.query('SELECT count(*)::int AS n FROM public.gantt_calendars WHERE id=$1', [id])).rows[0].n, 0);
  assert.equal((await pool.query('SELECT count(*)::int AS n FROM public.gantt_items WHERE calendar_id=$1', [id])).rows[0].n, 0);
  assert.equal((await pool.query('SELECT count(*)::int AS n FROM public.project_links WHERE target_id=$1', [id])).rows[0].n, 0);

  // Deleting through the Gantt route deletes the document.
  assert.equal((await G(owner, { action: 'deleteCalendar', calendar_id: second })).status, 200);
  assert.equal((await pool.query('SELECT count(*)::int AS n FROM public.pads WHERE id=$1', [second])).rows[0].n, 0);
  assert.equal((await G(owner, { action: 'listCalendars' })).body.calendars.length, 0);

  // Deleting a folder deletes the Gantt calendars inside it.
  const inside = (await P(owner, { action: 'createPad', name: 'In folder', kind: 'gantt', folderId: folder.id })).body.pad.id;
  assert.equal((await P(owner, { action: 'deleteFolder', folderId: folder.id })).status, 200);
  assert.equal((await pool.query('SELECT count(*)::int AS n FROM public.gantt_calendars WHERE id=$1', [inside])).rows[0].n, 0);
});

test('the separate Calendar page is not affected', async () => {
  const { pool } = await makeDb();
  const owner = await addUser(pool, 'ann');
  const calendar = ganttHandler(pool, 'calendar');
  const made = await call(calendar, { action: 'createCalendar', name: 'Diary' }, owner);
  assert.equal(made.status, 200);
  assert.equal((await pool.query('SELECT count(*)::int AS n FROM public.pads')).rows[0].n, 0, 'no document for it');
  assert.equal((await call(calendar, { action: 'renameCalendar', calendar_id: made.body.calendar.id, name: 'Journal' }, owner)).status, 200);
  assert.equal((await call(calendar, { action: 'deleteCalendar', calendar_id: made.body.calendar.id }, owner)).status, 200);
  assert.ok(randomUUID());
});
