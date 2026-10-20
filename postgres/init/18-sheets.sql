BEGIN;
-- Spreadsheets: a third document type ('sheet') beside 'pad' and 'notepad'.
-- The sheet itself is a small JSON document in the same doc column.
ALTER TABLE public.pads DROP CONSTRAINT IF EXISTS pads_kind;
ALTER TABLE public.pads ADD CONSTRAINT pads_kind CHECK (kind IN ('pad','notepad','sheet'));
COMMIT;
