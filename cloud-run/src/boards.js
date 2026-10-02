import { randomUUID } from 'node:crypto';

const fail = (message, statusCode = 400) => { throw Object.assign(new Error(message), { publicMessage: message, statusCode }); };
const idValid = id => typeof id === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(id);
function label(value, max = 100) {
  if (typeof value !== 'string' || !value.trim() || value.trim().length > max) fail(`Enter a name of 1–${max} characters.`);
  return value.trim();
}
function colour(value) {
  if (value == null || value === '') return null;
  if (typeof value !== 'string' || !/^#[a-f0-9]{6}$/i.test(value)) fail('Invalid colour.');
  return value;
}
function description(value) {
  if (typeof value !== 'string' || value.length > 5000) fail('Description must be at most 5000 characters.');
  return value;
}
function find(list, id) {
  const value = list.find(entry => entry.id === id);
  if (!value) fail('Board item not found.',404);
  return value;
}
function ids(value, allowed) {
  if (!Array.isArray(value) || value.length > 500 || new Set(value).size !== value.length || value.some(id => !allowed.some(entry => entry.id === id))) fail('Items must belong to this workplace.');
  return value;
}

export function boardsHandler(pool) {
  return async (request, reply) => {
    const b = request.body || {}, owner = request.userProfile.id;
    let db;
    try {
      db = await pool.connect();
      await db.query('BEGIN');
      let result;
      if (b.action === 'listWorkplaces') {
        result = { workplaces: (await db.query('SELECT id,name FROM public.board_workplaces WHERE owner_id=$1 ORDER BY created_at,id',[owner])).rows };
      } else if (b.action === 'createWorkplace') {
        const name = label(b.name);
        await db.query('SELECT id FROM public.users WHERE id=$1 FOR UPDATE',[owner]);
        const count = await db.query('SELECT count(*)::int AS count FROM public.board_workplaces WHERE owner_id=$1',[owner]);
        if (count.rows[0].count >= 100) fail('You can create up to 100 workplaces.');
        result = { workplace: (await db.query('INSERT INTO public.board_workplaces(owner_id,name) VALUES($1,$2) RETURNING id,name',[owner,name])).rows[0] };
      } else {
        if (!idValid(b.workplaceId)) fail('Invalid workplace.');
        // Serialize changes to the board so concurrent independent edits are retained.
        const row = (await db.query('SELECT board FROM public.board_workplaces WHERE id=$1 AND owner_id=$2 FOR UPDATE',[b.workplaceId,owner])).rows[0];
        if (!row) fail('Workplace not found.',404);
        const board = row.board;
        const {columns,tasks,tags} = board;
        const stamp = new Date().toISOString();
        const taskView = task => ({...task,tags:tags.filter(tag => task.tag_ids.includes(tag.id)),owner_first_name:request.userProfile.username || '',owner_last_name:''});
        let changed = false;
        switch (b.action) {
          case 'getBoard': result={columns,tags,tasks:tasks.map(taskView)};break;
          case 'renameWorkplace':
            await db.query('UPDATE public.board_workplaces SET name=$1,updated_at=now() WHERE id=$2',[label(b.name),b.workplaceId]);result={saved:true};break;
          case 'deleteWorkplace':
            await db.query('DELETE FROM public.board_workplaces WHERE id=$1',[b.workplaceId]);result={deleted:true};break;
          case 'listTaskColumns': result={columns,can_manage:true};break;
          case 'listTaskTags': result={tags};break;
          case 'listOrgTasks':
            if (b.archived != null && typeof b.archived !== 'boolean') fail('Invalid archive filter.');
            result={tasks:tasks.filter(task => task.archived === (b.archived ?? false)).map(taskView)};break;
          case 'reorderTaskColumns': {
            const order=ids(b.columnIds,columns);
            if(order.length!==columns.length)fail('The panels changed. Refresh and try again.',409);
            board.columns=order.map(id=>find(columns,id));
            result={saved:true};changed=true;break;
          }
          case 'createTaskColumn': {
            if(columns.length>=50) fail('A workplace can have up to 50 panels.');
            const column={id:randomUUID(),name:label(b.name),color:colour(b.color),created_at:stamp,updated_at:stamp};
            columns.push(column);result={column};changed=true;break;
          }
          case 'updateTaskColumn': {
            const column=find(columns,b.columnId);
            if(b.name!==undefined)column.name=label(b.name);
            if(b.color!==undefined)column.color=colour(b.color);
            column.updated_at=stamp;result={column};changed=true;break;
          }
          case 'deleteTaskColumn':
            find(columns,b.columnId);
            board.columns=columns.filter(c=>c.id!==b.columnId);
            board.tasks=tasks.filter(t=>t.column_id!==b.columnId);
            result={deleted:true};changed=true;break;
          case 'createTaskTag': {
            if(tags.length>=100) fail('A workplace can have up to 100 tags.');
            const tag={id:randomUUID(),name:label(b.name,50),color:colour(b.color)};
            tags.push(tag);result={tag};changed=true;break;
          }
          case 'deleteTaskTag':
            find(tags,b.tagId);board.tags=tags.filter(tag=>tag.id!==b.tagId);
            for(const task of tasks)task.tag_ids=task.tag_ids.filter(id=>id!==b.tagId);
            result={deleted:true};changed=true;break;
          case 'setTaskTags': {
            const task=find(tasks,b.taskId);task.tag_ids=ids(b.tagIds,tags);task.updated_at=stamp;
            result={task:taskView(task)};changed=true;break;
          }
          case 'createOrgTask': {
            if(tasks.length>=500) fail('A workplace can have up to 500 tasks, including archived tasks.');
            find(columns,b.columnId);
            if(b.completed!==undefined && typeof b.completed!=='boolean')fail('Invalid task status.');
            const task={id:randomUUID(),column_id:b.columnId,title:label(b.title,200),description:description(b.description??''),color:colour(b.color),tag_ids:ids(b.tagIds??[],tags),completed:b.completed??false,archived:false,created_at:stamp,updated_at:stamp};
            tasks.push(task);result={task:taskView(task)};changed=true;break;
          }
          case 'updateOrgTask': {
            const task=find(tasks,b.taskId);
            if(b.title!==undefined)task.title=label(b.title,200);
            if(b.description!==undefined)task.description=description(b.description);
            if(b.color!==undefined)task.color=colour(b.color);
            if(b.tagIds!==undefined)task.tag_ids=ids(b.tagIds,tags);
            for(const key of ['completed','archived'])if(b[key]!==undefined){if(typeof b[key]!=='boolean')fail('Invalid task status.');task[key]=b[key];}
            task.updated_at=stamp;result={task:taskView(task)};changed=true;break;
          }
          case 'deleteOrgTask':
            find(tasks,b.taskId);board.tasks=tasks.filter(t=>t.id!==b.taskId);result={deleted:true};changed=true;break;
          case 'reorderOrgTasks': {
            find(columns,b.columnId);
            const order=ids(b.taskIds,tasks);
            if(order.some(id=>find(tasks,id).archived))fail('Archived tasks must be restored before moving.');
            if(tasks.some(t=>t.column_id===b.columnId&&!t.archived&&!order.includes(t.id)))fail('The panel changed. Refresh and try again.',409);
            const moved=order.map(id=>find(tasks,id));
            for(const task of moved){task.column_id=b.columnId;task.updated_at=stamp;}
            board.tasks=[...tasks.filter(t=>!order.includes(t.id)),...moved];result={saved:true};changed=true;break;
          }
          default: fail('Unknown board action.');
        }
        if(changed)await db.query('UPDATE public.board_workplaces SET board=$1::jsonb,updated_at=now() WHERE id=$2',[JSON.stringify(board),b.workplaceId]);
      }
      await db.query('COMMIT');return result;
    } catch(error) {
      if(db)await db.query('ROLLBACK').catch(()=>{});
      if(error.publicMessage)return reply.code(error.statusCode).send({error:error.publicMessage});
      request.log.error({errorCode:error.code||'BOARDS_FAILED'},'Board request failed');
      return reply.code(503).send({error:'Boards are unavailable. Please try again.'});
    } finally { db?.release(); }
  };
}
