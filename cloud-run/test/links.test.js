import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import {createPool} from '../src/database.js';
import {buildApp} from '../src/app.js';

const databaseUrl=process.env.TEST_DATABASE_URL;
test('Event/task links work both ways, enforce ownership and clean up deleted items', {skip:!databaseUrl}, async t=>{
  assert.ok(['localhost','127.0.0.1','[::1]'].includes(new URL(databaseUrl).hostname));
  const pool=createPool(databaseUrl);
  for(const file of ['01-schema.sql','02-usernames.sql','08-profile-picture.sql','03-gantt.sql','04-boards.sql','05-event-task-links.sql','06-calendar.sql','07-schedule.sql','09-calendar-sessions.sql','10-calendar-location.sql','11-calendar-tags.sql','12-event-panel-links.sql','13-calendar-session-panel-links.sql'])
    await pool.query(await readFile(new URL(`../../postgres/init/${file}`,import.meta.url),'utf8'));
  const prefix=`links-${randomUUID()}`;
  const app=await buildApp({pool,logger:false,origins:[],verifyIdToken:async token=>({uid:`${prefix}-${token}`,firebase:{sign_in_provider:'password'}})});
  t.after(async()=>{await pool.query('DELETE FROM public.users WHERE firebase_uid IN ($1,$2)',[`${prefix}-owner`,`${prefix}-other`]);await app.close();});
  const call=async(path,data,token='owner',status=200)=>{
    const r=await app.inject({method:'POST',url:path,headers:{authorization:`Bearer ${token}`},payload:data});
    assert.equal(r.statusCode,status,r.body);return r.json();
  };
  assert.equal((await app.inject({method:'POST',url:'/links',payload:{action:'list'}})).statusCode,401);
  const calendar=(await call('/gantt',{action:'createCalendar',name:'Plan'})).calendar;
  const createEvent=async title=>{
    await call('/gantt',{action:'saveItem',calendar_id:calendar.id,kind:'task',title,start_date:'2026-09-01',end_date:'2026-09-02',completed:false});
    return (await call('/gantt',{action:'listItems',calendar_id:calendar.id})).items.find(i=>i.title===title);
  };
  const event=await createEvent('Launch'), second=await createEvent('Review');
  assert.equal(event.kind,'event');
  const workplace=(await call('/boards',{action:'createWorkplace',name:'Work'})).workplace;
  const column=(await call('/boards',{action:'createTaskColumn',workplaceId:workplace.id,name:'To do'})).column;
  const createTask=async title=>(await call('/boards',{action:'createOrgTask',workplaceId:workplace.id,columnId:column.id,title})).task;
  const task=await createTask('Prepare'), another=await createTask('Publish');
  const pair={source:'event',eventId:event.id,workplaceId:workplace.id,taskId:task.id};
  const eventList=()=>call('/links',{action:'list',source:'event',eventId:event.id});
  const taskList=()=>call('/links',{action:'list',source:'task',workplaceId:workplace.id,taskId:task.id});
  await call('/links',{action:'link',...pair});
  await call('/links',{action:'link',...pair}); // Idempotent, no duplicate link.
  assert.equal((await eventList()).options.filter(o=>o.linked).length,1);
  assert.equal((await taskList()).options.find(o=>o.event_id===event.id).linked,true);
  await call('/links',{action:'link',...pair,source:'task',eventId:second.id});
  await call('/links',{action:'link',...pair,taskId:another.id});
  assert.equal((await taskList()).options.filter(o=>o.linked).length,2);
  assert.equal((await eventList()).options.filter(o=>o.linked).length,2);
  await call('/links',{action:'unlink',...pair,source:'task'});
  assert.equal((await eventList()).options.find(o=>o.task_id===task.id).linked,false);
  for(const action of ['list','link','unlink'])await call('/links',{action,...pair},'other',404);
  await call('/links',{action:'list',source:'task',workplaceId:workplace.id,taskId:task.id},'other',404);
  const foreign=(await call('/gantt',{action:'createCalendar',name:'Private'},'other')).calendar;
  await call('/gantt',{action:'saveItem',calendar_id:foreign.id,title:'Private event',start_date:'2026-09-01',end_date:'2026-09-01',completed:false},'other');
  const foreignEvent=(await call('/gantt',{action:'listItems',calendar_id:foreign.id},'other')).items[0];
  assert.equal((await taskList()).options.some(o=>o.event_id===foreignEvent.id),false);
  await call('/links',{action:'link',...pair,eventId:foreignEvent.id},'owner',404);
  await call('/links',{action:'link',...pair,taskId:randomUUID()},'owner',404);
  await call('/boards',{action:'updateOrgTask',workplaceId:workplace.id,taskId:another.id,archived:true});
  assert.equal((await eventList()).options.find(o=>o.task_id===another.id).archived,true);
  await call('/boards',{action:'deleteOrgTask',workplaceId:workplace.id,taskId:another.id});
  assert.equal((await pool.query('SELECT * FROM public.event_task_links WHERE task_id=$1',[another.id])).rowCount,0);
  await call('/gantt',{action:'deleteItem',calendar_id:calendar.id,item_id:second.id});
  assert.equal((await taskList()).options.filter(o=>o.linked).length,0);
  await call('/links',{action:'link',...pair});
  await call('/boards',{action:'deleteTaskColumn',workplaceId:workplace.id,columnId:column.id});
  assert.equal((await pool.query('SELECT * FROM public.event_task_links WHERE workplace_id=$1',[workplace.id])).rowCount,0);
});
