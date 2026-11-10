import test from 'node:test';
import assert from 'node:assert/strict';
import {padsHandler} from '../src/pads.js';
import {addUser, call, makeDb} from './helpers/pglite.js';

const PNG = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSUAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

test('a picture in a note keeps the width it was resized to', async () => {
  const {pool} = await makeDb();
  const owner = await addUser(pool, 'owner');
  const pads = padsHandler(pool);
  const send = body => call(pads, body, owner);
  const pad = (await send({action: 'createPad', name: 'Pictures', kind: 'notepad'})).body.pad;
  const imageId = (await send({action: 'uploadImage', padId: pad.id, image: PNG})).body.imageId;
  const note = width => ({version: 1, text: `a￼b`, runs: [{start: 1, end: 2, embed: {type: 'image', imageId, ...(width === undefined ? {} : {width})}}]});

  assert.equal((await send({action: 'savePad', padId: pad.id, doc: note(212.46)})).status, 200);
  let saved = (await send({action: 'getPad', padId: pad.id})).body.pad.doc;
  assert.equal(saved.runs[0].embed.width, 212.5, 'kept, to a tenth of a pixel');
  assert.equal(saved.runs[0].embed.imageId, imageId);

  // A picture that was never resized has no width.
  await send({action: 'savePad', padId: pad.id, doc: note()});
  saved = (await send({action: 'getPad', padId: pad.id})).body.pad.doc;
  assert.equal('width' in saved.runs[0].embed, false);

  for (const bad of [5, 4001, -20, 'wide', NaN, null, {}]) {
    assert.equal((await send({action: 'savePad', padId: pad.id, doc: note(bad)})).status, 400, String(bad));
  }
});
