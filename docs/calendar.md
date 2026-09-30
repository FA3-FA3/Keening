# Calendar

The Calendar tab provides an iOS-inspired month grid and selected-day agenda, with Keening's green accent. It supports previous/next month, Today, event dots, calendar visibility filters, and a stacked layout on narrower screens.

Calendar has its own collections and all-day events via authenticated `POST /calendar`, stored in `calendar_collections` and `calendar_events`. Gantt records are entirely separate. Existing previously shared entries remain in Gantt; migration does not duplicate or delete them. Inclusive date ranges appear on every day they span. Add event creates a Personal calendar on first use; subsequent events can be added to an existing Calendar collection.

Opening an event lets the user edit its title, dates, notes and completion. Links → Manage links connects it to Gantt events and board tasks. Relationships can be added or removed from either endpoint and never synchronize the underlying event/task fields. See [Event/task links](event-task-links.md). Existing Gantt-to-task links are retained.

This is an all-day month/agenda calendar. Time-of-day scheduling, recurrence, notifications and external calendar sync are not included.

Widget tests cover month navigation, Today, inclusive date ranges, filters, narrow layout, first-calendar creation and load retry.
