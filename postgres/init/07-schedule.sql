BEGIN;
CREATE TABLE IF NOT EXISTS public.schedules (
  owner_id UUID PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
  data JSONB NOT NULL DEFAULT '{"groups":[],"rows":[],"blocks":[]}'::jsonb,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMIT;
