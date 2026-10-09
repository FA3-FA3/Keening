import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import {createPool} from '../src/database.js';
import {buildApp} from '../src/app.js';
import {cleanDoc,cleanNote,cleanRuns,noteImageIds} from '../src/pads.js';

// A valid 1x1 PNG.
const PNG='iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';
const OBJ=String.fromCharCode(0xfffc);
const text=(id,extra={})=>({id,type:'text',x:10,y:20,w:200,text:'Hello',fontSize:18,color:'#111111',...extra});

test('pad documents are validated and rebuilt from whitelisted fields', ()=>{
  const clean=cleanDoc({elements:[
    {...text('a'),evil:'<script>'},
    {id:'b',type:'line',x1:0,y1:0,x2:50,y2:50,width:4,color:'#ff0000'},
    {id:'c',type:'pen',points:[[1,2],[3,4.123456]],width:2,color:'#00ff00'},
    {id:'d',type:'image',x:0,y:0,w:100,h:80,imageId:randomUUID()},
  ]});
  assert.equal(clean.elements.length,4);
  assert.equal(clean.elements[0].evil,undefined);
  assert.equal(clean.elements[1].color,'#FF0000');
  assert.deepEqual(clean.elements[2].points[1],[3,4.12]);
  for(const bad of [
    null,{},{elements:'x'},
    {elements:[{id:'a',type:'nope'}]},
    {elements:[text('a'),text('a')]},                       // duplicate id
    {elements:[text('a',{color:'red'})]},
    {elements:[text('a',{x:NaN})]},
    {elements:[text('a',{x:1e9})]},
    {elements:[text('a',{fontSize:1})]},
    {elements:[text('a',{text:'x'.repeat(10001)})]},
    {elements:[{id:'p',type:'pen',points:[],width:2,color:'#000000'}]},
    {elements:[{id:'i',type:'image',x:0,y:0,w:10,h:10,imageId:'nope'}]},
    {elements:Array.from({length:3001},(_,i)=>text(`t${i}`))},
  ])assert.throws(()=>cleanDoc(bad),/./,JSON.stringify(bad).slice(0,60));
});

