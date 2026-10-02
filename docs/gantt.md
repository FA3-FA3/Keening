# Gantt calendars

The Gantt tab adapts Sorbit's corporate calendar timeline for user-owned calendars. Calendar has its own independent events; Boards has private workplaces. All three tabs support reciprocal links.

Users create calendars with a name and colour, switch between them, rename or delete them, and add phases with inclusive start/end dates, descriptions, completion and an optional prerequisite. The task type has been retired; existing Gantt tasks become phases without losing their data. Row dragging persists independently of dates. Period controls offer 2, 4 and 12 weeks, previous/next and Today. Timeline bars, weekend/current-day shading, hover highlighting and dependency arrows are retained from Sorbit.

Saved phases have a Links section for connecting board tasks. See [Event/task links](event-task-links.md).

`POST /gantt` requires a Firebase email/password token. Actions are listCalendars, createCalendar, renameCalendar, deleteCalendar, listItems, saveItem, deleteItem and reorderItems. The backend resolves the caller's internal profile and checks ownership for every calendar action. User IDs are never accepted from the client. Dependency links must stay in the same calendar and cannot cycle. Calendar locks serialize edits; reorder requires the current complete item list. Deleting a prerequisite clears incoming links; deleting a calendar removes its items.

Schema: `postgres/init/03-gantt.sql` (additive and repeatable). Setup scripts apply it after the user schema. Limits: 100 calendars per user and 200 items per calendar, name 100 characters, title 200, description 5000, dates 1900–2200. Calendars are private; team membership and sharing are not part of this implementation.

Verification: Flutter widget tests cover create/edit/switch/refresh, errors, and reorder rollback/off-screen items. The local Postgres integration test covers ownership rejection, CRUD, dates, cross-calendar dependencies, cycles, reorder and cascade cleanup. Run with a loopback TEST_DATABASE_URL; it removes its own fixture users and calendars.

Deployment verified on 2026-09-29: Cloud Run revision keening-api-00003-25f, Firebase Hosting version 25442190a481a20d. All 20 backend tests and 8 Flutter tests passed; Flutter analysis is clean. Hosted Chrome verification passed login, calendar creation, dated item creation/editing, completion, reload persistence and a second empty calendar. Temporary Firebase user and associated Neon data were removed.

Calendar events support a single date by default, an optional inclusive end date,
and an optional daily time slot (24-hour HH:mm, same-day end; 24:00 allowed).
Timed events generate one linked Schedule session per date, for up to 366 days,
within the existing 5,000-session limit. Event edits update generated dates,
titles, notes and times while preserving session tags/colours.
Removing the time slot or deleting the event removes its generated sessions.
Schedule sessions can link reciprocally to Calendar events, Gantt phases and
Board tasks. Apply `09-calendar-sessions.sql` before deploying this version.

Calendar events also accept an optional free-text location (up to 500 characters),
which is copied to generated sessions when the event is saved. Calendar's Events
view lists every event across the account in ascending start-date/time order,
with dates, times, location, notes and completion status. Calendar grouping controls and collection labels are hidden; existing events remain accessible together. It does not restrict the
list to the month currently selected in the calendar grid.

Calendar has a separate per-account tag library using the same name/colour editor
as Schedule. Calendar > Tags manages up to 50 tags; event editors assign one tag
or No tag. Tag colours appear in the calendar and event cards; labels appear in
the day agenda and Events list. Deleting a tag clears its event assignments.
