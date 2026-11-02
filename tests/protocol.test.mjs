import test from 'node:test';
import assert from 'node:assert/strict';
import {process as engine} from '../web/moonjsonc.mjs';
const run = request => JSON.parse(engine(JSON.stringify(request)));
test('transport rejects bad shapes, nesting and invalid paths without throwing',()=>{
  for(const text of ['','{','null','[]','{}','{"op":"parse","source":3}'])assert.equal(JSON.parse(engine(text)).ok,false);
  for(const path of [[true],[1.5],[-2],[2147483648],Array(129).fill('a')])assert.equal(run({op:'find',source:'{}',path}).ok,false);
  assert.equal(JSON.parse(engine('['.repeat(170)+']'.repeat(170))).ok,false);
  assert.equal(run({op:'unknown',source:'{}'}).ok,false);
});
test('parse exposes raw exact numbers and source ranges',()=>{
  const source='{/*文档😀*/"n":9007199254740993,"tiny":1e-400,"huge":1e400,"z":-0,}';
  const r=run({op:'parse',source});assert.equal(r.valid,true);
  for(const n of r.tree.children){const value=n.children[1];assert.equal(value.raw,source.slice(value.offset,value.offset+value.length));assert.equal(typeof value.value,'string');}
  assert.equal(run({op:'find',source,path:['n']}).node.value,'9007199254740993');
});
test('parse options diagnose strict JSON extensions',()=>{
  const r=run({op:'parse',source:'{/*c*/"a":1,}',options:{allowComments:false,allowTrailingComma:false}});
  assert.equal(r.valid,false);assert.ok(r.diagnostics.length>=2);
  for(const options of [{maxDepth:0},{maxErrors:0},{maxDepth:513}])assert.equal(run({op:'parse',source:'{}',options}).valid,false);
});
test('source editing preserves comments, exact unrelated numbers and local formatting',()=>{
  const source='//header\r\n{\r\n\t"a" : 1, /* keep */\r\n\t"id": 9007199254740993\r\n}\r\n';
  const r=run({op:'set',source,path:['a'],value:'2'});assert.equal(r.ok,true);
  assert.equal(r.source,source.replace('"a" : 1','"a" : 2'));
  assert.deepEqual(r.edits,[{offset:source.indexOf(': 1')+2,length:1,content:'2'}]);
});
test('transaction fails atomically and validates expected source',()=>{
  const source='{"version":3,"a":[1,2]}';
  const operations=[{op:'set',path:['version'],value:'4'},{op:'test',path:['a',0],value:'9'}];
  const failed=run({op:'transaction',source,operations});assert.equal(failed.ok,false);assert.equal(failed.code,'Conflict');assert.equal('source' in failed,false);
  assert.equal(run({op:'transaction',source,operations:[],expectedSource:'{}'}).code,'Conflict');
  const success=run({op:'transaction',source,operations:[{op:'test',path:['version'],value:'3'},{op:'set',path:['version'],value:'4'},{op:'insert',path:['a'],index:1,value:'9'}]});
  assert.equal(success.ok,true);assert.deepEqual(JSON.parse(success.source),{version:4,a:[1,9,2]});
  assert.equal(run({op:'apply',source,edits:success.edits}).source,success.source);
});
test('duplicate properties, overlapping patches and surrogate boundaries are rejected',()=>{
  assert.equal(run({op:'set',source:'{"a":1,"a":2}',path:['a'],value:'3'}).ok,false);
  assert.equal(run({op:'apply',source:'"😀"',edits:[{offset:2,length:0,content:'x'}]}).ok,false);
  assert.equal(run({op:'apply',source:'abcd',edits:[{offset:0,length:3,content:''},{offset:1,length:1,content:''}]}).ok,false);
});
test('visitor handles large flat configurations and reports stable paths',()=>{
  const source=JSON.stringify({values:Array.from({length:3000},(_,i)=>i)});
  const r=run({op:'visit',source});assert.equal(r.ok,true);assert.equal(r.events.filter(e=>e.kind==='literal').length,3000);
  assert.deepEqual(r.events.filter(e=>e.kind==='literal').at(-1).path,['values',2999]);
  assert.deepEqual(run({op:'locate',source,offset:source.lastIndexOf('2999')}).path,['values',2999]);
});
test('formatting and comment stripping do not rewrite string contents',()=>{
  const source='{"url":"https://host/a/*x*/","note":"//😀",/*real*/"a":[1,2,]}';
  const r=run({op:'format',source});assert.equal(r.ok,true);assert.ok(r.source.includes('/*real*/'));assert.ok(r.source.includes('https://host/a/*x*/'));
  assert.equal(run({op:'format',source:r.source}).edits.length,0);
  const stripped=run({op:'strip',source});assert.equal(stripped.source.length,source.length);assert.ok(stripped.source.includes('"//😀"'));
});