const databaseUrl=process.env.TEST_DATABASE_URL;
test('pads persist, validate, isolate owners and keep images', {skip:!databaseUrl}, async t=>{
  assert.ok(['localhost','127.0.0.1','[::1]'].includes(new URL(databaseUrl).hostname));
  const pool=createPool(databaseUrl);
  for(const file of ['01-schema.sql','02-usernames.sql','08-profile-picture.sql','03-gantt.sql','04-boards.sql','05-event-task-links.sql','06-calendar.sql','07-schedule.sql','09-calendar-sessions.sql','10-calendar-location.sql','11-calendar-tags.sql','12-event-panel-links.sql','13-calendar-session-panel-links.sql','14-pads.sql','15-pad-descriptions.sql','16-document-folders.sql','17-attachments.sql'])
    await pool.query(await readFile(new URL(`../../postgres/init/${file}`,import.meta.url),'utf8'));
  const prefix=`pads-${randomUUID()}`;
  const app=await buildApp({pool,logger:false,origins:[],verifyIdToken:async token=>({uid:`${prefix}-${token}`,firebase:{sign_in_provider:'password'}})});
  t.after(async()=>{await pool.query('DELETE FROM public.users WHERE firebase_uid IN ($1,$2)',[`${prefix}-owner`,`${prefix}-other`]);await app.close();});
  const call=async(data,token='owner',status=200)=>{
    const r=await app.inject({method:'POST',url:'/pads',headers:{authorization:`Bearer ${token}`},payload:data});
    assert.equal(r.statusCode,status,r.body);return r.json();
  };
  assert.equal((await app.inject({method:'POST',url:'/pads',payload:{action:'listPads'}})).statusCode,401);
  await call({action:'nope'},'owner',400);
  await call({action:'createPad',name:'  '},'owner',400);
  const pad=(await call({action:'createPad',name:'Sketches'})).pad;
  assert.deepEqual(pad.doc,{version:1,elements:[]});
  assert.deepEqual((await call({action:'listPads'})).pads.map(p=>p.name),['Sketches']);
  assert.deepEqual((await call({action:'listPads'},'other')).pads,[]);

  // Layout round trip.
  const doc={elements:[text('a'),{id:'l',type:'line',x1:0,y1:0,x2:9,y2:9,width:3,color:'#2563EB'},{id:'p',type:'pen',points:[[1,1],[2,2]],width:2,color:'#000000'}]};
  await call({action:'savePad',padId:pad.id,doc});
  const loaded=(await call({action:'getPad',padId:pad.id})).pad;
  assert.equal(loaded.doc.elements.length,3);
  assert.equal(loaded.doc.elements[0].text,'Hello');
  await call({action:'savePad',padId:pad.id,doc:{elements:[text('a',{color:'bad'})]}},'owner',400);
  assert.equal((await call({action:'getPad',padId:pad.id})).pad.doc.elements.length,3,'invalid saves change nothing');

  // Images: validated, stored once, referenced from the layout.
  await call({action:'uploadImage',padId:pad.id,image:Buffer.from('not an image').toString('base64')},'owner',400);
  await call({action:'uploadImage',padId:pad.id,image:''},'owner',400);
  await call({action:'uploadImage',padId:pad.id,image:'A'.repeat(5*1024*1024)},'owner',400);
  const {imageId}=await call({action:'uploadImage',padId:pad.id,image:PNG});
  const image=await call({action:'getImage',padId:pad.id,imageId});
  assert.equal(image.mime,'image/png');assert.equal(image.image,PNG);
  await call({action:'getImage',padId:pad.id,imageId:randomUUID()},'owner',404);
  await call({action:'uploadImage',padId:pad.id,image:PNG},'other',404);
  await call({action:'getImage',padId:pad.id,imageId},'other',404);
  const withImage={elements:[...doc.elements,{id:'i',type:'image',x:5,y:5,w:100,h:100,imageId}]};
  await call({action:'savePad',padId:pad.id,doc:withImage});
  await call({action:'savePad',padId:pad.id,doc:{elements:[{id:'i',type:'image',x:5,y:5,w:100,h:100,imageId:randomUUID()}]}},'owner',400);

  // Ownership.
  for(const action of ['getPad','savePad','renamePad','deletePad'])
    await call({action,padId:pad.id,name:'Mine',doc},'other',404);
  await call({action:'getPad',padId:'bad'},'owner',400);
  await call({action:'renamePad',padId:pad.id,name:'Renamed'});
  assert.equal((await call({action:'listPads'})).pads[0].name,'Renamed');

  // Old unused images are cleaned up on save; recent ones survive for undo.
  const old=(await call({action:'uploadImage',padId:pad.id,image:PNG})).imageId;
  await pool.query("UPDATE public.pad_images SET created_at=now()-interval '2 hours' WHERE id=$1",[old]);
  await call({action:'savePad',padId:pad.id,doc:withImage});
  await call({action:'getImage',padId:pad.id,imageId:old},'owner',404);
  assert.equal((await call({action:'getImage',padId:pad.id,imageId})).image,PNG);

  // Descriptions: optional, trimmed, limited, and kept when omitted from an update.
  assert.equal((await call({action:'listPads'})).pads[0].description,'');
  const described=(await call({action:'createPad',name:'Notes',description:'  Meeting sketches  '})).pad;
  assert.equal(described.description,'Meeting sketches');
  await call({action:'createPad',name:'Too long',description:'x'.repeat(1001)},'owner',400);
  await call({action:'createPad',name:'Bad',description:5},'owner',400);
  assert.equal((await call({action:'getPad',padId:described.id})).pad.description,'Meeting sketches');
  const updated=(await call({action:'updatePad',padId:described.id,name:'Notes v2',description:'New text'})).pad;
  assert.deepEqual([updated.name,updated.description],['Notes v2','New text']);
  assert.equal((await call({action:'updatePad',padId:described.id,name:'Notes v3'})).pad.description,'New text');
  await call({action:'updatePad',padId:described.id,name:''},'owner',400);
  await call({action:'updatePad',padId:described.id,name:'Ok',description:'y'.repeat(1001)},'owner',400);
  await call({action:'updatePad',padId:described.id,name:'Stolen',description:'x'},'other',404);
  assert.deepEqual((await call({action:'listPads'})).pads.map(x=>[x.name,x.description]),[['Renamed',''],['Notes v3','New text']]);
  await call({action:'deletePad',padId:described.id});

  await call({action:'deletePad',padId:pad.id});
  assert.equal((await pool.query('SELECT count(*)::int AS n FROM public.pad_images WHERE pad_id=$1',[pad.id])).rows[0].n,0);
  assert.deepEqual((await call({action:'listPads'})).pads,[]);
});

