import test from 'node:test';
import assert from 'node:assert/strict';
import * as reference from 'jsonc-parser';
import {process as processRequest} from '../web/moonjsonc.mjs';

// Independent, deterministic generators; the real Microsoft package is the
// oracle. This checks the shared behavior, not identical APIs, whitespace
// layouts, error recovery trees, or the reference's comment-value offset bug.
const SEED = 0x4d4a5343;
const CASES = 360;
const parseOptions = {allowTrailingComma: true, disallowComments: false};
function random(seed) {
  let state = seed >>> 0;
  return limit => {
    state += 0x6d2b79f5;
    let value = state;
    value = Math.imul(value ^ (value >>> 15), value | 1);
    value ^= value + Math.imul(value ^ (value >>> 7), value | 61);
    return ((value ^ (value >>> 14)) >>> 0) % limit;
  };
}
const rng = random(SEED);
const strings = ['', 'plain', '😀键', 'a/b~c', '// not a comment /* either */',
  'quote " slash \\ newline\n', '\u0000\t\r', '__proto__', 'e\u0301'];
function value(depth = 0) {
  const choice = rng(depth >= 4 ? 5 : 8);
  if (choice === 0) return null;
  if (choice === 1) return rng(2) === 0;
  if (choice === 2) return [0, -17, 1.25, 0.002, 8e15, -2.5e-12][rng(6)];
  if (choice <= 4) return strings[rng(strings.length)];
  if (choice === 5) return Array.from({length: rng(5)}, () => value(depth + 1));
  return Object.fromEntries(Array.from({length: rng(5)}, (_, i) =>
    [`${['key', '😀', 'a/b', '~', '__proto__'][rng(5)]}${i}`, value(depth + 1)]));
}
function trivia() {
  return ['', ' ', '\t', '\n', '\r\n', '/* note 😀 */', '// note\n',
    '\n/* multi\r\n line */\n'][rng(8)];
}
function render(item) {
  if (item === null || typeof item !== 'object') return JSON.stringify(item);
  const array = Array.isArray(item);
  const parts = array ? item.map(render) : Object.entries(item).map(([key, val]) =>
    JSON.stringify(key) + trivia() + ':' + trivia() + render(val));
  return (array ? '[' : '{') + trivia() + parts.join(',' + trivia()) +
    (parts.length && rng(2) ? ',' : '') + trivia() + (array ? ']' : '}');
}
const corpus = Array.from({length: CASES}, (_, index) => {
  const item = value();
  return {index, item, source: trivia() + render(item) + trivia()};
});
const context = (sample, operation) =>
  `${operation}; seed=${SEED}; case=${sample.index}; source=${JSON.stringify(sample.source)}`;
