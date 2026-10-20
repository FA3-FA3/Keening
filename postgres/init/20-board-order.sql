BEGIN;
-- Boards can be put in any order: the buttons that open them are reordered by
-- dragging. Existing boards keep their creation order.
ALTER TABLE public.board_workplaces ADD COLUMN IF NOT EXISTS position INTEGER NOT NULL DEFAULT 0;
UPDATE public.board_workplaces b SET position = o.n
  FROM (SELECT id, row_number() OVER (PARTITION BY owner_id ORDER BY created_at, id) AS n FROM public.board_workplaces) o
  WHERE b.id = o.id AND b.position = 0;
COMMIT;
