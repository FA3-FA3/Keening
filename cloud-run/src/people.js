// People: friends, and the requests that make them. A request goes from one
// person to another until it is accepted (then they are friends), declined or
// cancelled. People are found by username or email address; the client never
// sees anyone's internal id, only usernames and the ids of requests.
const uuid = value => typeof value === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);
const fail = (message, statusCode = 400) => { throw Object.assign(new Error(message), { publicMessage: message, statusCode }); };

export const LIMITS = { friends: 500, outgoing: 100 };

// What the person typed to find someone: an email address or a username.
export function lookupKey(value) {
  const text = typeof value === 'string' ? value.trim() : '';
  if (text.includes('@')) {
    if (text.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(text)) fail('Enter a valid email address or a username.');
    return { kind: 'email', value: text };
  }
  if (!/^[A-Za-z0-9_]{3,30}$/.test(text)) fail('Enter a valid email address or a username.');
  return { kind: 'username', value: text };
}

export function usernameOf(value) {
  if (typeof value !== 'string' || !/^[A-Za-z0-9_]{3,30}$/.test(value)) fail('Invalid username.');
  return value;
}

// A friendship is stored once per pair, smaller id first.
export const pair = (a, b) => (a < b ? [a, b] : [b, a]);

export async function areFriends(db, a, b) {
  const [x, y] = pair(a, b);
  return (await db.query('SELECT 1 FROM public.friendships WHERE user_a=$1 AND user_b=$2', [x, y])).rows.length > 0;
}

// The person named [username] if they are a friend of [owner]; otherwise a 404.
export async function friendNamed(db, owner, username) {
  const user = (await db.query('SELECT id,username,profile_picture FROM public.users WHERE lower(username)=lower($1)', [usernameOf(username)])).rows[0];
  if (!user || user.id === owner || !(await areFriends(db, owner, user.id))) fail('That person is not one of your friends.', 404);
  return user;
}

