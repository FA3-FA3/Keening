import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import {createPool} from '../src/database.js';
import {buildApp} from '../src/app.js';
const databaseUrl=process.env.TEST_DATABASE_URL;
test('Independent Calendar CRUD and reciprocal links to Gantt and Boards', {skip:!databaseUrl}, async t=>{
  assert.ok(['localhost','127.0.0.1','[::1]'].includes(new URL(databaseUrl).hostname));
  const pool=createPool(databaseUrl);
  for(const file of ['01-schema.sql','02-usernames.sql','08-profile-picture.sql','03-gantt.sql','04-boards.sql','05-event-task-links.sql','06-calendar.sql'])
    await pool.query(await readFile(new URL(`../../postgres/init/${file}`,import.meta.url),'utf8'));
  const prefix=`calendar-${randomUUID()}`;
  const app=await buildApp({pool,logger:false,origins:[],verifyIdToken:async token=>({uid:`${prefix}-${token}`,firebase:{sign_in_provider:'password'}})});
  t.after(async()=>{await pool.query('DELETE FROM public.users WHERE firebase_uid IN ($1,$2)',[`${prefix}-owner`,`${prefix}-other`]);await app.close();});
  const call=async(path,data,token='owner',status=200)=>{
    const r=await app.inject({method:'POST',url:path,headers:{authorization:`Bearer ${token}`},payload:data});
    assert.equal(r.statusCode,status,r.body);return r.json();
  };
  const create=async(path,title,token='owner')=>{
    const calendar=(await call(path,{action:'createCalendar',name:title},token)).calendar;
    await call(path,{action:'saveItem',calendar_id:calendar.id,title,start_date:'2026-09-01',end_date:'2026-09-02',completed:false},token);
    const event=(await call(path,{action:'listItems',calendar_id:calendar.id},token)).items[0];
    return {calendar,event};
  };
  assert.equal((await app.inject({method:'POST',url:'/calendar',payload:{action:'listCalendars'}})).statusCode,401);
  const g=await create('/gantt','Gantt only');
  assert.deepEqual((await call('/calendar',{action:'listCalendars'})).calendars,[]);
  const c=await create('/calendar','Calendar only');
  const foreign=await create('/calendar','Private','other');
  await call('/calendar',{action:'listItems',calendar_id:g.calendar.id},'owner',404);
  await call('/gantt',{action:'listItems',calendar_id:c.calendar.id},'owner',404);
  for(const action of ['listItems','saveItem','deleteItem','renameCalendar','deleteCalendar'])
    await call('/calendar',{action,calendar_id:c.calendar.id},'other',404);
  const w=(await call('/boards',{action:'createWorkplace',name:'Work'})).workplace;
  const col=(await call('/boards',{action:'createTaskColumn',workplaceId:w.id,name:'To do'})).column;
  const task=(await call('/boards',{action:'createOrgTask',workplaceId:w.id,columnId:col.id,title:'Board only'})).task;
  const calSource={source:'calendar',calendarEventId:c.event.id};
  const ganttSource={source:'event',eventId:g.event.id};
  const taskSource={source:'task',workplaceId:w.id,taskId:task.id};
  const pairG={...calSource,targetType:'event',eventId:g.event.id};
  const pairT={...calSource,targetType:'task',workplaceId:w.id,taskId:task.id};
  const list=async(source)=>(await call('/links',{action:'list',...source})).options;
  await call('/links',{action:'link',...pairG});
  await call('/links',{action:'link',...pairT});
  await call('/links',{action:'link',...pairG});
  assert.equal((await list(calSource)).filter(o=>o.linked).length,2);
  assert.equal((await list(ganttSource)).find(o=>o.calendar_event_id===c.event.id).linked,true);
  assert.equal((await list(taskSource)).find(o=>o.calendar_event_id===c.event.id).linked,true);
  assert.equal((await list(taskSource)).some(o=>o.calendar_event_id===foreign.event.id),false);
  for(const pair of [pairG,pairT])for(const action of ['link','unlink'])await call('/links',{action,...pair},'other',404);
  await call('/links',{action:'link',...pairG,calendarEventId:foreign.event.id},'owner',404);
  await call('/links',{action:'link',...pairT,taskId:randomUUID()},'owner',404);
  await call('/links',{action:'list',...calSource},'other',404);
  await call('/calendar',{action:'saveItem',calendar_id:c.calendar.id,item_id:c.event.id,title:'Changed Calendar',start_date:'2026-10-01',end_date:'2026-10-02',completed:true});
  const unchanged=(await call('/gantt',{action:'listItems',calendar_id:g.calendar.id})).items[0];
  assert.equal(unchanged.title,'Gantt only');assert.equal(unchanged.completed,false);assert.equal(unchanged.start_date,'2026-09-01');
  assert.equal((await call('/boards',{action:'getBoard',workplaceId:w.id})).tasks[0].completed,false);
  for(const source of [ganttSource,taskSource]) {
    await call('/links',{action:'unlink',...source,targetType:'calendar',calendarEventId:c.event.id});
    assert.equal((await list(source)).find(o=>o.calendar_event_id===c.event.id).linked,false);
    await call('/links',{action:'link',...source,targetType:'calendar',calendarEventId:c.event.id});
  }
  await call('/boards',{action:'deleteTaskColumn',workplaceId:w.id,columnId:col.id});
  assert.equal((await pool.query('SELECT * FROM public.calendar_task_links WHERE calendar_event_id=$1',[c.event.id])).rowCount,0);
  await call('/calendar',{action:'deleteItem',calendar_id:c.calendar.id,item_id:c.event.id});
  assert.equal((await pool.query('SELECT * FROM public.calendar_gantt_links WHERE calendar_event_id=$1',[c.event.id])).rowCount,0);
  assert.equal((await call('/gantt',{action:'listItems',calendar_id:g.calendar.id})).items.length,1);
});
