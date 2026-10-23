// Messages: private conversations between friends. A conversation is simply
// the messages between two people; you can only write to a friend. People are
// named by username, never by internal id.
import { friendNamed } from './people.js';

const fail = (message, statusCode = 400) => { throw Object.assign(new Error(message), { publicMessage: message, statusCode }); };

export const LIMITS = { body: 4000, page: 50, conversations: 100, preview: 200 };

export function messageBody(value) {
  if (typeof value !== 'string' || !value.trim()) fail('Write something to send.');
  if (value.trim().length > LIMITS.body) fail(`Messages can be up to ${LIMITS.body} characters.`);
  return value.trim();
}

// A time as the server writes it (UTC, with microseconds), used to ask for the
// messages before or after one.
export function messageTime(value) {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,6})?Z$/.test(value) || Number.isNaN(Date.parse(value))) fail('Invalid time.');
  return value;
}

const AT = `to_char(m.created_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"')`;

export function messagesHandler(pool) {
  return async (request, reply) => {
    const b = request.body || {}, owner = request.userProfile.id;
    let db;
    try {
      const actions = ['listConversations', 'getThread', 'send', 'unreadCount'];
      if (!actions.includes(b.action)) fail('Unknown messages action.');
      db = await pool.connect();
      await db.query('BEGIN');
      let result;
      if (b.action === 'listConversations') {
        const rows = (await db.query(
          `WITH mine AS (
             SELECT CASE WHEN sender_id=$1::uuid THEN recipient_id ELSE sender_id END AS other_id,
                    id,body,created_at,sender_id,recipient_id,read_at
               FROM public.messages WHERE sender_id=$1::uuid OR recipient_id=$1::uuid),
           last AS (
             SELECT DISTINCT ON (other_id) other_id,body,created_at,sender_id FROM mine ORDER BY other_id,created_at DESC,id DESC),
           unread AS (
             SELECT other_id,count(*)::int AS n FROM mine WHERE recipient_id=$1::uuid AND read_at IS NULL GROUP BY other_id)
           SELECT u.username,u.profile_picture AS "profilePicture",left(l.body,${LIMITS.preview}) AS preview,
                  to_char(l.created_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"') AS at,
                  (l.sender_id=$1::uuid) AS mine,COALESCE(un.n,0) AS unread
             FROM last l
             JOIN public.users u ON u.id=l.other_id
             JOIN public.friendships f ON (f.user_a=l.other_id AND f.user_b=$1::uuid) OR (f.user_a=$1::uuid AND f.user_b=l.other_id)
             LEFT JOIN unread un ON un.other_id=l.other_id
            WHERE u.username IS NOT NULL
            ORDER BY l.created_at DESC LIMIT ${LIMITS.conversations}`, [owner])).rows;
        result = { conversations: rows };
      } else if (b.action === 'unreadCount') {
        const row = (await db.query(
          `SELECT count(*)::int AS unread FROM public.messages m
            WHERE m.recipient_id=$1::uuid AND m.read_at IS NULL
              AND EXISTS (SELECT 1 FROM public.friendships f
                           WHERE (f.user_a=m.sender_id AND f.user_b=$1::uuid) OR (f.user_a=$1::uuid AND f.user_b=m.sender_id))`, [owner])).rows[0];
        result = { unread: row?.unread ?? 0 };
      } else if (b.action === 'getThread') {
        const friend = await friendNamed(db, owner, b.username);
        const params = [owner, friend.id];
        let where = '';
        if (b.before !== undefined) { params.push(messageTime(b.before)); where = ` AND m.created_at < $${params.length}::timestamptz`; }
        if (b.since !== undefined) { params.push(messageTime(b.since)); where += ` AND m.created_at > $${params.length}::timestamptz`; }
        // The newest page (or what is new since [since], or the page before [before]), oldest first.
        const rows = (await db.query(
          `SELECT m.id,(m.sender_id=$1::uuid) AS mine,m.body,${AT} AS at,(m.read_at IS NOT NULL) AS read
             FROM public.messages m
            WHERE ((m.sender_id=$1::uuid AND m.recipient_id=$2::uuid) OR (m.sender_id=$2::uuid AND m.recipient_id=$1::uuid))${where}
            ORDER BY m.created_at DESC,m.id DESC LIMIT ${LIMITS.page + 1}`, params)).rows;
        const more = rows.length > LIMITS.page;
        const messages = rows.slice(0, LIMITS.page).reverse();
        if (b.before === undefined) {
          await db.query('UPDATE public.messages SET read_at=now() WHERE sender_id=$2::uuid AND recipient_id=$1::uuid AND read_at IS NULL', [owner, friend.id]);
        }
        result = { friend: { username: friend.username, profilePicture: friend.profile_picture ?? null }, messages, more };
      } else {
        const friend = await friendNamed(db, owner, b.username);
        const body = messageBody(b.body);
        const message = (await db.query(
          `INSERT INTO public.messages(sender_id,recipient_id,body) VALUES($1,$2,$3)
           RETURNING id,true AS mine,body,to_char(created_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"') AS at,false AS read`, [owner, friend.id, body])).rows[0];
        result = { message };
      }
      await db.query('COMMIT');
      return result;
    } catch (error) {
      if (db) await db.query('ROLLBACK').catch(() => {});
      if (error.publicMessage) return reply.code(error.statusCode).send({ error: error.publicMessage });
      request.log.error({ errorCode: error.code || 'MESSAGES_FAILED' }, 'Messages request failed');
      return reply.code(503).send({ error: 'Messages are unavailable. Please try again.' });
    } finally {
      db?.release();
    }
  };
}
