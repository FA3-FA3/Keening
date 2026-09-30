BEGIN;
CREATE TABLE IF NOT EXISTS public.board_workplaces (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  name TEXT NOT NULL CHECK (length(trim(name)) BETWEEN 1 AND 100),
  board JSONB NOT NULL DEFAULT '{"columns":[],"tasks":[],"tags":[]}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (jsonb_typeof(board) = 'object')
);
CREATE INDEX IF NOT EXISTS board_workplaces_owner ON public.board_workplaces(owner_id);
COMMIT;
