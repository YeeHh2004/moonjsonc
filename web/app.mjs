import {process as engine} from './moonjsonc.mjs';
const $ = id => document.getElementById(id);
const presets = {
  package: {file:'package.jsonc', source:'{\n  // Keep the team’s test command documented.\n  "name": "workspace-tool",\n  "scripts": {\n    "test": "moon test",\n    "build": "moon build"\n  },\n  // Exact numeric identifiers stay unchanged.\n  "buildId": 9007199254740993\n}\n', path:['scripts','test'], value:'"moon test --target wasm-gc"', operations:[{op:'test',path:['name'],value:'"workspace-tool"'},{op:'set',path:['scripts','test'],value:'"moon test --target wasm-gc"'},{op:'set',path:['scripts','check'],value:'"moon check --deny-warn"'}]},
  settings: {file:'settings.jsonc', source:'{\n  // Editor preferences shared by the team.\n  "editor.fontSize": 14,\n  "editor": {\n    "rulers": [80, 100],\n    "formatOnSave": false,\n  },\n  /* Keep this explanation in the file. */\n  "files.exclude": {"**/_build": true}\n}\n', path:['editor','formatOnSave'], value:'true', operations:[{op:'set',path:['editor','formatOnSave'],value:'true'},{op:'insert',path:['editor','rulers'],index:1,value:'90'},{op:'set',path:['editor.fontSize'],value:'16'}]},
  deployment: {file:'deployment.jsonc', source:'{\n  // Changes require the expected deployment version.\n  "version": 3,\n  "service": {\n    "replicas": 2,\n    "regions": ["east", "west"]\n  },\n  // Owned by the operations team.\n  "audit": true\n}\n', path:['service','replicas'], value:'4', operations:[{op:'test',path:['version'],value:'3'},{op:'set',path:['service','replicas'],value:'4'},{op:'insert',path:['service','regions'],index:2,value:'"north"'},{op:'set',path:['version'],value:'4'}]}
};
let preview = null;
function status(message, error=false){$('status').textContent=message;$('status').classList.toggle('error',error);}
function reset(){preview=null;$('adopt').disabled=true;$('download').disabled=true;}
function cursor(){ $('cursor').textContent=`UTF-16 光标 ${$('source').selectionStart} / ${$('source').value.length}`; }
function load(name){const p=presets[name];$('source').value=p.source;$('path').value=JSON.stringify(p.path);$('value').value=p.value;$('operations').value=JSON.stringify(p.operations,null,2);$('filename').textContent=p.file;document.querySelectorAll('[data-preset]').forEach(b=>b.classList.toggle('active',b.dataset.preset===name));reset();cursor();$('result').textContent='运行一次操作后，结果会显示在这里。';$('details').textContent='[]';status('引擎就绪。修改保留在预览中，采纳后才会替换左侧原文。');}
function run(op){
  try {
    reset();
    const request={op,source:$('source').value};
    if(['set','remove'].includes(op))request.path=JSON.parse($('path').value);
    if(op==='set')request.value=$('value').value;
    if(op==='transaction'){request.operations=JSON.parse($('operations').value);request.expectedSource=request.source;}
    if(op==='locate')request.offset=$('source').selectionStart;
    const result=JSON.parse(engine(JSON.stringify(request)));
    $('details').textContent=JSON.stringify(result.edits??result.diagnostics??result,null,2);
    if(!result.ok||result.valid===false){status(result.error??`发现 ${result.diagnostics.length} 项诊断，原文保持不变。`,true);$('result').textContent='操作未应用。';return;}
    if(typeof result.source==='string'){
      preview={source:result.source,original:request.source};$('result').textContent=result.source;$('adopt').disabled=false;$('download').disabled=false;status(`预览完成 · ${result.edits?.length??0} 处文本补丁${result.applied!==undefined?` · ${result.applied} 项事务操作`:''}`);
    } else if(op==='locate'){$('result').textContent=JSON.stringify(result,null,2);status(`路径 ${JSON.stringify(result.path)} · 第 ${result.line+1} 行，第 ${result.column+1} 列`);}
    else {$('result').textContent='配置有效。';status('检查通过：支持 JSONC 注释与尾逗号。');}
  } catch(error){status(error.message,true);$('result').textContent='输入格式有误，未进行修改。';}
}
document.querySelectorAll('[data-preset]').forEach(b=>b.addEventListener('click',()=>load(b.dataset.preset)));
for(const op of ['set','remove','format','check','transaction','locate'])$(op).addEventListener('click',()=>run(op));
$('source').addEventListener('input',()=>{reset();cursor();status('原文已改变，请重新生成预览。');});
for(const event of ['select','keyup','click'])$('source').addEventListener(event,cursor);
$('adopt').addEventListener('click',()=>{if(!preview)return;if(preview.original!==$('source').value){reset();status('原文已改变，请重新生成预览。',true);return;}$('source').value=preview.source;reset();cursor();status('已采纳结果，可继续编辑。');});
$('download').addEventListener('click',()=>{if(!preview)return;const url=URL.createObjectURL(new Blob([preview.source],{type:'application/json'}));const a=document.createElement('a');a.href=url;a.download=$('filename').textContent;a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);});
load('package');document.documentElement.dataset.ready='true';
