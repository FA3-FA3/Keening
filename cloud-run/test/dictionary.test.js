import test from 'node:test';
import assert from 'node:assert/strict';
import { dictionaryHandler, dictionaryWord } from '../src/dictionary.js';
import { addUser, call, makeDb } from './helpers/pglite.js';

test('words are checked and made lower case', () => {
  assert.equal(dictionaryWord('  Keening '), 'keening');
  assert.equal(dictionaryWord('Don’t'), "don't");
  assert.equal(dictionaryWord('Café'), 'café');
  for (const bad of ['', 'two words', 'a-b', 'abc1', "a'b'c", "'ab", 'x'.repeat(61), 5, null, undefined]) {
    assert.throws(() => dictionaryWord(bad), /./, String(bad));
  }
});

test('added words are kept with the account, and each person has their own', async () => {
  const { pool } = await makeDb();
  const owner = await addUser(pool, 'owner');
  const other = await addUser(pool, 'other');
  const dictionary = dictionaryHandler(pool);
  const send = (body, who = owner) => call(dictionary, body, who);

  assert.deepEqual((await send({ action: 'list' })).body.words, []);
  const added = await send({ action: 'sync', add: ['Keening', 'frobnicate', 'keening', "isn't"] });
  assert.equal(added.status, 200);
  assert.deepEqual(added.body.words, ['frobnicate', "isn't", 'keening']);
  assert.deepEqual((await send({ action: 'list' })).body.words, ['frobnicate', "isn't", 'keening']);
  assert.deepEqual((await send({ action: 'list' }, other)).body.words, []);
  await send({ action: 'sync', add: ['zzz'] }, other);
  assert.deepEqual((await send({ action: 'list' })).body.words, ['frobnicate', "isn't", 'keening']);
});

test('words can be taken out again, in the same request as adding', async () => {
  const { pool } = await makeDb();
  const owner = await addUser(pool, 'owner');
  const send = body => call(dictionaryHandler(pool), body, owner);
  await send({ action: 'sync', add: ['alpha', 'beta', 'gamma'] });
  const next = await send({ action: 'sync', add: ['delta'], remove: ['Beta', 'missing'] });
  assert.deepEqual(next.body.words, ['alpha', 'delta', 'gamma']);
});

test('bad requests are refused and change nothing', async () => {
  const { pool } = await makeDb();
  const owner = await addUser(pool, 'owner');
  const send = body => call(dictionaryHandler(pool), body, owner);
  await send({ action: 'sync', add: ['keep'] });
  for (const bad of [
    { action: 'nonsense' },
    { action: 'sync', add: 'no' },
    { action: 'sync', add: ['fine', 'not fine'] },
    { action: 'sync', remove: [5] },
    { action: 'sync', add: Array.from({ length: 1001 }, () => 'a') },
  ]) {
    assert.equal((await send(bad)).status, 400, JSON.stringify(bad).slice(0, 60));
  }
  assert.deepEqual((await send({ action: 'list' })).body.words, ['keep']);
});

test('a dictionary has a limit', async () => {
  const { pool } = await makeDb();
  const owner = await addUser(pool, 'owner');
  const send = body => call(dictionaryHandler(pool), body, owner);
  const letters = n => {
    let w = '';
    do { w = String.fromCharCode(97 + (n % 26)) + w; n = Math.floor(n / 26); } while (n > 0);
    return 'w' + w;
  };
  const make = (from, n) => Array.from({ length: n }, (_, i) => letters(from + i));
  for (let i = 0; i < 5; i++) assert.equal((await send({ action: 'sync', add: make(i * 1000, 1000) })).status, 200);
  assert.equal((await send({ action: 'sync', add: ['onemore'] })).status, 400);
  assert.equal((await send({ action: 'list' })).body.words.length, 5000);
});
