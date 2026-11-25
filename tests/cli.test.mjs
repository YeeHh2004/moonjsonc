import test from 'node:test';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {mkdtempSync,writeFileSync,readFileSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join,resolve,dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
const cli=fileURLToPath(new URL('../cli/moonjsonc.mjs',import.meta.url));
const run=(args,input)=>spawnSync(process.execPath,[cli,...args],{input,encoding:'utf8',timeout:20000});
test('CLI supports stdout preview, explicit file updates and transaction rollback',()=>{
  const directory=mkdtempSync(join(tmpdir(),'moonjsonc-cli-'));
  try{
    const file=join(directory,'config.jsonc'),ops=join(directory,'ops.json');
    const source='// keep\n{"n":1,"id":9007199254740993}\n';writeFileSync(file,source);
    let r=run(['set',file,'["n"]','2']);assert.equal(r.status,0,r.stderr);assert.equal(r.stdout,source.replace('"n":1','"n":2'));assert.equal(readFileSync(file,'utf8'),source);
    r=run(['set',file,'["n"]','2','--write']);assert.equal(r.status,0,r.stderr);assert.equal(readFileSync(file,'utf8'),source.replace('"n":1','"n":2'));
    writeFileSync(ops,JSON.stringify([{op:'set',path:['n'],value:'3'},{op:'test',path:['id'],value:'1'}]));
    r=run(['transaction',file,ops,'--write']);assert.equal(r.status,1);assert.equal(readFileSync(file,'utf8'),source.replace('"n":1','"n":2'));
    assert.equal(run(['format',file,'--write','--check']).status,2);
    assert.equal(run(['format',file,'--check']).status,1);
    assert.equal(run(['check',file]).status,0);
  }finally{assert.equal(dirname(resolve(directory)),resolve(tmpdir()));rmSync(directory,{recursive:true,force:true});}
});
test('CLI consumes stdin and reports invalid documents and requests',()=>{
  const r=run(['set','-','["a"]','true'],'{"a":false}');assert.equal(r.status,0,r.stderr);assert.equal(r.stdout,'{"a":true}');
  assert.equal(run(['check','-'],'{"a":}').status,1);
  assert.equal(run(['locate','-','oops'],'{}').status,2);
  assert.equal(run(['--help']).status,0);
});

const malformedUtf8 = [
  Buffer.from([0x22, 0xff, 0x22]), // An invalid byte inside an otherwise valid JSON string.
  Buffer.from([0x22, 0xe4, 0xb8]), // An incomplete three-byte sequence at EOF.
];
function assertEncodingError(result, description) {
  assert.equal(result.status, 2, result.stderr);
  assert.equal(result.stdout, '', 'no partially decoded document is printed');
  assert.match(result.stderr, new RegExp(`Invalid UTF-8 in ${description}`));
  assert.doesNotMatch(result.stderr, /\uFFFD/);
}

test('CLI rejects malformed UTF-8 from stdin before commands run', () => {
  for (const bytes of malformedUtf8) {
    for (const command of ['check', 'parse', 'scan', 'format', 'check-json', 'parse-json', 'request']) {
      assertEncodingError(run([command, '-'], bytes), 'stdin');
    }
  }
});

test('CLI refuses malformed UTF-8 files without changing their bytes', () => {
  const directory = mkdtempSync(join(tmpdir(), 'moonjsonc-encoding-'));
  try {
    const file = join(directory, 'source.jsonc');
    for (const bytes of malformedUtf8) {
      writeFileSync(file, bytes);
      for (const args of [['check', file], ['parse-json', file], ['format', file, '--write']]) {
        assertEncodingError(run(args), 'input file');
        assert.deepEqual(readFileSync(file), bytes);
      }
    }
  } finally {
    assert.equal(dirname(resolve(directory)), resolve(tmpdir()));
    rmSync(directory, {recursive: true, force: true});
  }
});

test('CLI rejects malformed UTF-8 transaction operations files', () => {
  const directory = mkdtempSync(join(tmpdir(), 'moonjsonc-operations-encoding-'));
  try {
    const file = join(directory, 'source.jsonc');
    const ops = join(directory, 'ops.json');
    const source = '{"text":"中文😀"}';
    writeFileSync(file, source);
    const invalidOperation = Buffer.concat([
      Buffer.from('[{"op":"remove","path":["'),
      Buffer.from([0xff]),
      Buffer.from('"]}]'),
    ]);
    for (const bytes of [invalidOperation, malformedUtf8[1]]) {
      writeFileSync(ops, bytes);
      assertEncodingError(run(['transaction', file, ops, '--write']), 'operations file');
      assert.equal(readFileSync(file, 'utf8'), source);
      assert.deepEqual(readFileSync(ops), bytes);
    }
  } finally {
    assert.equal(dirname(resolve(directory)), resolve(tmpdir()));
    rmSync(directory, {recursive: true, force: true});
  }
});

test('CLI accepts UTF-8 Chinese and emoji in source and transaction files', () => {
  const directory = mkdtempSync(join(tmpdir(), 'moonjsonc-unicode-'));
  try {
    const file = join(directory, 'source.jsonc');
    const ops = join(directory, 'ops.json');
    const source = '{"text":"中文😀"}';
    writeFileSync(file, source);
    let result = run(['check', file]);
    assert.equal(result.status, 0, result.stderr);
    assert.equal(JSON.parse(result.stdout).tree.children[0].children[1].value, '中文😀');
    result = run(['parse', '-'], Buffer.from(source, 'utf8'));
    assert.equal(result.status, 0, result.stderr);
    assert.equal(JSON.parse(result.stdout).tree.children[0].children[1].value, '中文😀');
    writeFileSync(ops, JSON.stringify([{op: 'set', path: ['text'], value: JSON.stringify('新的😀')}]));
    result = run(['transaction', file, ops]);
    assert.equal(result.status, 0, result.stderr);
    assert.deepEqual(JSON.parse(result.stdout), {text: '新的😀'});
    assert.equal(readFileSync(file, 'utf8'), source);
  } finally {
    assert.equal(dirname(resolve(directory)), resolve(tmpdir()));
    rmSync(directory, {recursive: true, force: true});
  }
});

test('CLI strict JSON commands accept root values and distinguish JSONC extensions', () => {
  const roots = ['{}', '[]', '"中文😀"', '9007199254740993', 'true', 'false', 'null'];
  for (const source of roots) {
    for (const command of ['check-json', 'parse-json']) {
      const result = run([command, '-'], source);
      assert.equal(result.status, 0, result.stderr);
      assert.equal(JSON.parse(result.stdout).valid, true);
    }
  }
  const extended = '/*note*/{"x":1,}';
  assert.equal(run(['check', '-'], extended).status, 0);
  for (const command of ['check-json', 'parse-json']) {
    const result = run([command, '-'], extended);
    assert.equal(result.status, 1, result.stderr);
    const response = JSON.parse(result.stderr);
    assert.equal(response.valid, false);
    assert.ok(response.diagnostics.some(item => item.code === 'InvalidCommentToken'));
    assert.ok(response.diagnostics.some(item => item.code === 'TrailingComma'));
  }
  const help = run(['--help']);
  assert.match(help.stdout, /check-json FILE/);
  assert.match(help.stdout, /parse-json FILE/);
});

test('CLI preserves a leading BOM for grammar rejection in files and stdin', () => {
  const directory = mkdtempSync(join(tmpdir(), 'moonjsonc-bom-'));
  try {
    const file = join(directory, 'source.json');
    const bytes = Buffer.concat([Buffer.from([0xef, 0xbb, 0xbf]), Buffer.from('{"x":1}')]);
    writeFileSync(file, bytes);
    for (const command of ['check', 'check-json', 'parse-json']) {
      for (const result of [run([command, file]), run([command, '-'], bytes)]) {
        assert.equal(result.status, 1, result.stderr);
        const response = JSON.parse(result.stderr);
        assert.equal(response.valid, false);
        assert.ok(response.diagnostics.some(item => item.code === 'InvalidSymbol' && item.offset === 0));
      }
    }
    assert.deepEqual(readFileSync(file), bytes);
  } finally {
    assert.equal(dirname(resolve(directory)), resolve(tmpdir()));
    rmSync(directory, {recursive: true, force: true});
  }
});
