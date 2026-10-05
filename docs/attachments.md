# Attachments

Board **tasks**, Schedule **sessions** and Calendar **events** can have files attached: text files, pictures and any other file type.

## Using attachments

Open an existing task, session or event. Under its links there is an **Attachments** section:

- **Add files** opens the file chooser; pick one or several. Each file can be up to 5 MB, an item can have up to 10 attachments, and each user can store up to 100 MB in total.
- Click an attachment to open it. Pictures and text files open in a viewer (long text shows the first 100 000 characters); other files download. The download button saves any attachment.
- The bin button deletes an attachment after asking.
- A brand-new item must be saved once before files can be attached (attachments belong to the saved item). Attachments are saved immediately, independent of the item's own **Save** button.
- Downloading works in the browser version.

## Storage

Files are stored in the `attachments` table (migration `17-attachments.sql`): owner, item type (`task`, `session` or `event`), item id, name, content type, size and the bytes. Tasks and sessions live inside JSON documents, so there is no database link to them; instead, **attachments whose item has been deleted are removed the next time that user uploads a file** (so deleted items stop counting towards the 100 MB). Deleting a user removes their attachments.

Authenticated `POST /attachments` accepts `list` (`itemType`, `itemId`), `upload` (`itemType`, `itemId`, `name`, `mime`, base64 `data`), `get` (`attachmentId`) and `delete` (`attachmentId`). Every action checks ownership and that the item exists. Names lose any path parts and control characters; unknown content types are stored as `application/octet-stream`. The route allows request bodies up to 8 MB (a 5 MB file is about 6.7 MB as base64); other routes keep their small limit.

Recurring sessions that are regenerated when their Calendar event is edited get new session ids, so attachments on those generated sessions are not kept.
