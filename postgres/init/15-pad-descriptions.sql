BEGIN;
-- Pads get an optional description, shown when a pad is picked from the grid.
ALTER TABLE public.pads ADD COLUMN IF NOT EXISTS description TEXT NOT NULL DEFAULT '';
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='pads_description_length') THEN
    ALTER TABLE public.pads ADD CONSTRAINT pads_description_length CHECK (length(description) <= 1000);
  END IF;
END $$;
COMMIT;
