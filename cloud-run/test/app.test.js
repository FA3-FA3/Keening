import test from 'node:test';
import assert from 'node:assert/strict';
import { buildApp } from '../src/app.js';
import { readConfig } from '../src/config.js';

async function fixture(t, { verify, query } = {}) {
  const calls = [];
  let closed = false;
  const app = await buildApp({
    logger: false,
    origins: ['http://localhost:3000'],
    verifyIdToken: verify || (async token => {
      assert.equal(token, 'test-token');
      return { uid: 'anonymous-uid', firebase: { sign_in_provider: 'anonymous' } };
    }),
    pool: {
      async query(sql, params) {
        calls.push({ sql, params });
        if (query) return query(sql, params);
        return { rows: [{ id: 'private-uuid', firebase_uid: params[0], email: params[1] }] };
      },
      async end() { closed = true; },
    },
  });
  t.after(async () => { await app.close(); assert.equal(closed, true); });
  return { app, calls };
}

test('health does not authenticate or provision a user', async t => {
  const { app, calls } = await fixture(t);
  const response = await app.inject('/health');
  assert.equal(response.statusCode, 200);
  assert.deepEqual(response.json(), { status: 'ok' });
  assert.equal(calls.length, 0);
});

test('missing and malformed tokens cannot access database', async t => {
  const { app, calls } = await fixture(t);
  for (const authorization of ['', 'Basic foo', 'Bearer', 'Bearer one two']) {
    const response = await app.inject({ url: '/whoami', headers: { authorization } });
    assert.equal(response.statusCode, 401);
  }
  assert.equal(calls.length, 0);
});

test('expired, revoked, and forged tokens are rejected before provisioning', async t => {
  for (const code of ['auth/id-token-expired', 'auth/id-token-revoked', 'auth/argument-error']) {
    const { app, calls } = await fixture(t, { verify: async () => { throw Object.assign(new Error('private token'), { code }); } });
    const response = await app.inject({ url: '/whoami', headers: { authorization: 'Bearer bad' } });
    assert.equal(response.statusCode, 401);
    assert.equal(calls.length, 0);
    assert.ok(!response.body.includes('private token'));
  }
});

test('anonymous identity provisions nullable email and hides internal UUID', async t => {
  const { app, calls } = await fixture(t);
  const response = await app.inject({ url: '/whoami?firebaseUid=attacker', headers: { authorization: 'Bearer test-token' } });
  assert.equal(response.statusCode, 200);
  assert.deepEqual(response.json(), { firebaseUid: 'anonymous-uid', email: null, anonymous: true });
  assert.deepEqual(calls[0].params, ['anonymous-uid', null]);
  assert.ok(!response.body.includes('private-uuid'));
  assert.equal(response.headers['cache-control'], 'no-store');
});

test('only verified email claims are persisted using SQL parameters', async t => {
  const uid = "uid'; DROP TABLE users; --";
  const { app, calls } = await fixture(t, { verify: async () => ({ uid, email: 'user@example.test' }) });
  const response = await app.inject({ url: '/whoami', headers: { authorization: 'Bearer test-token' } });
  assert.equal(response.statusCode, 200);
  assert.deepEqual(calls[0].params, [uid, 'user@example.test']);
  assert.ok(!calls[0].sql.includes(uid));
});

test('database and auth outages return sanitized 503 responses', async t => {
  for (const failure of ['query', 'verify']) {
    const { app } = await fixture(t, { [failure]: async () => { throw new Error('secret-database-password'); } });
    const response = await app.inject({ url: '/whoami', headers: { authorization: 'Bearer test-token' } });
    assert.equal(response.statusCode, 503);
    assert.ok(!response.body.includes('secret-database-password'));
  }
});

test('CORS permits only configured browser origins', async t => {
  const { app } = await fixture(t);
  const allowed = await app.inject({ method: 'OPTIONS', url: '/whoami', headers: { origin: 'http://localhost:3000', 'access-control-request-method': 'GET', 'access-control-request-headers': 'authorization' } });
  assert.equal(allowed.statusCode, 204);
  assert.equal(allowed.headers['access-control-allow-origin'], 'http://localhost:3000');
  const denied = await app.inject({ url: '/health', headers: { origin: 'https://untrusted.example' } });
  assert.equal(denied.headers['access-control-allow-origin'], undefined);
});

test('emulator config cannot use Neon or run in Cloud Run', () => {
  const demo = { DATABASE_URL: 'postgresql://localhost/keening', FIREBASE_PROJECT_ID: 'demo-keening', FIREBASE_AUTH_EMULATOR_HOST: '127.0.0.1:9099' };
  assert.equal(readConfig(demo).projectId, 'demo-keening');
  assert.throws(() => readConfig({ ...demo, DATABASE_URL: 'postgresql://example.neon.tech/neondb?sslmode=require' }));
  assert.throws(() => readConfig({ ...demo, K_SERVICE: 'keening' }));
  assert.throws(() => readConfig({ ...demo, NODE_ENV: 'production' }));
  assert.throws(() => readConfig({ ...demo, FIREBASE_PROJECT_ID: 'keening-ece74' }));
});

test('production requires explicit CORS and remote database encryption', () => {
  const live = { DATABASE_URL: 'postgresql://example.neon.tech/neondb?sslmode=require', NODE_ENV: 'production' };
  assert.throws(() => readConfig(live));
  assert.throws(() => readConfig({ ...live, CORS_ORIGINS: '*' }));
  assert.throws(() => readConfig({ ...live, CORS_ORIGINS: 'https://keening.example', DATABASE_URL: 'postgresql://example.neon.tech/neondb' }));
  assert.equal(readConfig({ ...live, CORS_ORIGINS: 'https://keening.example' }).projectId, 'keening-ece74');
});
