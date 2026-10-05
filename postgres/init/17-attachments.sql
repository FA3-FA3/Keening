BEGIN;
-- Attachments: files (text, images, anything else) added to Board tasks,
-- Schedule sessions and Calendar events. Tasks and sessions live inside JSON
-- documents, so item_id is plain text and orphans are swept on upload.
CREATE TABLE IF NOT EXISTS public.attachments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  item_type TEXT NOT NULL CHECK (item_type IN ('task','session','event')),
  item_id TEXT NOT NULL CHECK (length(item_id) BETWEEN 1 AND 100),
  name TEXT NOT NULL CHECK (length(trim(name)) BETWEEN 1 AND 200),
  mime TEXT NOT NULL CHECK (length(mime) BETWEEN 1 AND 100),
  size INTEGER NOT NULL CHECK (size >= 0),
  data BYTEA NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS attachments_item ON public.attachments(owner_id, item_type, item_id);
COMMIT;
