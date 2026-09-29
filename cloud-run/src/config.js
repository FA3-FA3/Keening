export function readConfig(env = process.env) {
  if (!env.DATABASE_URL) throw new Error('DATABASE_URL is required');
  const database = new URL(env.DATABASE_URL);
  if (!['postgres:', 'postgresql:'].includes(database.protocol)) {
    throw new Error('DATABASE_URL must be a Postgres URI');
  }
  const emulatorHost = env.FIREBASE_AUTH_EMULATOR_HOST;
  const projectId = env.FIREBASE_PROJECT_ID || 'keening-ece74';
  const localDatabase = ['localhost', '127.0.0.1', '[::1]'].includes(database.hostname);
  if (emulatorHost) {
    if (env.K_SERVICE || env.NODE_ENV === 'production') {
      throw new Error('Auth Emulator is forbidden in production');
    }
    if (!projectId.startsWith('demo-') || !localDatabase) {
      throw new Error('Auth Emulator requires a demo project and a local database');
    }
    if (!/^(localhost|127\.0\.0\.1):\d+$/.test(emulatorHost)) {
      throw new Error('Auth Emulator must run on localhost');
    }
  } else if (projectId.startsWith('demo-')) {
    throw new Error('Demo project requires FIREBASE_AUTH_EMULATOR_HOST');
  }
  if (!localDatabase && !['require', 'verify-ca', 'verify-full'].includes(database.searchParams.get('sslmode'))) {
    throw new Error('Remote Postgres requires an SSL-enabled connection URI');
  }
  const origins = (env.CORS_ORIGINS || '').split(',').map(value => value.trim()).filter(Boolean);
  if (!origins.length && (env.K_SERVICE || env.NODE_ENV === 'production')) {
    throw new Error('CORS_ORIGINS is required in production');
  }
  for (const origin of origins) {
    const parsed = new URL(origin);
    if (!['http:', 'https:'].includes(parsed.protocol) || parsed.origin !== origin) {
      throw new Error('CORS_ORIGINS must contain exact HTTP(S) origins');
    }
  }
  const port = Number(env.PORT || 8080);
  if (!Number.isInteger(port) || port < 1 || port > 65535) throw new Error('Invalid PORT');
  return {
    databaseUrl: env.DATABASE_URL,
    projectId,
    emulatorHost,
    port,
    host: env.K_SERVICE ? '0.0.0.0' : (env.HOST || '127.0.0.1'),
    origins: origins.length ? origins : ['http://localhost:3000', 'http://127.0.0.1:3000'],
  };
}
