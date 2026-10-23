import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { makeDb, addUser, call } from './helpers/pglite.js';
import { lookupKey, pair, peopleHandler, usernameOf } from '../src/people.js';
import { messageBody, messageTime, messagesHandler } from '../src/messages.js';

test('lookup keys, usernames, message bodies and times are validated', () => {
  assert.deepEqual(lookupKey('  Ann_1 '), {kind: 'username', value: 'Ann_1'});
  assert.deepEqual(lookupKey(' ann@example.com '), {kind: 'email', value: 'ann@example.com'});
  for (const bad of [undefined, null, 5, '', '  ', 'ab', 'a b c', 'x'.repeat(31), 'a@b', '@x.com', 'a@b c.com', `${'x'.repeat(250)}@a.com`, 'ann!'])
    assert.throws(() => lookupKey(bad), /./, String(bad));
  assert.equal(usernameOf('bob_9'), 'bob_9');
  for (const bad of [undefined, 'a', 'a b', 'bob@x.com', 5]) assert.throws(() => usernameOf(bad), /./, String(bad));
  assert.deepEqual(pair('b', 'a'), ['a', 'b']);
  assert.deepEqual(pair('a', 'b'), ['a', 'b']);
  assert.equal(messageBody('  hi  '), 'hi');
  assert.equal(messageBody('x'.repeat(4000)).length, 4000);
  for (const bad of [undefined, null, 5, '', '   ', 'x'.repeat(4001)]) assert.throws(() => messageBody(bad), /./, String(bad));
  assert.equal(messageTime('2026-10-22T10:00:00.123456Z'), '2026-10-22T10:00:00.123456Z');
  assert.equal(messageTime('2026-10-22T10:00:00Z'), '2026-10-22T10:00:00Z');
  for (const bad of [undefined, 5, 'now', '2026-10-22', '2026-13-45T10:00:00Z', '2026-10-22T10:00:00+01:00']) assert.throws(() => messageTime(bad), /./, String(bad));
});

test('unknown actions and a database failure are reported safely', async () => {
  const owner = randomUUID();
  const ok = {query: async () => ({rows: []}), release() {}};
  const pool = {connect: async () => ok};
  for (const handler of [peopleHandler(pool), messagesHandler(pool)]) {
    assert.equal((await call(handler, {action: 'nope'}, owner)).status, 400);
    assert.equal((await call(handler, {}, owner)).status, 400);
  }
  const broken = {connect: async () => ({query: async sql => { if (/BEGIN|ROLLBACK/.test(sql)) return {rows: []}; throw Object.assign(new Error('secret sql detail'), {code: 'XX000'}); }, release() {}})};
  const r = await call(peopleHandler(broken), {action: 'listFriends'}, owner);
  assert.equal(r.status, 503);
  assert.ok(!JSON.stringify(r.body).includes('secret'));
});

