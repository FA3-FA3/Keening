import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import dotenv from 'dotenv';
import { fileURLToPath } from 'node:url';
import { createPool } from '../src/database.js';
// This script uses only the demo emulator and loopback Postgres.
dotenv.config({path:new URL('../.env',import.meta.url).pathname.replace(/^\/([A-Za-z]:)/,'$1'),quiet:true});
const authBase='http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1';
const pool=createPool('postgresql://keening_local@127.0.0.1:55440/postgres');
const suffix=Date.now();
const email=`local-${suffix}@example.com`,username=`local_${suffix}`,password=randomUUID();
const post=(url,body)=>fetch(url,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});
let account;
try {
 const signup=await post('http://127.0.0.1:8080/register',{email,username,password,code:process.env.REGISTRATION_CODE});
 assert.equal(signup.status,201,'Code-gated local registration must succeed');
 const login=await post(`${authBase}/accounts:signInWithPassword?key=demo-key`,{email,password,returnSecureToken:true});
 assert.equal(login.status,200);account=await login.json();
 const claims=JSON.parse(Buffer.from(account.idToken.split('.')[1],'base64url').toString());
 assert.equal(claims.aud,'demo-keening');assert.equal(claims.firebase.sign_in_provider,'password');
 for(let i=0;i<2;i++){
  const response=await fetch('http://127.0.0.1:8080/whoami',{headers:{Authorization:`Bearer ${account.idToken}`}});
  assert.equal(response.status,200);assert.deepEqual(await response.json(),{firebaseUid:account.localId,email,username,anonymous:false});
 }
 const result=await pool.query('SELECT username FROM public.users WHERE firebase_uid=$1',[account.localId]);
 assert.equal(result.rowCount,1);assert.equal(result.rows[0].username,username);
 assert.equal((await fetch('http://127.0.0.1:8080/whoami')).status,401);
 console.log('PASS: local code registration -> email login -> verified API -> single username profile.');
} finally {
 if(account?.localId){
  await post(`${authBase}/accounts:delete?key=demo-key`,{idToken:account.idToken});
  await pool.query('DELETE FROM public.users WHERE firebase_uid=$1',[account.localId]);
 }
 await pool.end();
}
