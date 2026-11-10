import {syncEventSessions} from './calendar-sessions.js';
const uuid = value => typeof value === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);
const fail = (message, statusCode = 400) => { throw Object.assign(new Error(message), { statusCode, publicMessage: message }); };
function text(value, max, label) {
  if (typeof value !== 'string' || !value.trim() || value.trim().length > max) fail(`Enter a valid ${label}.`);
  return value.trim();
}
function date(value) {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) fail('Enter valid dates.');
  const parsed = new Date(`${value}T00:00:00Z`);
  if (!Number.isFinite(parsed.getTime()) || parsed.toISOString().slice(0, 10) !== value || value < '1900-01-01' || value > '2200-12-31') fail('Enter valid dates between 1900 and 2200.');
  return value;
}
const itemSelect = `SELECT i.id, i.kind, i.title, i.description, i.start_date::text,
  i.end_date::text, i.completed, i.prerequisite_id, p.kind AS prerequisite_kind,
  i.calendar_position, c.name AS calendar_name, c.color
  FROM public.gantt_items i JOIN public.gantt_calendars c ON c.id=i.calendar_id
  LEFT JOIN public.gantt_items p ON p.id=i.prerequisite_id
  WHERE i.calendar_id=$1 ORDER BY i.calendar_position, i.id`;

// Progress of the board panels linked to Gantt phases: completed / total
// (non-archived) tasks across every linked panel.
async function panelProgress(db, owner, itemIds) {
  const out = new Map();
  if (!itemIds.length) return out;
  // Phases still load if the panel-links migration has not been applied yet.
  await db.query('SAVEPOINT panel_progress');
  let links;
  try {
    links = (await db.query(`SELECT l.event_id, l.workplace_id, l.panel_id, w.name AS board_name, w.board
      FROM public.event_panel_links l JOIN public.board_workplaces w ON w.id=l.workplace_id
      WHERE w.owner_id=$1 AND l.event_id=ANY($2::uuid[]) ORDER BY w.name, l.panel_id`, [owner, itemIds])).rows;
    await db.query('RELEASE SAVEPOINT panel_progress');
  } catch (error) {
    await db.query('ROLLBACK TO SAVEPOINT panel_progress');
    if (error.code === '42P01') return out;
    throw error;
  }
  for (const l of links) {
    const panel = (l.board.columns ?? []).find(c => c.id === l.panel_id);
    if (!panel) continue;
    const tasks = (l.board.tasks ?? []).filter(t => t.column_id === l.panel_id && t.archived !== true);
    const done = tasks.filter(t => t.completed === true).length;
    const entry = out.get(l.event_id) ?? { panels: [], done: 0, total: 0 };
    entry.panels.push({ workplace_id: l.workplace_id, panel_id: l.panel_id, name: panel.name, board_name: l.board_name, done, total: tasks.length });
    entry.done += done; entry.total += tasks.length;
    out.set(l.event_id, entry);
  }
  return out;
}

