BEGIN;
-- Preserve existing Gantt items while retiring the task/event distinction.
UPDATE public.gantt_items SET kind='event' WHERE kind='task';
CREATE TABLE IF NOT EXISTS public.event_task_links (
  event_id UUID NOT NULL REFERENCES public.gantt_items(id) ON DELETE CASCADE,
  workplace_id UUID NOT NULL REFERENCES public.board_workplaces(id) ON DELETE CASCADE,
  task_id UUID NOT NULL,
  PRIMARY KEY(event_id, workplace_id, task_id)
);
CREATE INDEX IF NOT EXISTS event_task_links_task ON public.event_task_links(workplace_id, task_id);
-- Board tasks live in JSONB. Remove their links atomically when tasks/panels are deleted.
CREATE OR REPLACE FUNCTION public.prune_event_task_links() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  DELETE FROM public.event_task_links l WHERE l.workplace_id=NEW.id
    AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(NEW.board->'tasks') t WHERE t->>'id'=l.task_id::text);
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS prune_event_task_links ON public.board_workplaces;
CREATE TRIGGER prune_event_task_links AFTER UPDATE OF board ON public.board_workplaces
  FOR EACH ROW EXECUTE FUNCTION public.prune_event_task_links();
COMMIT;
