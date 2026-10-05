import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import {createPool} from '../src/database.js';
import {buildApp} from '../src/app.js';

const databaseUrl=process.env.TEST_DATABASE_URL;
test('Gantt phases report progress of linked board panels and enforce ownership', {skip:!databaseUrl}, async t=>{
  assert.ok(['localhost','127.0.0.1','[::1]'].includes(new URL(databaseUrl).hostname));
  const pool=createPool(databaseUrl);
  for(const file of ['01-schema.sql','02-usernames.sql','08-profile-picture.sql','03-gantt.sql','04-boards.sql','05-event-task-links.sql','06-calendar.sql','07-schedule.sql','09-calendar-sessions.sql','10-calendar-location.sql','11-calendar-tags.sql','12-event-panel-links.sql','13-calendar-session-panel-links.sql','14-pads.sql','15-pad-descriptions.sql','16-document-folders.sql','17-attachments.sql'])
    await pool.query(await readFile(new URL(`../../postgres/init/${file}`,import.meta.url),'utf8'));
  const prefix=`panels-${randomUUID()}`;
  const app=await buildApp({pool,logger:false,origins:[],verifyIdToken:async token=>({uid:`${prefix}-${token}`,firebase:{sign_in_provider:'password'}})});
  t.after(async()=>{await pool.query('DELETE FROM public.users WHERE firebase_uid IN ($1,$2)',[`${prefix}-owner`,`${prefix}-other`]);await app.close();});
  const call=async(path,data,token='owner',status=200)=>{
    const r=await app.inject({method:'POST',url:path,headers:{authorization:`Bearer ${token}`},payload:data});
    assert.equal(r.statusCode,status,r.body);return r.json();
  };
  const calendar=(await call('/gantt',{action:'createCalendar',name:'Plan'})).calendar;
  await call('/gantt',{action:'saveItem',calendar_id:calendar.id,kind:'event',title:'Build',start_date:'2026-09-01',end_date:'2026-09-02',completed:false});
  const listItems=async()=>(await call('/gantt',{action:'listItems',calendar_id:calendar.id})).items;
  const phase=(await listItems())[0];
  assert.deepEqual(phase.progress,{done:0,total:0});
  assert.deepEqual(phase.panels,[]);

  const board=(await call('/boards',{action:'createWorkplace',name:'Work'})).workplace;
  const panel=async name=>(await call('/boards',{action:'createTaskColumn',workplaceId:board.id,name})).column;
  const build=await panel('Build'), review=await panel('Review');
  const task=async(columnId,title,completed=false)=>(await call('/boards',{action:'createOrgTask',workplaceId:board.id,columnId,title,completed})).task;
  await task(build.id,'a',true);await task(build.id,'b');await task(build.id,'c');
  const archived=await task(build.id,'archived',true);
  await call('/boards',{action:'updateOrgTask',workplaceId:board.id,taskId:archived.id,archived:true});
  await task(review.id,'r1',true);

  // Panels are link options for phases, Calendar events and sessions (never tasks).
  const phaseRef={source:'event',eventId:phase.id};
  const panelOptions=async(ref,token='owner')=>(await call('/links',{action:'list',...ref},token)).options.filter(o=>o.target_type==='panel');
  assert.deepEqual((await panelOptions(phaseRef)).map(o=>[o.title,o.location,o.linked]),[['Build','Boards · Work · Panel',false],['Review','Boards · Work · Panel',false]]);
  const taskRef={source:'task',workplaceId:board.id,taskId:(await call('/boards',{action:'getBoard',workplaceId:board.id})).tasks[0].id};
  assert.deepEqual((await call('/links',{action:'list',...taskRef})).options.filter(o=>o.target_type==='panel'),[]);

  const link=(panel,action='link',ref=phaseRef,token='owner',status=200)=>call('/links',{action,...ref,targetType:'panel',workplaceId:board.id,panelId:panel.id,...(ref.source==='task'?{}:{})},token,status);
  await link(build);
  await link(build); // idempotent
  let item=(await listItems())[0];
  assert.deepEqual(item.progress,{done:1,total:3}); // archived tasks are ignored
  assert.equal(item.panels[0].name,'Build');
  assert.equal((await panelOptions(phaseRef)).find(o=>o.title==='Build').linked,true);
  await link(review);
  assert.deepEqual((await listItems())[0].progress,{done:2,total:4});
  // Completing a task is reflected immediately.
  const open=(await call('/boards',{action:'getBoard',workplaceId:board.id})).tasks.find(x=>x.title==='b');
  await call('/boards',{action:'updateOrgTask',workplaceId:board.id,taskId:open.id,completed:true});
  assert.deepEqual((await listItems())[0].progress,{done:3,total:4});

  // Validation and ownership.
  await link({id:randomUUID()},'link',phaseRef,'owner',404);
  await link({id:'bad'},'link',phaseRef,'owner',400);
  await link(build,'link',phaseRef,'other',404);
  await call('/links',{action:'link',...taskRef,targetType:'panel',workplaceId:board.id,panelId:build.id},'owner',400);
  await call('/links',{action:'link',source:'panel',workplaceId:board.id,panelId:build.id},'owner',400);
  assert.equal((await listItems())[0].panels.length,2);

  // Calendar events and sessions link to panels too.
  const cal=(await call('/calendar',{action:'createCalendar',name:'Diary'})).calendar;
  await call('/calendar',{action:'saveItem',calendar_id:cal.id,title:'Standup',start_date:'2026-09-01',end_date:'2026-09-01',completed:false});
  const calEvent=(await call('/calendar',{action:'listItems',calendar_id:cal.id})).items[0];
  const calRef={source:'calendar',calendarEventId:calEvent.id};
  await link(review,'link',calRef);
  assert.deepEqual((await panelOptions(calRef)).map(o=>[o.title,o.linked]),[['Build',false],['Review',true]]);
  const session=(await call('/schedule',{action:'saveBlock',date:'2026-10-01',start:'09:00',end:'10:00',title:'Focus'})).block;
  const sessionRef={source:'session',sessionId:session.id};
  await link(build,'link',sessionRef);
  assert.deepEqual((await panelOptions(sessionRef)).map(o=>[o.title,o.linked]),[['Build',true],['Review',false]]);
  await link(build,'link',sessionRef,'other',404);
  await link(build,'unlink',sessionRef);
  assert.equal((await panelOptions(sessionRef)).some(o=>o.linked),false);
  await link(build,'link',sessionRef);

  // Deleting a panel removes its links everywhere and its tasks from the total.
  await call('/boards',{action:'deleteTaskColumn',workplaceId:board.id,columnId:review.id});
  item=(await listItems())[0];
  assert.deepEqual(item.panels.map(p=>p.name),['Build']);
  assert.deepEqual(item.progress,{done:2,total:3});
  assert.equal((await pool.query('SELECT count(*)::int AS n FROM public.calendar_panel_links WHERE calendar_event_id=$1',[calEvent.id])).rows[0].n,0);
  assert.equal((await pool.query('SELECT count(*)::int AS n FROM public.event_panel_links WHERE event_id=$1',[phase.id])).rows[0].n,1);
  await link(build,'unlink');
  assert.deepEqual((await listItems())[0].progress,{done:0,total:0});
  // Deleting a session or the board cascades.
  await call('/schedule',{action:'deleteBlock',blockId:session.id});
  assert.equal((await pool.query('SELECT count(*)::int AS n FROM public.session_panel_links WHERE session_id=$1',[session.id])).rows[0].n,0);
  await link(build);
  await call('/boards',{action:'deleteWorkplace',workplaceId:board.id});
  assert.equal((await pool.query('SELECT count(*)::int AS n FROM public.event_panel_links WHERE event_id=$1',[phase.id])).rows[0].n,0);
});

