# Calendar, Gantt and board links

Gantt now creates events only. Migration `05-event-task-links.sql` converts existing Gantt tasks to events, retaining IDs, dates, descriptions, completion, order and prerequisites.

After saving a Calendar event, Gantt event or board task, open its details and choose **Links → Manage links**. Search by title or calendar/workplace name and check or uncheck items from the other two tabs. Each option is labelled Calendar, Gantt or Boards. Changes save immediately, independently of the details form's Save/Cancel buttons, and are visible from both sides when opened. Many-to-many links are supported for all three pairs. Archived tasks remain linked and are labelled Archived. Links do not synchronize titles, notes, dates or completion.

Authenticated `POST /links` accepts `list`, `link`, `unlink` and a `source` (`event` for Gantt, `calendar`, or `task`). Gantt reads require `eventId`; Calendar reads require `calendarEventId`; task reads require `workplaceId` and `taskId`. Mutations specify `targetType` and both endpoints' IDs. The original Gantt/task pair remains compatible with clients that omit targetType. The server verifies ownership of both endpoints. Mutations lock Gantt, Calendar, then workplace as applicable. Lists return only the caller's items.

Migration `06-calendar.sql` adds independent Calendar storage and `calendar_gantt_links` / `calendar_task_links`, preserving `event_task_links`. Foreign keys cascade event/calendar/workplace deletion; triggers remove links to deleted JSONB board tasks. Archiving retains links. Live schema application and emulator startup include both migrations.

Widget tests exercise both link directions and failed-save retries. Postgres integration tests exercise many-to-many links, ownership, duplicate prevention, archive visibility and deletion cleanup.
