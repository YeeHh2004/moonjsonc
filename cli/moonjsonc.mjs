#!/usr/bin/env node
import {readFile, rename, unlink, lstat, open} from 'node:fs/promises';
import {resolve, dirname, basename, join} from 'node:path';
import {randomUUID} from 'node:crypto';
import {process as run} from '../web/moonjsonc.mjs';

const usage = `MoonJSONC — source-preserving configuration editing
Usage: node cli/moonjsonc.mjs COMMAND FILE [ARGUMENTS] [--write] [--json] [--check]
  check FILE                      validate JSONC (exit 1 on diagnostics)
  parse FILE                      inspect syntax tree and diagnostics
  scan FILE                       inspect tokens with UTF-16 spans
  locate FILE OFFSET              locate cursor path (zero-based UTF-16)
  find FILE PATH_JSON             find a node by typed path, e.g. '["scripts","test"]'
  format FILE                     format whitespace; --check detects changes
  strip FILE                      replace comments with spaces
  set FILE PATH_JSON VALUE_JSON   set a value; preserves exact numeric spelling
  remove FILE PATH_JSON           remove a value
  insert FILE PATH_JSON INDEX VALUE_JSON
  transaction FILE OPERATIONS_JSON_FILE
  request REQUEST_JSON_FILE       execute the documented JSON transport
Changes print to stdout unless --write is explicitly supplied.
FILE '-' reads stdin. --write requires a regular file and verifies it is unchanged.
`;

async function replaceFile(path, original, next) {
  const info = await lstat(path);
  if (!info.isFile()) throw new Error('--write requires a regular file');
  const temporary = join(dirname(path), `.${basename(path)}.moonjsonc-${randomUUID()}.tmp`);
  let created = false;
  try {
    const handle = await open(temporary, 'wx', info.mode);
    created = true;
    try { await handle.writeFile(next, 'utf8'); await handle.sync(); } finally { await handle.close(); }
    if (await readFile(path, 'utf8') !== original) throw new Error('source changed since read; write refused');
    await rename(temporary, path);
    created = false;
  } finally {
    if (created) await unlink(temporary).catch(() => {});
  }
}

async function main() {
  const input = process.argv.slice(2);
  if (!input.length || input.includes('--help')) { process.stdout.write(usage); return; }
  const options = new Set(input.filter(a => a.startsWith('--')));
  for (const option of options) if (!['--write', '--json', '--check'].includes(option)) throw new Error(`Unknown option ${option}`);
  if (options.has('--write') && options.has('--check')) throw new Error('--write and --check are mutually exclusive');
  const args = input.filter(a => !a.startsWith('--'));
  const [command, name, ...rest] = args;
  if (!name) throw new Error('A source file is required');
  let source;
  if (name === '-') {
    const chunks=[]; let size=0;
    for await (const chunk of process.stdin) { size+=chunk.length; if(size>8388608)throw new Error('stdin exceeds 8 MiB'); chunks.push(chunk); }
    source=Buffer.concat(chunks).toString('utf8');
  } else {
    if((await lstat(resolve(name))).size>8388608)throw new Error('input file exceeds 8 MiB');
    source=await readFile(resolve(name),'utf8');
  }
  let request;
  if (command === 'request') {
    if (options.has('--write')) throw new Error('request does not support --write');
    request = JSON.parse(source);
  } else {
    request = {op: command, source};
    if (['set', 'remove', 'insert', 'find'].includes(command)) {
      if (rest[0] === undefined) throw new Error('PATH_JSON is required');
      request.path = JSON.parse(rest[0]);
    }
    if (command === 'set') request.value = rest[1];
    if (command === 'insert') { request.index = Number(rest[1]); request.value = rest[2]; }
    if (command === 'locate') {
      request.offset = Number(rest[0]);
      if (!Number.isInteger(request.offset)) throw new Error('OFFSET must be an integer');
    }
    if (command === 'transaction') {
      if (!rest[0]) throw new Error('OPERATIONS_JSON_FILE is required');
      request.operations = JSON.parse(await readFile(rest[0], 'utf8'));
      request.expectedSource = source;
    }
  }
  const response = JSON.parse(run(JSON.stringify(request)));
  if (!response.ok || response.valid === false) {
    process.stderr.write(JSON.stringify(response, null, 2) + '\n');
    process.exitCode = 1;
    return;
  }
  const hasSource = typeof response.source === 'string';
  if (options.has('--write')) {
    if (!hasSource || name === '-') throw new Error('--write requires a file-editing command');
    if (response.source !== source) await replaceFile(resolve(name), source, response.source);
  }
  if (options.has('--check') && response.changed) process.exitCode = 1;
  if (options.has('--json') || !hasSource) process.stdout.write(JSON.stringify(response, null, 2) + '\n');
  else if (!options.has('--write') && !options.has('--check')) process.stdout.write(response.source);
}

main().catch(error => { process.stderr.write(`MoonJSONC: ${error.message}\n`); process.exitCode = 2; });
