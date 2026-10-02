BEGIN;
-- Calendar events and Schedule sessions can link to board panels, like Gantt
-- phases (event_panel_links, migration 12).
CREATE TABLE IF NOT EXISTS public.calendar_panel_links (
  calendar_event_id UUID NOT NULL REFERENCES public.calendar_events(id) ON DELETE CASCADE,
  workplace_id UUID NOT NULL REFERENCES public.board_workplaces(id) ON DELETE CASCADE,
  panel_id UUID NOT NULL,
  PRIMARY KEY(calendar_event_id, workplace_id, panel_id)
);
CREATE INDEX IF NOT EXISTS calendar_panel_links_panel ON public.calendar_panel_links(workplace_id, panel_id);
CREATE TABLE IF NOT EXISTS public.session_panel_links (
  owner_id UUID NOT NULL REFERENCES public.schedules(owner_id) ON DELETE CASCADE,
  session_id TEXT NOT NULL,
  workplace_id UUID NOT NULL REFERENCES public.board_workplaces(id) ON DELETE CASCADE,
  panel_id UUID NOT NULL,
  PRIMARY KEY(owner_id, session_id, workplace_id, panel_id)
);
CREATE INDEX IF NOT EXISTS session_panel_links_panel ON public.session_panel_links(workplace_id, panel_id);
-- Panels live in the board's JSONB document and sessions in the schedule's:
-- remove links atomically when either is deleted.
CREATE OR REPLACE FUNCTION public.prune_other_panel_links() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  DELETE FROM public.calendar_panel_links l WHERE l.workplace_id=NEW.id
    AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(NEW.board->'columns') c WHERE c->>'id'=l.panel_id::text);
  DELETE FROM public.session_panel_links l WHERE l.workplace_id=NEW.id
    AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(NEW.board->'columns') c WHERE c->>'id'=l.panel_id::text);
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS prune_other_panel_links ON public.board_workplaces;
CREATE TRIGGER prune_other_panel_links AFTER UPDATE OF board ON public.board_workplaces
  FOR EACH ROW EXECUTE FUNCTION public.prune_other_panel_links();
CREATE OR REPLACE FUNCTION public.prune_session_panel_links() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  DELETE FROM public.session_panel_links l WHERE l.owner_id=NEW.owner_id
    AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(NEW.data->'blocks') b WHERE b->>'id'=l.session_id);
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS prune_session_panel_links ON public.schedules;
CREATE TRIGGER prune_session_panel_links AFTER UPDATE OF data ON public.schedules
  FOR EACH ROW EXECUTE FUNCTION public.prune_session_panel_links();
COMMIT;
