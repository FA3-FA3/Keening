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

test('a spreadsheet keeps its conditional formatting rules, validated and rebuilt', () => {
  const base = {rows: 20, cols: 5, cells: {}};
  assert.equal(cleanSheet(base).rules, undefined, 'untouched sheets store none');
  assert.equal(cleanSheet({...base, rules: []}).rules, undefined);
  const rule = {r: 'A1:C10', c: 'gt', v: '10', bg: '#ffc7ce', fg: '#9c0006', evil: 1};
  assert.deepEqual(cleanSheet({...base, rules: [rule]}).rules, [{r: 'A1:C10', c: 'gt', v: '10', bg: '#FFC7CE', fg: '#9C0006'}]);
  assert.deepEqual(cleanSheet({...base, rules: [{r: 'B2', c: 'between', v: '1', v2: '5', b: true}]}).rules, [{r: 'B2', c: 'between', v: '1', v2: '5', b: true}]);
  assert.deepEqual(cleanSheet({...base, rules: [{r: 'A1:A5', c: 'empty', v: 'ignored', bg: '#ffffff'}]}).rules, [{r: 'A1:A5', c: 'empty', bg: '#FFFFFF'}]);
  const bad = [
    'x', {}, [null], [[]], [{}],
    [{r: 'F1', c: 'gt', v: '1', bg: '#ffffff'}], [{r: 'A21', c: 'gt', v: '1', bg: '#ffffff'}], [{r: 'A1:B2:C3', c: 'gt', v: '1', bg: '#ffffff'}],
    [{r: 'a1', c: 'gt', v: '1', bg: '#ffffff'}], [{r: 'A0', c: 'gt', v: '1', bg: '#ffffff'}], [{r: 5, c: 'gt', v: '1', bg: '#ffffff'}],
    [{r: 'A1', c: 'nope', v: '1', bg: '#ffffff'}], [{r: 'A1', c: '__proto__', v: '1', bg: '#ffffff'}], [{r: 'A1', c: 'toString', v: '1', bg: '#ffffff'}],
    [{r: 'A1', c: 'gt', bg: '#ffffff'}], [{r: 'A1', c: 'gt', v: 1, bg: '#ffffff'}], [{r: 'A1', c: 'between', v: '1', bg: '#ffffff'}],
    [{r: 'A1', c: 'gt', v: 'x'.repeat(201), bg: '#ffffff'}],
    [{r: 'A1', c: 'gt', v: '1', bg: 'red'}], [{r: 'A1', c: 'gt', v: '1', fg: '#fff'}], [{r: 'A1', c: 'gt', v: '1', b: false}],
    [{r: 'A1', c: 'gt', v: '1'}],
    Array.from({length: 51}, () => ({r: 'A1', c: 'empty', bg: '#ffffff'})),
  ];
  for (const rules of bad) assert.throws(() => cleanSheet({...base, rules}), /./, JSON.stringify(rules).slice(0, 80));
  assert.equal(cleanSheet({...base, rules: Array.from({length: 50}, () => ({r: 'A1', c: 'empty', bg: '#ffffff'}))}).rules.length, 50);
});
