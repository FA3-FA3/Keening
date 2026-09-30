# Gantt calendars

The Gantt tab adapts Sorbit's corporate calendar timeline for user-owned calendars. Calendar has its own independent events; Boards has private workplaces. All three tabs support reciprocal links.

Users create calendars with a name and colour, switch between them, rename or delete them, and add events with inclusive start/end dates, descriptions, completion and an optional prerequisite. The task type has been retired; existing Gantt tasks become events without losing their data. Row dragging persists independently of dates. Period controls offer 2, 4 and 12 weeks, previous/next and Today. Timeline bars, weekend/current-day shading, hover highlighting and dependency arrows are retained from Sorbit.

Saved events have a Links section for connecting board tasks. See [Event/task links](event-task-links.md).

`POST /gantt` requires a Firebase email/password token. Actions are listCalendars, createCalendar, renameCalendar, deleteCalendar, listItems, saveItem, deleteItem and reorderItems. The backend resolves the caller's internal profile and checks ownership for every calendar action. User IDs are never accepted from the client. Dependency links must stay in the same calendar and cannot cycle. Calendar locks serialize edits; reorder requires the current complete item list. Deleting a prerequisite clears incoming links; deleting a calendar removes its items.

Schema: `postgres/init/03-gantt.sql` (additive and repeatable). Setup scripts apply it after the user schema. Limits: 100 calendars per user and 200 items per calendar, name 100 characters, title 200, description 5000, dates 1900–2200. Calendars are private; team membership and sharing are not part of this implementation.

Verification: Flutter widget tests cover create/edit/switch/refresh, errors, and reorder rollback/off-screen items. The local Postgres integration test covers ownership rejection, CRUD, dates, cross-calendar dependencies, cycles, reorder and cascade cleanup. Run with a loopback TEST_DATABASE_URL; it removes its own fixture users and calendars.

Deployment verified on 2026-09-29: Cloud Run revision keening-api-00003-25f, Firebase Hosting version 25442190a481a20d. All 20 backend tests and 8 Flutter tests passed; Flutter analysis is clean. Hosted Chrome verification passed login, calendar creation, dated item creation/editing, completion, reload persistence and a second empty calendar. Temporary Firebase user and associated Neon data were removed.