export function peopleHandler(pool) {
  return async (request, reply) => {
    const b = request.body || {}, owner = request.userProfile.id;
    let db;
    try {
      const actions = ['listFriends', 'listRequests', 'sendRequest', 'acceptRequest', 'declineRequest', 'cancelRequest', 'removeFriend'];
      if (!actions.includes(b.action)) fail('Unknown people action.');
      db = await pool.connect();
      await db.query('BEGIN');
      let result;
      if (b.action === 'listFriends') {
        const rows = (await db.query(
          `SELECT u.username,u.profile_picture AS "profilePicture",f.created_at AS since
             FROM public.friendships f JOIN public.users u ON u.id = CASE WHEN f.user_a=$1 THEN f.user_b ELSE f.user_a END
            WHERE (f.user_a=$1 OR f.user_b=$1) AND u.username IS NOT NULL
            ORDER BY lower(u.username),u.id LIMIT ${LIMITS.friends}`, [owner])).rows;
        result = { friends: rows };
      } else if (b.action === 'listRequests') {
        const incoming = (await db.query(
          `SELECT r.id,u.username,u.profile_picture AS "profilePicture",r.created_at AS at
             FROM public.friend_requests r JOIN public.users u ON u.id=r.sender_id
            WHERE r.recipient_id=$1 AND u.username IS NOT NULL ORDER BY r.created_at DESC,r.id LIMIT 200`, [owner])).rows;
        const outgoing = (await db.query(
          `SELECT r.id,u.username,u.profile_picture AS "profilePicture",r.created_at AS at
             FROM public.friend_requests r JOIN public.users u ON u.id=r.recipient_id
            WHERE r.sender_id=$1 AND u.username IS NOT NULL ORDER BY r.created_at DESC,r.id LIMIT ${LIMITS.outgoing}`, [owner])).rows;
        result = { incoming, outgoing };
      } else if (b.action === 'sendRequest') {
        const key = lookupKey(b.who);
        const target = (await db.query(
          key.kind === 'email'
            ? 'SELECT id,username FROM public.users WHERE lower(email)=lower($1) ORDER BY created_at LIMIT 1'
            : 'SELECT id,username FROM public.users WHERE lower(username)=lower($1) LIMIT 1', [key.value])).rows[0];
        if (!target || !target.username) fail('No one with that username or email was found.', 404);
        if (target.id === owner) fail('You cannot add yourself.');
        // Both people are locked (in a fixed order) so two requests at once cannot cross.
        await db.query('SELECT id FROM public.users WHERE id=ANY($1::uuid[]) ORDER BY id FOR UPDATE', [[owner, target.id]]);
        if (await areFriends(db, owner, target.id)) fail('You are already friends.', 409);
        const theirs = (await db.query('SELECT id FROM public.friend_requests WHERE sender_id=$1 AND recipient_id=$2 FOR UPDATE', [target.id, owner])).rows[0];
        if (theirs) {
          // They already asked you: asking back makes you friends.
          const [x, y] = pair(owner, target.id);
          await db.query('DELETE FROM public.friend_requests WHERE id=$1', [theirs.id]);
          await db.query('INSERT INTO public.friendships(user_a,user_b) VALUES($1,$2) ON CONFLICT DO NOTHING', [x, y]);
          result = { status: 'friends', username: target.username };
        } else {
          if ((await db.query('SELECT 1 FROM public.friend_requests WHERE sender_id=$1 AND recipient_id=$2', [owner, target.id])).rows.length) {
            fail('You have already sent them a request.', 409);
          }
          const counts = (await db.query(
            `SELECT (SELECT count(*)::int FROM public.friend_requests WHERE sender_id=$1) AS outgoing,
                    (SELECT count(*)::int FROM public.friendships WHERE user_a=$1 OR user_b=$1) AS friends`, [owner])).rows[0];
          if (counts.outgoing >= LIMITS.outgoing) fail(`You can have up to ${LIMITS.outgoing} requests waiting.`);
          if (counts.friends >= LIMITS.friends) fail(`You can have up to ${LIMITS.friends} friends.`);
          await db.query('INSERT INTO public.friend_requests(sender_id,recipient_id) VALUES($1,$2)', [owner, target.id]);
          result = { status: 'sent', username: target.username };
        }
      } else if (b.action === 'acceptRequest') {
        if (!uuid(b.requestId)) fail('Invalid request.');
        const req = (await db.query('SELECT id,sender_id FROM public.friend_requests WHERE id=$1 AND recipient_id=$2 FOR UPDATE', [b.requestId, owner])).rows[0];
        if (!req) fail('Request not found.', 404);
        const friends = (await db.query('SELECT count(*)::int AS n FROM public.friendships WHERE user_a=$1 OR user_b=$1', [owner])).rows[0].n;
        if (friends >= LIMITS.friends) fail(`You can have up to ${LIMITS.friends} friends.`);
        const [x, y] = pair(owner, req.sender_id);
        await db.query('INSERT INTO public.friendships(user_a,user_b) VALUES($1,$2) ON CONFLICT DO NOTHING', [x, y]);
        // Any request the other way round is now pointless.
        await db.query('DELETE FROM public.friend_requests WHERE (sender_id=$1 AND recipient_id=$2) OR (sender_id=$2 AND recipient_id=$1)', [req.sender_id, owner]);
        const who = (await db.query('SELECT username FROM public.users WHERE id=$1', [req.sender_id])).rows[0];
        result = { accepted: true, username: who?.username ?? null };
      } else if (b.action === 'declineRequest' || b.action === 'cancelRequest') {
        if (!uuid(b.requestId)) fail('Invalid request.');
        // Only the person it was sent to can decline it; only the sender can cancel it.
        const mine = b.action === 'declineRequest' ? 'recipient_id' : 'sender_id';
        const gone = await db.query(`DELETE FROM public.friend_requests WHERE id=$1 AND ${mine}=$2 RETURNING id`, [b.requestId, owner]);
        if (!gone.rows.length) fail('Request not found.', 404);
        result = { removed: true };
      } else {
        const user = (await db.query('SELECT id FROM public.users WHERE lower(username)=lower($1)', [usernameOf(b.username)])).rows[0];
        if (!user || user.id === owner) fail('That person is not one of your friends.', 404);
        const [x, y] = pair(owner, user.id);
        const gone = await db.query('DELETE FROM public.friendships WHERE user_a=$1 AND user_b=$2 RETURNING user_a', [x, y]);
        if (!gone.rows.length) fail('That person is not one of your friends.', 404);
        result = { removed: true };
      }
      await db.query('COMMIT');
      return result;
    } catch (error) {
      if (db) await db.query('ROLLBACK').catch(() => {});
      if (error.publicMessage) return reply.code(error.statusCode).send({ error: error.publicMessage });
      request.log.error({ errorCode: error.code || 'PEOPLE_FAILED' }, 'People request failed');
      return reply.code(503).send({ error: 'People are unavailable. Please try again.' });
    } finally {
      db?.release();
    }
  };
}
