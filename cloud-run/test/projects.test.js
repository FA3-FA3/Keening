import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import {createPool} from '../src/database.js';
import {buildApp} from '../src/app.js';
import {boardSummary, folderPath, folderTree, LINK_KINDS, projectColour, projectDescription, projectName, projectsHandler} from '../src/projects.js';

const id = () => randomUUID();

test('project names, descriptions and colours are validated', () => {
  assert.equal(projectName('  Launch  '), 'Launch');
  assert.equal(projectDescription('  notes  '), 'notes');
  assert.equal(projectColour('#e3f2fd'), '#E3F2FD');
  for (const bad of [undefined, null, 5, '', '   ', 'x'.repeat(101)]) assert.throws(() => projectName(bad), /./, String(bad));
  for (const bad of [undefined, null, 5, 'x'.repeat(1001)]) assert.throws(() => projectDescription(bad), /./, String(bad));
  for (const bad of [undefined, 'red', '#fff', '#12345g', 5]) assert.throws(() => projectColour(bad), /./, String(bad));
});

test('a folder brings every folder below it, and cycles cannot loop', () => {
  const [a, b, c, d, e] = [id(), id(), id(), id(), id()];
  const folders = [
    {id: a, name: 'Work', parent_id: null}, {id: b, name: 'Plans', parent_id: a},
    {id: c, name: '2026', parent_id: b}, {id: d, name: 'Home', parent_id: null}, {id: e, name: 'Taxes', parent_id: d},
  ];
  assert.deepEqual([...folderTree(folders, [a])].sort(), [a, b, c].sort());
  assert.deepEqual([...folderTree(folders, [b, d])].sort(), [b, c, d, e].sort());
  assert.deepEqual([...folderTree(folders, [])], []);
  assert.equal(folderPath(folders, c), 'Work / Plans / 2026');
  assert.equal(folderPath(folders, null), '');
  assert.equal(folderPath(folders, id()), '');
  // A damaged cycle ends rather than looping for ever.
  const loop = [{id: a, name: 'A', parent_id: b}, {id: b, name: 'B', parent_id: a}];
  assert.deepEqual([...folderTree(loop, [a])].sort(), [a, b].sort());
  assert.ok(folderPath(loop, a).length > 0);
});

test('a board is summarised without descriptions or attachments', () => {
  const summary = boardSummary({id: 'b', name: 'Sprint', board: {
    columns: [{id: 'c1', name: 'To do', extra: 1}],
    tags: [{id: 't1', name: 'Urgent', color: '#ff0000'}],
    tasks: [{id: 'k1', column_id: 'c1', title: 'Write', description: 'secret', completed: true, tag_ids: ['t1'], created_at: 'x'}, {id: 'k2', column_id: 'c1', title: 'Old', archived: true}],
  }});
  assert.deepEqual(summary, {
    id: 'b', name: 'Sprint', columns: [{id: 'c1', name: 'To do'}], tags: [{id: 't1', name: 'Urgent', color: '#ff0000'}],
    tasks: [
      {id: 'k1', column_id: 'c1', title: 'Write', color: null, completed: true, archived: false, tag_ids: ['t1']},
      {id: 'k2', column_id: 'c1', title: 'Old', color: null, completed: false, archived: true, tag_ids: []},
    ],
  });
  assert.deepEqual(boardSummary({id: 'x', name: 'Empty', board: null}).tasks, []);
});

// A scripted database: each call is answered by the first rule whose pattern
// matches the SQL; calls are recorded so a test can see what was written.
function fakePool(rules) {
  const calls = [];
  const db = {
    async query(sql, params = []) {
      calls.push({sql, params});
      for (const [pattern, answer] of rules) {
        if (pattern.test(sql)) return typeof answer === 'function' ? answer(params, sql) : {rows: answer};
      }
      return {rows: []};
    },
    release() {},
  };
  return {pool: {connect: async () => db}, calls};
}

async function call(pool, body, owner = id()) {
  const handler = projectsHandler(pool);
  const reply = {code(status) { this.status = status; return this; }, send(payload) { this.payload = payload; return payload; }};
  const result = await handler({body, userProfile: {id: owner}, log: {error() {}}}, reply);
  return {status: reply.status ?? 200, body: reply.payload ?? result};
}

