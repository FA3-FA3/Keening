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

export function ganttHandler(pool, scope = 'gantt') {
  if (!['gantt', 'calendar'].includes(scope)) throw new Error('Invalid calendar storage scope');
  return async (request, reply) => {
    const body = request.body || {};
    const owner = request.userProfile.id;
    const actions = ['listCalendars', 'createCalendar', 'renameCalendar', 'deleteCalendar', 'listItems', 'saveItem', 'deleteItem', 'reorderItems'];
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
        result = { calendar: (await query('INSERT INTO public.gantt_calendars(owner_id,name,color) VALUES($1,$2,$3) RETURNING id,name,color', [owner,name,color])).rows[0] };
      } else {
        if (!uuid(body.calendar_id)) fail('Invalid calendar.');
        // Serialize mutations within a calendar, including dependency validation.
        const calendar = await query('SELECT id FROM public.gantt_calendars WHERE id=$1 AND owner_id=$2 FOR UPDATE', [body.calendar_id,owner]);
        if (!calendar.rowCount) fail('Calendar not found.', 404);
        const calendarId = body.calendar_id;
        if (body.action === 'listItems') {
          result = { items: (await query(itemSelect, [calendarId])).rows };
        } else if (body.action === 'renameCalendar') {
          const name = text(body.name,100,'calendar name');
          await query('UPDATE public.gantt_calendars SET name=$1 WHERE id=$2', [name,calendarId]);
          result = { saved: true };
        } else if (body.action === 'deleteCalendar') {
          await query('DELETE FROM public.gantt_calendars WHERE id=$1', [calendarId]);
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
