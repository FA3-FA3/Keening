import {sessionOptions,sessionSourceOptions,mutateSessionLink} from './calendar-sessions.js';
const uuid = value => typeof value === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);
const fail = (message, statusCode = 400) => { throw Object.assign(new Error(message), { publicMessage: message, statusCode }); };

// Board panels a phase, Calendar event or session can link to (panels are
// link targets only, so there is no panel-side list).
async function panelOptions(db, owner, b) {
  const [table, where, value] = b.source === 'event'
    ? ['event_panel_links', 'l.event_id=$2', b.eventId]
    : b.source === 'calendar'
      ? ['calendar_panel_links', 'l.calendar_event_id=$2', b.calendarEventId]
      : ['session_panel_links', 'l.owner_id=w.owner_id AND l.session_id=$2', b.sessionId];
  // Panel links need migrations 12 and 13; without them there are simply no panel options.
  await db.query('SAVEPOINT panel_options');
  try {
    const rows = (await db.query(`SELECT 'panel' AS target_type,w.id AS workplace_id,c->>'id' AS panel_id,c->>'name' AS title,
    'Boards · ' || w.name || ' · Panel' AS location,
    EXISTS(SELECT 1 FROM public.${table} l WHERE ${where} AND l.workplace_id=w.id AND l.panel_id::text=c->>'id') AS linked
    FROM public.board_workplaces w CROSS JOIN LATERAL jsonb_array_elements(w.board->'columns') c
    WHERE w.owner_id=$1 ORDER BY w.name,c->>'name'`, [owner, value])).rows;
    await db.query('RELEASE SAVEPOINT panel_options');
    return rows;
  } catch (error) {
    await db.query('ROLLBACK TO SAVEPOINT panel_options');
    if (error.code === '42P01') return [];
    throw error;
  }
}


// Every link the owner has, for the desktop app to keep a copy it can change offline.
async function allLinks(db, owner) {
  const rows = async sql => (await db.query(sql, [owner])).rows;
  const viaEvents = (table, cols) => `SELECT ${cols} FROM public.${table} l JOIN public.gantt_items i ON i.id=l.event_id JOIN public.gantt_calendars c ON c.id=i.calendar_id WHERE c.owner_id=$1`;
  const viaCalendar = (table, cols) => `SELECT ${cols} FROM public.${table} l JOIN public.calendar_events i ON i.id=l.calendar_event_id JOIN public.calendar_collections c ON c.id=i.calendar_id WHERE c.owner_id=$1`;
  return {
    eventTask: await rows(viaEvents('event_task_links', 'l.event_id,l.workplace_id,l.task_id')),
    calendarTask: await rows(viaCalendar('calendar_task_links', 'l.calendar_event_id,l.workplace_id,l.task_id')),
    calendarGantt: await rows(viaCalendar('calendar_gantt_links', 'l.calendar_event_id,l.event_id')),
    session: await rows('SELECT session_id,event_id,calendar_event_id,workplace_id,task_id FROM public.session_links WHERE owner_id=$1'),
    eventPanel: await rows(viaEvents('event_panel_links', 'l.event_id,l.workplace_id,l.panel_id')),
    calendarPanel: await rows(viaCalendar('calendar_panel_links', 'l.calendar_event_id,l.workplace_id,l.panel_id')),
    sessionPanel: await rows('SELECT session_id,workplace_id,panel_id FROM public.session_panel_links WHERE owner_id=$1'),
  };
}

