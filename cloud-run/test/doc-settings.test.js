import test from 'node:test';
import assert from 'node:assert/strict';
import {cleanNote, cleanSheet} from '../src/pads.js';

test('a note keeps its settings, rebuilt from whitelisted fields', () => {
  assert.equal(cleanNote({text: 'Hi'}).settings, undefined, 'untouched notes store none');
  assert.deepEqual(
    cleanNote({text: 'Hi', settings: {pages: false, background: '#e3f2fd', evil: 1}}).settings,
    {pages: false, background: '#E3F2FD'},
  );
  assert.deepEqual(cleanNote({text: 'Hi', settings: {pages: true, background: '#000000'}}).settings, {pages: true, background: '#000000'});
  for (const bad of [null, [], 'x', 5, {}, {pages: 'yes', background: '#ffffff'}, {pages: true}, {pages: true, background: 'white'}, {pages: true, background: '#fff'}, {background: '#ffffff'}])
    assert.throws(() => cleanNote({text: 'Hi', settings: bad}), /./, JSON.stringify(bad));
});

test('a spreadsheet keeps its settings, validated', () => {
  const base = {rows: 5, cols: 5, cells: {}};
  assert.equal(cleanSheet(base).settings, undefined, 'untouched sheets store none');
  assert.deepEqual(
    cleanSheet({...base, settings: {gridlines: false, headers: true, colWidth: 150.456, evil: 1}}).settings,
    {gridlines: false, headers: true, colWidth: 150.46},
  );
  assert.equal(cleanSheet({...base, settings: {gridlines: true, headers: false, colWidth: 40}}).settings.colWidth, 40);
  assert.equal(cleanSheet({...base, settings: {gridlines: true, headers: false, colWidth: 600}}).settings.colWidth, 600);
  for (const bad of [null, [], 'x', {}, {gridlines: 'y', headers: true, colWidth: 100}, {gridlines: true, headers: 1, colWidth: 100},
    {gridlines: true, headers: true}, {gridlines: true, headers: true, colWidth: 39}, {gridlines: true, headers: true, colWidth: 601},
    {gridlines: true, headers: true, colWidth: '100'}])
    assert.throws(() => cleanSheet({...base, settings: bad}), /./, JSON.stringify(bad));
});
