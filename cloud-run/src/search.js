export function searchHandler(pool) {
  return async (request, reply) => {
    const {query, offset = 0} = request.body ?? {};
    if (typeof query !== 'string' || !query.trim() || query.length > 200 || !Number.isInteger(offset) || offset < 0) {
      return reply.code(400).send({error: 'Enter a search of 1–200 characters.'});
    }
    const owner = request.userProfile.id;
    try {
      const [gantt, phases, events, boards, schedules, calendarTags] = await Promise.all([
        pool.query('SELECT id, name FROM public.gantt_calendars WHERE owner_id=$1', [owner]),
        pool.query('SELECT i.*, i.start_date::text AS date, c.name AS parent FROM public.gantt_items i JOIN public.gantt_calendars c ON c.id=i.calendar_id WHERE c.owner_id=$1', [owner]),
        pool.query('SELECT i.*, i.start_date::text AS date FROM public.calendar_events i JOIN public.calendar_collections c ON c.id=i.calendar_id WHERE c.owner_id=$1', [owner]),
        pool.query('SELECT id, name, board FROM public.board_workplaces WHERE owner_id=$1', [owner]),
        pool.query('SELECT data FROM public.schedules WHERE owner_id=$1', [owner]),
        pool.query('SELECT tags FROM public.calendar_tags WHERE owner_id=$1', [owner]),
      ]);
      const all = [];
      const add = (type, page, item, extra = {}) => all.push({type, page, id: item.id, title: item.title ?? item.name, description: item.description ?? item.note ?? '', location: item.location ?? '', date: item.date ?? '', completed: item.completed === true, archived: item.archived === true, ...extra});
      for (const c of gantt.rows) add('Gantt calendar', 'Gantt', c, {parentId: c.id});
      for (const p of phases.rows) add('Phase', 'Gantt', p, {parentId: p.calendar_id, parent: p.parent});
      const eventTags = calendarTags.rows[0]?.tags ?? [];
      for (const e of events.rows) add('Event', 'Calendar', e, {parentId: e.calendar_id, tags: eventTags.filter(t => t.id === e.tag_id).map(t => t.name).join(' ')});
      for (const w of boards.rows) {
        add('Board', 'Boards', w, {parentId: w.id});
        for (const p of w.board.columns ?? []) add('Panel', 'Boards', p, {parentId: w.id, parent: w.name});
        for (const t of w.board.tasks ?? []) add('Task', 'Boards', t, {parentId: w.id, parent: [w.name, w.board.columns.find(c => c.id === t.column_id)?.name].filter(Boolean).join(' / '), tags: (w.board.tags ?? []).filter(tag => (t.tag_ids ?? []).includes(tag.id)).map(tag => tag.name).join(' ')});
      }
      const schedule = schedules.rows[0]?.data;
      for (const s of schedule?.blocks ?? []) add('Session', 'Schedule', s, {time: `${s.start}–${s.end}`, tags: (schedule.tagDefinitions ?? []).filter(t => t.id === s.tagId).map(t => t.name).join(' ')});
      const terms = query.trim().toLocaleLowerCase().split(/\s+/);
      const matches = all.filter(item => {
        const text = [item.title, item.description, item.location, item.parent, item.tags, item.date, item.type].filter(Boolean).join(' ').toLocaleLowerCase();
        return terms.every(term => text.includes(term));
      }).sort((a,b) => Number(!a.title.toLocaleLowerCase().includes(query.trim().toLocaleLowerCase())) - Number(!b.title.toLocaleLowerCase().includes(query.trim().toLocaleLowerCase())) || a.title.localeCompare(b.title) || a.type.localeCompare(b.type) || a.id.localeCompare(b.id));
      return {results: matches.slice(offset, offset + 50), total: matches.length};
    } catch (error) {
      request.log.error({errorCode: error.code ?? 'SEARCH_FAILED'}, 'Search failed');
      return reply.code(503).send({error: 'Search is unavailable. Please try again.'});
    }
  };
}
