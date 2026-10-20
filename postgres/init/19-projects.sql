BEGIN;
-- Projects: a named group of things from the rest of the app. A project links
-- Gantt calendars, boards, single documents and document folders (a linked
-- folder brings its sub-folders and documents), so they can be viewed together.
CREATE TABLE IF NOT EXISTS public.projects (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  name TEXT NOT NULL CHECK (length(trim(name)) BETWEEN 1 AND 100),
  description TEXT NOT NULL DEFAULT '' CHECK (length(description) <= 1000),
  color TEXT NOT NULL DEFAULT '#2563EB' CHECK (color ~ '^#[0-9a-fA-F]{6}$'),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS projects_owner ON public.projects(owner_id, created_at);

-- What a project links. The target lives in a different table for each kind,
-- so there is no foreign key; triggers below remove a link when its target goes.
CREATE TABLE IF NOT EXISTS public.project_links (
  project_id UUID NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,
  owner_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  kind TEXT NOT NULL CHECK (kind IN ('gantt', 'board', 'document', 'folder')),
  target_id UUID NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (project_id, kind, target_id)
);
CREATE INDEX IF NOT EXISTS project_links_target ON public.project_links(kind, target_id);
CREATE INDEX IF NOT EXISTS project_links_owner ON public.project_links(owner_id);

CREATE OR REPLACE FUNCTION public.prune_project_links() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  DELETE FROM public.project_links WHERE kind = TG_ARGV[0] AND target_id = OLD.id;
  RETURN OLD;
END;
$$;
DROP TRIGGER IF EXISTS prune_project_links ON public.gantt_calendars;
CREATE TRIGGER prune_project_links AFTER DELETE ON public.gantt_calendars
  FOR EACH ROW EXECUTE FUNCTION public.prune_project_links('gantt');
DROP TRIGGER IF EXISTS prune_project_links ON public.board_workplaces;
CREATE TRIGGER prune_project_links AFTER DELETE ON public.board_workplaces
  FOR EACH ROW EXECUTE FUNCTION public.prune_project_links('board');
DROP TRIGGER IF EXISTS prune_project_links ON public.pads;
CREATE TRIGGER prune_project_links AFTER DELETE ON public.pads
  FOR EACH ROW EXECUTE FUNCTION public.prune_project_links('document');
DROP TRIGGER IF EXISTS prune_project_links ON public.pad_folders;
CREATE TRIGGER prune_project_links AFTER DELETE ON public.pad_folders
  FOR EACH ROW EXECUTE FUNCTION public.prune_project_links('folder');
COMMIT;
