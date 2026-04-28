#!/usr/bin/env node
'use strict';

/**
 * Tests for lib/platform-registry.js — the single source of truth for
 * supported CLI hosts.
 */

const path = require('path');
const assert = require('assert');

const REPO_ROOT = path.resolve(__dirname, '..', '..');
const registry = require(path.join(REPO_ROOT, 'lib', 'platform-registry'));

let pass = 0;
let fail = 0;

function check(label, fn) {
  try {
    fn();
    console.log(`  PASS: ${label}`);
    pass++;
  } catch (e) {
    console.log(`  FAIL: ${label}`);
    console.log(`        ${e.message}`);
    fail++;
  }
}

// 1. Exports the expected API
check('exports platformKeys', () => assert.strictEqual(typeof registry.platformKeys, 'function'));
check('exports getPlatform',  () => assert.strictEqual(typeof registry.getPlatform, 'function'));
check('exports allPlatforms', () => assert.strictEqual(typeof registry.allPlatforms, 'function'));
check('exports resolvePlatform', () => assert.strictEqual(typeof registry.resolvePlatform, 'function'));
check('exports PLATFORMS object', () => assert.strictEqual(typeof registry.PLATFORMS, 'object'));

// 2. Knows about all four current CLIs in canonical order
check('platformKeys returns four platforms in canonical order', () => {
  const keys = registry.platformKeys();
  assert.deepStrictEqual(keys, ['claude', 'codex', 'gemini', 'opencode']);
});

// 3. Each platform has the required fields for downstream consumers
const REQUIRED_FIELDS = [
  'key', 'name', 'command', 'instructionFile', 'setupCommand',
  'installMethod', 'installCommand', 'parallelDispatch', 'summary',
];

for (const key of registry.platformKeys()) {
  check(`${key} platform has all required fields`, () => {
    const p = registry.getPlatform(key);
    for (const field of REQUIRED_FIELDS) {
      assert.ok(p[field] !== undefined && p[field] !== '', `Missing/empty: ${field}`);
    }
  });
}

// 4. resolvePlatform() converts callable fields to values
check('resolvePlatform resolves callable configDir', () => {
  const p = registry.resolvePlatform('claude');
  assert.strictEqual(typeof p.configDir, 'string');
  assert.ok(p.configDir.includes('.claude'));
});

check('resolvePlatform resolves callable installDir for codex', () => {
  const p = registry.resolvePlatform('codex');
  assert.strictEqual(typeof p.installDir, 'string');
  assert.ok(p.installDir.endsWith('metaswarm'));
});

check('resolvePlatform returns frozen object', () => {
  const p = registry.resolvePlatform('opencode');
  assert.ok(Object.isFrozen(p));
});

// 5. AGENTS.md is shared between codex and opencode (key invariant)
check('codex and opencode share AGENTS.md', () => {
  const codex = registry.getPlatform('codex');
  const opencode = registry.getPlatform('opencode');
  assert.strictEqual(codex.instructionFile, 'AGENTS.md');
  assert.strictEqual(opencode.instructionFile, 'AGENTS.md');
});

// 6. Each platform's setupCommand is non-empty and starts with '/' or '$'
for (const key of registry.platformKeys()) {
  check(`${key} setupCommand is well-formed`, () => {
    const p = registry.getPlatform(key);
    assert.ok(/^[\/\$]/.test(p.setupCommand), `Bad: ${p.setupCommand}`);
  });
}

// 7. Unknown platforms throw
check('getPlatform throws on unknown key', () => {
  assert.throws(() => registry.getPlatform('xyz'), /Unknown platform/);
});

// 8. allPlatforms returns same length as platformKeys
check('allPlatforms returns ordered array', () => {
  const keys = registry.platformKeys();
  const all = registry.allPlatforms();
  assert.strictEqual(all.length, keys.length);
  for (let i = 0; i < keys.length; i++) {
    assert.strictEqual(all[i].key, keys[i]);
  }
});

// 9. Command-format platforms have commandsDir
check('platforms with commandFormat also have commandsDir', () => {
  for (const p of registry.allPlatforms()) {
    if (p.commandFormat) {
      assert.ok(p.commandsDir, `${p.key} has commandFormat but no commandsDir`);
    }
  }
});

console.log(`\nResults: ${pass} passed, ${fail} failed`);
if (fail > 0) process.exit(1);