function call(op, source, extra = {}) {
  const response = JSON.parse(processRequest(JSON.stringify({op, source, ...extra})));
  assert.equal(response.ok, true, `${op} rejected: ${JSON.stringify(response)}`);
  return response;
}
function referenceValue(source) {
  const errors = [];
  const result = reference.parse(source, errors, parseOptions);
  assert.deepEqual(errors, [], `oracle rejected generated source ${JSON.stringify(source)}`);
  return result;
}
function treeValue(node) {
  assert.ok(node, 'expected a root node');
  if (node.kind === 'number') return Number(node.value);
  if (node.kind === 'array') return node.children.map(treeValue);
  if (node.kind === 'object') return Object.fromEntries(node.children.map(property =>
    [property.children[0].value, treeValue(property.children[1])]));
  return node.value;
}
const tokenNames = {
  OpenBraceToken: 'OpenBrace', CloseBraceToken: 'CloseBrace',
  OpenBracketToken: 'OpenBracket', CloseBracketToken: 'CloseBracket',
  CommaToken: 'Comma', ColonToken: 'Colon', NullKeyword: 'Null',
  TrueKeyword: 'True', FalseKeyword: 'False', StringLiteral: 'String',
  NumericLiteral: 'Number', LineCommentTrivia: 'LineComment',
  BlockCommentTrivia: 'BlockComment', LineBreakTrivia: 'LineBreak',
  Trivia: 'Whitespace', Unknown: 'Unknown', EOF: 'Eof',
};
function referenceTokens(source, ignoreTrivia = false) {
  const scanner = reference.createScanner(source, ignoreTrivia);
  const tokens = [];
  let code;
  do {
    code = scanner.scan();
    const kind = tokenNames[reference.SyntaxKind[code]];
    const offset = scanner.getTokenOffset();
    const length = scanner.getTokenLength();
    // Microsoft gives punctuation an empty value, and comment getTokenValue()
    // can include the preceding character. Normalize these API differences to
    // their authoritative original source spans; decoded strings still compare.
    const value = kind === 'String' || kind === 'Number' ? scanner.getTokenValue() :
      source.slice(offset, offset + length);
    tokens.push({kind, offset, length, value});
    assert.equal(scanner.getTokenError(), reference.ScanError.None);
  } while (code !== reference.SyntaxKind.EOF);
  return tokens;
}
function tokens(source) {
  return call('scan', source).tokens.filter(token =>
    !['Whitespace', 'LineBreak', 'Eof'].includes(token.kind));
}
function referenceStripBySpans(source, spaces) {
  let output = '';
  let end = 0;
  for (const token of referenceTokens(source)) {
    if (token.kind !== 'LineComment' && token.kind !== 'BlockComment') continue;
    output += source.slice(end, token.offset);
    if (spaces) output += source.slice(token.offset, token.offset + token.length).replace(/[^\r\n]/g, ' ');
    end = token.offset + token.length;
  }
  return output + source.slice(end);
}

test('360 seeded JSONC cases match Microsoft scanner kinds, UTF-16 spans and values', () => {
  for (const sample of corpus) {
    for (const ignoreTrivia of [false, true]) {
      const actual = call('scan', sample.source, {ignoreTrivia}).tokens;
      assert.deepEqual(actual.map(({kind, offset, length, value}) =>
        ({kind, offset, length, value})), referenceTokens(sample.source, ignoreTrivia),
      context(sample, `scan ignoreTrivia=${ignoreTrivia}`));
      assert.ok(actual.every(token => token.error === null), context(sample, 'scan errors'));
    }
  }
});

test('360 seeded JSONC trees agree with the Microsoft parse value', () => {
  for (const sample of corpus) {
    const actual = call('parse', sample.source);
    assert.equal(actual.valid, true, context(sample, 'parse'));
    assert.deepEqual(actual.diagnostics, []);
    assert.deepEqual(treeValue(actual.tree), referenceValue(sample.source), context(sample, 'tree value'));
  }
});

test('360 seeded formatter cases preserve tokens, semantics and idempotence', () => {
  for (const sample of corpus) {
    const options = {
      indentSize: sample.index % 5,
      useTabs: sample.index % 3 === 0,
      eol: sample.index % 2 ? '\r\n' : '\n',
      finalNewline: sample.index % 4 === 0,
    };
    const actual = call('format', sample.source, {options});
    assert.deepEqual(referenceValue(actual.source), referenceValue(sample.source), context(sample, 'format value'));
    assert.deepEqual(tokens(actual.source).map(t => [t.kind, t.value]),
      tokens(sample.source).map(t => [t.kind, t.value]), context(sample, 'format token preservation'));
    const again = call('format', actual.source, {options});
    assert.deepEqual(again.edits, [], context(sample, 'format idempotence'));
    assert.equal(again.source, actual.source);
    const referenceOutput = reference.applyEdits(sample.source, reference.format(sample.source, undefined, {
      tabSize: options.indentSize, insertSpaces: !options.useTabs, eol: options.eol,
      insertFinalNewline: options.finalNewline,
    }));
    assert.deepEqual(referenceValue(actual.source), referenceValue(referenceOutput), context(sample, 'reference formatting'));
  }
});

