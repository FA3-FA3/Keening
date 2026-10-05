import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import {createPool} from '../src/database.js';
import {buildApp} from '../src/app.js';
import {LIMITS} from '../src/attachments.js';

const databaseUrl=process.env.TEST_DATABASE_URL;
const b64=text=>Buffer.from(text).toString('base64');

test('attachments are validated, owner-scoped, limited and swept when items disappear', {skip:!databaseUrl}, async t=>{
  assert.ok(['localhost','127.0.0.1','[::1]'].includes(new URL(databaseUrl).hostname));
  const pool=createPool(databaseUrl);
  for(const file of ['01-schema.sql','02-usernames.sql','08-profile-picture.sql','03-gantt.sql','04-boards.sql','05-event-task-links.sql','06-calendar.sql','07-schedule.sql','09-calendar-sessions.sql','10-calendar-location.sql','11-calendar-tags.sql','12-event-panel-links.sql','13-calendar-session-panel-links.sql','14-pads.sql','15-pad-descriptions.sql','16-document-folders.sql','17-attachments.sql'])
    await pool.query(await readFile(new URL(`../../postgres/init/${file}`,import.meta.url),'utf8'));
  const prefix=`att-${randomUUID()}`;
  const app=await buildApp({pool,logger:false,origins:[],verifyIdToken:async token=>({uid:`${prefix}-${token}`,firebase:{sign_in_provider:'password'}})});
  t.after(async()=>{await pool.query('DELETE FROM public.users WHERE firebase_uid IN ($1,$2)',[`${prefix}-owner`,`${prefix}-other`]);await app.close();});
  const call=async(path,data,token='owner',status=200)=>{
    const r=await app.inject({method:'POST',url:path,headers:{authorization:`Bearer ${token}`},payload:data});
    assert.equal(r.statusCode,status,r.body);return r.json();
  };
  const att=(data,token='owner',status=200)=>call('/attachments',data,token,status);
  assert.equal((await app.inject({method:'POST',url:'/attachments',payload:{action:'list'}})).statusCode,401);
  await att({action:'nope'},'owner',400);

  // One item of each kind.
  const board=(await call('/boards',{action:'createWorkplace',name:'Work'})).workplace;
  const column=(await call('/boards',{action:'createTaskColumn',workplaceId:board.id,name:'To do'})).column;
  const task=(await call('/boards',{action:'createOrgTask',workplaceId:board.id,columnId:column.id,title:'Do it'})).task;
  const session=(await call('/schedule',{action:'saveBlock',date:'2026-10-01',start:'09:00',end:'10:00',title:'Focus'})).block;
  const calendar=(await call('/calendar',{action:'createCalendar',name:'Diary'})).calendar;
  await call('/calendar',{action:'saveItem',calendar_id:calendar.id,title:'Trip',start_date:'2026-09-01',end_date:'2026-09-02',completed:false});
  const event=(await call('/calendar',{action:'listItems',calendar_id:calendar.id})).items[0];
  const items=[['task',task.id],['session',session.id],['event',event.id]];

  for(const [itemType,itemId] of items){
    assert.deepEqual((await att({action:'list',itemType,itemId})).attachments,[]);
    const saved=(await att({action:'upload',itemType,itemId,name:'notes.txt',mime:'text/plain',data:b64('hello world')})).attachment;
    assert.deepEqual([saved.name,saved.mime,saved.size],['notes.txt','text/plain',11]);
    assert.equal('data' in saved,false,'listings never carry file contents');
    assert.deepEqual((await att({action:'list',itemType,itemId})).attachments.map(a=>a.id),[saved.id]);
    const got=await att({action:'get',attachmentId:saved.id});
    assert.equal(Buffer.from(got.data,'base64').toString(),'hello world');
    // Other users can neither see the item, nor read or delete the file.
    await att({action:'list',itemType,itemId},'other',404);
    await att({action:'upload',itemType,itemId,name:'x.txt',data:b64('x')},'other',404);
    await att({action:'get',attachmentId:saved.id},'other',404);
    await att({action:'delete',attachmentId:saved.id},'other',404);
    await att({action:'delete',attachmentId:saved.id});
    await att({action:'delete',attachmentId:saved.id},'owner',404);
  }

  // Validation.
  const [itemType,itemId]=items[0];
  const up=data=>att({action:'upload',itemType,itemId,name:'f.bin',data:b64('abc'),...data},'owner',400);
  await up({itemType:'gantt'});
  await up({itemId:''});
  await up({name:'   '});
  await up({name:'a'.repeat(LIMITS.name+1)});
  await up({data:''});
  await up({data:'not base64!!'});
  await up({data:'A'.repeat(7*1024*1024)});
  await att({action:'upload',itemType:'task',itemId:randomUUID(),name:'f.txt',data:b64('abc')},'owner',404);
  await att({action:'get',attachmentId:'nope'},'owner',400);
  // Names lose path parts; odd types fall back to a generic one.
  const odd=(await att({action:'upload',itemType,itemId,name:'..\\..\\evil/../a.txt',mime:'<script>',data:b64('abc')})).attachment;
  assert.equal(odd.name,'.._.._evil_.._a.txt');assert.equal(odd.mime,'application/octet-stream');
  await att({action:'delete',attachmentId:odd.id});

  // Per-item limit.
  for(let i=0;i<LIMITS.perItem;i++)await att({action:'upload',itemType,itemId,name:`f${i}.txt`,data:b64('abc')});
  await att({action:'upload',itemType,itemId,name:'one-too-many.txt',data:b64('abc')},'owner',400);

  // Deleting the items leaves orphans that the next upload sweeps away.
  await call('/boards',{action:'deleteOrgTask',workplaceId:board.id,taskId:task.id});
  await call('/schedule',{action:'deleteBlock',blockId:session.id});
  await call('/calendar',{action:'deleteItem',calendar_id:calendar.id,item_id:event.id});
  const user=(await pool.query('SELECT id FROM public.users WHERE firebase_uid=$1',[`${prefix}-owner`])).rows[0].id;
  assert.equal((await pool.query('SELECT count(*)::int AS n FROM public.attachments WHERE owner_id=$1',[user])).rows[0].n,LIMITS.perItem);
  const next=(await call('/boards',{action:'createOrgTask',workplaceId:board.id,columnId:column.id,title:'Next'})).task;
  await att({action:'upload',itemType:'task',itemId:next.id,name:'new.txt',data:b64('abc')});
  assert.equal((await pool.query('SELECT count(*)::int AS n FROM public.attachments WHERE owner_id=$1',[user])).rows[0].n,1);
});