export function ganttHandler(pool, scope = 'gantt') {
  if (!['gantt', 'calendar'].includes(scope)) throw new Error('Invalid calendar storage scope');
  return async (request, reply) => {
    const body = request.body || {};
    const owner = request.userProfile.id;
    const actions = ['listCalendars', 'createCalendar', 'renameCalendar', 'deleteCalendar', 'listItems', 'saveItem', 'deleteItem', 'reorderItems', 'syncCalendar'];
    if(scope==='calendar')actions.push('saveTagDefinitions');
    let db;
    // Scope comes from route registration, never from request data. Both views
    // use the same validation/CRUD while storing entirely separate records.
    const query = (sql, values) => db.query(scope === 'calendar'
      ? sql.replace('i.calendar_position,', 'i.start_time,i.end_time,i.location,i.tag_id,i.calendar_position,').replaceAll('public.gantt_calendars', 'public.calendar_collections').replaceAll('public.gantt_items', 'public.calendar_events')
      : sql, values);
    try {
      if (!actions.includes(body.action)) fail('Unknown calendar action.');
      db = await pool.connect();
      await query('BEGIN');
      let calendarTags=[];
      if(scope==='calendar'){
        await db.query('SELECT id FROM public.users WHERE id=$1 FOR UPDATE',[owner]);
        calendarTags=(await db.query('SELECT tags FROM public.calendar_tags WHERE owner_id=$1',[owner])).rows[0]?.tags??[];
      }
      let result;
      if(body.action==='saveTagDefinitions' && scope==='calendar'){
        if(!Array.isArray(body.tags)||body.tags.length>50)fail('You can create up to 50 tags.');
        const seen=new Set();
        const tags=body.tags.map(t=>{
          if(!t||typeof t!=='object')fail('Invalid tag.');
          const id=text(t.id,100,'tag ID'),name=text(t.name,40,'tag name');
          if(seen.has(id))fail('Duplicate tag.');seen.add(id);
          if(typeof t.color!=='string'||!/^#[0-9a-f]{6}$/i.test(t.color))fail('Invalid colour.');
          return {id,name,color:t.color.toUpperCase()};
        });
        await db.query('INSERT INTO public.calendar_tags(owner_id,tags) VALUES($1,$2::jsonb) ON CONFLICT(owner_id) DO UPDATE SET tags=EXCLUDED.tags',[owner,JSON.stringify(tags)]);
        await db.query('UPDATE public.calendar_events i SET tag_id=NULL FROM public.calendar_collections c WHERE c.id=i.calendar_id AND c.owner_id=$1 AND i.tag_id IS NOT NULL AND NOT(i.tag_id=ANY($2::text[]))',[owner,tags.map(t=>t.id)]);
        result={tagDefinitions:tags};
      } else if (body.action === 'listCalendars') {
        result = { ...(scope==='calendar'?{tagDefinitions:calendarTags}:{}), calendars: (await query('SELECT id,name,color FROM public.gantt_calendars WHERE owner_id=$1 ORDER BY created_at,id', [owner])).rows };
      } else if (body.action === 'createCalendar') {
        const name = text(body.name, 100, 'calendar name');
        const color = body.color || '#2E7D5B';
        if (typeof color !== 'string' || !/^#[0-9a-fA-F]{6}$/.test(color)) fail('Invalid calendar colour.');
        await query('SELECT id FROM public.users WHERE id=$1 FOR UPDATE', [owner]);
        const count = await query('SELECT count(*)::int AS count FROM public.gantt_calendars WHERE owner_id=$1', [owner]);
        if (count.rows[0].count >= 100) fail('You can create up to 100 calendars.');
        if (scope === 'gantt') {
          // A Gantt calendar is a document (in the top-level folder); the database
          // makes the calendar itself when the document is added.
          const docs = await db.query('SELECT count(*)::int AS count FROM public.pads WHERE owner_id=$1', [owner]);
          if (docs.rows[0].count >= 500) fail('You can create up to 500 documents.');
          const pad = (await db.query("INSERT INTO public.pads(owner_id,name,kind,doc) VALUES($1,$2,'gantt','{\"version\":1}'::jsonb) RETURNING id", [owner,name])).rows[0];
          result = { calendar: (await db.query('UPDATE public.gantt_calendars SET color=$1 WHERE id=$2 RETURNING id,name,color', [color,pad.id])).rows[0] };
        } else {
          result = { calendar: (await query('INSERT INTO public.gantt_calendars(owner_id,name,color) VALUES($1,$2,$3) RETURNING id,name,color', [owner,name,color])).rows[0] };
        }
      } else if (body.action === 'syncCalendar') {
        // After working offline the desktop app sends a calendar and all its items,
        // and they replace the ones here (a calendar made offline is added). Items
        // that stay keep their links; the ones left out are removed.
        if (!uuid(body.calendar_id)) fail('Invalid calendar.');
        const calendarId = body.calendar_id;
        const color = body.color || '#2E7D5B';
        if (typeof color !== 'string' || !/^#[0-9a-fA-F]{6}$/.test(color)) fail('Invalid calendar colour.');
        const calendarName = text(body.name, 100, 'calendar name');
        const calendars = scope === 'calendar' ? 'public.calendar_collections' : 'public.gantt_calendars';
        const itemsTable = scope === 'calendar' ? 'public.calendar_events' : 'public.gantt_items';
        const given = body.items;
        if (!Array.isArray(given) || given.length > 200) fail('A calendar can contain up to 200 items.');
        const ids = new Set();
        for (const item of given) {
          if (!item || typeof item !== 'object' || !uuid(item.id) || ids.has(item.id)) fail('Invalid item.');
          ids.add(item.id);
        }
        const timePattern = /^([01]\d|2[0-3]):[0-5]\d$/;
        const tagIds = scope === 'calendar' ? ((await db.query('SELECT tags FROM public.calendar_tags WHERE owner_id=$1', [owner])).rows[0]?.tags ?? []).map(t => t.id) : [];
        const clean = given.map((item, index) => {
          const description = item.description ?? '';
          if (typeof description !== 'string' || description.length > 5000) fail('Description must be at most 5000 characters.');
          if (typeof item.completed !== 'boolean') fail(scope === 'calendar' ? 'Invalid event details.' : 'Invalid phase details.');
          const start = date(item.start_date), end = date(item.end_date ?? item.start_date);
          if (end < start) fail('End date must follow the start date.');
          const prerequisite = item.prerequisite_id ?? null;
          if (prerequisite !== null && (!uuid(prerequisite) || !ids.has(prerequisite) || prerequisite === item.id)) fail('Prerequisite must belong to this calendar.');
          const row = { id: item.id, title: text(item.title, 200, 'title'), description, start, end, completed: item.completed, prerequisite, position: index + 1 };
          if (scope === 'calendar') {
            const startTime = item.start_time ?? null, endTime = item.end_time ?? null;
            if (startTime !== null || endTime !== null) {
              if (typeof startTime !== 'string' || typeof endTime !== 'string' || !timePattern.test(startTime) || !(endTime === '24:00' || timePattern.test(endTime)) || endTime <= startTime) fail('Enter a start and end time (HH:mm), with end after start.');
            }
            const location = item.location ?? '';
            if (typeof location !== 'string' || location.length > 500) fail('Location must be at most 500 characters.');
            const tagId = item.tag_id ?? null;
            if (tagId !== null && !tagIds.includes(tagId)) fail('Choose a tag from your Calendar tags.');
            Object.assign(row, { startTime, endTime, location: location.trim(), tagId });
          }
          return row;
        });
        for (const row of clean) {
          const seen = new Set([row.id]);
          let next = row.prerequisite;
          while (next) {
            if (seen.has(next)) fail('Prerequisites cannot form a cycle.');
            seen.add(next); next = clean.find(r => r.id === next)?.prerequisite;
          }
        }
        await db.query('SELECT id FROM public.users WHERE id=$1 FOR UPDATE', [owner]);
        const existing = (await db.query(`SELECT owner_id FROM ${calendars} WHERE id=$1`, [calendarId])).rows[0];
        if (existing && existing.owner_id !== owner) fail('Calendar not found.', 404);
        if (!existing) {
          // A Gantt calendar is made along with its document, which comes first.
          if (scope === 'gantt') fail('Calendar not found.', 404);
          const count = await db.query(`SELECT count(*)::int AS count FROM ${calendars} WHERE owner_id=$1`, [owner]);
          if (count.rows[0].count >= 100) fail('You can create up to 100 calendars.');
          await db.query(`INSERT INTO ${calendars}(id,owner_id,name,color) VALUES($1,$2,$3,$4)`, [calendarId, owner, calendarName, color]);
        } else if (scope === 'calendar') {
          await db.query(`UPDATE ${calendars} SET name=$2,color=$3 WHERE id=$1`, [calendarId, calendarName, color]);
        } else {
          // (A Gantt calendar is renamed through its document.)
          await db.query(`UPDATE ${calendars} SET color=$2 WHERE id=$1`, [calendarId, color]);
        }
        const clash = (await db.query(`SELECT count(*)::int AS n FROM ${itemsTable} WHERE id=ANY($1::uuid[]) AND calendar_id<>$2`, [[...ids], calendarId])).rows[0].n;
        if (clash) fail('Invalid item.');
        await db.query(`DELETE FROM ${itemsTable} WHERE calendar_id=$1 AND NOT (id=ANY($2::uuid[]))`, [calendarId, [...ids]]);
        for (const r of clean) {
          if (scope === 'calendar') {
            await db.query(`INSERT INTO ${itemsTable}(id,calendar_id,kind,title,description,start_date,end_date,completed,calendar_position,start_time,end_time,location,tag_id)
              VALUES($1,$2,'event',$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)
              ON CONFLICT (id) DO UPDATE SET title=EXCLUDED.title,description=EXCLUDED.description,start_date=EXCLUDED.start_date,end_date=EXCLUDED.end_date,completed=EXCLUDED.completed,calendar_position=EXCLUDED.calendar_position,start_time=EXCLUDED.start_time,end_time=EXCLUDED.end_time,location=EXCLUDED.location,tag_id=EXCLUDED.tag_id`,
              [r.id, calendarId, r.title, r.description, r.start, r.end, r.completed, r.position, r.startTime, r.endTime, r.location, r.tagId]);
          } else {
            await db.query(`INSERT INTO ${itemsTable}(id,calendar_id,kind,title,description,start_date,end_date,completed,calendar_position)
              VALUES($1,$2,'event',$3,$4,$5,$6,$7,$8)
              ON CONFLICT (id) DO UPDATE SET title=EXCLUDED.title,description=EXCLUDED.description,start_date=EXCLUDED.start_date,end_date=EXCLUDED.end_date,completed=EXCLUDED.completed,calendar_position=EXCLUDED.calendar_position`,
              [r.id, calendarId, r.title, r.description, r.start, r.end, r.completed, r.position]);
          }
        }
        for (const r of clean) {
          await db.query(`UPDATE ${itemsTable} SET prerequisite_id=$2 WHERE id=$1`, [r.id, r.prerequisite]);
        }
        // Events saved offline on a computer that had no copy of the schedule: their
        // sessions are made here, as they would be if they had been saved one by one.
        if (scope === 'calendar' && Array.isArray(body.session_events)) {
          for (const eventId of [...new Set(body.session_events)]) {
            if (ids.has(eventId)) await syncEventSessions(db, owner, eventId, {});
          }
        }
        result = { saved: true, count: clean.length };
      } else {
        if (!uuid(body.calendar_id)) fail('Invalid calendar.');
        // Serialize mutations within a calendar, including dependency validation.
        const calendar = await query('SELECT id FROM public.gantt_calendars WHERE id=$1 AND owner_id=$2 FOR UPDATE', [body.calendar_id,owner]);
        if (!calendar.rowCount) fail('Calendar not found.', 404);
        const calendarId = body.calendar_id;
        if (body.action === 'listItems') {
          const items = (await query(itemSelect, [calendarId])).rows;
          if (scope === 'gantt') {
            const progress = await panelProgress(db, owner, items.map(i => i.id));
            for (const item of items) {
              const p = progress.get(item.id);
              item.panels = p?.panels ?? [];
              item.progress = { done: p?.done ?? 0, total: p?.total ?? 0 };
            }
          }
          result = { items };
        } else if (body.action === 'renameCalendar') {
          const name = text(body.name,100,'calendar name');
          if (scope === 'gantt') await db.query('UPDATE public.pads SET name=$1,updated_at=now() WHERE id=$2', [name,calendarId]);
          else await query('UPDATE public.gantt_calendars SET name=$1 WHERE id=$2', [name,calendarId]);
          result = { saved: true };
        } else if (body.action === 'deleteCalendar') {
          // A Gantt calendar is a document: deleting it deletes the calendar and its phases.
          if (scope === 'gantt') await db.query('DELETE FROM public.pads WHERE id=$1', [calendarId]);
          else await query('DELETE FROM public.gantt_calendars WHERE id=$1', [calendarId]);
          result = { deleted: true };
        } else {
          const items = (await query('SELECT id,prerequisite_id FROM public.gantt_items WHERE calendar_id=$1 ORDER BY calendar_position,id', [calendarId])).rows;
          const byId = new Map(items.map(item => [item.id,item]));
          if (body.action === 'reorderItems') {
            const ids = body.item_ids;
            if (!Array.isArray(ids) || ids.length !== items.length || new Set(ids).size !== ids.length || ids.some(id => !byId.has(id))) fail('Calendar items changed. Refresh and try again.', 409);
            await query('UPDATE public.gantt_items i SET calendar_position=ordered.position::int FROM unnest($1::uuid[]) WITH ORDINALITY AS ordered(id,position) WHERE i.id=ordered.id AND i.calendar_id=$2', [ids,calendarId]);
            result = { saved: true };
          } else {
            const id = body.item_id;
            if (id != null && (!uuid(id) || !byId.has(id))) fail('Item not found.',404);
            if (body.action === 'deleteItem') {
              if (!id) fail('Item not found.',404);
              await query('DELETE FROM public.gantt_items WHERE id=$1 AND calendar_id=$2', [id,calendarId]);
              result = { deleted: true };
            } else {
              const title = text(body.title,200,'title');
              const description = body.description ?? '';
              if (typeof description !== 'string' || description.length > 5000) fail('Description must be at most 5000 characters.');
              if (typeof body.completed !== 'boolean') fail(scope === 'calendar' ? 'Invalid event details.' : 'Invalid phase details.');
              const start = date(body.start_date), end = date(body.end_date ?? (scope === 'calendar' ? body.start_date : undefined));
              if (end < start) fail('End date must follow the start date.');
              const prerequisite = body.prerequisite_id ?? null;
              if (prerequisite !== null && (!uuid(prerequisite) || !byId.has(prerequisite))) fail('Prerequisite must belong to this calendar.');
              const seen = new Set(id ? [id] : []);
              let next = prerequisite;
              while (next) {
                if (seen.has(next)) fail('Prerequisites cannot form a cycle.');
                seen.add(next); next = byId.get(next)?.prerequisite_id;
              }
              let savedId = id;
              const values = [calendarId,'event',title,description,start,end,body.completed,prerequisite];
              if (id) {
                await query('UPDATE public.gantt_items SET kind=$2,title=$3,description=$4,start_date=$5,end_date=$6,completed=$7,prerequisite_id=$8 WHERE calendar_id=$1 AND id=$9', [...values,id]);
              } else {
                if (items.length >= 200) fail('A calendar can contain up to 200 items.');
                const inserted = await query('INSERT INTO public.gantt_items(calendar_id,kind,title,description,start_date,end_date,completed,prerequisite_id,calendar_position) SELECT $1,$2,$3,$4,$5,$6,$7,$8,COALESCE(MAX(calendar_position),0)+1 FROM public.gantt_items WHERE calendar_id=$1 RETURNING id', values);
                savedId = inserted.rows[0].id;
              }
              if(scope === 'calendar') await syncEventSessions(db,owner,savedId,body);
              result = { saved: true };
            }
          }
        }
      }
      await query('COMMIT');
      return result;
    } catch (error) {
      if (db) await query('ROLLBACK').catch(() => {});
      if (error.publicMessage) return reply.code(error.statusCode).send({ error: error.publicMessage });
      request.log.error({ errorCode: error.code || 'GANTT_FAILED' }, 'Calendar request failed');
      return reply.code(503).send({ error: 'Calendar is unavailable. Please try again.' });
    } finally {
      db?.release();
    }
  };
}
