BEGIN;
-- Documents: the old "pads" become documents of a type ('pad' = Dynamic Pad, or
-- 'notepad' = plain text) that can live in folders.
CREATE TABLE IF NOT EXISTS public.pad_folders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  parent_id UUID REFERENCES public.pad_folders(id) ON DELETE CASCADE,
  name TEXT NOT NULL CHECK (length(trim(name)) BETWEEN 1 AND 100),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS pad_folders_owner ON public.pad_folders(owner_id);
ALTER TABLE public.pads ADD COLUMN IF NOT EXISTS kind TEXT NOT NULL DEFAULT 'pad';
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='pads_kind') THEN
    ALTER TABLE public.pads ADD CONSTRAINT pads_kind CHECK (kind IN ('pad','notepad'));
  END IF;
END $$;
-- Deleting a folder deletes the documents inside it.
ALTER TABLE public.pads ADD COLUMN IF NOT EXISTS folder_id UUID REFERENCES public.pad_folders(id) ON DELETE CASCADE;
CREATE INDEX IF NOT EXISTS pads_folder ON public.pads(owner_id, folder_id);
COMMIT;
