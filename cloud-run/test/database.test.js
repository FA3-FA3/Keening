import test from 'node:test';
import assert from 'node:assert/strict';
import { createPool, ensureUserProfile } from '../src/database.js';

const url = process.env.TEST_DATABASE_URL;
test('Postgres concurrent provisioning creates one identity with stable internal ID', { skip: !url }, async () => {
  assert.ok(['localhost', '127.0.0.1', '[::1]'].includes(new URL(url).hostname), 'Integration test only permits a local database');
  const pool = createPool(url);
  const uid = `test-${crypto.randomUUID()}`;
  try {
    const rows = await Promise.all(Array.from({ length: 8 }, () => ensureUserProfile(pool, { uid })));
    assert.equal(new Set(rows.map(row => row.id)).size, 1);
    assert.ok(rows.every(row => row.email === null));
    const updated = await ensureUserProfile(pool, { uid, email: 'linked@example.test' });
    assert.equal(updated.id, rows[0].id);
    assert.equal(updated.email, 'linked@example.test');
    const result = await pool.query('SELECT count(*)::int AS count FROM public.users WHERE firebase_uid=$1', [uid]);
    assert.equal(result.rows[0].count, 1);
  } finally {
    await pool.query('DELETE FROM public.users WHERE firebase_uid=$1', [uid]);
    await pool.end();
  }
});
