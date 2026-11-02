import test from 'node:test';
import assert from 'node:assert/strict';
import {parse as referenceParse, createScanner, SyntaxKind} from 'jsonc-parser';
import {process as engine} from '../web/moonjsonc.mjs';

const run = request => JSON.parse(engine(JSON.stringify(request)));
const comments = source => {
  const scanner = createScanner(source), result = [];
  for (let kind = scanner.scan(); kind !== SyntaxKind.EOF; kind = scanner.scan()) {
    if (kind === SyntaxKind.LineCommentTrivia || kind === SyntaxKind.BlockCommentTrivia) {
      result.push(source.slice(scanner.getTokenOffset(), scanner.getTokenOffset() + scanner.getTokenLength()));
    }
  }
  return result;
};
function checked(request) {
  const result = run(request);
  assert.equal(result.ok, true, JSON.stringify({request, result}));
  const errors = [];
  const value = referenceParse(result.source, errors, {allowTrailingComma:true, allowEmptyContent:true});
  assert.deepEqual(errors, [], JSON.stringify({request, result, errors}));
  assert.equal(run({op:'parse', source:result.source, options:{allowEmpty:true}}).valid, true);
  assert.equal(run({op:'apply', source:request.source, edits:result.edits}).source, result.source);
  return {result, value};
}

const arrays = [
  '[1,2,3]',
  '[1,2,3,]',
  '[/*h*/1/*a*/,/*b*/2/*c*/,/*d*/3/*e*/,/*t*/]',
  '[1//a\n,2//b\n,3//c\n,//tail\n]',
  '[\r\n  1,\r\n  2,\r\n  3,\r\n]',
];
const objects = [
  '{"a":1,"b":2,"c":3}',
  '{"a":1,"b":2,"c":3,}',
  '{/*h*/"a":1/*a*/,/*b*/"b":2/*c*/,/*d*/"c":3/*e*/,/*t*/}',
  '{"a":1//a\n, "b":2//b\n, "c":3//c\n,//tail\n}',
];

test('adversarial removals preserve first middle last siblings and outside comments', () => {
  for (const source of arrays) {
    for (let index = 0; index < 3; index++) {
      const {result, value} = checked({op:'remove', source, path:[index]});
      assert.deepEqual(value, [1,2,3].filter((_, i) => i !== index));
      assert.deepEqual(comments(result.source), comments(source));
    }
  }
  for (const source of objects) {
    for (const key of ['a','b','c']) {
      const {result, value} = checked({op:'remove', source, path:[key]});
      const expected = {a:1,b:2,c:3};
      delete expected[key];
      assert.deepEqual(value, expected);
      assert.deepEqual(comments(result.source), comments(source));
    }
  }
  for (const source of ['[1,/*tail*/]', '[/*head*/1/*note*/]', '{"a":1,/*tail*/}', '{/*head*/"a":1/*note*/}']) {
    const path = source[0] === '[' ? [0] : ['a'];
    const {result, value} = checked({op:'remove', source, path});
    assert.deepEqual(value, source[0] === '[' ? [] : {});
    assert.deepEqual(comments(result.source), comments(source));
  }
});

test('adversarial insertions shift exactly one array position with trailing comments and commas', () => {
  for (const source of arrays) {
    for (let index = 0; index <= 3; index++) {
      const {result, value} = checked({op:'insert', source, path:[], index, value:'{"new":9}'});
      const expected = [1,2,3];
      expected.splice(index, 0, {new:9});
      assert.deepEqual(value, expected);
      assert.deepEqual(comments(result.source), comments(source));
    }
  }
});

test('adversarial comment-only empty containers accept their first member', () => {
  for (const source of ['{/* note , : { ] */}', '{\n//line\n}', '{\r\n /*😀*/\r\n}', '{/*x*/\n/*y*/}']) {
    const {result, value} = checked({op:'set', source, path:['new'], value:'[1,{"x":2}]'});
    assert.deepEqual(value, {new:[1,{x:2}]});
    assert.deepEqual(comments(result.source), comments(source));
  }
  for (const source of ['[/*note*/]', '[\n//line\n]', '[\r\n /*😀*/\r\n]']) {
    const {result, value} = checked({op:'insert', source, path:[], index:0, value:'[1,{"x":2}]'});
    assert.deepEqual(value, [[1,{x:2}]]);
    assert.deepEqual(comments(result.source), comments(source));
  }
});

test('adversarial root removal yields legal empty content and can be recreated in one transaction', () => {
  const source = '//head\r\n{"a":1} //tail';
  const empty = checked({op:'remove', source, path:[]});
  assert.equal(empty.value, undefined);
  assert.deepEqual(comments(empty.result.source), comments(source));
  const {result, value} = checked({op:'transaction', source, operations:[
    {op:'remove', path:[]},
    {op:'set', path:['created',0,'ok'], value:'true'},
    {op:'test', path:['created'], value:'[{"ok":true}]'},
  ]});
  assert.deepEqual(value, {created:[{ok:true}]});
  assert.equal(result.applied, 3);
  assert.deepEqual(comments(result.source), comments(source));
});

test('adversarial missing parents never overwrite existing siblings or exact numeric spellings', () => {
  const source = '{"keep":{"id":9007199254740993,"zero":-0},"groups":[{"stable":true}],"after":[false,null]}';
  const untouched = [['keep'], ['keep','id'], ['keep','zero'], ['after']];
  const {result, value} = checked({op:'set', source, path:['groups',0,'created',0,'enabled'], value:'true'});
  assert.deepEqual(value.groups, [{stable:true,created:[{enabled:true}]}]);
  for (const path of untouched) {
    assert.equal(run({op:'find', source:result.source, path}).node.raw, run({op:'find', source, path}).node.raw);
  }
  const appended = checked({op:'set', source, path:['groups',-1,'added'], value:'["😀"]'});
  assert.deepEqual(appended.value.groups, [{stable:true},{added:['😀']}]);
  assert.equal(run({op:'find', source:appended.result.source, path:['keep']}).node.raw, run({op:'find', source, path:['keep']}).node.raw);
  const path = Array.from({length:30}, (_, i) => i % 2 ? 0 : `level${i}`);
  const deep = checked({op:'set', source:'// retained', path, value:'1'});
  assert.equal(run({op:'find', source:deep.result.source, path}).node.raw, '1');
  assert.deepEqual(comments(deep.result.source), ['// retained']);
});

test('adversarial invalid parent conversion sparse arrays and failed post-removal tests are atomic', () => {
  const source = '{"user":{"name":"stable"},"a":[1]}';
  for (const request of [
    {op:'set', path:['user','name','first'], value:'"changed"'},
    {op:'set', path:['a',3], value:'2'},
    {op:'transaction', operations:[{op:'set',path:['user','new'],value:'1'},{op:'set',path:['user','name','first'],value:'2'}]},
    {op:'transaction', operations:[{op:'remove',path:[]},{op:'test',path:['a'],value:'[1]'}]},
  ]) {
    const result = run({...request, source});
    assert.equal(result.ok, false);
    assert.equal('source' in result, false);
    assert.equal('edits' in result, false);
  }
  assert.equal(run({op:'find', source, path:['user','name']}).node.raw, '"stable"');
});
