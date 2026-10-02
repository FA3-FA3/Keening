BEGIN;
ALTER TABLE public.calendar_events ADD COLUMN IF NOT EXISTS start_time TEXT;
ALTER TABLE public.calendar_events ADD COLUMN IF NOT EXISTS end_time TEXT;
DO $$ BEGIN
 IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='calendar_event_time_pair') THEN
 ALTER TABLE public.calendar_events ADD CONSTRAINT calendar_event_time_pair CHECK (
 (start_time IS NULL AND end_time IS NULL) OR
 (start_time IS NOT NULL AND end_time IS NOT NULL AND start_time ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
 AND (end_time ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' OR end_time='24:00') AND end_time>start_time));
 END IF;
END $$;
CREATE TABLE IF NOT EXISTS public.session_links (
 owner_id UUID NOT NULL REFERENCES public.schedules(owner_id) ON DELETE CASCADE,
 session_id TEXT NOT NULL,
 event_id UUID REFERENCES public.gantt_items(id) ON DELETE CASCADE,
 calendar_event_id UUID REFERENCES public.calendar_events(id) ON DELETE CASCADE,
 workplace_id UUID REFERENCES public.board_workplaces(id) ON DELETE CASCADE,
 task_id UUID,
 CHECK (num_nonnulls(event_id,calendar_event_id,workplace_id)=1),
 CHECK ((workplace_id IS NULL)=(task_id IS NULL))
);
CREATE UNIQUE INDEX IF NOT EXISTS session_links_gantt ON public.session_links(owner_id,session_id,event_id) WHERE event_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS session_links_calendar ON public.session_links(owner_id,session_id,calendar_event_id) WHERE calendar_event_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS session_links_task ON public.session_links(owner_id,session_id,workplace_id,task_id) WHERE task_id IS NOT NULL;
CREATE OR REPLACE FUNCTION public.prune_session_links() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 DELETE FROM public.session_links l WHERE l.owner_id=NEW.owner_id
 AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(NEW.data->'blocks') b WHERE b->>'id'=l.session_id);
 RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS prune_session_links ON public.schedules;
CREATE TRIGGER prune_session_links AFTER UPDATE OF data ON public.schedules FOR EACH ROW EXECUTE FUNCTION public.prune_session_links();
CREATE OR REPLACE FUNCTION public.prune_session_task_links() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 DELETE FROM public.session_links l WHERE l.workplace_id=NEW.id
 AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(NEW.board->'tasks') t WHERE t->>'id'=l.task_id::text);
 RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS prune_session_task_links ON public.board_workplaces;
CREATE TRIGGER prune_session_task_links AFTER UPDATE OF board ON public.board_workplaces FOR EACH ROW EXECUTE FUNCTION public.prune_session_task_links();
CREATE OR REPLACE FUNCTION public.remove_event_sessions() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 UPDATE public.schedules SET data=jsonb_set(data,'{blocks}',COALESCE((SELECT jsonb_agg(b) FROM jsonb_array_elements(data->'blocks') b WHERE b->>'calendarEventId' IS DISTINCT FROM OLD.id::text),'[]'::jsonb)),updated_at=now()
 WHERE data->'blocks' @> jsonb_build_array(jsonb_build_object('calendarEventId',OLD.id::text));
 RETURN OLD;
END $$;
DROP TRIGGER IF EXISTS remove_event_sessions ON public.calendar_events;
CREATE TRIGGER remove_event_sessions BEFORE DELETE ON public.calendar_events FOR EACH ROW EXECUTE FUNCTION public.remove_event_sessions();
COMMIT;
