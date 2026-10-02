# Boards workplaces

Boards adapts Sorbit's Tasks page: user-created panels, draggable task cards,
coloured panels/tasks/tags, expanded panel details, double-click task details,
completion and archive/restore. Create board replaces team selection.
There are no team, member or assignment controls. Each user owns private
workplaces. Calendar stores independent events. Saved tasks have a Links section for connecting Calendar and Gantt events; see [Event/task links](event-task-links.md).

The frontend uses BoardsService and authenticated POST /boards. The backend
checks workplace ownership before every action. `postgres/init/04-boards.sql`
adds board_workplaces. Each workplace stores its panel/task/tag document in
JSONB; row locks serialize edits so independent concurrent changes survive.
Tags save atomically with task edits. Resource IDs must belong to the current
workplace. Deleting a panel removes active and archived tasks; deleting a tag
removes its task links; deleting a workplace removes all its board data.

Limits: 100 workplaces per user; 50 panels, 100 tags, and 500 tasks (including
archived) per workplace. Names: 100 characters, tags: 50, titles: 200,
descriptions: 5000. Setup scripts apply the additive schema.

Tests cover ownership and cross-workplace rejection, concurrent edits, task
movement, tags, completion, archive/restore, deletion, failed-form retry and
workplace switching.

Verified on 2026-09-29: all 21 backend tests and 11 Flutter tests passed, with clean static analysis. The hosted Chrome test passed workplace/panel/task creation, completion, archive/restore, persistence after reload, and creation of a second isolated workplace. Temporary test user and board data were removed. API revision: keening-api-00004-4m2. The frontend includes separate accessible actions for opening task details and completion.
