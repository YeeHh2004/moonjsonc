import {mkdtempSync,cpSync,writeFileSync,readFileSync,rmSync,readdirSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join,resolve,dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {execFileSync} from 'node:child_process';
import assert from 'node:assert/strict';
const root=fileURLToPath(new URL('../',import.meta.url)).replaceAll('\\','/');
const version=JSON.parse(readFileSync(join(root,'package.json'),'utf8')).version;
const workspace=mkdtempSync(join(tmpdir(),'moonjsonc-consumer-')),consumer=join(workspace,'consumer');
const registry=process.argv.includes('--registry');
try{
  cpSync(new URL('../examples/consumer/',import.meta.url),consumer,{recursive:true,filter:source=>!/[\\/](_build|\.mooncakes)([\\/]|$)/.test(source)});
  const run=args=>execFileSync('moon',args,{cwd:consumer,encoding:'utf8',stdio:['ignore','pipe','inherit']});
  if(registry){
    writeFileSync(join(consumer,'moon.mod'),`name = "moonjsonc-examples/consumer"\n\nversion = "${version}"\n`);
    run(['add',`YeeHh2004/moonjsonc@${version}`]);
    run(['build','--target','js']);
    const downloaded=join(consumer,'.mooncakes','YeeHh2004','moonjsonc');
    const sourceFiles=readdirSync(root).filter(n=>n.endsWith('.mbt')||n.endsWith('.mbti'));
    for(const file of readdirSync(join(root,'protocol')).filter(n=>n.endsWith('.mbt')||n.endsWith('.mbti')))sourceFiles.push('protocol/'+file);
    for(const name of sourceFiles){
      const norm=text=>text.replaceAll('\r\n','\n');
      assert.equal(norm(readFileSync(join(downloaded,name),'utf8')),norm(readFileSync(join(root,name),'utf8')),`Published source: ${name}`);
    }
  }else writeFileSync(join(workspace,'moon.work'),`members = [\n  ${JSON.stringify(root)},\n  "consumer",\n]\n`);
  run(['fmt','--check']);
  for(const target of ['js','wasm-gc']){
    process.stdout.write(run(['test','--target',target]));
    assert.equal(run(['run','.','--target',target]).trim().replaceAll('\r\n','\n'),'{/* keep */"enabled":true,"id":9007199254740993}\n0');
  }
  console.log(`${registry?'Public registry':'Local workspace'} consumer verified on JS and Wasm GC.`);
}finally{
  assert.equal(dirname(resolve(workspace)),resolve(tmpdir()));
  rmSync(workspace,{recursive:true,force:true});
}
