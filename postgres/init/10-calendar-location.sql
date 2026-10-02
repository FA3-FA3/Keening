BEGIN;
ALTER TABLE public.calendar_events ADD COLUMN IF NOT EXISTS location TEXT NOT NULL DEFAULT '' CHECK (length(location)<=500);
COMMIT;
