import test from 'node:test';
import assert from 'node:assert/strict';
import sharp from 'sharp';
import { readFile } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';
import { createPool } from '../src/database.js';
import { buildApp } from '../src/app.js';

test('profile pictures validate, persist, resize, isolate owners and remove', { skip: !process.env.TEST_DATABASE_URL }, async t => {
  const url = process.env.TEST_DATABASE_URL;
  assert.ok(['localhost', '127.0.0.1'].includes(new URL(url).hostname));
  const pool = createPool(url);
  for (const file of ['01-schema.sql', '02-usernames.sql', '08-profile-picture.sql']) {
    await pool.query(await readFile(new URL(`../../postgres/init/${file}`, import.meta.url), 'utf8'));
  }
  const prefix = randomUUID();
  const app = await buildApp({ pool, logger: false, origins: [], verifyIdToken: async token => ({ uid: `${prefix}-${token}`, firebase: { sign_in_provider: 'password' } }) });
  t.after(async () => {
    await pool.query('DELETE FROM users WHERE firebase_uid IN ($1,$2)', [`${prefix}-owner`, `${prefix}-other`]);
    await app.close();
  });
  const upload = (image, token = 'owner') => app.inject({ method: 'POST', url: '/profile-picture', headers: { authorization: `Bearer ${token}` }, payload: { image, userId: 'someone-else' } });
  const profile = async token => (await app.inject({ url: '/whoami', headers: { authorization: `Bearer ${token}` } })).json();
  assert.equal((await app.inject({ method: 'POST', url: '/profile-picture', payload: { image: null } })).statusCode, 401);
  const image = await sharp({ create: { width: 600, height: 300, channels: 3, background: '#008877' } }).png().toBuffer();
  const saved = await upload(image.toString('base64'));
  assert.equal(saved.statusCode, 200, saved.body);
  const picture = saved.json().profilePicture;
  const metadata = await sharp(Buffer.from(picture.split(',')[1], 'base64')).metadata();
  assert.equal(metadata.width, 256);
  assert.equal(metadata.height, 256);
  assert.equal(metadata.format, 'jpeg');
  assert.equal((await profile('owner')).profilePicture, picture);
  assert.equal((await profile('other')).profilePicture, null);
  for (const invalid of ['invalid!', Buffer.from('<svg/>').toString('base64'), Buffer.alloc(5 * 1024 * 1024 + 1).toString('base64')]) {
    assert.equal((await upload(invalid)).statusCode, 400);
  }
  assert.equal((await profile('owner')).profilePicture, picture);
  assert.equal((await upload(null)).statusCode, 200);
  assert.equal((await profile('owner')).profilePicture, null);
});
