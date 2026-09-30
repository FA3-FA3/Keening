export function usernameHandler(pool) {
  return async (request, reply) => {
    const username = request.body?.username;
    if (typeof username !== 'string' || !/^[A-Za-z0-9_]{3,30}$/.test(username)) {
      return reply.code(400).send({ error: 'Use 3-30 letters, numbers or underscores.' });
    }
    try {
      const { rows } = await pool.query(
        'UPDATE public.users SET username = $1 WHERE id = $2 RETURNING username',
        [username, request.userProfile.id],
      );
      return { username: rows[0].username };
    } catch (error) {
      if (error.code === '23505') return reply.code(409).send({ error: 'This username is already taken.' });
      throw error;
    }
  };
}
