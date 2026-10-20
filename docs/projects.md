# Projects

**Projects** is a sidebar page (second tab, after Dashboard) for grouping things from the rest of Keening and seeing them **all together**. A project holds links, not copies: the linked Gantt calendars, boards, folders and documents stay where they are and keep being edited on their own pages.

## Using Projects

- **New project** asks for a name, an optional description and a colour. The new project opens straight away. Projects appear as cards showing what each links; click one to open it. The back arrow returns to the list.
- **Link items** (top of an open project) lists everything you own in four groups, with a search box: **Gantt calendars**, **Boards**, **Folders** (a linked folder brings every sub-folder and document inside it, including ones added later) and **Single documents**. Tick what you want and choose **Link n items**. What is already linked is shown ticked and cannot be linked twice. A project can link up to 200 things; you can have up to 100 projects.
- **Edit** (pencil) changes the name, description and colour; **Delete** (bin) deletes the project only, never the things it links.
- If a linked calendar, board, document or folder is deleted elsewhere, its link disappears from the project by itself.

### The views

Each project has five views, chosen with the buttons under its name:

- **Overview**: everything together. Three summary cards (Gantt phases done and how many are overdue; board tasks done, not counting archived ones; how many documents, from linked folders and single), then **Coming up** (unfinished phases, soonest first, overdue ones in red), a compact **Timeline**, a **Boards** summary (progress and how many tasks are in each panel) and **Recent documents**. Each section has **See all** to jump to its own view. Clicking a phase, task or document opens it on its own page.
- **Timeline**: every linked Gantt calendar on one time axis, each calendar in its own colour with a heading and its phases underneath as bars. Completed phases are faded with a tick, overdue ones have a red outline, and a line marks today. Zoom in and out, or jump to today. Click a bar to open that phase in the Gantt page.
- **Boards**: each linked board with its panels side by side and its tasks as cards (done tasks ticked and struck through, tags shown). **Show archived tasks** adds the archived ones. **Open board** and clicking a task open them on the Boards page.
- **Documents**: every document in the project, newest first, with its type, folder, last-edited date and (for notes) the start of its text. Filter by **All**, **Single documents** or **From linked folders**. Clicking a document opens it, in its folder, on the Documents page.
- **Linked items**: what the project links, by kind, with **Open** and **Unlink** for each. Unlinking a folder removes it and the documents that came through it; unlinking never deletes the thing itself.

"Open" works through the dashboard's tabs, the same way a search result does: the Gantt, Boards or Documents tab opens (or comes to the front) showing the item.

## Storage and API

Migration `postgres/init/19-projects.sql` (run `scripts/apply-schema.ps1` before deploying the API that uses it) adds:

- `projects` (`id`, `owner_id`, `name` 1–100 characters, `description` up to 1000, `color` `#RRGGBB`, timestamps).
- `project_links` (`project_id`, `owner_id`, `kind` one of `gantt`, `board`, `document`, `folder`, `target_id`). The target is in a different table for each kind, so it has no foreign key; triggers on `gantt_calendars`, `board_workplaces`, `pads` and `pad_folders` delete a link when its target is deleted.

Authenticated `POST /projects` (`cloud-run/src/projects.js`) accepts `listProjects` (with a count of links by kind), `createProject`, `updateProject`, `deleteProject`, `getProject`, `listLinkable`, `linkItems` (several `{kind, id}` at once; every item must belong to the caller, and the whole request is refused otherwise) and `unlinkItem`. Every action checks ownership.

`getProject` returns the project and everything linked, ready to show: each linked Gantt calendar with its phases; each board trimmed to its panels, tags and tasks (title, panel, colour, done, archived, tags; no descriptions); the linked folders with their path and counts; and the documents (linked ones plus everything below linked folders, up to 500, newest first) with a short preview of a note's text and whether each was linked directly.

Not part of a project yet: Calendar events, Schedule sessions, and individual phases or tasks (link the whole calendar or board instead). Projects are not included in the global search.
