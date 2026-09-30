import test from 'node:test';
import assert from 'node:assert/strict';
import { buildApp } from '../src/app.js';

async function fixture(t, { failDb = false, failEnable = false } = {}) {
 const events=[];
 const app=await buildApp({logger:false,origins:['http://localhost:3000'],registrationCode:'test-code',
  verifyIdToken:async()=>{},
  pool:{query:async(sql,values)=>{events.push(['db',sql,values]);if(failDb)throw Object.assign(new Error(),{code:'23505'});return {rows:[]};},end:async()=>{}},
  auth:{createUser:async(data)=>{events.push(['create',data]);return {uid:'new-user',email:data.email};},updateUser:async(uid,data)=>{events.push(['enable',uid,data]);if(failEnable)throw new Error('private');},deleteUser:async(uid)=>events.push(['delete',uid])}});
 t.after(()=>app.close());return {app,events};
}
const body={email:'test@example.com',username:'Tester_1',password:'test-password',code:'test-code'};
test('missing and wrong codes have no account or database side effects',async t=>{
 const {app,events}=await fixture(t);
 for(const code of [undefined,'wrong']){const r=await app.inject({method:'POST',url:'/register',payload:{...body,code}});assert.equal(r.statusCode,403);}
 assert.equal(events.length,0);
});
test('invalid username and password are rejected before account creation',async t=>{
 const {app,events}=await fixture(t);
 for(const data of [{username:'bad name'},{password:'short'}])assert.equal((await app.inject({method:'POST',url:'/register',payload:{...body,...data}})).statusCode,400);
 assert.equal(events.length,0);
});
test('registration stores username before enabling account and returns no secrets',async t=>{
 const {app,events}=await fixture(t);const r=await app.inject({method:'POST',url:'/register',payload:body});
 assert.equal(r.statusCode,201);assert.deepEqual(r.json(),{created:true});
 assert.deepEqual(events.map(e=>e[0]),['create','db','enable']);assert.equal(events[0][1].disabled,true);assert.deepEqual(events[1][2],['new-user',body.email,body.username]);
});
test('duplicate username removes newly-created Firebase account',async t=>{
 const {app,events}=await fixture(t,{failDb:true});assert.equal((await app.inject({method:'POST',url:'/register',payload:body})).statusCode,409);
 assert.equal(events.at(-1)[0],'delete');assert.ok(!events.some(e=>e[0]==='enable'));
});
test('enable failure compensates Firebase account and database row',async t=>{
 const {app,events}=await fixture(t,{failEnable:true});assert.equal((await app.inject({method:'POST',url:'/register',payload:body})).statusCode,503);
 assert.equal(events.at(-2)[0],'delete');assert.match(events.at(-1)[1],/^DELETE/);
});
test('registration throttles repeated requests',async t=>{
 const {app}=await fixture(t);for(let i=0;i<10;i++)await app.inject({method:'POST',url:'/register',payload:{...body,code:'wrong'}});
 assert.equal((await app.inject({method:'POST',url:'/register',payload:body})).statusCode,429);
});
