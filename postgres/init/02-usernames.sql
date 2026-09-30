BEGIN;
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS username TEXT;
CREATE UNIQUE INDEX IF NOT EXISTS users_username_unique ON public.users (lower(username));
COMMIT;
