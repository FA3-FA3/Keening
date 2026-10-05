# Documents

**Documents** is a sidebar page for your own files, organised in folders and shown as icons, like a file explorer. There are two document types: the **Dynamic Pad** (a free-form canvas) and the **Notepad** (a plain page of text).

## Using Documents

- **New folder** creates a folder inside the folder you are viewing. Click a folder to open it; the breadcrumbs (and the up-arrow) take you back. A folder's `⋮` menu has **Rename**, **Move** (into another folder or the top level, taking everything inside it along; a folder can't go inside itself or its own sub-folders, or deeper than 8 levels) and **Delete**. Deleting a folder asks first and also deletes everything inside it (sub-folders, documents and pictures).
- **New document** opens a dropdown menu of the document types; picking one asks for a name and an optional description. The document is created in the folder you are viewing.
- Click a document icon to open its details popup: type, name, description and last-edited time, with **Edit** (name and description), **Move** (choose any folder or the top level), **Delete**, and **Open**. **Open** shows the editor full screen; the back arrow in its top-left corner returns to the grid and saves any pending edits.
- Everything **autosaves** shortly after each change (the editors show *Saved*, *Unsaved changes…*, *Saving…* or *Not saved* with a Retry button), and closing a document saves any pending edits.

### Dynamic Pad

A blank 3000 × 2000 space holding text boxes, pictures, straight lines and hand drawing.

- Tools: **Select and move**, **Text box**, **Line**, **Pen**, **Add picture**.
  - *Select*: click an item to select it, drag it to move it, drag its corner handle to resize (text boxes change width, pictures keep their proportions), drag a line's end handles to reposition it. Double-click a text box to edit it. Dragging the empty background scrolls the pad.
  - *Text box*: click where the text should go and type. Clicking away (or Esc) finishes; empty boxes are discarded.
  - *Line / Pen*: drag to draw. Strokes are smoothed and simplified when you let go.
  - *Add picture*: choose a file, or **drag a picture file from your desktop onto the pad** (browser version) to drop it where you release it. Pictures are shrunk to at most 1600 px and stored as PNG (up to 3 MB each, 50 per pad).
- The colour swatches, **Width** and **Text** size menus apply to new items and to the selected item.
- **Undo / Redo** (also Ctrl/⌘+Z, Ctrl+Y or Ctrl+Shift+Z), **Delete selected** (also Delete/Backspace), and **Zoom** (25 %–200 %).
- Layers are drawn pictures first, then lines and pen strokes, then text.

### Notepad

A plain page of text with a word and character count, using the normal text-field editing and undo of your browser. Notes hold up to 200 000 characters.

## Adding another document type

Types are listed in `documentTypes` in `lib/pages/documents_page.dart` (name, icon and a one-line description shown in the chooser). The server's allowed types are `KINDS` in `cloud-run/src/pads.js`, and `pads.kind` is checked by migration `16-document-folders.sql`. A new type also needs its own editor screen and save validation.

## Storage and limits

Documents are stored in the `pads` table (kept under its original name so existing pads carry over as Dynamic Pads), with a `kind` (`pad` or `notepad`), a `folder_id`, a description (migration `15-pad-descriptions.sql`) and a small JSON `doc`: a Dynamic Pad's layout, or a Notepad's `{text}`. Folders are in `pad_folders` (nested, up to 8 levels); deleting a folder cascades to its sub-folders and documents. Pad pictures are stored once in `pad_images`, so autosaves send only the layout.

Authenticated `POST /pads` accepts `listPads`, `createPad` (with `kind` and `folderId`), `renamePad`, `updatePad`, `movePad`, `deletePad`, `getPad`, `savePad`, `uploadImage`, `getImage`, `listFolders`, `createFolder`, `renameFolder`, `moveFolder` and `deleteFolder`. Every action checks ownership. Only Dynamic Pads accept pictures. The route allows bodies up to 6 MB for picture uploads; all other routes keep their small limit.

Limits: 500 documents and 200 folders per user; Dynamic Pads hold up to 3000 items and 150 000 pen points (layouts up to 1.5 MB, text boxes up to 10 000 characters); Notepads up to 200 000 characters. The server rebuilds every saved document from whitelisted fields and rejects anything out of range. Pad pictures no longer on a pad are removed an hour after the next save, so undo still works for a while.

## Search

The global search (the search button on the dashboard) finds folders and documents by name, description and folder, and also looks **inside Notepads**; a Notepad result shows the start of its text. Picking a folder opens it on the Documents page; picking a document opens its folder and shows the document's details popup. Search keeps working if the document tables are missing (before migrations 14–16 are applied), it just returns no documents.
