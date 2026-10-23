import { PGlite } from '@electric-sql/pglite';
import { readdir, readFile } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';

// A real (in-process) Postgres with every migration applied, so SQL is tested
// for real without a database server.
const init = new URL('../../../postgres/init/', import.meta.url);

export async function makeDb(upTo = 99) {
  const pg = new PGlite();
  const files = (await readdir(init)).filter(f => /^\d\d-.*\.sql$/.test(f)).sort();
  for (const f of files) {
    if (Number(f.slice(0, 2)) > upTo) continue;
    try {
      await pg.exec(await readFile(new URL(f, init), 'utf8'));
    } catch (e) {
      throw new Error(`${f}: ${e.message}`);
    }
  }
  const client = {
    query: (sql, params) => pg.query(sql, params),
    release() {},
  };
  return { pg, pool: { connect: async () => client, query: (s, p) => pg.query(s, p) } };
}

// Applies the migrations numbered after [from] (to test one on existing data).
export async function migrateFrom(pg, from) {
  const files = (await readdir(init)).filter(f => /^\d\d-.*\.sql$/.test(f)).sort();
  for (const f of files) {
    if (Number(f.slice(0, 2)) > from) await pg.exec(await readFile(new URL(f, init), 'utf8'));
  }
}

export async function addUser(pool, username, email) {
  const { rows } = await pool.query(
    'INSERT INTO public.users(firebase_uid,email,username) VALUES($1,$2,$3) RETURNING id',
    [randomUUID(), email ?? `${username}@example.com`, username],
  );
  return rows[0].id;
}

export async function call(handler, body, owner) {
  const reply = { code(s) { this.status = s; return this; }, send(p) { this.payload = p; return p; } };
  const result = await handler({ body, userProfile: { id: owner }, log: { error() {} } }, reply);
  return { status: reply.status ?? 200, body: reply.payload ?? result };
}
