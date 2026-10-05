// Attachments: files on Board tasks, Schedule sessions and Calendar events.
const uuid = value => typeof value === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);
const fail = (message, statusCode = 400) => { throw Object.assign(new Error(message), { publicMessage: message, statusCode }); };

export const TYPES = ['task', 'session', 'event'];
export const LIMITS = {
  fileBytes: 5 * 1024 * 1024,
  perItem: 10,
  perUserBytes: 100 * 1024 * 1024,
  name: 200,
};

function fileName(value) {
  // Keep just a file name: no paths or control characters.
  const clean = typeof value === 'string' ? value.replace(/[\\/]+/g, '_').replace(/[\u0000-\u001f\u007f]/g, '').trim() : '';
  if (!clean || clean.length > LIMITS.name) fail(`Enter a file name of 1–${LIMITS.name} characters.`);
  return clean;
}
function mimeType(value) {
  return typeof value === 'string' && /^[a-z0-9][a-z0-9!#$&^_.+-]{0,60}\/[a-z0-9][a-z0-9!#$&^_.+-]{0,60}$/i.test(value)
    ? value.toLowerCase() : 'application/octet-stream';
}
function fileBytes(value) {
  if (typeof value !== 'string' || !/^[A-Za-z0-9+/]*={0,2}$/.test(value)) fail('Invalid file.');
  const data = Buffer.from(value, 'base64');
  if (data.length > LIMITS.fileBytes) fail(`Files can be up to ${LIMITS.fileBytes / 1024 / 1024} MB.`);
  return data;
}

// Does the item exist and belong to this owner? Locks nothing: attachments are
// independent of the item's own document.
async function itemExists(db, owner, type, id) {
  if (type === 'task') {
    return (await db.query(`SELECT 1 FROM public.board_workplaces w CROSS JOIN LATERAL jsonb_array_elements(w.board->'tasks') t
      WHERE w.owner_id=$1 AND t->>'id'=$2 LIMIT 1`, [owner, id])).rowCount > 0;
  }
  if (type === 'session') {
    return (await db.query(`SELECT 1 FROM public.schedules s CROSS JOIN LATERAL jsonb_array_elements(s.data->'blocks') b
      WHERE s.owner_id=$1 AND b->>'id'=$2 LIMIT 1`, [owner, id])).rowCount > 0;
  }
  if (!uuid(id)) return false;
  return (await db.query(`SELECT 1 FROM public.calendar_events e JOIN public.calendar_collections c ON c.id=e.calendar_id
    WHERE e.id=$1 AND c.owner_id=$2`, [id, owner])).rowCount > 0;
}

// Remove attachments whose task, session or event has since been deleted.
async function sweep(db, owner) {
  await db.query(`DELETE FROM public.attachments a WHERE a.owner_id=$1 AND (
    (a.item_type='task' AND NOT EXISTS (SELECT 1 FROM public.board_workplaces w CROSS JOIN LATERAL jsonb_array_elements(w.board->'tasks') t
       WHERE w.owner_id=a.owner_id AND t->>'id'=a.item_id))
    OR (a.item_type='session' AND NOT EXISTS (SELECT 1 FROM public.schedules s CROSS JOIN LATERAL jsonb_array_elements(s.data->'blocks') b
       WHERE s.owner_id=a.owner_id AND b->>'id'=a.item_id))
    OR (a.item_type='event' AND NOT EXISTS (SELECT 1 FROM public.calendar_events e JOIN public.calendar_collections c ON c.id=e.calendar_id
       WHERE c.owner_id=a.owner_id AND e.id::text=a.item_id)))`, [owner]);
}

export function attachmentsHandler(pool) {
  return async (request, reply) => {
    const b = request.body || {}, owner = request.userProfile.id;
    let db;
    try {
      if (!['list', 'upload', 'get', 'delete'].includes(b.action)) fail('Unknown attachment action.');
      db = await pool.connect();
      await db.query('BEGIN');
      let result;
      const item = async () => {
        if (!TYPES.includes(b.itemType) || typeof b.itemId !== 'string' || !b.itemId || b.itemId.length > 100) fail('Invalid item.');
        if (!(await itemExists(db, owner, b.itemType, b.itemId))) fail('Save the item before adding attachments.', 404);
      };
      if (b.action === 'list') {
        await item();
        result = { attachments: (await db.query(`SELECT id,name,mime,size,created_at FROM public.attachments
          WHERE owner_id=$1 AND item_type=$2 AND item_id=$3 ORDER BY created_at,id`, [owner, b.itemType, b.itemId])).rows };
      } else if (b.action === 'upload') {
        await item();
        const name = fileName(b.name), mime = mimeType(b.mime), data = fileBytes(b.data);
        if (!data.length) fail('That file is empty.');
        // Serialise uploads per user so the quotas below cannot be raced.
        await db.query('SELECT id FROM public.users WHERE id=$1 FOR UPDATE', [owner]);
        await sweep(db, owner);
        const itemCount = (await db.query('SELECT count(*)::int AS n FROM public.attachments WHERE owner_id=$1 AND item_type=$2 AND item_id=$3', [owner, b.itemType, b.itemId])).rows[0].n;
        if (itemCount >= LIMITS.perItem) fail(`An item can have up to ${LIMITS.perItem} attachments.`);
        const used = Number((await db.query('SELECT COALESCE(sum(size),0) AS bytes FROM public.attachments WHERE owner_id=$1', [owner])).rows[0].bytes);
        if (used + data.length > LIMITS.perUserBytes) fail(`Attachments can use up to ${LIMITS.perUserBytes / 1024 / 1024} MB in total.`);
        result = { attachment: (await db.query(`INSERT INTO public.attachments(owner_id,item_type,item_id,name,mime,size,data)
          VALUES($1,$2,$3,$4,$5,$6,$7) RETURNING id,name,mime,size,created_at`, [owner, b.itemType, b.itemId, name, mime, data.length, data])).rows[0] };
      } else {
        if (!uuid(b.attachmentId)) fail('Invalid attachment.');
        if (b.action === 'get') {
          const row = (await db.query('SELECT id,name,mime,size,data FROM public.attachments WHERE id=$1 AND owner_id=$2', [b.attachmentId, owner])).rows[0];
          if (!row) fail('Attachment not found.', 404);
          result = { id: row.id, name: row.name, mime: row.mime, size: row.size, data: row.data.toString('base64') };
        } else {
          const gone = await db.query('DELETE FROM public.attachments WHERE id=$1 AND owner_id=$2', [b.attachmentId, owner]);
          if (!gone.rowCount) fail('Attachment not found.', 404);
          result = { ok: true };
        }
      }
      await db.query('COMMIT');
      return result;
    } catch (error) {
      if (db) await db.query('ROLLBACK').catch(() => {});
      if (error.publicMessage) return reply.code(error.statusCode).send({ error: error.publicMessage });
      request.log.error({ errorCode: error.code || 'ATTACHMENTS_FAILED' }, 'Attachment request failed');
      return reply.code(503).send({ error: 'Attachments are unavailable. Please try again.' });
    } finally {
      db?.release();
    }
  };
}
