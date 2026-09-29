import Fastify from 'fastify';
import cors from '@fastify/cors';
import { ensureUserProfile } from './database.js';

export async function buildApp({ pool, verifyIdToken, origins, logger = true }) {
  const app = Fastify({
    logger: logger === false ? false : {
      redact: ['req.headers.authorization', 'req.headers.cookie'],
    },
    bodyLimit: 16384,
    requestTimeout: 15000,
  });
  await app.register(cors, {
    origin: origins,
    methods: ['GET'],
    allowedHeaders: ['Authorization', 'Content-Type'],
  });
  app.decorateRequest('userProfile', null);
  app.decorateRequest('authToken', null);
  app.addHook('onClose', async () => pool.end());

  // Avoid logging exception messages containing tokens, credentials or SQL data.
  app.setErrorHandler((error, request, reply) => {
    request.log.error({ errorCode: error.code || 'INTERNAL_ERROR' }, 'Request failed');
    const status = error.statusCode >= 400 && error.statusCode < 500 ? error.statusCode : 500;
    reply.code(status).send({ error: status === 500 ? 'Internal server error' : 'Invalid request' });
  });

  app.get('/health', async () => ({ status: 'ok' }));

  async function authenticate(request, reply) {
    reply.header('Cache-Control', 'no-store');
    const match = /^Bearer ([^\s]+)$/i.exec(request.headers.authorization || '');
    if (!match) {
      return reply.code(401).header('WWW-Authenticate', 'Bearer').send({ error: 'Authentication required' });
    }
    let token;
    try {
      token = await verifyIdToken(match[1]);
    } catch (error) {
      const invalid = new Set([
        'auth/argument-error', 'auth/invalid-argument', 'auth/invalid-id-token',
        'auth/id-token-expired', 'auth/id-token-revoked', 'auth/user-disabled',
        'auth/user-not-found',
      ]);
      if (invalid.has(error.code)) {
        return reply.code(401).header('WWW-Authenticate', 'Bearer').send({ error: 'Invalid or expired token' });
      }
      request.log.error({ errorCode: error.code || 'AUTH_UNAVAILABLE' }, 'Token verification unavailable');
      return reply.code(503).send({ error: 'Authentication service unavailable' });
    }
    if (typeof token?.uid !== 'string' || !token.uid) {
      return reply.code(401).send({ error: 'Invalid token' });
    }
    try {
      request.userProfile = await ensureUserProfile(pool, token);
      request.authToken = token;
    } catch (error) {
      request.log.error({ errorCode: error.code || 'DATABASE_UNAVAILABLE' }, 'Profile provisioning failed');
      return reply.code(503).send({ error: 'Database unavailable' });
    }
  }

  app.get('/whoami', { preHandler: authenticate }, async request => ({
    firebaseUid: request.userProfile.firebase_uid,
    email: request.userProfile.email,
    anonymous: request.authToken.firebase?.sign_in_provider === 'anonymous',
  }));
  return app;
}
