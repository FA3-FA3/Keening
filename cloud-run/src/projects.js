// Projects: a named group of Gantt calendars, boards, documents and document
// folders, read together. A project only holds links; the linked things keep
// living (and being edited) on their own pages.
const uuid = value => typeof value === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);
const fail = (message, statusCode = 400) => { throw Object.assign(new Error(message), { publicMessage: message, statusCode }); };

export const LINK_KINDS = ['gantt', 'board', 'document', 'folder'];
export const LIMITS = { projects: 100, links: 200, description: 1000, documents: 500 };

// The table each kind of link points at (every one has an owner_id).
const TARGETS = {
  gantt: 'public.gantt_calendars',
  board: 'public.board_workplaces',
  document: 'public.pads',
  folder: 'public.pad_folders',
};

export function projectName(value) {
  if (typeof value !== 'string' || !value.trim() || value.trim().length > 100) fail('Enter a name of 1–100 characters.');
  return value.trim();
}
export function projectDescription(value) {
  if (typeof value !== 'string' || value.length > LIMITS.description) fail(`Descriptions can be up to ${LIMITS.description} characters.`);
  return value.trim();
}
export function projectColour(value) {
  if (typeof value !== 'string' || !/^#[0-9a-f]{6}$/i.test(value)) fail('Invalid colour.');
  return value.toUpperCase();
}

// The ids of [roots] and every folder below them (a folder cycle cannot loop).
export function folderTree(folders, roots) {
  const children = new Map();
  for (const f of folders) {
    if (!children.has(f.parent_id)) children.set(f.parent_id, []);
    children.get(f.parent_id).push(f.id);
  }
  const seen = new Set();
  const stack = [...roots];
  while (stack.length) {
    const id = stack.pop();
    if (seen.has(id)) continue;
    seen.add(id);
    stack.push(...(children.get(id) ?? []));
  }
  return seen;
}

// "Work / Plans" for the folder [id].
export function folderPath(folders, id) {
  const names = [];
  const byId = new Map(folders.map(f => [f.id, f]));
  for (let f = byId.get(id); f && names.length < 20; f = byId.get(f.parent_id)) names.unshift(f.name);
  return names.join(' / ');
}

// What the board view needs of a board: panels and a trimmed task list.
export function boardSummary(row) {
  const board = row.board ?? {};
  return {
    id: row.id,
    name: row.name,
    columns: (board.columns ?? []).map(c => ({ id: c.id, name: c.name })),
    tags: (board.tags ?? []).map(t => ({ id: t.id, name: t.name, color: t.color ?? null })),
    tasks: (board.tasks ?? []).map(t => ({
      id: t.id, column_id: t.column_id, title: t.title, color: t.color ?? null,
      completed: t.completed === true, archived: t.archived === true, tag_ids: t.tag_ids ?? [],
    })),
  };
}

const PROJECT_COLUMNS = 'id,name,description,color,created_at,updated_at';

export function projectsHandler(pool) {
  return async (request, reply) => {
    const b = request.body || {}, owner = request.userProfile.id;
    let db;
    try {
      const actions = ['listProjects', 'createProject', 'updateProject', 'deleteProject', 'getProject', 'listLinkable', 'linkItems', 'unlinkItem'];
      if (!actions.includes(b.action)) fail('Unknown project action.');
      db = await pool.connect();
      await db.query('BEGIN');
      let result;
      const owned = async id => {
        if (!uuid(id)) fail('Invalid project.');
        const row = (await db.query(`SELECT ${PROJECT_COLUMNS} FROM public.projects WHERE id=$1 AND owner_id=$2 FOR UPDATE`, [id, owner])).rows[0];
        if (!row) fail('Project not found.', 404);
        return row;
      };
      if (b.action === 'listProjects') {
        const projects = (await db.query(`SELECT ${PROJECT_COLUMNS} FROM public.projects WHERE owner_id=$1 ORDER BY lower(name),created_at,id`, [owner])).rows;
        const counts = (await db.query('SELECT project_id,kind,count(*)::int AS n FROM public.project_links WHERE owner_id=$1 GROUP BY 1,2', [owner])).rows;
        result = {
          projects: projects.map(p => ({
            ...p,
            counts: Object.fromEntries(LINK_KINDS.map(k => [k, counts.find(c => c.project_id === p.id && c.kind === k)?.n ?? 0])),
          })),
        };
      } else if (b.action === 'createProject') {
        const name = projectName(b.name);
        const description = b.description === undefined ? '' : projectDescription(b.description);
        const color = b.color === undefined ? '#2563EB' : projectColour(b.color);
        await db.query('SELECT id FROM public.users WHERE id=$1 FOR UPDATE', [owner]);
        const count = await db.query('SELECT count(*)::int AS count FROM public.projects WHERE owner_id=$1', [owner]);
        if (count.rows[0].count >= LIMITS.projects) fail(`You can create up to ${LIMITS.projects} projects.`);
        result = { project: (await db.query(`INSERT INTO public.projects(owner_id,name,description,color) VALUES($1,$2,$3,$4) RETURNING ${PROJECT_COLUMNS}`, [owner, name, description, color])).rows[0] };
      } else if (b.action === 'listLinkable') {
        const [gantt, boards, folders, documents] = await Promise.all([
          db.query('SELECT id,name,color FROM public.gantt_calendars WHERE owner_id=$1 ORDER BY lower(name),id', [owner]),
          db.query('SELECT id,name FROM public.board_workplaces WHERE owner_id=$1 ORDER BY lower(name),id', [owner]),
          db.query('SELECT id,name,parent_id FROM public.pad_folders WHERE owner_id=$1 ORDER BY lower(name),id', [owner]),
          db.query('SELECT id,name,kind,folder_id FROM public.pads WHERE owner_id=$1 ORDER BY lower(name),id', [owner]),
        ]);
        result = {
          gantt: gantt.rows,
          board: boards.rows,
          folder: folders.rows.map(f => ({ ...f, path: folderPath(folders.rows, f.id) })),
          document: documents.rows.map(d => ({ ...d, path: folderPath(folders.rows, d.folder_id) })),
        };
      } else {
        const project = await owned(b.projectId);
        if (b.action === 'updateProject') {
          const name = b.name === undefined ? project.name : projectName(b.name);
          const description = b.description === undefined ? project.description : projectDescription(b.description);
          const color = b.color === undefined ? project.color : projectColour(b.color);
          result = { project: (await db.query(`UPDATE public.projects SET name=$1,description=$2,color=$3,updated_at=now() WHERE id=$4 RETURNING ${PROJECT_COLUMNS}`, [name, description, color, project.id])).rows[0] };
        } else if (b.action === 'deleteProject') {
          await db.query('DELETE FROM public.projects WHERE id=$1', [project.id]);
          result = { deleted: true };
        } else if (b.action === 'linkItems') {
          // [items] is a list of {kind, id}; ones already linked are left as they are.
          if (!Array.isArray(b.items) || !b.items.length || b.items.length > LIMITS.links) fail('Choose something to link.');
          const wanted = new Map();
          for (const item of b.items) {
            if (!item || typeof item !== 'object' || !LINK_KINDS.includes(item.kind) || !uuid(item.id)) fail('Invalid item.');
            wanted.set(`${item.kind}:${item.id}`, item);
          }
          for (const kind of LINK_KINDS) {
            const ids = [...wanted.values()].filter(i => i.kind === kind).map(i => i.id);
            if (!ids.length) continue;
            const found = (await db.query(`SELECT id FROM ${TARGETS[kind]} WHERE owner_id=$1 AND id=ANY($2::uuid[])`, [owner, ids])).rows.length;
            if (found !== ids.length) fail('Something you chose could not be found.', 404);
          }
          const existing = (await db.query('SELECT count(*)::int AS n FROM public.project_links WHERE project_id=$1', [project.id])).rows[0].n;
          if (existing + wanted.size > LIMITS.links) fail(`A project can link up to ${LIMITS.links} things.`);
          for (const item of wanted.values()) {
            await db.query('INSERT INTO public.project_links(project_id,owner_id,kind,target_id) VALUES($1,$2,$3,$4) ON CONFLICT DO NOTHING', [project.id, owner, item.kind, item.id]);
          }
          await db.query('UPDATE public.projects SET updated_at=now() WHERE id=$1', [project.id]);
          result = { linked: wanted.size };
        } else if (b.action === 'unlinkItem') {
          if (!LINK_KINDS.includes(b.kind) || !uuid(b.targetId)) fail('Invalid item.');
          await db.query('DELETE FROM public.project_links WHERE project_id=$1 AND kind=$2 AND target_id=$3', [project.id, b.kind, b.targetId]);
          await db.query('UPDATE public.projects SET updated_at=now() WHERE id=$1', [project.id]);
          result = { unlinked: true };
        } else {
          // getProject: the project and everything it links, ready to view together.
          const links = (await db.query('SELECT kind,target_id FROM public.project_links WHERE project_id=$1', [project.id])).rows;
          const ids = kind => links.filter(l => l.kind === kind).map(l => l.target_id);
          const [calendars, boards, folders] = await Promise.all([
            db.query('SELECT id,name,color FROM public.gantt_calendars WHERE owner_id=$1 AND id=ANY($2::uuid[]) ORDER BY lower(name),id', [owner, ids('gantt')]),
            db.query('SELECT id,name,board FROM public.board_workplaces WHERE owner_id=$1 AND id=ANY($2::uuid[]) ORDER BY lower(name),id', [owner, ids('board')]),
            db.query('SELECT id,name,parent_id FROM public.pad_folders WHERE owner_id=$1', [owner]),
          ]);
          const items = calendars.rows.length
            ? (await db.query(`SELECT calendar_id,id,kind,title,description,start_date::text,end_date::text,completed,prerequisite_id
                FROM public.gantt_items WHERE calendar_id=ANY($1::uuid[]) ORDER BY calendar_id,calendar_position,id`, [calendars.rows.map(c => c.id)])).rows
            : [];
          const linkedFolders = folders.rows.filter(f => ids('folder').includes(f.id));
          const tree = folderTree(folders.rows, linkedFolders.map(f => f.id));
          const directIds = ids('document');
          const documents = await db.query(`SELECT id,name,description,kind,folder_id,updated_at,
              CASE WHEN kind='notepad' THEN left(doc->>'text',240) END AS preview
            FROM public.pads WHERE owner_id=$1 AND (id=ANY($2::uuid[]) OR folder_id=ANY($3::uuid[]))
            ORDER BY updated_at DESC,id LIMIT ${LIMITS.documents}`, [owner, directIds, [...tree]]);
          result = {
            project,
            gantt: calendars.rows.map(c => ({ ...c, items: items.filter(i => i.calendar_id === c.id).map(({ calendar_id, ...i }) => i) })),
            boards: boards.rows.map(boardSummary),
            folders: linkedFolders.map(f => {
              const below = folderTree(folders.rows, [f.id]);
              return { id: f.id, name: f.name, path: folderPath(folders.rows, f.id), subfolders: below.size - 1, documents: documents.rows.filter(d => below.has(d.folder_id)).length };
            }),
            documents: documents.rows.map(d => ({
              ...d,
              path: folderPath(folders.rows, d.folder_id),
              direct: directIds.includes(d.id),
            })),
          };
        }
      }
      await db.query('COMMIT');
      return result;
    } catch (error) {
      if (db) await db.query('ROLLBACK').catch(() => {});
      if (error.publicMessage) return reply.code(error.statusCode).send({ error: error.publicMessage });
      // Projects need migration 19 (and the documents tables); say so plainly.
      request.log.error({ errorCode: error.code || 'PROJECTS_FAILED' }, 'Project request failed');
      return reply.code(503).send({ error: 'Projects are unavailable. Please try again.' });
    } finally {
      db?.release();
    }
  };
}
