BEGIN;
CREATE TABLE IF NOT EXISTS public.calendar_tags (
 owner_id UUID PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
 tags JSONB NOT NULL DEFAULT '[]'::jsonb CHECK(jsonb_typeof(tags)='array')
);
ALTER TABLE public.calendar_events ADD COLUMN IF NOT EXISTS tag_id TEXT;
COMMIT;
