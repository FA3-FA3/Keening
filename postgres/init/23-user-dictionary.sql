BEGIN;
-- The words a person has added to their spelling dictionary, kept with their
-- account so they follow them to every computer and browser.
CREATE TABLE IF NOT EXISTS public.user_dictionary (
  owner_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  word TEXT NOT NULL CHECK (word <> '' AND length(word) <= 60),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (owner_id, word)
);
COMMIT;
