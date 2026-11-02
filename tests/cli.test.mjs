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
