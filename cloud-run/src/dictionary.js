// The words a person has added to their spelling dictionary, kept with their
// account. The app sends the words it has added and removed since it last
// spoke to the server, and gets back the whole list.
const fail = (message, statusCode = 400) => { throw Object.assign(new Error(message), { publicMessage: message, statusCode }); };

export const DICTIONARY_LIMIT = 5000;

// One word: letters (any case), with at most one apostrophe in the middle.
export function dictionaryWord(value) {
  const word = typeof value === 'string' ? value.trim().toLowerCase().replace(/’/g, "'") : '';
  if (!/^\p{L}+('\p{L}+)?$/u.test(word) || word.length > 60) fail('Enter one word, with letters only.');
  return word;
}

const words = (value, label) => {
  if (value === undefined) return [];
  if (!Array.isArray(value) || value.length > 1000) fail(`Invalid ${label}.`);
  return [...new Set(value.map(dictionaryWord))];
};

export function dictionaryHandler(pool) {
  return async (request, reply) => {
    const b = request.body || {}, owner = request.userProfile.id;
    let db;
    try {
      if (!['list', 'sync'].includes(b.action)) fail('Unknown dictionary action.');
      const add = b.action === 'sync' ? words(b.add, 'words to add') : [];
      const remove = b.action === 'sync' ? words(b.remove, 'words to remove') : [];
      db = await pool.connect();
      await db.query('BEGIN');
      if (add.length || remove.length) {
        await db.query('SELECT id FROM public.users WHERE id=$1 FOR UPDATE', [owner]);
        if (remove.length) await db.query('DELETE FROM public.user_dictionary WHERE owner_id=$1 AND word=ANY($2::text[])', [owner, remove]);
        if (add.length) {
          await db.query('INSERT INTO public.user_dictionary(owner_id,word) SELECT $1,w FROM unnest($2::text[]) AS w ON CONFLICT DO NOTHING', [owner, add]);
          const now = (await db.query('SELECT count(*)::int AS n FROM public.user_dictionary WHERE owner_id=$1', [owner])).rows[0].n;
          if (now > DICTIONARY_LIMIT) fail(`Your dictionary can hold up to ${DICTIONARY_LIMIT} words.`);
        }
      }
      const result = { words: (await db.query('SELECT word FROM public.user_dictionary WHERE owner_id=$1 ORDER BY word', [owner])).rows.map(r => r.word) };
      await db.query('COMMIT');
      return result;
    } catch (error) {
      if (db) await db.query('ROLLBACK').catch(() => {});
      if (error.publicMessage) return reply.code(error.statusCode).send({ error: error.publicMessage });
      request.log.error({ errorCode: error.code || 'DICTIONARY_FAILED' }, 'Dictionary request failed');
      return reply.code(503).send({ error: 'Your dictionary is unavailable. Please try again.' });
    } finally {
      db?.release();
    }
  };
}