test('friends and messages against a real Postgres', async () => {
  const { pool } = await makeDb();
  const people = peopleHandler(pool), messages = messagesHandler(pool);
  const ann = await addUser(pool, 'ann', 'Ann@Example.com');
  const bob = await addUser(pool, 'bob');
  const cat = await addUser(pool, 'cat');
  const P = (who, body) => call(people, body, who);
  const M = (who, body) => call(messages, body, who);

  // Finding people.
  assert.equal((await P(ann, { action: 'sendRequest', who: 'nobody' })).status, 404);
  assert.equal((await P(ann, { action: 'sendRequest', who: 'ann' })).status, 400, 'not yourself');
  assert.equal((await P(ann, { action: 'sendRequest', who: 'ANN@example.com' })).status, 400);
  let r = await P(ann, { action: 'sendRequest', who: 'BOB' });
  assert.deepEqual(r.body, { status: 'sent', username: 'bob' });
  assert.equal((await P(ann, { action: 'sendRequest', who: 'bob@example.com' })).status, 409, 'already sent');
  r = await P(bob, { action: 'listRequests' });
  assert.equal(r.body.incoming.length, 1);
  assert.equal(r.body.incoming[0].username, 'ann');
  assert.equal(r.body.outgoing.length, 0);
  r = await P(ann, { action: 'listRequests' });
  assert.equal(r.body.outgoing[0].username, 'bob');
  assert.equal(r.body.incoming.length, 0);

  // Only the recipient can accept or decline; only the sender can cancel.
  const reqId = (await P(bob, { action: 'listRequests' })).body.incoming[0].id;
  assert.equal((await P(ann, { action: 'acceptRequest', requestId: reqId })).status, 404);
  assert.equal((await P(ann, { action: 'declineRequest', requestId: reqId })).status, 404);
  assert.equal((await P(bob, { action: 'cancelRequest', requestId: reqId })).status, 404);
  assert.equal((await P(cat, { action: 'acceptRequest', requestId: reqId })).status, 404);
  assert.equal((await P(bob, { action: 'acceptRequest', requestId: 'bad' })).status, 400);
  r = await P(bob, { action: 'acceptRequest', requestId: reqId });
  assert.deepEqual(r.body, { accepted: true, username: 'ann' });
  assert.equal((await P(bob, { action: 'listRequests' })).body.incoming.length, 0);
  assert.deepEqual((await P(ann, { action: 'listFriends' })).body.friends.map(f => f.username), ['bob']);
  assert.deepEqual((await P(bob, { action: 'listFriends' })).body.friends.map(f => f.username), ['ann']);
  assert.equal((await P(ann, { action: 'sendRequest', who: 'bob' })).status, 409, 'already friends');
  assert.equal((await P(bob, { action: 'sendRequest', who: 'ann@example.com' })).status, 409);

  // Asking someone who already asked you makes you friends.
  await P(cat, { action: 'sendRequest', who: 'ann' });
  r = await P(ann, { action: 'sendRequest', who: 'cat' });
  assert.deepEqual(r.body, { status: 'friends', username: 'cat' });
  assert.equal((await P(cat, { action: 'listRequests' })).body.outgoing.length, 0);
  assert.deepEqual((await P(ann, { action: 'listFriends' })).body.friends.map(f => f.username), ['bob', 'cat']);

  // Declining and cancelling.
  const dan = await addUser(pool, 'dan');
  await P(dan, { action: 'sendRequest', who: 'bob' });
  const danReq = (await P(bob, { action: 'listRequests' })).body.incoming[0].id;
  assert.equal((await P(bob, { action: 'declineRequest', requestId: danReq })).status, 200);
  assert.equal((await P(bob, { action: 'listRequests' })).body.incoming.length, 0);
  await P(dan, { action: 'sendRequest', who: 'bob' }); // can ask again after a decline
  const again = (await P(dan, { action: 'listRequests' })).body.outgoing[0].id;
  assert.equal((await P(dan, { action: 'cancelRequest', requestId: again })).status, 200);
  assert.equal((await P(dan, { action: 'listRequests' })).body.outgoing.length, 0);

  // Messages need a friendship.
  assert.equal((await M(ann, { action: 'send', username: 'dan', body: 'hi' })).status, 404);
  assert.equal((await M(ann, { action: 'getThread', username: 'dan' })).status, 404);
  assert.equal((await M(ann, { action: 'send', username: 'bob', body: '   ' })).status, 400);
  assert.equal((await M(ann, { action: 'send', username: 'bob', body: 'x'.repeat(4001) })).status, 400);
  assert.equal((await M(ann, { action: 'send', username: 'ann', body: 'me' })).status, 404);
  const first = (await M(ann, { action: 'send', username: 'bob', body: '  Hello Bob  ' })).body.message;
  assert.equal(first.body, 'Hello Bob');
  assert.equal(first.mine, true);
  assert.match(first.at, /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{6}Z$/);
  await M(ann, { action: 'send', username: 'bob', body: 'Second' });
  await M(ann, { action: 'send', username: 'cat', body: 'Hi Cat' });

  // Unread counts and the conversation list.
  assert.equal((await M(bob, { action: 'unreadCount' })).body.unread, 2);
  assert.equal((await M(ann, { action: 'unreadCount' })).body.unread, 0);
  let list = (await M(bob, { action: 'listConversations' })).body.conversations;
  assert.deepEqual(list.map(c => [c.username, c.preview, c.mine, c.unread]), [['ann', 'Second', false, 2]]);
  list = (await M(ann, { action: 'listConversations' })).body.conversations;
  assert.deepEqual(list.map(c => [c.username, c.mine, c.unread]), [['cat', true, 0], ['bob', true, 0]]);

  // Reading a thread marks it read, oldest first.
  let t = (await M(bob, { action: 'getThread', username: 'ann' })).body;
  assert.deepEqual(t.messages.map(m => [m.body, m.mine]), [['Hello Bob', false], ['Second', false]]);
  assert.equal(t.more, false);
  assert.equal(t.friend.username, 'ann');
  assert.equal((await M(bob, { action: 'unreadCount' })).body.unread, 0);
  // Ann now sees her messages as read.
  t = (await M(ann, { action: 'getThread', username: 'bob' })).body;
  assert.deepEqual(t.messages.map(m => m.read), [true, true]);

  // Replies, and asking only for what is new.
  const since = t.messages.at(-1).at;
  await M(bob, { action: 'send', username: 'ann', body: 'Reply' });
  t = (await M(ann, { action: 'getThread', username: 'bob', since })).body;
  assert.deepEqual(t.messages.map(m => [m.body, m.mine]), [['Reply', false]]);
  assert.deepEqual((await M(ann, { action: 'getThread', username: 'bob', since: t.messages[0].at })).body.messages, []);
  assert.equal((await M(ann, { action: 'getThread', username: 'bob', since: 'yesterday' })).status, 400);

  // Paging back through a long conversation.
  for (let i = 0; i < 60; i++) await M(ann, { action: 'send', username: 'cat', body: `m${i}` });
  t = (await M(ann, { action: 'getThread', username: 'cat' })).body;
  assert.equal(t.messages.length, 50);
  assert.equal(t.more, true);
  assert.equal(t.messages.at(-1).body, 'm59');
  const older = (await M(ann, { action: 'getThread', username: 'cat', before: t.messages[0].at })).body;
  assert.equal(older.messages.length, 11);
  assert.equal(older.more, false);
  assert.equal(older.messages[0].body, 'Hi Cat');

  // Un-friending closes the conversation (the history stays for if they re-friend).
  assert.equal((await P(ann, { action: 'removeFriend', username: 'dan' })).status, 404);
  assert.equal((await P(ann, { action: 'removeFriend', username: 'bob' })).status, 200);
  assert.deepEqual((await P(ann, { action: 'listFriends' })).body.friends.map(f => f.username), ['cat']);
  assert.equal((await M(ann, { action: 'send', username: 'bob', body: 'still there?' })).status, 404);
  assert.deepEqual((await M(ann, { action: 'listConversations' })).body.conversations.map(c => c.username), ['cat']);
  assert.equal((await M(bob, { action: 'unreadCount' })).body.unread, 0);
  await P(ann, { action: 'sendRequest', who: 'bob' });
  await P(bob, { action: 'acceptRequest', requestId: (await P(bob, { action: 'listRequests' })).body.incoming[0].id });
  assert.equal((await M(ann, { action: 'getThread', username: 'bob' })).body.messages.length, 3);

  // Deleting an account removes their requests, friendships and messages.
  await pool.query('DELETE FROM public.users WHERE id=$1', [cat]);
  assert.deepEqual((await P(ann, { action: 'listFriends' })).body.friends.map(f => f.username), ['bob']);
  assert.equal((await pool.query('SELECT count(*)::int AS n FROM public.messages WHERE sender_id=$1 OR recipient_id=$1', [cat])).rows[0].n, 0);
});