test('plain notes are validated and rebuilt from the text only', ()=>{
  assert.deepEqual(cleanNote({text:'Hello\nworld',evil:1}),{version:1,text:'Hello\nworld'});
  assert.deepEqual(cleanNote({text:''}),{version:1,text:''});

  // Formatting runs: rebuilt from whitelisted attributes and checked against the text.
  const runs=[{start:0,end:5,bold:true,size:24,color:'#dc2626',evil:1},{start:6,end:11,underline:true,italic:true,bg:'#fde047'}];
  assert.deepEqual(cleanNote({text:'Hello world',runs}).runs,[{start:0,end:5,size:24,color:'#DC2626',bold:true},{start:6,end:11,bg:'#FDE047',italic:true,underline:true}]);
  assert.equal(cleanNote({text:'Hello',runs:[]}).runs,undefined,'plain notes carry no runs');
  assert.deepEqual(cleanNote({text:'Hello',runs:[{start:0,end:2,sub:true},{start:3,end:5,sup:true}]}).runs,[{start:0,end:2,sub:true},{start:3,end:5,sup:true}]);
  assert.throws(()=>cleanNote({text:'Hello',runs:[{start:0,end:2,sub:true,sup:true}]}),/./,'not both');
  assert.throws(()=>cleanNote({text:'Hello',runs:[{start:0,end:2,sub:false}]}),/./);
  assert.deepEqual(cleanRuns(undefined,5,10),[]);
  for(const bad of [{start:0,end:12,bold:true},{start:3,end:3,bold:true},{start:-1,end:2,bold:true},{start:0.5,end:2,bold:true},{start:0,end:2},{start:0,end:2,bold:false},{start:0,end:2,size:4},{start:0,end:2,color:'red'},{start:0,end:2,bg:'#FFF'}])
    assert.throws(()=>cleanNote({text:'Hello world',runs:[bad]}),/./,JSON.stringify(bad));
  assert.throws(()=>cleanNote({text:'Hello world',runs:[{start:0,end:5,bold:true},{start:4,end:8,bold:true}]}),/./,'overlap');
  assert.throws(()=>cleanNote({text:'Hello world',runs:[{start:5,end:8,bold:true},{start:0,end:2,bold:true}]}),/./,'unsorted');
  assert.throws(()=>cleanNote({text:'Hello world',runs:'bold'}),/./);
  assert.throws(()=>cleanNote({text:'x'.repeat(20),runs:Array.from({length:5001},(_,i)=>({start:0,end:1,bold:true}))}),/./,'too many runs');
  // Pictures and equations stand in for one placeholder character of a note.
  const image=randomUUID();
  const embedded=cleanNote({text:'a'+OBJ+'b'+OBJ,runs:[{start:1,end:2,embed:{type:'image',imageId:image,evil:1}},{start:3,end:4,size:24,embed:{type:'equation',latex:'\\frac{a}{b}'}}]});
  assert.deepEqual(embedded.runs,[{start:1,end:2,embed:{type:'image',imageId:image}},{start:3,end:4,size:24,embed:{type:'equation',latex:'\\frac{a}{b}'}}]);
  assert.deepEqual(noteImageIds(embedded.runs),[image]);
  assert.deepEqual(noteImageIds(undefined),[]);
  for(const bad of [
    {start:0,end:1,embed:{type:'image',imageId:'nope'}},            // not a uuid
    {start:0,end:1,embed:{type:'video',imageId:image}},
    {start:0,end:1,embed:{type:'equation',latex:''}},
    {start:0,end:1,embed:{type:'equation',latex:'x'.repeat(2001)}},
    {start:0,end:1,embed:'image'},
    {start:0,end:2,embed:{type:'equation',latex:'x'}},               // covers a normal character
    {start:2,end:3,embed:{type:'equation',latex:'x'}},               // not a placeholder
  ])assert.throws(()=>cleanNote({text:OBJ+'a'+'b',runs:[bad]}),/./,JSON.stringify(bad));
  assert.throws(()=>cleanDoc({elements:[{...text('t'),runs:[{start:0,end:1,embed:{type:'equation',latex:'x'}}]}]}),/./,'text boxes cannot hold embeds');
  assert.throws(()=>cleanNote({text:OBJ.repeat(101),runs:[{start:0,end:101,embed:{type:'equation',latex:'x'}}]}),/./,'too many embeds');
  assert.equal(cleanNote({text:OBJ.repeat(100),runs:[{start:0,end:100,embed:{type:'equation',latex:'x'}}]}).runs.length,1);

  // Equations on a pad.
  const eq={id:'q',type:'equation',x:10,y:20,w:120,h:40,latex:'x^2+y^2=z^2',color:'#2563eb'};
  assert.deepEqual(cleanDoc({elements:[{...eq,evil:1}]}).elements[0],{...eq,color:'#2563EB'});
  for(const bad of [{latex:''},{latex:'x'.repeat(2001)},{latex:5},{w:2},{h:99999},{color:'blue'},{x:1e9}])
    assert.throws(()=>cleanDoc({elements:[{...eq,...bad}]}),/./,JSON.stringify(bad));
  const box=cleanDoc({elements:[{...text('t'),runs:[{start:0,end:2,bold:true}]},text('u')]}).elements;
  assert.deepEqual(box[0].runs,[{start:0,end:2,bold:true}]);assert.equal(box[1].runs,undefined);
  assert.throws(()=>cleanDoc({elements:[{...text('t'),runs:[{start:0,end:99,bold:true}]}]}),/./,'run beyond the text box text');
  for(const bad of [null,{},{text:5},{elements:[]},{text:'x'.repeat(200001)}])
    assert.throws(()=>cleanNote(bad),/./,JSON.stringify(bad)?.slice(0,40));
});

