// Documents: folders, and documents of four types: Dynamic Pads ("pad": text boxes,
// images, lines and pen strokes), Notepads ("notepad": formatted text), spreadsheets
// ("sheet": a grid of cells holding text, numbers and formulas) and Gantt calendars
// ("gantt": the document only names it and places it in a folder; its phases live in
// the Gantt tables under the same id, and a trigger keeps the two in step).
const uuid = value => typeof value === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);
const fail = (message, statusCode = 400) => { throw Object.assign(new Error(message), { publicMessage: message, statusCode }); };

export const KINDS = ['pad', 'notepad', 'sheet', 'gantt'];
export const LIMITS = {
  documents: 500,
  folders: 200,
  folderDepth: 8,
  description: 1000,
  noteChars: 200000,
  noteRuns: 5000,
  boxRuns: 500,
  noteEmbeds: 100,
  latex: 2000,
  elements: 3000,
  penPoints: 150000,
  docBytes: 1_500_000,
  imagesPerPad: 50,
  imageBytes: 3 * 1024 * 1024,
  coordinate: 20000,
  pageSize: [100, 10000],
  gridSize: [5, 500],
  sheetRows: 1000,
  sheetCols: 52,
  sheetCells: 20000,
  sheetCellChars: 1000,
  sheetColWidth: [40, 600],
  sheetRules: 50,
  ruleValueChars: 200,
};

