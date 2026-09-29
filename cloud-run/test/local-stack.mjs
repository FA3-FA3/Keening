// Run explicitly with `npm run test:local` after starting the emulator stack.
// All endpoints are fixed to the local demo stack; no live credentials are read.
import assert from 'node:assert/strict';
import { createPool } from '../src/database.js';

const authBase = 'http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1';
const pool = createPool('postgresql://keening_local@127.0.0.1:55440/postgres');
let account;
try {
  const signup = await fetch(`${authBase}/accounts:signUp?key=demo-key`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ returnSecureToken: true }),
  });
  assert.equal(signup.status, 200, 'Anonymous emulator login must succeed');
  account = await signup.json();
  const claims = JSON.parse(Buffer.from(account.idToken.split('.')[1], 'base64url').toString());
  assert.equal(claims.aud, 'demo-keening');
  assert.equal(claims.firebase.sign_in_provider, 'anonymous');
  for (let attempt = 0; attempt < 2; attempt++) {
    const response = await fetch('http://127.0.0.1:8080/whoami', {
      headers: { Authorization: `Bearer ${account.idToken}` },
    });
    assert.equal(response.status, 200, 'API must verify the emulator token');
    assert.deepEqual(await response.json(), { firebaseUid: account.localId, email: null, anonymous: true });
  }
  const result = await pool.query('SELECT id, email FROM public.users WHERE firebase_uid=$1', [account.localId]);
  assert.equal(result.rowCount, 1);
  assert.equal(result.rows[0].email, null);
  assert.match(result.rows[0].id, /^[a-f0-9-]{36}$/);
  const denied = await fetch('http://127.0.0.1:8080/whoami');
  assert.equal(denied.status, 401);
  console.log('PASS: anonymous sign-in -> verified API -> single Postgres profile; unauthenticated access denied.');
} finally {
  if (account?.localId) {
    await pool.query('DELETE FROM public.users WHERE firebase_uid=$1', [account.localId]);
    await fetch(`${authBase}/accounts:delete?key=demo-key`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ idToken: account.idToken }),
    });
  }
  await pool.end();
}