// After working offline the desktop app sends all of its links, and they replace
// the ones here. A link to something that no longer exists is left out.
async function replaceLinks(db, owner, given) {
  const kinds = ['eventTask', 'calendarTask', 'calendarGantt', 'session', 'eventPanel', 'calendarPanel', 'sessionPanel'];
  if (!given || typeof given !== 'object' || kinds.some(k => given[k] !== undefined && !Array.isArray(given[k]))) fail('Invalid links.');
  const list = k => given[k] ?? [];
  if (kinds.reduce((n, k) => n + list(k).length, 0) > 20000) fail('There are too many links.');
  const isUuid = v => uuid(v);
  const clean = (k, fields) => list(k).map(l => {
    if (!l || typeof l !== 'object' || fields.some(f => !isUuid(l[f]))) fail('Invalid links.');
    return l;
  });
  const eventTask = clean('eventTask', ['event_id', 'workplace_id', 'task_id']);
  const calendarTask = clean('calendarTask', ['calendar_event_id', 'workplace_id', 'task_id']);
  const calendarGantt = clean('calendarGantt', ['calendar_event_id', 'event_id']);
  const eventPanel = clean('eventPanel', ['event_id', 'workplace_id', 'panel_id']);
  const calendarPanel = clean('calendarPanel', ['calendar_event_id', 'workplace_id', 'panel_id']);
  const sessionPanel = clean('sessionPanel', ['session_id', 'workplace_id', 'panel_id']);
  const session = list('session').map(l => {
    const set = ['event_id', 'calendar_event_id', 'workplace_id'].filter(f => l?.[f] != null);
    if (!l || typeof l !== 'object' || !isUuid(l.session_id) || set.length !== 1 || !isUuid(l[set[0]]) || ((l.workplace_id != null) !== (l.task_id != null)) || (l.task_id != null && !isUuid(l.task_id))) fail('Invalid links.');
    return l;
  });

  await db.query('SELECT id FROM public.users WHERE id=$1 FOR UPDATE', [owner]);
  const events = new Set((await db.query('SELECT i.id FROM public.gantt_items i JOIN public.gantt_calendars c ON c.id=i.calendar_id WHERE c.owner_id=$1', [owner])).rows.map(r => r.id));
  const calendarEvents = new Set((await db.query('SELECT i.id FROM public.calendar_events i JOIN public.calendar_collections c ON c.id=i.calendar_id WHERE c.owner_id=$1', [owner])).rows.map(r => r.id));
  const boards = new Map((await db.query('SELECT id,board FROM public.board_workplaces WHERE owner_id=$1', [owner])).rows.map(r => [r.id, r.board]));
  const hasTask = (w, t) => !!boards.get(w)?.tasks?.some(x => x.id === t);
  const hasPanel = (w, p) => !!boards.get(w)?.columns?.some(x => x.id === p);
  await db.query('INSERT INTO public.schedules(owner_id) VALUES($1) ON CONFLICT DO NOTHING', [owner]);
  const blocks = (await db.query('SELECT data FROM public.schedules WHERE owner_id=$1', [owner])).rows[0].data.blocks ?? [];
  const sessions = new Set(blocks.map(b => b.id));

  const ownedEvents = `(SELECT i.id FROM public.gantt_items i JOIN public.gantt_calendars c ON c.id=i.calendar_id WHERE c.owner_id=$1)`;
  const ownedCalendarEvents = `(SELECT i.id FROM public.calendar_events i JOIN public.calendar_collections c ON c.id=i.calendar_id WHERE c.owner_id=$1)`;
  for (const t of ['event_task_links', 'event_panel_links']) await db.query(`DELETE FROM public.${t} WHERE event_id IN ${ownedEvents}`, [owner]);
  for (const t of ['calendar_task_links', 'calendar_gantt_links', 'calendar_panel_links']) await db.query(`DELETE FROM public.${t} WHERE calendar_event_id IN ${ownedCalendarEvents}`, [owner]);
  await db.query('DELETE FROM public.session_links WHERE owner_id=$1', [owner]);
  await db.query('DELETE FROM public.session_panel_links WHERE owner_id=$1', [owner]);

  let count = 0;
  const add = async (table, columns, values) => {
    await db.query(`INSERT INTO public.${table}(${columns.join(',')}) VALUES(${values.map((_, i) => `$${i + 1}`).join(',')}) ON CONFLICT DO NOTHING`, values);
    count++;
  };
  for (const l of eventTask) if (events.has(l.event_id) && hasTask(l.workplace_id, l.task_id)) await add('event_task_links', ['event_id', 'workplace_id', 'task_id'], [l.event_id, l.workplace_id, l.task_id]);
  for (const l of calendarTask) if (calendarEvents.has(l.calendar_event_id) && hasTask(l.workplace_id, l.task_id)) await add('calendar_task_links', ['calendar_event_id', 'workplace_id', 'task_id'], [l.calendar_event_id, l.workplace_id, l.task_id]);
  for (const l of calendarGantt) if (calendarEvents.has(l.calendar_event_id) && events.has(l.event_id)) await add('calendar_gantt_links', ['calendar_event_id', 'event_id'], [l.calendar_event_id, l.event_id]);
  for (const l of eventPanel) if (events.has(l.event_id) && hasPanel(l.workplace_id, l.panel_id)) await add('event_panel_links', ['event_id', 'workplace_id', 'panel_id'], [l.event_id, l.workplace_id, l.panel_id]);
  for (const l of calendarPanel) if (calendarEvents.has(l.calendar_event_id) && hasPanel(l.workplace_id, l.panel_id)) await add('calendar_panel_links', ['calendar_event_id', 'workplace_id', 'panel_id'], [l.calendar_event_id, l.workplace_id, l.panel_id]);
  for (const l of sessionPanel) if (sessions.has(l.session_id) && hasPanel(l.workplace_id, l.panel_id)) await add('session_panel_links', ['owner_id', 'session_id', 'workplace_id', 'panel_id'], [owner, l.session_id, l.workplace_id, l.panel_id]);
  for (const l of session) {
    if (!sessions.has(l.session_id)) continue;
    if (l.event_id != null && events.has(l.event_id)) await add('session_links', ['owner_id', 'session_id', 'event_id'], [owner, l.session_id, l.event_id]);
    else if (l.calendar_event_id != null && calendarEvents.has(l.calendar_event_id)) await add('session_links', ['owner_id', 'session_id', 'calendar_event_id'], [owner, l.session_id, l.calendar_event_id]);
    else if (l.workplace_id != null && hasTask(l.workplace_id, l.task_id)) await add('session_links', ['owner_id', 'session_id', 'workplace_id', 'task_id'], [owner, l.session_id, l.workplace_id, l.task_id]);
  }
  return { saved: true, linked: count };
}

