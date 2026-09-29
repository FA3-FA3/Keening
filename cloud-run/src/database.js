import pg from 'pg';

export function createPool(databaseUrl) {
  return new pg.Pool({
    connectionString: databaseUrl,
    max: 5,
    connectionTimeoutMillis: 10000,
    idleTimeoutMillis: 30000,
    statement_timeout: 10000,
    enableChannelBinding: true,
  });
}

export async function ensureUserProfile(pool, token) {
  // One atomic statement handles simultaneous first requests. Never trust a
  // client-supplied UID/email, and never return this internal ID to the client.
  const { rows } = await pool.query(
    `INSERT INTO public.users (firebase_uid, email)
     VALUES ($1, $2)
     ON CONFLICT (firebase_uid) DO UPDATE SET email = EXCLUDED.email
     RETURNING id, firebase_uid, email`,
    [token.uid, typeof token.email === 'string' ? token.email : null],
  );
  return rows[0];
}
