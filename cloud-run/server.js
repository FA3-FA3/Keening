import dotenv from 'dotenv';
import { fileURLToPath } from 'node:url';
import { applicationDefault, initializeApp, deleteApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { readConfig } from './src/config.js';
import { createPool } from './src/database.js';
import { buildApp } from './src/app.js';

dotenv.config({ path: fileURLToPath(new URL('.env', import.meta.url)), quiet: true });

let pool;
let firebase;
try {
  const config = readConfig();
  firebase = initializeApp({
    projectId: config.projectId,
    ...(config.emulatorHost ? {} : { credential: applicationDefault() }),
  });
  pool = createPool(config.databaseUrl);
  const app = await buildApp({
    pool,
    auth: getAuth(firebase),
    registrationCode: process.env.REGISTRATION_CODE,
    verifyIdToken: token => getAuth(firebase).verifyIdToken(token, true),
    origins: config.origins,
  });
  pool.on('error', () => app.log.error('Idle database connection failed'));
  app.addHook('onClose', async () => deleteApp(firebase));
  for (const signal of ['SIGINT', 'SIGTERM']) {
    process.once(signal, async () => {
      await app.close();
    });
  }
  await app.listen({ port: config.port, host: config.host });
} catch (error) {
  // Configuration errors are actionable; runtime errors may contain secrets.
  console.error('Keening API failed to start.', pool ? (error.code || 'STARTUP_ERROR') : 'Check environment configuration.');
  if (pool) await pool.end();
  if (firebase) await deleteApp(firebase);
  process.exitCode = 1;
}
