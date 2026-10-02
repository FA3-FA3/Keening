// One-off import of the university timetable into a user's Schedule.
// Usage: DATABASE_URL=... node import-university-timetable.mjs <owner-uuid|--first-user> [--apply]
// Without --apply it only prints what it would add.
import {randomUUID} from 'node:crypto';
import {createRequire} from 'node:module';
const {Client} = createRequire(import.meta.url)('../cloud-run/node_modules/pg');

const TAG = 'University Course', COLOR = '#2563EB';
const FIRST_DAY = '2026-10-02'; // the export starts on this date
const WEEK1 = Date.UTC(2026, 8, 28); // Monday of week 1
const DAY = {Mon: 0, Tue: 1, Wed: 2, Thu: 3, Fri: 4};
const ALL = [[1, 11], [15, 15]], W = [[1, 11], [15, 15]];
// [title, day, start, end, location, week ranges]
const T = [
  ['CM52052A-Leca Applied Data Science', 'Mon', '10:15', '11:05', '6W 1.1 (112)', W],
  ['CM52055-Comp lab Analytic Software Technologies', 'Mon', '12:15', '14:05', 'CB 5.13 [GTA Comp Rm] (100)', W],
  ['CM52059-Leca Understanding Deep Learning', 'Mon', '15:15', '16:05', '5W 2.4 (112)', W],
  ['CM52055-Leca Analytic Software Technologies', 'Tue', '10:15', '11:05', '6W 1.2 (110)', W],
  ['CM52058-Leca Statistical Data Science', 'Tue', '12:15', '14:05', '3WN 3.8 (36)', W],
  ['CM52055-Lecb Analytic Software Technologies', 'Wed', '10:15', '11:05', '3E 3.5 (90)', W],
  ['CM52058-Comp lab Statistical Data Science', 'Wed', '11:15', '13:05', 'EB 0.9  [Comp Rm] (40)', W],
  ['CM52054A-Comp lab Foundational Machine Learning', 'Wed', '13:15', '15:05', 'Library Level 4 GTA PC area (100)', W],
  ['CM52059-Comp lab Understanding Deep Learning', 'Wed', '15:15', '17:05', 'CB 4.17  [GTA Comp Rm] (100)', [[2, 11], [15, 15]]],
  ['CM52059-Lecb Understanding Deep Learning', 'Thu', '10:15', '11:05', '6W 1.1 (112)', [[1, 5], [7, 11], [15, 15]]],
  ['CM-PG Placement Development S1', 'Fri', '10:15', '11:05', '3E 2.1 (133)', [[1, 9]]],
  ['CM-PG DoS Variable Session S1', 'Fri', '12:15', '13:05', '5W 2.4 (112)', [[1, 11]]],
  ['CM52052A-Lecb Applied Data Science', 'Fri', '13:15', '14:05', '6W 1.1 (112)', W],
  ['CM52054A-Leca Foundational Machine Learning', 'Fri', '14:15', '15:05', '6W 1.1 (112)', W],
  ['CM52054A-Lecb Foundational Machine Learning', 'Fri', '15:15', '16:05', '6W 1.1 (112)', [[1, 5], [7, 11], [15, 15]]],
];
const sessions = [];
for (const [title, day, start, end, location, ranges] of T)
  for (const [from, to] of ranges)
    for (let week = from; week <= to; week++) {
      const date = new Date(WEEK1 + ((week - 1) * 7 + DAY[day]) * 864e5).toISOString().slice(0, 10);
      if (date >= FIRST_DAY) sessions.push({title, date, start, end, location: location.replace(/\s*\([^)]*\)/g, '').trim()});
    }
sessions.sort((a, b) => a.date.localeCompare(b.date) || a.start.localeCompare(b.start));

const [owner, flag] = process.argv.slice(2);
const apply = flag === '--apply';
const client = new Client({connectionString: process.env.DATABASE_URL});
await client.connect();
try {
  const id = owner === '--first-user' ? (await client.query('SELECT id FROM public.users ORDER BY created_at LIMIT 1')).rows[0]?.id : owner;
  if (!id) throw new Error('No owner found');
  await client.query('BEGIN');
  await client.query('INSERT INTO public.schedules(owner_id) VALUES($1) ON CONFLICT DO NOTHING', [id]);
  const data = (await client.query('SELECT data FROM public.schedules WHERE owner_id=$1 FOR UPDATE', [id])).rows[0].data;
  data.tagDefinitions ??= [];
  let tag = data.tagDefinitions.find(t => t.name.toLowerCase() === TAG.toLowerCase());
  if (!tag) data.tagDefinitions.push(tag = {id: randomUUID(), name: TAG, color: COLOR});
  const key = b => `${b.date}|${b.start}|${b.title}`;
  const byKey = new Map(data.blocks.map(b => [key(b), b]));
  const seen = new Set(byKey.keys());
  let relocated = 0;
  for (const s of sessions) {
    const b = byKey.get(key(s));
    if (b && b.location !== s.location) { b.location = s.location; relocated++; }
  }
  const fresh = sessions.filter(s => !seen.has(`${s.date}|${s.start}|${s.title}`));
  for (const s of fresh) data.blocks.push({id: randomUUID(), ...s, end: s.end, note: '', color: tag.color, tagId: tag.id});
  console.log(`${sessions.length} timetable sessions, ${sessions.length - fresh.length} already present (${relocated} locations updated), ${fresh.length} to add. Range ${sessions[0].date} → ${sessions.at(-1).date}. Tag "${tag.name}". Owner ${id}.`);
  if (data.blocks.length > 5000) throw new Error('Would exceed 5000 sessions');
  if (apply) {
    await client.query('UPDATE public.schedules SET data=$1::jsonb, updated_at=now() WHERE owner_id=$2', [JSON.stringify(data), id]);
    await client.query('COMMIT');
    console.log('Applied.');
  } else {
    await client.query('ROLLBACK');
    console.log('Dry run only; nothing written.');
  }
} catch (e) { await client.query('ROLLBACK').catch(() => {}); throw e; } finally { await client.end(); }
