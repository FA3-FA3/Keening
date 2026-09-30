BEGIN;
CREATE TABLE IF NOT EXISTS public.calendar_collections (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  name TEXT NOT NULL CHECK(length(trim(name)) BETWEEN 1 AND 100),
  color TEXT NOT NULL DEFAULT '#2E7D5B' CHECK(color ~ '^#[0-9a-fA-F]{6}$'),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS calendar_collections_owner ON public.calendar_collections(owner_id);
CREATE TABLE IF NOT EXISTS public.calendar_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  calendar_id UUID NOT NULL REFERENCES public.calendar_collections(id) ON DELETE CASCADE,
  kind TEXT NOT NULL DEFAULT 'event' CHECK(kind='event'),
  title TEXT NOT NULL CHECK(length(trim(title)) BETWEEN 1 AND 200),
  description TEXT NOT NULL DEFAULT '' CHECK(length(description)<=5000),
  start_date DATE NOT NULL CHECK(start_date>=DATE '1900-01-01'),
  end_date DATE NOT NULL CHECK(end_date>=start_date AND end_date<=DATE '2200-12-31'),
  completed BOOLEAN NOT NULL DEFAULT false,
  prerequisite_id UUID,
  calendar_position INTEGER NOT NULL DEFAULT 0,
  UNIQUE(calendar_id,id),
  FOREIGN KEY(calendar_id,prerequisite_id) REFERENCES public.calendar_events(calendar_id,id) ON DELETE SET NULL (prerequisite_id),
  CHECK(prerequisite_id IS DISTINCT FROM id)
);
CREATE INDEX IF NOT EXISTS calendar_events_calendar ON public.calendar_events(calendar_id,calendar_position);
CREATE TABLE IF NOT EXISTS public.calendar_gantt_links (
  calendar_event_id UUID NOT NULL REFERENCES public.calendar_events(id) ON DELETE CASCADE,
  event_id UUID NOT NULL REFERENCES public.gantt_items(id) ON DELETE CASCADE,
  PRIMARY KEY(calendar_event_id,event_id)
);
CREATE INDEX IF NOT EXISTS calendar_gantt_links_gantt ON public.calendar_gantt_links(event_id);
CREATE TABLE IF NOT EXISTS public.calendar_task_links (
  calendar_event_id UUID NOT NULL REFERENCES public.calendar_events(id) ON DELETE CASCADE,
  workplace_id UUID NOT NULL REFERENCES public.board_workplaces(id) ON DELETE CASCADE,
  task_id UUID NOT NULL,
  PRIMARY KEY(calendar_event_id,workplace_id,task_id)
);
CREATE INDEX IF NOT EXISTS calendar_task_links_task ON public.calendar_task_links(workplace_id,task_id);
CREATE OR REPLACE FUNCTION public.prune_calendar_task_links() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  DELETE FROM public.calendar_task_links l WHERE l.workplace_id=NEW.id
    AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(NEW.board->'tasks') t WHERE t->>'id'=l.task_id::text);
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS prune_calendar_task_links ON public.board_workplaces;
CREATE TRIGGER prune_calendar_task_links AFTER UPDATE OF board ON public.board_workplaces
  FOR EACH ROW EXECUTE FUNCTION public.prune_calendar_task_links();
COMMIT;
