import {sessionOptions,sessionSourceOptions,mutateSessionLink} from './calendar-sessions.js';
const uuid = value => typeof value === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);
const fail = (message, statusCode = 400) => { throw Object.assign(new Error(message), { publicMessage: message, statusCode }); };

export function linksHandler(pool) {
  return async (request, reply) => {
    const b = request.body || {}, owner = request.userProfile.id;
    let db;
    try {
      if (!['list', 'link', 'unlink'].includes(b.action)) fail('Unknown link action.');
      if (!['event', 'task', 'calendar', 'session'].includes(b.source)) fail('Invalid link source.');
      const mutation = b.action !== 'list';
      // Infer the original event/task pair for older clients.
      const target = b.targetType ?? (b.source === 'event' ? 'task' : 'event');
      if (mutation && (!['event','task','calendar','session'].includes(target) || target === b.source)) fail('Invalid link target.');
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
      if(types.has('session')){
        if(!uuid(b.sessionId))fail('Invalid session.');
        const row=await db.query('SELECT data FROM public.schedules WHERE owner_id=$1 FOR UPDATE',[owner]);
        if(!row.rows[0]?.data.blocks.some(s=>s.id===b.sessionId))fail('Session not found.',404);
      }
      let result;
      if(mutation && types.has('session')){
        await mutateSessionLink(db,owner,b,types);result={saved:true};
      } else if(!mutation && b.source==='session'){
        result={options:await sessionSourceOptions(db,owner,b.sessionId)};
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