test('360 seeded comment stripping cases match Microsoft token spans without offset drift', () => {
  for (const sample of corpus) {
    const spaces = call('strip', sample.source, {replaceWithSpaces: true}).source;
    assert.equal(spaces, referenceStripBySpans(sample.source, true), context(sample, 'strip spaces'));
    assert.equal(spaces.length, sample.source.length);
    assert.deepEqual(Array.from(spaces.matchAll(/\r\n|\r|\n/g), match => [match.index, match[0]]),
      Array.from(sample.source.matchAll(/\r\n|\r|\n/g), match => [match.index, match[0]]));
    const removed = call('strip', sample.source, {replaceWithSpaces: false}).source;
    assert.equal(removed, referenceStripBySpans(sample.source, false), context(sample, 'strip delete'));
    assert.deepEqual(referenceValue(removed), referenceValue(sample.source));
  }
});

test('360 seeded set, remove and insertion cases agree with Microsoft edit semantics', () => {
  const sentinel = JSON.stringify('UNCHANGED 😀 /* string */ \\u0061');
  for (const sample of corpus) {
    const source = `{// untouched comment\r\n"keep":${sentinel},"payload":${sample.source},"list":[1,2],"number":1.20e+03}`;
    const next = corpus[(sample.index + 73) % CASES].item;
    const value = JSON.stringify(next);
    for (const operation of ['set', 'remove', 'insert']) {
      const index = sample.index % 3;
      const path = operation === 'insert' ? ['list'] : ['payload'];
      const actual = call(operation, source, {path, ...(operation === 'remove' ? {} : {value}), index});
      const referencePath = operation === 'insert' ? ['list', index] : path;
      const referenceOutput = reference.applyEdits(source, reference.modify(source, referencePath,
        operation === 'remove' ? undefined : next, {
          isArrayInsertion: operation === 'insert', formattingOptions: {tabSize: 2, insertSpaces: true},
        }));
      assert.deepEqual(referenceValue(actual.source), referenceValue(referenceOutput), context(sample, operation));
      assert.ok(actual.source.includes(sentinel), context(sample, `${operation} unrelated string`));
      assert.ok(actual.source.includes('// untouched comment\r\n'), context(sample, `${operation} unrelated comment`));
      assert.ok(actual.source.includes('1.20e+03'), context(sample, `${operation} unrelated numeric spelling`));
    }
  }
});

test('180 seeded damaged inputs have bounded deterministic diagnostics and refuse unsafe edits', () => {
  const damage = random(SEED ^ 0x426164);
  let invalid = 0;
  for (const sample of corpus.slice(0, 180)) {
    const chars = Array.from(sample.source);
    const at = damage(chars.length + 1);
    if (sample.index % 3 === 0) chars.splice(at, damage(3), '@');
    else if (sample.index % 3 === 1) chars.push(' ', '@');
    else chars.splice(at, 1);
    const source = chars.join('');
    const response = call('parse', source, {options: {maxErrors: 8, maxDepth: 12}});
    assert.ok(response.diagnostics.length <= 8, context(sample, 'bounded diagnostics'));
    for (const diagnostic of response.diagnostics) {
      assert.ok(Number.isInteger(diagnostic.offset) && diagnostic.offset >= 0 && diagnostic.offset <= source.length);
      assert.ok(Number.isInteger(diagnostic.length) && diagnostic.length >= 0 &&
        diagnostic.length <= source.length - diagnostic.offset);
    }
    assert.deepEqual(call('parse', source, {options: {maxErrors: 8, maxDepth: 12}}), response);
    if (!response.valid) {
      invalid++;
      const formatted = JSON.parse(processRequest(JSON.stringify({op: 'format', source})));
      assert.equal(formatted.ok, false, context(sample, 'invalid formatting refused'));
      assert.equal(formatted.code, 'InvalidDocument');
    }
  }
  assert.ok(invalid >= 100, `damage generator exercised only ${invalid} invalid cases`);
  const deep = call('parse', '['.repeat(180) + '0' + ']'.repeat(180), {options: {maxErrors: 8, maxDepth: 12}});
  assert.equal(deep.valid, false);
  assert.ok(deep.diagnostics.length > 0 && deep.diagnostics.length <= 8);
});