test('the handler validates actions, ids and ownership', async () => {
  const mine = {id: id(), name: 'Launch', description: '', color: '#2563EB'};
  const {pool} = fakePool([[/FROM public\.projects WHERE id=\$1 AND owner_id=\$2/, params => ({rows: params[0] === mine.id ? [mine] : []})]]);
  assert.equal((await call(pool, {action: 'nope'})).status, 400);
  assert.equal((await call(pool, {})).status, 400);
  assert.equal((await call(pool, {action: 'getProject', projectId: 'bad'})).status, 400);
  assert.equal((await call(pool, {action: 'getProject', projectId: id()})).status, 404);
  assert.equal((await call(pool, {action: 'deleteProject', projectId: id()})).status, 404);
  assert.equal((await call(pool, {action: 'createProject', name: '  '})).status, 400);
  assert.equal((await call(pool, {action: 'createProject', name: 'ok', color: 'red'})).status, 400);
  assert.equal((await call(pool, {action: 'updateProject', projectId: mine.id, name: ''})).status, 400);
  assert.equal((await call(pool, {action: 'linkItems', projectId: mine.id, items: []})).status, 400);
  assert.equal((await call(pool, {action: 'linkItems', projectId: mine.id, items: [{kind: 'chart', id: id()}]})).status, 400);
  assert.equal((await call(pool, {action: 'linkItems', projectId: mine.id, items: [{kind: 'gantt', id: 'bad'}]})).status, 400);
  assert.equal((await call(pool, {action: 'linkItems', projectId: mine.id, items: 'x'})).status, 400);
  assert.equal((await call(pool, {action: 'unlinkItem', projectId: mine.id, kind: 'chart', targetId: id()})).status, 400);
});

test('linking checks that every item is the owner\'s, and respects the limit', async () => {
  const mine = {id: id(), name: 'Launch', description: '', color: '#2563EB'};
  const cal = id(), doc = id();
  let known = [cal];
  let linked = 0;
  const {pool, calls} = fakePool([
    [/FROM public\.projects WHERE id=\$1/, [mine]],
    [/SELECT id FROM public\.gantt_calendars WHERE owner_id/, params => ({rows: params[1].filter(i => known.includes(i)).map(i => ({id: i}))})],
    [/SELECT id FROM public\.pads WHERE owner_id/, params => ({rows: params[1].filter(i => known.includes(i)).map(i => ({id: i}))})],
    [/count\(\*\)::int AS n FROM public\.project_links/, () => ({rows: [{n: linked}]})],
  ]);
  const ok = await call(pool, {action: 'linkItems', projectId: mine.id, items: [{kind: 'gantt', id: cal}, {kind: 'gantt', id: cal}]});
  assert.equal(ok.status, 200);
  assert.deepEqual(ok.body, {linked: 1}, 'the same item twice is one link');
  assert.equal(calls.filter(c => /INSERT INTO public\.project_links/.test(c.sql)).length, 1);
  // Something that belongs to someone else (or does not exist) is refused whole.
  const before = calls.length;
  const other = await call(pool, {action: 'linkItems', projectId: mine.id, items: [{kind: 'gantt', id: cal}, {kind: 'document', id: doc}]});
  assert.equal(other.status, 404);
  assert.equal(calls.slice(before).filter(c => /INSERT/.test(c.sql)).length, 0);
  // The limit counts what is already linked.
  linked = 199;
  known = [cal, doc];
  const over = await call(pool, {action: 'linkItems', projectId: mine.id, items: [{kind: 'gantt', id: cal}, {kind: 'document', id: doc}]});
  assert.equal(over.status, 400);
  assert.match(over.body.error, /up to 200/);
});