function name(value) {
  if (typeof value !== 'string' || !value.trim() || value.trim().length > 100) fail('Enter a name of 1–100 characters.');
  return value.trim();
}
function description(value) {
  if (typeof value !== 'string' || value.length > LIMITS.description) fail(`Descriptions can be up to ${LIMITS.description} characters.`);
  return value.trim();
}
const num = (value, min, max, label) => {
  if (typeof value !== 'number' || !Number.isFinite(value) || value < min || value > max) fail(`Invalid ${label}.`);
  return Math.round(value * 100) / 100;
};
const coord = (value, label) => num(value, -LIMITS.coordinate, LIMITS.coordinate, label);
const colour = value => {
  if (typeof value !== 'string' || !/^#[0-9a-f]{6}$/i.test(value)) fail('Invalid colour.');
  return value.toUpperCase();
};

// Formatting runs shared by Notepads and Dynamic Pad text boxes: ranges of text with a
// size, text colour, highlight colour, bold, italic, underline and/or sub/superscript. Runs are sorted,
// never overlap, stay inside the text, and carry at least one attribute. A Notepad's runs
// (those given its [text]) may also carry an "embed": a picture or equation standing in for
// one placeholder character of the text.
export const EMBED_CHAR = '\uFFFC';
export function cleanRuns(value, length, max, text = null) {
  if (value === undefined || value === null) return [];
  if (!Array.isArray(value) || value.length > max) fail('Invalid text formatting.');
  let previousEnd = 0;
  return value.map(r => {
    if (!r || typeof r !== 'object' || !Number.isInteger(r.start) || !Number.isInteger(r.end)
      || r.start < previousEnd || r.end <= r.start || r.end > length) fail('Invalid text formatting.');
    previousEnd = r.end;
    const run = { start: r.start, end: r.end };
    if (r.size !== undefined) run.size = num(r.size, 8, 200, 'font size');
    if (r.color !== undefined) run.color = colour(r.color);
    if (r.bg !== undefined) run.bg = colour(r.bg);
    for (const key of ['bold', 'italic', 'underline', 'sub', 'sup']) {
      if (r[key] === undefined) continue;
      if (r[key] !== true) fail('Invalid text formatting.');
      run[key] = true;
    }
    if (run.sub && run.sup) fail('Invalid text formatting.');
    if (r.embed !== undefined) {
      const e = r.embed;
      if (text === null || !e || typeof e !== 'object') fail('Invalid text formatting.');
      if (e.type === 'image') {
        if (!uuid(e.imageId)) fail('Invalid image.');
        run.embed = { type: 'image', imageId: e.imageId };
      } else if (e.type === 'equation') {
        if (typeof e.latex !== 'string' || !e.latex.trim() || e.latex.length > LIMITS.latex) fail(`Equations can be up to ${LIMITS.latex} characters.`);
        run.embed = { type: 'equation', latex: e.latex };
      } else fail('Invalid text formatting.');
      if (text.slice(r.start, r.end) !== EMBED_CHAR.repeat(r.end - r.start)) fail('Invalid text formatting.');
    }
    if (Object.keys(run).length === 2) fail('Invalid text formatting.');
    return run;
  });
}

// The pictures a note's runs refer to.
export const noteImageIds = runs => [...new Set((runs ?? []).filter(r => r.embed?.type === 'image').map(r => r.embed.imageId))];

// A Notepad's own settings: laid out on A4 pages or not, and its background colour.
function cleanNoteSettings(settings) {
  if (!settings || typeof settings !== 'object' || Array.isArray(settings)) fail('Invalid note settings.');
  if (typeof settings.pages !== 'boolean') fail('Invalid note settings.');
  return { pages: settings.pages, background: colour(settings.background) };
}

// A spreadsheet's own settings: gridlines, headers and the usual column width.
function cleanSheetSettings(settings) {
  if (!settings || typeof settings !== 'object' || Array.isArray(settings)) fail('Invalid spreadsheet settings.');
  if (typeof settings.gridlines !== 'boolean' || typeof settings.headers !== 'boolean') fail('Invalid spreadsheet settings.');
  return { gridlines: settings.gridlines, headers: settings.headers, colWidth: num(settings.colWidth, LIMITS.sheetColWidth[0], LIMITS.sheetColWidth[1], 'column width') };
}

// A spreadsheet's conditional formatting rules: a range, a condition on the cell's value and
// the look to give the cells that meet it. Rebuilt from whitelisted fields.
const RULE_CONDITIONS = {
  gt: 1, ge: 1, lt: 1, le: 1, eq: 1, ne: 1, between: 2,
  contains: 1, notContains: 1, beginsWith: 1, endsWith: 1, empty: 0, notEmpty: 0,
};
function cleanSheetRules(rules, rows, cols) {
  if (!Array.isArray(rules) || rules.length > LIMITS.sheetRules) fail(`A spreadsheet can have up to ${LIMITS.sheetRules} formatting rules.`);
  const cell = /^([A-Z]{1,2})([1-9][0-9]{0,3})$/;
  return rules.map(rule => {
    if (!rule || typeof rule !== 'object' || Array.isArray(rule)) fail('Invalid formatting rule.');
    if (typeof rule.r !== 'string') fail('Invalid formatting rule.');
    const ends = rule.r.split(':');
    if (ends.length > 2) fail('Invalid formatting rule.');
    for (const end of ends) {
      const m = cell.exec(end);
      if (!m || columnIndex(m[1]) >= cols || Number(m[2]) > rows) fail('Invalid formatting rule.');
    }
    if (!Object.hasOwn(RULE_CONDITIONS, rule.c)) fail('Invalid formatting rule.');
    const clean = { r: rule.r, c: rule.c };
    const wanted = RULE_CONDITIONS[rule.c];
    for (const [key, needed] of [['v', wanted >= 1], ['v2', wanted >= 2]]) {
      if (!needed) continue;
      if (typeof rule[key] !== 'string' || rule[key].length > LIMITS.ruleValueChars) fail('Invalid formatting rule.');
      clean[key] = rule[key];
    }
    if (rule.bg !== undefined) clean.bg = colour(rule.bg);
    if (rule.fg !== undefined) clean.fg = colour(rule.fg);
    if (rule.b !== undefined) {
      if (rule.b !== true) fail('Invalid formatting rule.');
      clean.b = true;
    }
    if (clean.bg === undefined && clean.fg === undefined && !clean.b) fail('A formatting rule needs a colour or bold.');
    return clean;
  });
}

// Rebuild a Notepad's content from whitelisted fields.
export function cleanNote(doc) {
  if (!doc || typeof doc !== 'object' || typeof doc.text !== 'string') fail('Invalid note.');
  if (doc.text.length > LIMITS.noteChars) fail(`Notes can hold up to ${LIMITS.noteChars} characters.`);
  const runs = cleanRuns(doc.runs, doc.text.length, LIMITS.noteRuns, doc.text);
  const embeds = runs.filter(r => r.embed).reduce((sum, r) => sum + r.end - r.start, 0);
  if (embeds > LIMITS.noteEmbeds) fail(`A note can hold up to ${LIMITS.noteEmbeds} pictures and equations.`);
  return { version: 1, text: doc.text, ...(runs.length ? { runs } : {}), ...(doc.settings === undefined ? {} : { settings: cleanNoteSettings(doc.settings) }) };
}

// A Dynamic Pad's page: its size in pixels, background colour and grid lines.
function cleanPage(page) {
  if (!page || typeof page !== 'object' || Array.isArray(page)) fail('Invalid page settings.');
  const grid = page.grid ?? {};
  if (typeof grid !== 'object' || Array.isArray(grid) || typeof (grid.show ?? false) !== 'boolean') fail('Invalid page settings.');
  return {
    width: num(page.width, ...LIMITS.pageSize, 'page width'),
    height: num(page.height, ...LIMITS.pageSize, 'page height'),
    background: colour(page.background),
    grid: { show: grid.show ?? false, size: num(grid.size ?? 50, ...LIMITS.gridSize, 'grid spacing'), color: colour(grid.color ?? '#D1D5DB') },
  };
}

// Rebuild a Dynamic Pad's layout from whitelisted fields so nothing unexpected is stored.
export function cleanDoc(doc) {
  if (!doc || typeof doc !== 'object' || !Array.isArray(doc.elements)) fail('Invalid pad.');
  if (doc.elements.length > LIMITS.elements) fail(`A pad can hold up to ${LIMITS.elements} items.`);
  const ids = new Set();
  let points = 0;
  const elements = doc.elements.map(e => {
    if (!e || typeof e !== 'object') fail('Invalid pad item.');
    if (typeof e.id !== 'string' || !e.id || e.id.length > 64 || ids.has(e.id)) fail('Invalid pad item.');
    ids.add(e.id);
    const base = { id: e.id, type: e.type };
    switch (e.type) {
      case 'text': {
        if (typeof e.text !== 'string' || e.text.length > 10000) fail('Text boxes can hold up to 10000 characters.');
        const runs = cleanRuns(e.runs, e.text.length, LIMITS.boxRuns);
        return { ...base, x: coord(e.x, 'position'), y: coord(e.y, 'position'), w: num(e.w, 20, 5000, 'width'), text: e.text, fontSize: num(e.fontSize, 8, 200, 'font size'), color: colour(e.color), ...(runs.length ? { runs } : {}) };
      }
      case 'equation': {
        if (typeof e.latex !== 'string' || !e.latex.trim() || e.latex.length > LIMITS.latex) fail(`Equations can be up to ${LIMITS.latex} characters.`);
        return { ...base, x: coord(e.x, 'position'), y: coord(e.y, 'position'), w: num(e.w, 10, 10000, 'width'), h: num(e.h, 10, 10000, 'height'), latex: e.latex, color: colour(e.color) };
      }
      case 'image': {
        if (!uuid(e.imageId)) fail('Invalid image.');
        return { ...base, x: coord(e.x, 'position'), y: coord(e.y, 'position'), w: num(e.w, 10, 10000, 'width'), h: num(e.h, 10, 10000, 'height'), imageId: e.imageId };
      }
      case 'line':
        return { ...base, x1: coord(e.x1, 'position'), y1: coord(e.y1, 'position'), x2: coord(e.x2, 'position'), y2: coord(e.y2, 'position'), width: num(e.width, 1, 60, 'line width'), color: colour(e.color) };
      case 'pen': {
        if (!Array.isArray(e.points) || e.points.length < 1) fail('Invalid drawing.');
        points += e.points.length;
        if (points > LIMITS.penPoints) fail('This pad has too much hand drawing. Delete some strokes and try again.');
        return {
          ...base,
          points: e.points.map(p => {
            if (!Array.isArray(p) || p.length !== 2) fail('Invalid drawing.');
            return [coord(p[0], 'position'), coord(p[1], 'position')];
          }),
          width: num(e.width, 1, 60, 'line width'),
          color: colour(e.color),
        };
      }
      default: fail('Unknown pad item.');
    }
  });
  const clean = { version: 1, elements, ...(doc.page === undefined ? {} : { page: cleanPage(doc.page) }) };
  if (Buffer.byteLength(JSON.stringify(clean)) > LIMITS.docBytes) fail('This pad is too large to save.');
  return clean;
}

// Spreadsheet column names: A..Z, AA..AZ (at most sheetCols of them).
const columnIndex = letters => [...letters].reduce((n, ch) => n * 26 + ch.charCodeAt(0) - 64, 0) - 1;

// Rebuild a spreadsheet from whitelisted fields: its size, the cells that hold
// something (the text typed, or a formula starting with "="; bold, italic and
// alignment) and any changed column widths.
export function cleanSheet(doc) {
  if (!doc || typeof doc !== 'object' || Array.isArray(doc)) fail('Invalid spreadsheet.');
  const size = (value, max, label) => {
    if (!Number.isInteger(value) || value < 1 || value > max) fail(`A spreadsheet can have 1–${max} ${label}.`);
    return value;
  };
  const rows = size(doc.rows, LIMITS.sheetRows, 'rows'), cols = size(doc.cols, LIMITS.sheetCols, 'columns');
  const given = doc.cells ?? {};
  if (typeof given !== 'object' || Array.isArray(given)) fail('Invalid spreadsheet.');
  const keys = Object.keys(given);
  if (keys.length > LIMITS.sheetCells) fail(`A spreadsheet can hold up to ${LIMITS.sheetCells} filled cells.`);
  const cells = {};
  for (const key of keys) {
    const m = /^([A-Z]{1,2})([1-9][0-9]{0,3})$/.exec(key);
    const cell = given[key];
    if (!m || !cell || typeof cell !== 'object' || Array.isArray(cell) || columnIndex(m[1]) >= cols || Number(m[2]) > rows) fail('Invalid spreadsheet cell.');
    const clean = {};
    if (cell.v !== undefined) {
      if (typeof cell.v !== 'string' || cell.v.length > LIMITS.sheetCellChars) fail(`A cell can hold up to ${LIMITS.sheetCellChars} characters.`);
      if (cell.v) clean.v = cell.v;
    }
    for (const flag of ['b', 'i']) {
      if (cell[flag] === undefined) continue;
      if (cell[flag] !== true) fail('Invalid spreadsheet cell.');
      clean[flag] = true;
    }
    if (cell.a !== undefined) {
      if (!['l', 'c', 'r'].includes(cell.a)) fail('Invalid spreadsheet cell.');
      clean.a = cell.a;
    }
    if (Object.keys(clean).length) cells[key] = clean;
  }
  const widths = {};
  const givenWidths = doc.widths ?? {};
  if (typeof givenWidths !== 'object' || Array.isArray(givenWidths)) fail('Invalid spreadsheet.');
  for (const [letters, width] of Object.entries(givenWidths)) {
    if (!/^[A-Z]{1,2}$/.test(letters) || columnIndex(letters) >= cols) fail('Invalid column width.');
    widths[letters] = num(width, LIMITS.sheetColWidth[0], LIMITS.sheetColWidth[1], 'column width');
  }
  const rules = doc.rules === undefined ? [] : cleanSheetRules(doc.rules, rows, cols);
  const clean = { version: 1, rows, cols, cells, ...(Object.keys(widths).length ? { widths } : {}), ...(doc.settings === undefined ? {} : { settings: cleanSheetSettings(doc.settings) }), ...(rules.length ? { rules } : {}) };
  if (Buffer.byteLength(JSON.stringify(clean)) > LIMITS.docBytes) fail('This spreadsheet is too large to save.');
  return clean;
}

function imageBytes(value) {
  if (typeof value !== 'string' || !value || value.length > Math.ceil(LIMITS.imageBytes * 4 / 3) + 8) fail('Images must be under 3 MB.');
  const data = Buffer.from(value, 'base64');
  if (!data.length || data.length > LIMITS.imageBytes) fail('Images must be under 3 MB.');
  const png = data.length > 8 && data.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]));
  const jpeg = data.length > 3 && data[0] === 0xff && data[1] === 0xd8 && data[2] === 0xff;
  if (!png && !jpeg) fail('Only PNG and JPEG images are supported.');
  return { data, mime: png ? 'image/png' : 'image/jpeg' };
}

