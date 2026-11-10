import test from 'node:test';
import assert from 'node:assert/strict';
import {padsHandler} from '../src/pads.js';
import {addUser, call, makeDb} from './helpers/pglite.js';

test('a note keeps the text colour and size set for it', async () => {
  const {pool} = await makeDb();
  const owner = await addUser(pool, 'owner');
  const pads = padsHandler(pool);
  const send = body => call(pads, body, owner);
  const pad = (await send({action: 'createPad', name: 'Note', kind: 'notepad'})).body.pad;
  const save = settings => send({action: 'savePad', padId: pad.id, doc: {version: 1, text: 'hi', settings}});
  const saved = async () => (await send({action: 'getPad', padId: pad.id})).body.pad.doc.settings;

  assert.equal((await save({pages: true, background: '#1F2937', textColour: '#86efac', textSize: 24})).status, 200);
  assert.deepEqual(await saved(), {pages: true, background: '#1F2937', textColour: '#86EFAC', textSize: 24});
  // Automatic colour and the usual size are simply left out.
  assert.equal((await save({pages: true, background: '#FFFFFF'})).status, 200);
  assert.deepEqual(await saved(), {pages: true, background: '#FFFFFF'});
  assert.equal((await save({pages: true, background: '#FFFFFF', textColour: null})).status, 200);
  for (const bad of [{textColour: 'red'}, {textColour: 5}, {textSize: 7}, {textSize: 73}, {textSize: 'big'}, {textSize: null}]) {
    assert.equal((await save({pages: true, background: '#FFFFFF', ...bad})).status, 400, JSON.stringify(bad));
  }
});
