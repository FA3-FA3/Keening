import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import {createPool} from '../src/database.js';
import {buildApp} from '../src/app.js';

test('username updates persist, enforce uniqueness and only modify authenticated owner', {skip:!process.env.TEST_DATABASE_URL}, async t => {
  const url=process.env.TEST_DATABASE_URL;
  assert.ok(['localhost','127.0.0.1'].includes(new URL(url).hostname));
  const pool=createPool(url);
  for(const file of ['01-schema.sql','02-usernames.sql','08-profile-picture.sql']) await pool.query(await readFile(new URL(`../../postgres/init/${file}`,import.meta.url),'utf8'));
  const prefix=randomUUID();
  const app=await buildApp({pool,logger:false,origins:[],verifyIdToken:async token=>({uid:`${prefix}-${token}`,firebase:{sign_in_provider:'password'}})});
  t.after(async()=>{await pool.query('DELETE FROM users WHERE firebase_uid IN ($1,$2)',[`${prefix}-a`,`${prefix}-b`]);await app.close();});
  const change=(username,token='a')=>app.inject({method:'POST',url:'/account/username',headers:{authorization:`Bearer ${token}`},payload:{username,userId:'another-user'}});
  const name='user_'+prefix.replaceAll('-','').slice(0,15);
  assert.equal((await app.inject({method:'POST',url:'/account/username',payload:{username:name}})).statusCode,401);
  for(const bad of ['ab','spaces bad','x'.repeat(31),null]) assert.equal((await change(bad)).statusCode,400);
  assert.equal((await change(name)).statusCode,200);
  assert.equal((await change(name.toUpperCase(),'b')).statusCode,409);
  assert.equal((await change(name+'b','b')).statusCode,200);
  const a=await app.inject({url:'/whoami',headers:{authorization:'Bearer a'}});
  assert.equal(a.json().username,name);
  assert.equal((await change(name.toUpperCase())).statusCode,200);
});
