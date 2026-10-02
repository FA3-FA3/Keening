BEGIN;
-- Gantt phases can be linked to board panels; the phase bar shows how many of
-- the panel's tasks are complete.
CREATE TABLE IF NOT EXISTS public.event_panel_links (
  event_id UUID NOT NULL REFERENCES public.gantt_items(id) ON DELETE CASCADE,
  workplace_id UUID NOT NULL REFERENCES public.board_workplaces(id) ON DELETE CASCADE,
  panel_id UUID NOT NULL,
  PRIMARY KEY(event_id, workplace_id, panel_id)
);
CREATE INDEX IF NOT EXISTS event_panel_links_panel ON public.event_panel_links(workplace_id, panel_id);
-- Panels live in the board's JSONB document. Remove links when a panel is deleted.
CREATE OR REPLACE FUNCTION public.prune_event_panel_links() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  DELETE FROM public.event_panel_links l WHERE l.workplace_id=NEW.id
    AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(NEW.board->'columns') c WHERE c->>'id'=l.panel_id::text);
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS prune_event_panel_links ON public.board_workplaces;
CREATE TRIGGER prune_event_panel_links AFTER UPDATE OF board ON public.board_workplaces
  FOR EACH ROW EXECUTE FUNCTION public.prune_event_panel_links();
COMMIT;
