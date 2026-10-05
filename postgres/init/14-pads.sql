BEGIN;
-- Dynamic Pad: free-form documents ("pads") holding text boxes, images, lines
-- and hand drawing. The layout is a small JSON document; images are stored
-- separately so autosaves stay small.
CREATE TABLE IF NOT EXISTS public.pads (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  name TEXT NOT NULL CHECK (length(trim(name)) BETWEEN 1 AND 100),
  doc JSONB NOT NULL DEFAULT '{"version":1,"elements":[]}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (jsonb_typeof(doc) = 'object')
);
CREATE INDEX IF NOT EXISTS pads_owner ON public.pads(owner_id, created_at);
CREATE TABLE IF NOT EXISTS public.pad_images (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  pad_id UUID NOT NULL REFERENCES public.pads(id) ON DELETE CASCADE,
  owner_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  mime TEXT NOT NULL CHECK (mime IN ('image/png','image/jpeg')),
  data BYTEA NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS pad_images_pad ON public.pad_images(pad_id);
COMMIT;