test('Gantt still lists phases when the panel-links migration is missing', async()=>{
  const {ganttHandler}=await import('../src/gantt.js');
  const statements=[];
  const db={
    release(){},
    query:async sql=>{
      statements.push(sql.trim().split(" ").slice(0,3).join(" "));
      if(sql.includes('FROM public.gantt_calendars'))return {rowCount:1,rows:[{id:'c'}]};
      if(sql.includes('FROM public.gantt_items i'))return {rowCount:1,rows:[{id:'11111111-1111-4111-8111-111111111111',title:'Build'}]};
      if(sql.includes('event_panel_links'))throw Object.assign(new Error('relation does not exist'),{code:'42P01'});
      return {rowCount:0,rows:[]};
    },
  };
  const reply={code:()=>({send:b=>{throw new Error('unexpected '+JSON.stringify(b));}})};
  const result=await ganttHandler({connect:async()=>db})(
    {body:{action:'listItems',calendar_id:'22222222-2222-4222-8222-222222222222'},userProfile:{id:'u'},log:{error(){}}},reply);
  assert.deepEqual(result.items[0].progress,{done:0,total:0});
  assert.deepEqual(result.items[0].panels,[]);
  assert.ok(statements.includes('ROLLBACK TO SAVEPOINT'));
  assert.equal(statements.at(-1),'COMMIT');
});

test('Links still list other items when the panel-link migrations are missing', async()=>{
  const {linksHandler}=await import('../src/links.js');
  const statements=[];
  const db={
    release(){},
    query:async sql=>{
      statements.push(sql.trim().split(' ').slice(0,3).join(' '));
      if(sql.includes('event_panel_links'))throw Object.assign(new Error('relation does not exist'),{code:'42P01'});
      if(sql.includes('FOR UPDATE'))return {rowCount:1,rows:[{id:'x'}]};
      if(sql.includes("'task' AS target_type"))return {rows:[{target_type:'task',title:'Write',linked:false}]};
      return {rowCount:0,rows:[]};
    },
  };
  const reply={code:()=>({send:b=>{throw new Error('unexpected '+JSON.stringify(b));}})};
  const result=await linksHandler({connect:async()=>db})(
    {body:{action:'list',source:'event',eventId:'11111111-1111-4111-8111-111111111111'},userProfile:{id:'u'},log:{error(){}}},reply);
  assert.deepEqual(result.options.map(o=>o.title),['Write']);
  assert.ok(statements.includes('ROLLBACK TO SAVEPOINT'));
  assert.equal(statements.at(-1),'COMMIT');
});