test('documents: folders, document types, moving and notes', {skip:!databaseUrl}, async t=>{
  const pool=createPool(databaseUrl);
  for(const file of ['01-schema.sql','02-usernames.sql','08-profile-picture.sql','03-gantt.sql','04-boards.sql','05-event-task-links.sql','06-calendar.sql','07-schedule.sql','09-calendar-sessions.sql','10-calendar-location.sql','11-calendar-tags.sql','12-event-panel-links.sql','13-calendar-session-panel-links.sql','14-pads.sql','15-pad-descriptions.sql','16-document-folders.sql','17-attachments.sql'])
    await pool.query(await readFile(new URL(`../../postgres/init/${file}`,import.meta.url),'utf8'));
  const prefix=`docs-${randomUUID()}`;
  const app=await buildApp({pool,logger:false,origins:[],verifyIdToken:async token=>({uid:`${prefix}-${token}`,firebase:{sign_in_provider:'password'}})});
  t.after(async()=>{await pool.query('DELETE FROM public.users WHERE firebase_uid IN ($1,$2)',[`${prefix}-owner`,`${prefix}-other`]);await app.close();});
  const call=async(data,token='owner',status=200)=>{
    const r=await app.inject({method:'POST',url:'/pads',headers:{authorization:`Bearer ${token}`},payload:data});
    assert.equal(r.statusCode,status,r.body);return r.json();
  };

  // Folders.
  const work=(await call({action:'createFolder',name:'Work'})).folder;
  assert.equal(work.parent_id,null);
  const plans=(await call({action:'createFolder',name:'Plans',parentId:work.id})).folder;
  assert.equal(plans.parent_id,work.id);
  await call({action:'createFolder',name:'  '},'owner',400);
  await call({action:'createFolder',name:'x',parentId:'bad'},'owner',400);
  await call({action:'createFolder',name:'x',parentId:work.id},'other',404);
  assert.deepEqual((await call({action:'listFolders'})).folders.map(f=>[f.name,f.parent_id]),[['Plans',work.id],['Work',null]]);
  assert.deepEqual((await call({action:'listFolders'},'other')).folders,[]);
  // Nesting is limited to 8 levels (Work > Plans is 2).
  let deepest=plans;
  for(let level=3;level<=8;level++)deepest=(await call({action:'createFolder',name:`L${level}`,parentId:deepest.id})).folder;
  await call({action:'createFolder',name:'too deep',parentId:deepest.id},'owner',400);

  // Document types and where they live.
  const pad=(await call({action:'createPad',name:'Sketch',folderId:work.id})).pad;
  assert.deepEqual([pad.kind,pad.folder_id],['pad',work.id]);
  assert.deepEqual(pad.doc,{version:1,elements:[]});
  const note=(await call({action:'createPad',name:'Shopping',kind:'notepad',description:'Weekly list',folderId:plans.id})).pad;
  assert.deepEqual([note.kind,note.folder_id,note.description],['notepad',plans.id,'Weekly list']);
  assert.deepEqual(note.doc,{version:1,text:''});
  const loose=(await call({action:'createPad',name:'Loose',kind:'notepad'})).pad;
  assert.equal(loose.folder_id,null);
  await call({action:'createPad',name:'x',kind:'spreadsheet'},'owner',400);
  await call({action:'createPad',name:'x',folderId:randomUUID()},'owner',404);
  await call({action:'createPad',name:'x',folderId:work.id},'other',404);
  assert.deepEqual((await call({action:'listPads'})).pads.map(p=>[p.name,p.kind,p.folder_id]),[['Sketch','pad',work.id],['Shopping','notepad',plans.id],['Loose','notepad',null]]);

  // Notes save plain text; pads keep their layout; the two are not interchangeable.
  await call({action:'savePad',padId:note.id,doc:{text:'Milk\neggs'}});
  assert.equal((await call({action:'getPad',padId:note.id})).pad.doc.text,'Milk\neggs');
  // Formatting round-trips; bad runs are rejected and change nothing.
  const styled=[{start:0,end:4,bold:true,color:'#DC2626'}];
  await call({action:'savePad',padId:note.id,doc:{text:'Milk\neggs',runs:styled}});
  assert.deepEqual((await call({action:'getPad',padId:note.id})).pad.doc.runs,styled);
  await call({action:'savePad',padId:note.id,doc:{text:'Milk',runs:[{start:0,end:99,bold:true}]}},'owner',400);
  assert.deepEqual((await call({action:'getPad',padId:note.id})).pad.doc.runs,styled);
  await call({action:'savePad',padId:note.id,doc:{text:'Milk\neggs'}});
  assert.equal((await call({action:'getPad',padId:note.id})).pad.doc.runs,undefined);
  await call({action:'savePad',padId:note.id,doc:{elements:[]}},'owner',400);
  await call({action:'savePad',padId:note.id,doc:{text:'x'.repeat(200001)}},'owner',400);
  await call({action:'savePad',padId:pad.id,doc:{text:'nope'}},'owner',400);
  // Notes hold pictures and equations too: pictures are stored per note and must exist to be used.
  const noteImage=(await call({action:'uploadImage',padId:note.id,image:PNG})).imageId;
  assert.equal((await call({action:'getImage',padId:note.id,imageId:noteImage})).image,PNG);
  await call({action:'getImage',padId:pad.id,imageId:noteImage},'owner',404);
  await call({action:'getImage',padId:note.id,imageId:randomUUID()},'owner',404);
  await call({action:'uploadImage',padId:note.id,image:PNG},'other',404);
  const withEmbeds={text:'See '+OBJ+' and '+OBJ,runs:[{start:4,end:5,embed:{type:'image',imageId:noteImage}},{start:10,end:11,embed:{type:'equation',latex:'E=mc^2'}}]};
  await call({action:'savePad',padId:note.id,doc:withEmbeds});
  assert.deepEqual((await call({action:'getPad',padId:note.id})).pad.doc.runs,withEmbeds.runs);
  await call({action:'savePad',padId:note.id,doc:{...withEmbeds,runs:[{start:4,end:5,embed:{type:'image',imageId:randomUUID()}}]}},'owner',400);
  assert.deepEqual((await call({action:'getPad',padId:note.id})).pad.doc.runs,withEmbeds.runs,'a rejected save changes nothing');
  await call({action:'savePad',padId:note.id,doc:{text:'Milk\neggs'}});
  await call({action:'uploadImage',padId:pad.id,image:PNG});

  // Moving documents.
  assert.equal((await call({action:'movePad',padId:note.id,folderId:work.id})).pad.folder_id,work.id);
  assert.equal((await call({action:'movePad',padId:note.id,folderId:null})).pad.folder_id,null);
  assert.equal((await call({action:'movePad',padId:note.id,folderId:plans.id})).pad.folder_id,plans.id);
  assert.equal((await call({action:'movePad',padId:note.id})).pad.folder_id,null,'no folder means the top level');
  await call({action:'movePad',padId:note.id,folderId:randomUUID()},'owner',404);
  await call({action:'movePad',padId:note.id,folderId:'bad'},'owner',400);
  await call({action:'movePad',padId:note.id,folderId:work.id},'other',404);
  await call({action:'movePad',padId:pad.id,folderId:null},'other',404);
  await call({action:'movePad',padId:note.id,folderId:plans.id});

  // Moving folders: never into themselves or their own sub-folders, within the depth limit.
  const archive=(await call({action:'createFolder',name:'Archive'})).folder;
  assert.equal((await call({action:'moveFolder',folderId:archive.id,parentId:plans.id})).folder.parent_id,plans.id);
  await call({action:'moveFolder',folderId:work.id,parentId:archive.id},'owner',400); // into its own sub-folder
  await call({action:'moveFolder',folderId:work.id,parentId:work.id},'owner',400);   // into itself
  await call({action:'moveFolder',folderId:archive.id,parentId:deepest.id},'owner',400); // would be 9 levels deep
  assert.equal((await call({action:'moveFolder',folderId:archive.id,parentId:null})).folder.parent_id,null);
  assert.equal((await call({action:'moveFolder',folderId:archive.id})).folder.parent_id,null,'no parent means the top level');
  await call({action:'moveFolder',folderId:work.id,parentId:archive.id},'owner',400); // Work and its 6 levels below it would reach 9
  await call({action:'moveFolder',folderId:archive.id,parentId:plans.id},'other',404);
  await call({action:'moveFolder',folderId:work.id,parentId:null},'other',404);
  await call({action:'moveFolder',folderId:archive.id,parentId:randomUUID()},'owner',404);
  await call({action:'moveFolder',folderId:'bad'},'owner',400);
  // A moved folder takes its documents with it.
  const keep=(await call({action:'createPad',name:'Keep',folderId:archive.id})).pad;
  await call({action:'moveFolder',folderId:archive.id,parentId:work.id});
  assert.equal((await call({action:'getPad',padId:keep.id})).pad.folder_id,archive.id);
  assert.deepEqual((await call({action:'listFolders'})).folders.filter(f=>f.id===archive.id).map(f=>f.parent_id),[work.id]);

  // Renaming and deleting folders.
  assert.equal((await call({action:'renameFolder',folderId:work.id,name:'Projects'})).folder.name,'Projects');
  await call({action:'renameFolder',folderId:work.id,name:''},'owner',400);
  await call({action:'renameFolder',folderId:work.id,name:'x'},'other',404);
  await call({action:'renameFolder',name:'x'},'owner',400);
  await call({action:'deleteFolder',folderId:work.id},'other',404);
  await call({action:'deleteFolder',folderId:work.id});
  // The folder, its sub-folders, their documents and the pictures all go; loose documents stay.
  assert.deepEqual((await call({action:'listFolders'})).folders,[]);
  assert.deepEqual((await call({action:'listPads'})).pads.map(p=>p.name),['Loose']);
  assert.equal((await pool.query('SELECT count(*)::int AS n FROM public.pad_images WHERE pad_id=$1',[pad.id])).rows[0].n,0);
});