function referenceEvents(source) {
  const events = [];
  const stack = [];
  const emit = (kind, offset, length, path) => events.push({kind, offset, length, ...(path ? {path} : {})});
  reference.visit(source, {
    onObjectBegin(offset, length, _line, _column, path) {
      const current = path(); stack.push(current); emit('object_begin', offset, length, current);
    },
    onArrayBegin(offset, length, _line, _column, path) {
      const current = path(); stack.push(current); emit('array_begin', offset, length, current);
    },
    onObjectEnd(offset, length) { emit('object_end', offset, length, stack.pop()); },
    onArrayEnd(offset, length) { emit('array_end', offset, length, stack.pop()); },
    onObjectProperty(name, offset, length, _line, _column, path) {
      emit('property', offset, length, [...path(), name]);
    },
    onLiteralValue(_value, offset, length, _line, _column, path) { emit('literal', offset, length, path()); },
    onSeparator(_separator, offset, length) { emit('separator', offset, length); },
    onComment(offset, length) { emit('comment', offset, length); },
    onError(error, offset) { assert.fail(`oracle visit error ${error} at ${offset}`); },
  }, parseOptions);
  return events;
}
test('360 seeded visitor event sequences and structural paths match Microsoft', () => {
  for (const sample of corpus) {
    const actual = call('visit', sample.source);
    assert.deepEqual(actual.diagnostics, []);
    assert.equal(actual.count, actual.events.length);
    assert.deepEqual(actual.events.map(({kind, offset, length, path}) =>
      ({kind, offset, length, ...(['separator', 'comment'].includes(kind) ? {} : {path})})),
    referenceEvents(sample.source), context(sample, 'visitor'));
  }
});

test('cursor locations at token starts agree with Microsoft structural paths', () => {
  for (const sample of corpus.slice(0, 80)) {
    for (const event of referenceEvents(sample.source)) {
      if (!['property', 'literal', 'object_begin', 'array_begin'].includes(event.kind)) continue;
      const expected = reference.getLocation(sample.source, event.offset);
      const actual = call('locate', sample.source, {offset: event.offset});
      assert.deepEqual(actual.path, expected.path, context(sample, `locate ${event.offset}`));
      // Derive key-ness independently from the visitor event. Microsoft 3.3.1
      // leaks isAtPropertyKey=true past an empty object in an array; copying
      // that state leak would incorrectly label an ordinary string value.
      assert.equal(actual.isPropertyKey, event.kind === 'property', context(sample, `locate key ${event.offset}`));
    }
  }
});

test('exact numeric source and the explicit reference comment-value difference stay visible', () => {
  const source = '{"big":900719925474099312345678901,"tiny":1e-999,"huge":1e+999,"zero":-0}';
  const parsed = call('parse', source);
  assert.equal(parsed.valid, true);
  assert.deepEqual(parsed.tree.children.map(property => property.children[1].value),
    ['900719925474099312345678901', '1e-999', '1e+999', '-0']);
  assert.deepEqual(tokens(call('format', source).source).map(token => [token.kind, token.value]),
    tokens(source).map(token => [token.kind, token.value]));
  const scanner = reference.createScanner('1/*a*/');
  scanner.scan(); scanner.scan();
  assert.equal(scanner.getTokenOffset(), 1);
  assert.equal(scanner.getTokenLength(), 5);
  assert.equal(scanner.getTokenValue(), '1/*a*/'); // Pinned 3.3.1 quirk, not copied.
  assert.equal(call('scan', '1/*a*/').tokens[1].value, '/*a*/');
  assert.equal(reference.stripComments('1/*a*/', ' '), '1      ');
  assert.equal(call('strip', '1/*a*/').source, '1     ');
  assert.equal(reference.getLocation('[{},"x"]', 4).isAtPropertyKey, true);
  const location = call('locate', '[{},"x"]', {offset: 4});
  assert.deepEqual(location.path, [1]);
  assert.equal(location.isPropertyKey, false);
});