test('getProject gathers calendars, boards, folders and documents', async () => {
  const mine = {id: id(), name: 'Launch', description: 'd', color: '#2563EB'};
  const [cal, board, work, plans, home, docA, docB, docC] = [id(), id(), id(), id(), id(), id(), id(), id()];
  const folders = [{id: work, name: 'Work', parent_id: null}, {id: plans, name: 'Plans', parent_id: work}, {id: home, name: 'Home', parent_id: null}];
  const {pool} = fakePool([
    [/FROM public\.projects WHERE id=\$1/, [mine]],
    [/SELECT kind,target_id FROM public\.project_links/, [
      {kind: 'gantt', target_id: cal}, {kind: 'board', target_id: board}, {kind: 'folder', target_id: work}, {kind: 'document', target_id: docC},
    ]],
    [/FROM public\.gantt_calendars/, [{id: cal, name: 'Plan', color: '#2E7D5B'}]],
    [/FROM public\.board_workplaces/, [{id: board, name: 'Sprint', board: {columns: [{id: 'c', name: 'Doing'}], tasks: [{id: 't', column_id: 'c', title: 'Do', completed: false}], tags: []}}]],
    [/FROM public\.pad_folders/, folders],
    [/FROM public\.gantt_items/, [{calendar_id: cal, id: id(), kind: 'event', title: 'Phase', description: '', start_date: '2026-01-01', end_date: '2026-01-31', completed: false, prerequisite_id: null}]],
    [/FROM public\.pads/, [
      {id: docA, name: 'Spec', description: '', kind: 'notepad', folder_id: plans, updated_at: 'x', preview: 'hello'},
      {id: docC, name: 'Budget', description: '', kind: 'sheet', folder_id: home, updated_at: 'y', preview: null},
    ]],
  ]);
  const r = await call(pool, {action: 'getProject', projectId: mine.id});
  assert.equal(r.status, 200);
  const p = r.body;
  assert.equal(p.project.name, 'Launch');
  assert.equal(p.gantt.length, 1);
  assert.equal(p.gantt[0].items.length, 1);
  assert.equal(p.gantt[0].items[0].calendar_id, undefined);
  assert.equal(p.boards[0].tasks[0].title, 'Do');
  assert.deepEqual(p.folders, [{id: work, name: 'Work', path: 'Work', subfolders: 1, documents: 1}]);
  const byName = Object.fromEntries(p.documents.map(d => [d.name, d]));
  assert.deepEqual([byName.Spec.direct, byName.Spec.path], [false, 'Work / Plans']);
  assert.deepEqual([byName.Budget.direct, byName.Budget.path], [true, 'Home']);
});

test('listProjects counts what each project links', async () => {
  const a = id(), b = id();
  const {pool} = fakePool([
    [/FROM public\.projects WHERE owner_id/, [{id: a, name: 'A'}, {id: b, name: 'B'}]],
    [/GROUP BY 1,2/, [{project_id: a, kind: 'gantt', n: 2}, {project_id: a, kind: 'document', n: 1}]],
  ]);
  const r = await call(pool, {action: 'listProjects'});
  assert.deepEqual(r.body.projects[0].counts, {gantt: 2, board: 0, document: 1, folder: 0});
  assert.deepEqual(r.body.projects[1].counts, {gantt: 0, board: 0, document: 0, folder: 0});
  assert.deepEqual(LINK_KINDS, ['gantt', 'board', 'document', 'folder']);
});

test('a project limit stops creation', async () => {
  const {pool} = fakePool([[/count\(\*\)::int AS count FROM public\.projects/, [{count: 100}]]]);
  const r = await call(pool, {action: 'createProject', name: 'One more'});
  assert.equal(r.status, 400);
  assert.match(r.body.error, /up to 100 projects/);
});

test('a database failure is reported without details', async () => {
  const pool = {connect: async () => ({query: async sql => { if (/BEGIN|ROLLBACK/.test(sql)) return {rows: []}; throw Object.assign(new Error('secret sql'), {code: '42P01'}); }, release() {}})};
  const r = await call(pool, {action: 'listProjects'});
  assert.equal(r.status, 503);
  assert.doesNotMatch(JSON.stringify(r.body), /secret/);
});