export function linksHandler(pool) {
  return async (request, reply) => {
    const b = request.body || {}, owner = request.userProfile.id;
    let db;
    try {
      if (b.action === 'listAll' || b.action === 'syncLinks') {
        db = await pool.connect();
        await db.query('BEGIN');
        const everything = b.action === 'listAll' ? await allLinks(db, owner) : await replaceLinks(db, owner, b.links);
        await db.query('COMMIT');
        return everything;
      }
      if (!['list', 'link', 'unlink'].includes(b.action)) fail('Unknown link action.');
      if (!['event', 'task', 'calendar', 'session'].includes(b.source)) fail('Invalid link source.');
      const mutation = b.action !== 'list';
      // Infer the original event/task pair for older clients.
      const target = b.targetType ?? (b.source === 'event' ? 'task' : 'event');
      if (mutation && (!['event','task','calendar','session','panel'].includes(target) || target === b.source || (target === 'panel' && b.source === 'task'))) fail('Invalid link target.');
      const types = new Set(mutation ? [b.source,target] : [b.source]);
      db = await pool.connect();
      await db.query('BEGIN');
      // Fixed lock order for both directions of every pair.
      if (types.has('event')) {
        if (!uuid(b.eventId)) fail('Invalid Gantt phase.');
        const event = await db.query(`SELECT i.id FROM public.gantt_items i JOIN public.gantt_calendars c ON c.id=i.calendar_id
          WHERE i.id=$1 AND c.owner_id=$2 FOR UPDATE OF c`, [b.eventId,owner]);
        if (!event.rowCount) fail('Phase not found.',404);
      }
      if (types.has('calendar')) {
        if (!uuid(b.calendarEventId)) fail('Invalid Calendar event.');
        const event = await db.query(`SELECT i.id FROM public.calendar_events i JOIN public.calendar_collections c ON c.id=i.calendar_id
          WHERE i.id=$1 AND c.owner_id=$2 FOR UPDATE OF c`, [b.calendarEventId,owner]);
        if (!event.rowCount) fail('Calendar event not found.',404);
      }
      if (types.has('task')) {
        if (!uuid(b.workplaceId) || !uuid(b.taskId)) fail('Invalid task.');
        const row = await db.query('SELECT board FROM public.board_workplaces WHERE id=$1 AND owner_id=$2 FOR UPDATE',[b.workplaceId,owner]);
        if (!row.rows[0]?.board.tasks.some(t=>t.id===b.taskId)) fail('Task not found.',404);
      }
      if (types.has('panel')) {
        if (!uuid(b.workplaceId) || !uuid(b.panelId)) fail('Invalid panel.');
        const row = await db.query('SELECT board FROM public.board_workplaces WHERE id=$1 AND owner_id=$2 FOR UPDATE',[b.workplaceId,owner]);
        if (!row.rows[0]?.board.columns?.some(c=>c.id===b.panelId)) fail('Panel not found.',404);
      }
      if(types.has('session')){
        if(!uuid(b.sessionId))fail('Invalid session.');
        const row=await db.query('SELECT data FROM public.schedules WHERE owner_id=$1 FOR UPDATE',[owner]);
        if(!row.rows[0]?.data.blocks.some(s=>s.id===b.sessionId))fail('Session not found.',404);
      }
      let result;
      if (mutation && target === 'panel') {
        const [table, keys, keyValues] = b.source === 'event'
          ? ['event_panel_links', ['event_id'], [b.eventId]]
          : b.source === 'calendar'
            ? ['calendar_panel_links', ['calendar_event_id'], [b.calendarEventId]]
            : ['session_panel_links', ['owner_id','session_id'], [owner,b.sessionId]];
        const columns = [...keys,'workplace_id','panel_id'], values = [...keyValues,b.workplaceId,b.panelId];
        if (b.action === 'link') {
          await db.query(`INSERT INTO public.${table}(${columns.join(',')}) VALUES(${values.map((_,i)=>`$${i+1}`).join(',')}) ON CONFLICT DO NOTHING`,values);
        } else {
          await db.query(`DELETE FROM public.${table} WHERE ${columns.map((c,i)=>`${c}=$${i+1}`).join(' AND ')}`,values);
        }
        result={saved:true};
      } else if(mutation && types.has('session')){
        await mutateSessionLink(db,owner,b,types);result={saved:true};
      } else if(!mutation && b.source==='session'){
        result={options:[...await sessionSourceOptions(db,owner,b.sessionId),...await panelOptions(db,owner,b)]};
      } else if (mutation) {
        // Identifiers below are chosen solely from server constants.
        const calendarPair = types.has('calendar'), taskPair = types.has('task');
        const table = calendarPair ? (taskPair ? 'calendar_task_links' : 'calendar_gantt_links') : 'event_task_links';
        const columns = calendarPair ? (taskPair ? ['calendar_event_id','workplace_id','task_id'] : ['calendar_event_id','event_id']) : ['event_id','workplace_id','task_id'];
        const values = calendarPair ? (taskPair ? [b.calendarEventId,b.workplaceId,b.taskId] : [b.calendarEventId,b.eventId]) : [b.eventId,b.workplaceId,b.taskId];
        if (b.action === 'link') {
          await db.query(`INSERT INTO public.${table}(${columns.join(',')}) VALUES(${values.map((_,i)=>`$${i+1}`).join(',')}) ON CONFLICT DO NOTHING`,values);
        } else {
          await db.query(`DELETE FROM public.${table} WHERE ${columns.map((c,i)=>`${c}=$${i+1}`).join(' AND ')}`,values);
        }
        result={saved:true};
      } else {
        const options=[];
        if (b.source !== 'task') {
          const table=b.source==='calendar'?'calendar_task_links':'event_task_links';
          const col=b.source==='calendar'?'calendar_event_id':'event_id';
          options.push(...(await db.query(`SELECT 'task' AS target_type,w.id AS workplace_id,t->>'id' AS task_id,
            t->>'title' AS title,'Boards · ' || w.name AS location,COALESCE((t->>'archived')::boolean,false) AS archived,
            EXISTS(SELECT 1 FROM public.${table} l WHERE l.${col}=$2 AND l.workplace_id=w.id AND l.task_id::text=t->>'id') AS linked
            FROM public.board_workplaces w CROSS JOIN LATERAL jsonb_array_elements(w.board->'tasks') t
            WHERE w.owner_id=$1 ORDER BY w.name,t->>'title'`,[owner,b.source==='calendar'?b.calendarEventId:b.eventId])).rows);
        }
        if (b.source !== 'event') {
          const condition=b.source==='calendar'
            ? 'SELECT 1 FROM public.calendar_gantt_links l WHERE l.event_id=i.id AND l.calendar_event_id=$2'
            : 'SELECT 1 FROM public.event_task_links l WHERE l.event_id=i.id AND l.workplace_id=$2 AND l.task_id=$3';
          options.push(...(await db.query(`SELECT 'event' AS target_type,i.id AS event_id,i.title,'Gantt · ' || c.name AS location,
            EXISTS(${condition}) AS linked FROM public.gantt_items i JOIN public.gantt_calendars c ON c.id=i.calendar_id
            WHERE c.owner_id=$1 ORDER BY c.name,i.start_date,i.title`,b.source==='calendar'?[owner,b.calendarEventId]:[owner,b.workplaceId,b.taskId])).rows);
        }
        if (b.source !== 'calendar') {
          const condition=b.source==='event'
            ? 'SELECT 1 FROM public.calendar_gantt_links l WHERE l.calendar_event_id=i.id AND l.event_id=$2'
            : 'SELECT 1 FROM public.calendar_task_links l WHERE l.calendar_event_id=i.id AND l.workplace_id=$2 AND l.task_id=$3';
          options.push(...(await db.query(`SELECT 'calendar' AS target_type,i.id AS calendar_event_id,i.title,'Calendar · ' || c.name AS location,
            EXISTS(${condition}) AS linked FROM public.calendar_events i JOIN public.calendar_collections c ON c.id=i.calendar_id
            WHERE c.owner_id=$1 ORDER BY c.name,i.start_date,i.title`,b.source==='event'?[owner,b.eventId]:[owner,b.workplaceId,b.taskId])).rows);
        }
        options.push(...await sessionOptions(db,owner,b));
        if (b.source !== 'task') options.push(...await panelOptions(db,owner,b));
        result={options};
      }
      await db.query('COMMIT');return result;
    } catch(error) {
      if(db)await db.query('ROLLBACK').catch(()=>{});
      if(error.publicMessage)return reply.code(error.statusCode).send({error:error.publicMessage});
      request.log.error({errorCode:error.code||'LINKS_FAILED'},'Link request failed');
      return reply.code(503).send({error:'Links are unavailable. Please try again.'});
    } finally {db?.release();}
  };
}
