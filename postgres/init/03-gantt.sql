BEGIN;
CREATE TABLE IF NOT EXISTS public.gantt_calendars (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  name TEXT NOT NULL CHECK (length(trim(name)) BETWEEN 1 AND 100),
  color TEXT NOT NULL DEFAULT '#2E7D5B' CHECK (color ~ '^#[0-9a-fA-F]{6}$'),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS gantt_calendars_owner ON public.gantt_calendars(owner_id);
CREATE TABLE IF NOT EXISTS public.gantt_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  calendar_id UUID NOT NULL REFERENCES public.gantt_calendars(id) ON DELETE CASCADE,
  kind TEXT NOT NULL CHECK (kind IN ('task', 'event')),
  title TEXT NOT NULL CHECK (length(trim(title)) BETWEEN 1 AND 200),
  description TEXT NOT NULL DEFAULT '' CHECK (length(description) <= 5000),
  start_date DATE NOT NULL CHECK (start_date >= DATE '1900-01-01'),
  end_date DATE NOT NULL CHECK (end_date >= start_date AND end_date <= DATE '2200-12-31'),
  completed BOOLEAN NOT NULL DEFAULT false,
  prerequisite_id UUID,
  calendar_position INTEGER NOT NULL DEFAULT 0,
  UNIQUE (calendar_id, id),
  FOREIGN KEY (calendar_id, prerequisite_id) REFERENCES public.gantt_items(calendar_id, id)
    ON DELETE SET NULL (prerequisite_id),
  CHECK (prerequisite_id IS DISTINCT FROM id)
);
CREATE INDEX IF NOT EXISTS gantt_items_calendar ON public.gantt_items(calendar_id, calendar_position);
COMMIT;
