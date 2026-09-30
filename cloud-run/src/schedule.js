import {randomUUID} from 'node:crypto';
const fail=(message,statusCode=400)=>{throw Object.assign(new Error(message),{publicMessage:message,statusCode});};
function text(v,max){if(typeof v!=='string'||!v.trim()||v.trim().length>max)fail(`Enter 1–${max} characters.`);return v.trim();}
function date(v){if(typeof v!=='string'||!/^\d{4}-\d{2}-\d{2}$/.test(v)||v<'1900-01-01'||v>'2200-12-31')fail('Invalid date.');const d=new Date(v+'T00:00:00Z');if(!Number.isFinite(d.getTime())||d.toISOString().slice(0,10)!==v)fail('Invalid date.');return v;}
function time(v){if(typeof v!=='string'||!/^([01]\d|2[0-3]):[0-5]\d$/.test(v))fail('Enter a valid time.');return v;}
const find=(items,id)=>{const item=items.find(i=>i.id===id);if(!item)fail('Schedule item not found.',404);return item;};
export function scheduleHandler(pool){
 return async(request,reply)=>{
  const b=request.body||{},owner=request.userProfile.id;
  let db;
  try{
   const actions=['getWeek','createGroup','updateGroup','deleteGroup','createRow','updateRow','deleteRow','saveBlock','deleteBlock'];
   if(!actions.includes(b.action))fail('Unknown schedule action.');
   db=await pool.connect();await db.query('BEGIN');
   await db.query('INSERT INTO public.schedules(owner_id) VALUES($1) ON CONFLICT DO NOTHING',[owner]);
   const data=(await db.query('SELECT data FROM public.schedules WHERE owner_id=$1 FOR UPDATE',[owner])).rows[0].data;
   let result={saved:true};
   if(b.action==='getWeek'){
    const start=date(b.startDate),endDate=new Date(start+'T00:00:00Z');endDate.setUTCDate(endDate.getUTCDate()+6);
    const end=endDate.toISOString().slice(0,10);
    result={groups:data.groups,rows:data.rows,blocks:data.blocks.filter(e=>e.date>=start&&e.date<=end)};
   }else if(b.action==='createGroup'){
    if(data.groups.length>=50)fail('You can create up to 50 groups.');
    const group={id:randomUUID(),name:text(b.name,100)};data.groups.push(group);result={group};
   }else if(b.action==='updateGroup'){
    find(data.groups,b.groupId).name=text(b.name,100);
   }else if(b.action==='deleteGroup'){
    find(data.groups,b.groupId);const ids=data.rows.filter(r=>r.group_id===b.groupId).map(r=>r.id);
    data.groups=data.groups.filter(g=>g.id!==b.groupId);data.rows=data.rows.filter(r=>r.group_id!==b.groupId);data.blocks=data.blocks.filter(e=>!ids.includes(e.row_id));
   }else if(b.action==='createRow'){
    find(data.groups,b.groupId);if(data.rows.length>=200)fail('You can create up to 200 rows.');
    const row={id:randomUUID(),group_id:b.groupId,name:text(b.name,100)};data.rows.push(row);result={row};
   }else if(b.action==='updateRow'){
    find(data.rows,b.rowId).name=text(b.name,100);
   }else if(b.action==='deleteRow'){
    find(data.rows,b.rowId);data.rows=data.rows.filter(r=>r.id!==b.rowId);data.blocks=data.blocks.filter(e=>e.row_id!==b.rowId);
   }else if(b.action==='deleteBlock'){
    find(data.blocks,b.blockId);data.blocks=data.blocks.filter(e=>e.id!==b.blockId);
   }else{
    // Legacy row IDs remain readable; hourly blocks no longer need a group or row.
    if(b.rowId!=null)find(data.rows,b.rowId);
    const existing=b.blockId?find(data.blocks,b.blockId):null;
    const start=time(b.start),end=b.end==='24:00'?'24:00':time(b.end);
    if(end<=start)fail('End time must be after start time on the same day.');
    const color=b.color??'#D97706';if(!/^#[0-9a-f]{6}$/i.test(color))fail('Invalid colour.');
    const note=b.note??'';if(typeof note!=='string'||note.length>2000)fail('Notes must be at most 2000 characters.');
    const block={id:b.blockId??randomUUID(),...(b.rowId||existing?.row_id?{row_id:b.rowId??existing.row_id}:{}),date:date(b.date),start,end,title:text(b.title,200),note,color};
    if(b.blockId){find(data.blocks,b.blockId);data.blocks=data.blocks.map(e=>e.id===b.blockId?block:e);}
    else{if(data.blocks.length>=5000)fail('You can save up to 5000 schedule blocks.');data.blocks.push(block);}
    result={block};
   }
   if(b.action!=='getWeek')await db.query('UPDATE public.schedules SET data=$1::jsonb,updated_at=now() WHERE owner_id=$2',[JSON.stringify(data),owner]);
   await db.query('COMMIT');return result;
  }catch(error){
   if(db)await db.query('ROLLBACK').catch(()=>{});
   if(error.publicMessage)return reply.code(error.statusCode).send({error:error.publicMessage});
   request.log.error({errorCode:error.code||'SCHEDULE_FAILED'},'Schedule request failed');
   return reply.code(503).send({error:'Schedule is unavailable. Please try again.'});
  }finally{db?.release();}
 };
}
