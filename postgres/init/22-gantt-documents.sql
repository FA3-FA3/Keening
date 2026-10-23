BEGIN;
-- Gantt calendars become a document type ('gantt'), listed in Documents like the
-- others. A calendar and its document share one id, so everything that already
-- refers to the calendar (phases, projects, links, attachments) keeps working.
-- Existing calendars become documents at the top level (the default directory).
ALTER TABLE public.pads DROP CONSTRAINT IF EXISTS pads_kind;
ALTER TABLE public.pads ADD CONSTRAINT pads_kind CHECK (kind IN ('pad','notepad','sheet','gantt'));

INSERT INTO public.pads (id, owner_id, name, kind, folder_id, doc, created_at, updated_at)
SELECT c.id, c.owner_id, c.name, 'gantt', NULL, '{"version":1}'::jsonb, c.created_at, c.created_at
  FROM public.gantt_calendars c
 WHERE NOT EXISTS (SELECT 1 FROM public.pads p WHERE p.id = c.id);

-- Deleting the document deletes the calendar and its phases.
ALTER TABLE public.gantt_calendars DROP CONSTRAINT IF EXISTS gantt_calendars_document;
ALTER TABLE public.gantt_calendars ADD CONSTRAINT gantt_calendars_document
  FOREIGN KEY (id) REFERENCES public.pads(id) ON DELETE CASCADE;

-- Creating a Gantt document makes its calendar; renaming it renames the calendar.
CREATE OR REPLACE FUNCTION public.create_gantt_calendar() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO public.gantt_calendars (id, owner_id, name) VALUES (NEW.id, NEW.owner_id, NEW.name)
    ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS pads_create_gantt_calendar ON public.pads;
CREATE TRIGGER pads_create_gantt_calendar AFTER INSERT ON public.pads
  FOR EACH ROW WHEN (NEW.kind = 'gantt') EXECUTE FUNCTION public.create_gantt_calendar();

CREATE OR REPLACE FUNCTION public.rename_gantt_calendar() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  UPDATE public.gantt_calendars SET name = NEW.name WHERE id = NEW.id;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS pads_rename_gantt_calendar ON public.pads;
CREATE TRIGGER pads_rename_gantt_calendar AFTER UPDATE OF name ON public.pads
  FOR EACH ROW WHEN (NEW.kind = 'gantt' AND NEW.name IS DISTINCT FROM OLD.name)
  EXECUTE FUNCTION public.rename_gantt_calendar();
COMMIT;