const databaseUrl = process.env.TEST_DATABASE_URL;
test('projects persist, link, view together and clean up', {skip: !databaseUrl}, async t => {
  assert.ok(['localhost', '127.0.0.1', '[::1]'].includes(new URL(databaseUrl).hostname));
  const pool = createPool(databaseUrl);
  for (const file of ['01-schema.sql', '02-usernames.sql', '08-profile-picture.sql', '03-gantt.sql', '04-boards.sql', '05-event-task-links.sql', '06-calendar.sql', '07-schedule.sql', '09-calendar-sessions.sql', '10-calendar-location.sql', '11-calendar-tags.sql', '12-event-panel-links.sql', '13-calendar-session-panel-links.sql', '14-pads.sql', '15-pad-descriptions.sql', '16-document-folders.sql', '17-attachments.sql', '18-sheets.sql', '19-projects.sql', '20-board-order.sql'])
    await pool.query(await readFile(new URL(`../../postgres/init/${file}`, import.meta.url), 'utf8'));
  const prefix = `proj-${randomUUID()}`;
  const app = await buildApp({pool, logger: false, origins: [], verifyIdToken: async token => ({uid: `${prefix}-${token}`, firebase: {sign_in_provider: 'password'}})});
  t.after(async () => { await pool.query('DELETE FROM public.users WHERE firebase_uid IN ($1,$2)', [`${prefix}-owner`, `${prefix}-other`]); await app.close(); });
  const post = async (url, data, token = 'owner', status = 200) => {
    const r = await app.inject({method: 'POST', url, headers: {authorization: `Bearer ${token}`}, payload: data});
    assert.equal(r.statusCode, status, r.body); return r.json();
  };
  const projects = (data, token, status) => post('/projects', data, token, status);
  assert.equal((await app.inject({method: 'POST', url: '/projects', payload: {action: 'listProjects'}})).statusCode, 401);

  const cal = (await post('/gantt', {action: 'createCalendar', name: 'Plan', color: '#2E7D5B'})).calendar;
  await post('/gantt', {action: 'saveItem', calendar_id: cal.id, title: 'Phase one', start_date: '2026-01-01', end_date: '2026-01-31', completed: false});
  const board = (await post('/boards', {action: 'createWorkplace', name: 'Sprint'})).workplace;
  const work = (await post('/pads', {action: 'createFolder', name: 'Work'})).folder;
  const plans = (await post('/pads', {action: 'createFolder', name: 'Plans', parentId: work.id})).folder;
  const spec = (await post('/pads', {action: 'createPad', name: 'Spec', kind: 'notepad', folderId: plans.id})).pad;
  const loose = (await post('/pads', {action: 'createPad', name: 'Loose', kind: 'sheet'})).pad;

  const project = (await projects({action: 'createProject', name: 'Launch', description: 'The big one', color: '#dc2626'})).project;
  assert.deepEqual([project.name, project.color], ['Launch', '#DC2626']);
  await projects({action: 'createProject', name: ' '}, 'owner', 400);
  assert.equal((await projects({action: 'listProjects'}, 'other')).projects.length, 0, 'projects are private');
  await projects({action: 'getProject', projectId: project.id}, 'other', 404);
  await projects({action: 'linkItems', projectId: project.id, items: [{kind: 'document', id: loose.id}]}, 'other', 404);

  await projects({action: 'linkItems', projectId: project.id, items: [{kind: 'gantt', id: cal.id}, {kind: 'board', id: board.id}, {kind: 'folder', id: work.id}, {kind: 'document', id: loose.id}]});
  await projects({action: 'linkItems', projectId: project.id, items: [{kind: 'gantt', id: cal.id}]}); // again: nothing changes
  const link = await projects({action: 'listLinkable'});
  assert.deepEqual([link.gantt.length, link.board.length, link.folder.length, link.document.length], [1, 1, 2, 2]);
  assert.equal(link.folder.find(f => f.id === plans.id).path, 'Work / Plans');
  assert.deepEqual((await projects({action: 'listProjects'})).projects[0].counts, {gantt: 1, board: 1, document: 1, folder: 1});

  const view = await projects({action: 'getProject', projectId: project.id});
  assert.equal(view.gantt[0].items[0].title, 'Phase one');
  assert.equal(view.boards[0].name, 'Sprint');
  assert.deepEqual(view.documents.map(d => [d.name, d.direct]).sort(), [['Loose', true], ['Spec', false]]);
  assert.deepEqual(view.folders.map(f => [f.name, f.subfolders, f.documents]), [['Work', 1, 1]]);

  // Deleting a linked thing removes its link; deleting a folder takes its documents' links too.
  await post('/pads', {action: 'deletePad', padId: loose.id});
  await post('/pads', {action: 'deleteFolder', folderId: work.id});
  await post('/boards', {action: 'deleteWorkplace', workplaceId: board.id});
  const left = await projects({action: 'getProject', projectId: project.id});
  assert.deepEqual([left.documents.length, left.folders.length, left.boards.length, left.gantt.length], [0, 0, 0, 1]);
  assert.equal((await pool.query('SELECT count(*)::int AS n FROM public.project_links WHERE project_id=$1', [project.id])).rows[0].n, 1);
  await projects({action: 'unlinkItem', projectId: project.id, kind: 'gantt', targetId: cal.id});
  assert.equal((await projects({action: 'getProject', projectId: project.id})).gantt.length, 0);
  assert.equal((await projects({action: 'updateProject', projectId: project.id, name: 'Renamed'})).project.name, 'Renamed');
  await projects({action: 'deleteProject', projectId: project.id});
  await projects({action: 'getProject', projectId: project.id}, 'owner', 404);
  assert.equal(spec.kind, 'notepad');
});
