import {randomUUID} from 'node:crypto';
const fail=message=>{throw Object.assign(new Error(message),{publicMessage:message,statusCode:400});};
export async function syncEventSessions(db,owner,eventId,times) {
 const event=(await db.query('SELECT i.*,i.start_date::text AS start_date,i.end_date::text AS end_date,c.color FROM public.calendar_events i JOIN public.calendar_collections c ON c.id=i.calendar_id WHERE i.id=$1 AND c.owner_id=$2',[eventId,owner])).rows[0];
 if(!event)fail('Event not found.');
 const tagId=times.tag_id===undefined?event.tag_id:times.tag_id;
 const tags=(await db.query('SELECT tags FROM public.calendar_tags WHERE owner_id=$1',[owner])).rows[0]?.tags??[];
 const tag=tagId==null?null:tags.find(t=>t.id===tagId);
 if(tagId!=null&&!tag)fail('Choose a tag from your Calendar tags.');
 await db.query('UPDATE public.calendar_events SET tag_id=$2 WHERE id=$1',[eventId,tagId??null]);
 const location=times.location===undefined?event.location:times.location;
 if(typeof location!=='string'||location.length>500)fail('Location must be at most 500 characters.');
 const start=times.start_time===undefined?event.start_time:times.start_time;
 const end=times.end_time===undefined?event.end_time:times.end_time;
 if(start!=null||end!=null){
  if(typeof start!=='string'||typeof end!=='string'||!/^([01]\d|2[0-3]):[0-5]\d$/.test(start)||!(end==='24:00'||/^([01]\d|2[0-3]):[0-5]\d$/.test(end))||end<=start)fail('Enter a start and end time (HH:mm), with end after start.');
 }
 await db.query('UPDATE public.calendar_events SET start_time=$2,end_time=$3,location=$4 WHERE id=$1',[eventId,start??null,end??null,location.trim()]);
 await db.query('INSERT INTO public.schedules(owner_id) VALUES($1) ON CONFLICT DO NOTHING',[owner]);
 const data=(await db.query('SELECT data FROM public.schedules WHERE owner_id=$1 FOR UPDATE',[owner])).rows[0].data;
 const existing=data.blocks.filter(b=>b.calendarEventId===eventId);
 const blocks=data.blocks.filter(b=>b.calendarEventId!==eventId);
 const generated=[];
 if(start!=null){
  const day=new Date(event.start_date+'T00:00:00Z'), last=new Date(event.end_date+'T00:00:00Z');
  if((last-day)/86400000>=366)fail('Timed events can span up to 366 days.');
  while(day<=last){
   const date=day.toISOString().slice(0,10);
   const old=existing.find(b=>b.date===date)??(existing.length===1&&event.start_date===event.end_date?existing[0]:null);
   generated.push({...old,id:old?.id??randomUUID(),calendarEventId:eventId,date,start,end,title:event.title,note:event.description.slice(0,2000),color:old?.color??event.color,location:times.location===undefined?(old?.location??location.trim()):location.trim()});
   day.setUTCDate(day.getUTCDate()+1);
  }
 }
 if(blocks.length+generated.length>5000)fail('You can save up to 5000 sessions.');
 data.blocks=[...blocks,...generated];
 await db.query('UPDATE public.schedules SET data=$2::jsonb,updated_at=now() WHERE owner_id=$1',[owner,JSON.stringify(data)]);
 for(const block of generated)await db.query('INSERT INTO public.session_links(owner_id,session_id,calendar_event_id) VALUES($1,$2,$3) ON CONFLICT DO NOTHING',[owner,block.id,eventId]);
}

export async function sessionOptions(db,owner,b) {
 const values=[owner];let condition;
 if(b.source==='calendar'){values.push(b.calendarEventId);condition='l.calendar_event_id=$2';}
 else if(b.source==='event'){values.push(b.eventId);condition='l.event_id=$2';}
 else {values.push(b.workplaceId,b.taskId);condition='l.workplace_id=$2 AND l.task_id=$3';}
 return (await db.query(`SELECT 'session' AS target_type,b->>'id' AS session_id,b->>'title' AS title,
 'Schedule / ' || (b->>'date') || ' / ' || (b->>'start') AS location,
 EXISTS(SELECT 1 FROM public.session_links l WHERE l.owner_id=s.owner_id AND l.session_id=b->>'id' AND ${condition}) AS linked
 FROM public.schedules s CROSS JOIN LATERAL jsonb_array_elements(s.data->'blocks') b WHERE s.owner_id=$1 ORDER BY b->>'date',b->>'start'`,values)).rows;
}
export async function sessionSourceOptions(db,owner,sessionId){
 const args=[owner,sessionId];
 const phases=await db.query(`SELECT 'event' AS target_type,i.id AS event_id,i.title,'Gantt / '||c.name AS location,
 EXISTS(SELECT 1 FROM public.session_links l WHERE l.owner_id=$1 AND l.session_id=$2 AND l.event_id=i.id) AS linked
 FROM public.gantt_items i JOIN public.gantt_calendars c ON c.id=i.calendar_id WHERE c.owner_id=$1 ORDER BY c.name,i.start_date`,args);
 const events=await db.query(`SELECT 'calendar' AS target_type,i.id AS calendar_event_id,i.title,'Calendar / '||c.name AS location,
 EXISTS(SELECT 1 FROM public.session_links l WHERE l.owner_id=$1 AND l.session_id=$2 AND l.calendar_event_id=i.id) AS linked
 FROM public.calendar_events i JOIN public.calendar_collections c ON c.id=i.calendar_id WHERE c.owner_id=$1 ORDER BY c.name,i.start_date`,args);
 const tasks=await db.query(`SELECT 'task' AS target_type,w.id AS workplace_id,t->>'id' AS task_id,t->>'title' AS title,'Boards / '||w.name AS location,
 COALESCE((t->>'archived')::boolean,false) AS archived,
 EXISTS(SELECT 1 FROM public.session_links l WHERE l.owner_id=$1 AND l.session_id=$2 AND l.workplace_id=w.id AND l.task_id::text=t->>'id') AS linked
 FROM public.board_workplaces w CROSS JOIN LATERAL jsonb_array_elements(w.board->'tasks') t WHERE w.owner_id=$1 ORDER BY w.name,t->>'title'`,args);
 return [...phases.rows,...events.rows,...tasks.rows];
}
export async function mutateSessionLink(db,owner,b,types){
 let cols,values;
 if(types.has('event')){cols=['event_id'];values=[b.eventId];}
 else if(types.has('calendar')){cols=['calendar_event_id'];values=[b.calendarEventId];}
 else {cols=['workplace_id','task_id'];values=[b.workplaceId,b.taskId];}
 const args=[owner,b.sessionId,...values];
 if(b.action==='link')await db.query(`INSERT INTO public.session_links(owner_id,session_id,${cols.join(',')}) VALUES(${args.map((_,i)=>'$'+(i+1)).join(',')}) ON CONFLICT DO NOTHING`,args);
 else await db.query(`DELETE FROM public.session_links WHERE owner_id=$1 AND session_id=$2 AND ${cols.map((c,i)=>c+'=$'+(i+3)).join(' AND ')}`,args);
}