const DOCUMENT_COLUMNS = 'id,name,description,kind,folder_id,updated_at';

export function padsHandler(pool) {
  return async (request, reply) => {
    const b = request.body || {}, owner = request.userProfile.id;
    let db;
    try {
      const actions = ['listPads', 'createPad', 'renamePad', 'updatePad', 'movePad', 'deletePad', 'getPad', 'savePad', 'uploadImage', 'getImage',
        'listFolders', 'createFolder', 'renameFolder', 'moveFolder', 'deleteFolder'];
      if (!actions.includes(b.action)) fail('Unknown document action.');
      db = await pool.connect();
      await db.query('BEGIN');
      let result;
      // A folder of this owner, or null when no folder is given (the top level).
      const ownedFolder = async value => {
        if (value === undefined || value === null) return null;
        if (!uuid(value)) fail('Invalid folder.');
        const row = (await db.query('SELECT id,parent_id FROM public.pad_folders WHERE id=$1 AND owner_id=$2', [value, owner])).rows[0];
        if (!row) fail('Folder not found.', 404);
        return row;
      };
      if (b.action === 'listPads') {
        result = { pads: (await db.query(`SELECT ${DOCUMENT_COLUMNS} FROM public.pads WHERE owner_id=$1 ORDER BY created_at,id`, [owner])).rows };
      } else if (b.action === 'listFolders') {
        result = { folders: (await db.query('SELECT id,name,parent_id FROM public.pad_folders WHERE owner_id=$1 ORDER BY lower(name),created_at,id', [owner])).rows };
      } else if (b.action === 'createFolder') {
        const folderName = name(b.name);
        await db.query('SELECT id FROM public.users WHERE id=$1 FOR UPDATE', [owner]);
        const parent = await ownedFolder(b.parentId);
        const count = await db.query('SELECT count(*)::int AS count FROM public.pad_folders WHERE owner_id=$1', [owner]);
        if (count.rows[0].count >= LIMITS.folders) fail(`You can create up to ${LIMITS.folders} folders.`);
        let depth = 1, ancestor = parent?.id;
        while (ancestor) {
          depth++;
          ancestor = (await db.query('SELECT parent_id FROM public.pad_folders WHERE id=$1', [ancestor])).rows[0]?.parent_id;
        }
        if (depth > LIMITS.folderDepth) fail(`Folders can be nested up to ${LIMITS.folderDepth} levels deep.`);
        result = { folder: (await db.query('INSERT INTO public.pad_folders(owner_id,parent_id,name) VALUES($1,$2,$3) RETURNING id,name,parent_id', [owner, parent?.id ?? null, folderName])).rows[0] };
      } else if (b.action === 'moveFolder') {
        // No parent (or null) moves the folder to the top level.
        if (!uuid(b.folderId)) fail('Invalid folder.');
        const folder = await ownedFolder(b.folderId);
        const parent = await ownedFolder(b.parentId);
        const all = (await db.query('SELECT id,parent_id FROM public.pad_folders WHERE owner_id=$1', [owner])).rows;
        const byId = new Map(all.map(f => [f.id, f]));
        const ancestors = start => {
          const chain = [];
          for (let id = start; id && chain.length < 100; id = byId.get(id)?.parent_id) chain.push(id);
          return chain;
        };
        const above = ancestors(parent?.id);
        if (above.includes(folder.id)) fail('A folder cannot be moved into one of its own folders.');
        const height = (id, guard = 0) => 1 + Math.max(0, ...all.filter(f => f.parent_id === id && guard < 100).map(f => height(f.id, guard + 1)));
        if (above.length + height(folder.id) > LIMITS.folderDepth) fail(`Folders can be nested up to ${LIMITS.folderDepth} levels deep.`);
        result = { folder: (await db.query('UPDATE public.pad_folders SET parent_id=$1 WHERE id=$2 RETURNING id,name,parent_id', [parent?.id ?? null, folder.id])).rows[0] };
      } else if (b.action === 'renameFolder' || b.action === 'deleteFolder') {
        if (!uuid(b.folderId)) fail('Invalid folder.');
        const folder = await ownedFolder(b.folderId);
        if (b.action === 'renameFolder') {
          result = { folder: (await db.query('UPDATE public.pad_folders SET name=$1 WHERE id=$2 RETURNING id,name,parent_id', [name(b.name), folder.id])).rows[0] };
        } else {
          // Everything inside (sub-folders and documents) is deleted with it.
          await db.query('DELETE FROM public.pad_folders WHERE id=$1', [folder.id]);
          result = { deleted: true };
        }
      } else if (b.action === 'createPad') {
        const padName = name(b.name);
        const padDescription = b.description === undefined ? '' : description(b.description);
        const kind = b.kind === undefined ? 'pad' : b.kind;
        if (!KINDS.includes(kind)) fail('Unknown document type.');
        await db.query('SELECT id FROM public.users WHERE id=$1 FOR UPDATE', [owner]);
        const folder = await ownedFolder(b.folderId);
        const count = await db.query('SELECT count(*)::int AS count FROM public.pads WHERE owner_id=$1', [owner]);
        if (count.rows[0].count >= LIMITS.documents) fail(`You can create up to ${LIMITS.documents} documents.`);
        const doc = kind === 'gantt' ? { version: 1 } : kind === 'notepad' ? { version: 1, text: '' } : kind === 'sheet' ? { version: 1, rows: 50, cols: 12, cells: {} } : { version: 1, elements: [] };
        result = { pad: (await db.query(`INSERT INTO public.pads(owner_id,name,description,kind,folder_id,doc) VALUES($1,$2,$3,$4,$5,$6::jsonb) RETURNING ${DOCUMENT_COLUMNS},doc`, [owner, padName, padDescription, kind, folder?.id ?? null, JSON.stringify(doc)])).rows[0] };
      } else {
        if (!uuid(b.padId)) fail('Invalid document.');
        const pad = (await db.query('SELECT id,name,description,kind,folder_id,doc,updated_at FROM public.pads WHERE id=$1 AND owner_id=$2 FOR UPDATE', [b.padId, owner])).rows[0];
        if (!pad) fail('Document not found.', 404);
        if (b.action === 'getPad') {
          result = { pad };
        } else if (b.action === 'renamePad') {
          await db.query('UPDATE public.pads SET name=$1,updated_at=now() WHERE id=$2', [name(b.name), pad.id]);
          result = { saved: true };
        } else if (b.action === 'updatePad') {
          // The description is optional: leaving it out keeps the current one.
          const next = b.description === undefined ? pad.description : description(b.description);
          result = { pad: (await db.query(`UPDATE public.pads SET name=$1,description=$2,updated_at=now() WHERE id=$3 RETURNING ${DOCUMENT_COLUMNS}`, [name(b.name), next, pad.id])).rows[0] };
        } else if (b.action === 'movePad') {
          // No folder (or null) moves the document to the top level.
          const folder = await ownedFolder(b.folderId);
          result = { pad: (await db.query(`UPDATE public.pads SET folder_id=$1 WHERE id=$2 RETURNING ${DOCUMENT_COLUMNS}`, [folder?.id ?? null, pad.id])).rows[0] };
        } else if (b.action === 'deletePad') {
          await db.query('DELETE FROM public.pads WHERE id=$1', [pad.id]);
          result = { deleted: true };
        } else if (b.action === 'savePad') {
          if (pad.kind === 'gantt') fail('A Gantt calendar keeps its phases on its own.');
          if (pad.kind === 'sheet') {
            const sheet = cleanSheet(b.doc);
            const saved = (await db.query('UPDATE public.pads SET doc=$1::jsonb,updated_at=now() WHERE id=$2 RETURNING updated_at', [JSON.stringify(sheet), pad.id])).rows[0];
            result = { saved: true, updated_at: saved.updated_at };
          } else if (pad.kind === 'notepad') {
            const note = cleanNote(b.doc);
            const imageIds = noteImageIds(note.runs);
            if (imageIds.length) {
              const known = (await db.query('SELECT id FROM public.pad_images WHERE pad_id=$1 AND id=ANY($2::uuid[])', [pad.id, imageIds])).rows.map(r => r.id);
              if (imageIds.some(id => !known.includes(id))) fail('A picture in this note could not be found. Remove it and add it again.');
            }
            const saved = (await db.query('UPDATE public.pads SET doc=$1::jsonb,updated_at=now() WHERE id=$2 RETURNING updated_at', [JSON.stringify(note), pad.id])).rows[0];
            await db.query("DELETE FROM public.pad_images WHERE pad_id=$1 AND created_at < now() - interval '1 hour' AND NOT (id=ANY($2::uuid[]))", [pad.id, imageIds]);
            result = { saved: true, updated_at: saved.updated_at };
          } else {
            const doc = cleanDoc(b.doc);
            const imageIds = [...new Set(doc.elements.filter(e => e.type === 'image').map(e => e.imageId))];
            if (imageIds.length) {
              const known = (await db.query('SELECT id FROM public.pad_images WHERE pad_id=$1 AND id=ANY($2::uuid[])', [pad.id, imageIds])).rows.map(r => r.id);
              if (imageIds.some(id => !known.includes(id))) fail('A picture on this pad could not be found. Remove it and add it again.');
            }
            const saved = (await db.query('UPDATE public.pads SET doc=$1::jsonb,updated_at=now() WHERE id=$2 RETURNING updated_at', [JSON.stringify(doc), pad.id])).rows[0];
            // Drop images no longer on the pad (recent uploads are kept so undo still works).
            await db.query("DELETE FROM public.pad_images WHERE pad_id=$1 AND created_at < now() - interval '1 hour' AND NOT (id=ANY($2::uuid[]))", [pad.id, imageIds]);
            result = { saved: true, updated_at: saved.updated_at };
          }
        } else {
          if (pad.kind === 'sheet') fail('Spreadsheets cannot hold pictures.');
          if (pad.kind === 'gantt') fail('Gantt calendars cannot hold pictures.');
          if (b.action === 'uploadImage') {
            const { data, mime } = imageBytes(b.image);
            const count = await db.query('SELECT count(*)::int AS count FROM public.pad_images WHERE pad_id=$1', [pad.id]);
            if (count.rows[0].count >= LIMITS.imagesPerPad) fail(`A document can hold up to ${LIMITS.imagesPerPad} pictures.`);
            result = { imageId: (await db.query('INSERT INTO public.pad_images(pad_id,owner_id,mime,data) VALUES($1,$2,$3,$4) RETURNING id', [pad.id, owner, mime, data])).rows[0].id };
          } else {
            if (!uuid(b.imageId)) fail('Invalid image.');
            const image = (await db.query('SELECT mime,data FROM public.pad_images WHERE id=$1 AND pad_id=$2', [b.imageId, pad.id])).rows[0];
            if (!image) fail('Image not found.', 404);
            result = { mime: image.mime, image: image.data.toString('base64') };
          }
        }
      }
      await db.query('COMMIT');
      return result;
    } catch (error) {
      if (db) await db.query('ROLLBACK').catch(() => {});
      if (error.publicMessage) return reply.code(error.statusCode).send({ error: error.publicMessage });
      request.log.error({ errorCode: error.code || 'PADS_FAILED' }, 'Document request failed');
      return reply.code(503).send({ error: 'Documents are unavailable. Please try again.' });
    } finally {
      db?.release();
    }
  };
}
