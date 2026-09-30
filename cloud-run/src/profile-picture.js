import sharp from 'sharp';

export function profilePictureHandler(pool) {
  return async (request, reply) => {
    const { image } = request.body || {};
    let picture = null;
    if (image !== null) {
      if (typeof image !== 'string' || image.length > 6990508 ||
          (image.length % 4 !== 0 || !/^[A-Za-z0-9+/]*={0,2}$/.test(image))) {
        return reply.code(400).send({ error: 'Choose a JPG, PNG or WebP image up to 5 MB.' });
      }
      const bytes = Buffer.from(image, 'base64');
      if (!bytes.length || bytes.length > 5 * 1024 * 1024) {
        return reply.code(400).send({ error: 'Choose an image up to 5 MB.' });
      }
      try {
        const input = sharp(bytes, { limitInputPixels: 40000000, animated: false });
        const metadata = await input.metadata();
        if (!['jpeg', 'png', 'webp'].includes(metadata.format)) throw new Error('Unsupported image');
        const thumbnail = await input.rotate().resize(256, 256, { fit: 'cover' })
          .flatten({ background: '#ffffff' }).jpeg({ quality: 85 }).toBuffer();
        picture = `data:image/jpeg;base64,${thumbnail.toString('base64')}`;
      } catch {
        return reply.code(400).send({ error: 'Unable to read this image. Choose a JPG, PNG or WebP image under 40 megapixels.' });
      }
    }
    await pool.query('UPDATE public.users SET profile_picture = $1 WHERE id = $2', [picture, request.userProfile.id]);
    return { profilePicture: picture };
  };
}
