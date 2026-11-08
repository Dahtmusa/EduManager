// Minimal automated smoke tests for the pure branding helpers in index.html.
//
// Run with:  node tests/branding.test.mjs
//
// Pulls each helper out of index.html individually, wraps them in a single
// function body, and asserts shape + edge cases. The rest of the branding
// flow depends on the DOM and Supabase client and is covered by the manual
// preview checklist in PHASE-D-RESPONSIVE-QA.md.

import fs from 'node:fs';
import assert from 'node:assert/strict';

const src = fs.readFileSync(new URL('../index.html', import.meta.url), 'utf8');

function extract(name) {
  const start = src.indexOf(`function ${name}(`);
  assert.ok(start >= 0, `could not find ${name} in index.html`);
  // Walk braces starting from the first '{' after the signature.
  let i = src.indexOf('{', start);
  let depth = 0;
  for (; i < src.length; i++) {
    const c = src[i];
    if (c === '{') depth++;
    else if (c === '}') { depth--; if (depth === 0) { return src.slice(start, i + 1); } }
  }
  throw new Error(`unterminated function ${name}`);
}

const body = [
  extract('_shadeHex'),
  extract('_brandPathFor'),
  extract('_fileExt'),
  'return { _shadeHex, _brandPathFor, _fileExt };',
].join('\n\n');

const factory = new Function(body);
const { _shadeHex, _brandPathFor, _fileExt } = factory();

// _shadeHex
assert.equal(_shadeHex('#087a43',   0), '#087a43',    'identity when percent = 0');
assert.equal(_shadeHex('#087a43', -22).length, 7,     'returns a 7-char hex');
assert.equal(_shadeHex('bad-input', 50), 'bad-input', 'returns input unchanged when not 6 hex chars');
assert.equal(_shadeHex('#ffffff', -50), '#808080',    '50% toward black from white is mid-grey');
assert.equal(_shadeHex('#000000',  50), '#808080',    '50% toward white from black is mid-grey');

// _brandPathFor — enforces uppercase code and sanitised extension
assert.equal(_brandPathFor('bnfodio', 'logo', 'png'),    'BNFODIO/logo.png');
assert.equal(_brandPathFor('bnfodio', 'crest', 'JPG'),   'BNFODIO/crest.jpg');
assert.equal(_brandPathFor('demo',    'signature', 'webp'), 'DEMO/signature.webp');
assert.equal(_brandPathFor('demo',    'signature', '../../../etc/passwd'), 'DEMO/signature.etcpasswd',
  'strips non-alphanumerics from the extension to prevent path escape via ext');

// _fileExt — prefers the real extension, falls back to MIME
assert.equal(_fileExt('logo.PNG',       'image/png'),       'png');
assert.equal(_fileExt('logo',           'image/png'),       'png');
assert.equal(_fileExt('logo',           'image/jpeg'),      'jpg');
assert.equal(_fileExt('logo',           'image/webp'),      'webp');
assert.equal(_fileExt('logo',           'image/svg+xml'),   'svg');
assert.equal(_fileExt('whatever.heic',  'image/heic'),      'heic', 'preserves known extensions');
assert.equal(_fileExt('nope',           'application/pdf'), 'png',  'falls back to png when unknown');

console.log('OK — branding helper tests passed');
