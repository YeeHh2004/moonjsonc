import test from 'node:test';
import assert from 'node:assert/strict';
import {process as engine} from '../web/moonjsonc.mjs';
const run = request => JSON.parse(engine(JSON.stringify(request)));

test('strict transport accepts all root kinds and preserves exact numeric source', () => {
  for (const [source, kind] of [['{}','object'],['[]','array'],['"text"','string'],['42','number'],['true','boolean'],['false','boolean'],['null','null']]) {
    const result = run({op:'check-json', source});
    assert.equal(result.valid, true, source);
    assert.equal(result.tree.kind, kind);
    assert.equal(result.tree.raw, source);
  }
  for (const source of ['-0','9007199254740993','1e400','1e-400']) {
    const result = run({op:'parse-json', source});
    assert.equal(result.valid, true, source);
    assert.equal(result.tree.value, source);
  }
});

test('strict transport keeps extensions disabled even with permissive options', () => {
  for (const source of ['','/*c*/42','[1,]','01','+1','1.','1e+','NaN','Infinity','true false',"{'x':1}",'"\\x41"','"line\nbreak"']) {
    const result = run({op:'check-json',source,options:{allowComments:true,allowTrailingComma:true,allowEmpty:true}});
    assert.equal(result.valid, false, source);
    assert.ok(result.diagnostics.length > 0, source);
    assert.equal(result.tree, null);
  }
  assert.equal(run({op:'check',source:'{/*keep*/"enabled":false,}'}).valid,true);
});

test('strict JSON duplicate syntax stays separate from ambiguous configuration editing', () => {
  const source='{"a":1,"\\u0061":2}';
  const result=run({op:'parse-json',source});
  assert.equal(result.valid,true);
  assert.equal(result.tree.children.length,2);
  assert.equal(result.tree.value.a,2);
  assert.equal(run({op:'set',source,path:['a'],value:'3'}).code,'InvalidDocument');
  const invalid=run({op:'parse-json',source:'{"a":1,"a":2 "b":3}',options:{maxErrors:1}});
  assert.equal(invalid.valid,false);
  assert.equal(invalid.diagnostics[0].code,'CommaExpected');
});

test('proposal input/output examples reproduce exactly', () => {
  const source='{/*keep*/"enabled":false,"id":9007199254740993}';
  const result=run({op:'set',source,path:['enabled'],value:'true'});
  assert.equal(result.source,'{/*keep*/"enabled":true,"id":9007199254740993}');
  assert.deepEqual(result.edits,[{offset:19,length:5,content:'true'}]);
  const invalid=run({op:'check-json',source:'[1,]'});
  assert.equal(invalid.diagnostics[0].code,'TrailingComma');
  assert.equal(invalid.diagnostics[0].offset,2);
  assert.equal(invalid.diagnostics[0].length,1);
  const formatted=run({op:'format',source:'{"id":9007199254740993,"ok":true}'});
  assert.equal(formatted.ok,true);
  assert.equal(run({op:'check-json',source:formatted.source}).valid,true);
  assert.ok(formatted.source.includes('9007199254740993'));
  const operations=[{op:'test',path:['version'],value:'3'},{op:'set',path:['version'],value:'4'},{op:'set',path:['replicas'],value:'5'}];
  const tx=run({op:'transaction',source:'{"version":3,"replicas":2}',operations});
  assert.equal(tx.source,'{"version":4,"replicas":5}');
  assert.equal(run({op:'check-json',source:tx.source}).valid,true);
  const conflict=run({op:'transaction',source:'{"version":3,"replicas":2}',operations:[{op:'test',path:['version'],value:'2'},...operations.slice(1)]});
  assert.equal(conflict.code,'Conflict');
  assert.equal('source' in conflict,false);
});
