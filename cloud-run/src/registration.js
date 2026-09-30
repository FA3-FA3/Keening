import { createHash, timingSafeEqual } from 'node:crypto';

export function registrationHandler({ pool, auth, registrationCode }) {
  return async (request, reply) => {
    reply.header('Cache-Control', 'no-store');
    const { email, username, password, code } = request.body || {};
    if (!registrationCode || !auth) return reply.code(503).send({ error: 'Registration is unavailable.' });
    const digest = value => createHash('sha256').update(value).digest();
    if (typeof code !== 'string' || !timingSafeEqual(digest(code), digest(registrationCode))) {
      return reply.code(403).send({ error: 'Invalid registration code.' });
    }
    if (typeof email !== 'string' || email.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email.trim()) ||
        typeof username !== 'string' || !/^[A-Za-z0-9_]{3,30}$/.test(username) ||
        typeof password !== 'string' || password.length < 8 || password.length > 128) {
      return reply.code(400).send({ error: 'Enter a valid email, a username of 3–30 letters, numbers or underscores, and a password of 8–128 characters.' });
    }
    let user;
    let profileCreated = false;
    try {
      user = await auth.createUser({ email: email.trim(), password, displayName: username, disabled: true });
      await pool.query('INSERT INTO public.users (firebase_uid, email, username) VALUES ($1, $2, $3)', [user.uid, user.email, username]);
      profileCreated = true;
      await auth.updateUser(user.uid, { disabled: false });
      return reply.code(201).send({ created: true });
    } catch (error) {
      // Keep incomplete accounts disabled; compensate without logging credentials.
      if (user) {
        try {
          await auth.deleteUser(user.uid);
          if (profileCreated) await pool.query('DELETE FROM public.users WHERE firebase_uid = $1', [user.uid]);
        } catch {
          request.log.error({ firebaseUid: user.uid }, 'Registration cleanup requires attention');
        }
      }
      if (error.code === 'auth/email-already-exists') return reply.code(409).send({ error: 'An account with this email already exists.' });
      if (error.code === '23505') return reply.code(409).send({ error: 'This username is already taken.' });
      if (['auth/invalid-email', 'auth/invalid-password', 'auth/password-does-not-meet-requirements'].includes(error.code)) return reply.code(400).send({ error: 'Check your email and password requirements.' });
      request.log.error({ errorCode: error.code || 'REGISTRATION_FAILED' }, 'Registration failed');
      return reply.code(503).send({ error: 'Registration is unavailable. Please try again later.' });
    }
  };
}
