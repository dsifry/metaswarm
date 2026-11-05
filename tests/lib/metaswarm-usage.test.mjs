// Unit tests for bin/metaswarm-usage (run: node --test tests/lib/metaswarm-usage.test.mjs)
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import fs from 'node:fs';
import { spawnSync } from 'node:child_process';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const require = createRequire(import.meta.url);
const usage = require('../../bin/metaswarm-usage');
const FX = path.join(here, 'fixtures', 'usage');

function run(args, opts = {}) {
  let out = '';
  let err = '';
  const code = usage.main(args, {
    out: (s) => { out += s + '\n'; },
    err: (s) => { err += s + '\n'; },
    home: opts.home,
  });
  return { code, out, err };
}
const json = (args) => JSON.parse(run([...args, '--json']).out);
const rows = (list) => Object.fromEntries(list.map((r) => [r.key, r]));
const tok = (r) => [r.input, r.cacheWrite, r.cacheRead, r.output, r.spawns];

const PRICING = {
  'claude-opus-5-5': { input: 15, cacheWrite: 18.75, cacheRead: 1.5, output: 75 },
  'claude-sonnet-5-5': { input: 3, cache_write: 3.75, cache_read: 0.3, output: 15 },
};

test('classifyPhase: role types, prefixes and legacy names', () => {
  const c = (t) => usage.classifyPhase(t, '');
  assert.equal(c('design-reviewer'), 'design-review');
  assert.equal(c('metaswarm:plan-reviewer'), 'plan-review');
  assert.equal(c('metaswarm-researcher'), 'research');
  assert.equal(c('planner'), 'plan/decompose');
  assert.equal(c('coder'), 'implement');
  assert.equal(c('adversarial-reviewer'), 'adversarial-review');
  assert.equal(c('pr-shepherd-agent'), 'pr-shepherd');
  assert.equal(c('knowledge-curator-agent'), 'knowledge-curator');
  assert.equal(c('metaswarm:coder-agent'), 'implement');
  assert.equal(c('code-review-agent'), 'adversarial-review');
  assert.equal(c('researcher-agent'), 'research');
});

test('classifyPhase: keyword fallback on description', () => {
  const c = (d) => usage.classifyPhase('general-purpose', d);
  assert.equal(c('Plan review gate'), 'plan-review');
  assert.equal(c('Final review of Plan 2b'), 'plan-review');
  assert.equal(c('Design review round 2'), 'design-review');
  assert.equal(c('Adversarial review of WU1'), 'adversarial-review');
  assert.equal(c('Re-review shards'), 'adversarial-review');
  assert.equal(c('Decompose work units'), 'plan/decompose');
  assert.equal(c('Draft the plan'), 'plan/decompose');
  assert.equal(c('Research the API'), 'research');
  assert.equal(c('Explore the repo'), 'research');
  assert.equal(c('Implement WU3'), 'implement');
  assert.equal(c('Fix the bug'), 'implement');
  assert.equal(c('Water the plants'), 'unclassified');
  assert.equal(c(undefined), 'unclassified');
  assert.equal(usage.classifyPhase(undefined, undefined), 'unclassified');
});

test('exact per-type totals', () => {
  const r = json(['--root', FX]);
  const t = rows(r.byType);
  assert.deepEqual(tok(t['metaswarm:plan-reviewer']), [10, 100, 1000, 50, 1]);
  assert.deepEqual(tok(t['plan-reviewer']), [21, 201, 2001, 101, 2]);
  assert.deepEqual(tok(t['unknown']), [6, 51, 501, 26, 2]);
  assert.deepEqual(tok(t['general-purpose']), [16, 97, 907, 52, 8]);
  assert.deepEqual(tok(t['metaswarm-plan-reviewer']), [1, 2, 3, 4, 1]);
  assert.equal(r.agents, 25);
});

test('exact per-model totals', () => {
  const m = rows(json(['--root', FX]).byModel);
  assert.deepEqual(tok(m['claude-opus-5-5']), [56, 498, 4909, 255, 12]);
  assert.deepEqual(tok(m['claude-sonnet-5-5']), [20, 119, 1109, 64, 12]);
  assert.deepEqual(tok(m['unknown']), [0, 0, 0, 0, 1]);
});

test('exact per-phase totals', () => {
  const p = rows(json(['--root', FX]).byPhase);
  assert.deepEqual(tok(p['plan-review']), [34, 305, 3006, 157, 5]);
  assert.deepEqual(tok(p['design-review']), [13, 130, 1300, 65, 2]);
  assert.deepEqual(tok(p['adversarial-review']), [4, 22, 202, 12, 3]);
  assert.deepEqual(tok(p['research']), [3, 3, 3, 3, 3]);
  assert.deepEqual(tok(p['plan/decompose']), [5, 41, 401, 21, 2]);
  assert.deepEqual(tok(p['implement']), [7, 61, 601, 31, 4]);
  assert.deepEqual(tok(p['pr-shepherd']), [1, 1, 1, 1, 1]);
  assert.deepEqual(tok(p['knowledge-curator']), [1, 1, 1, 1, 1]);
  assert.deepEqual(tok(p['unclassified']), [8, 53, 503, 28, 4]);
});

test('grand totals and skipped malformed lines', () => {
  const r = json(['--root', FX]);
  assert.deepEqual(
    [r.totals.input, r.totals.cacheWrite, r.totals.cacheRead, r.totals.output],
    [76, 617, 6018, 319],
  );
  assert.equal(r.skippedLines, 1);
  const text = run(['--root', FX]);
  assert.match(text.out, /Skipped 1 malformed line/);
});

test('--project glob filters projects', () => {
  const r = json(['--root', FX, '--project', '*beta*']);
  assert.equal(r.agents, 10);
  const q = json(['--root', FX, '--project', '-fx-alph?']);
  assert.equal(q.agents, 15);
  assert.equal(json(['--root', FX, '--project', 'nomatch']).agents, 0);
  assert.equal(json(['--root', FX, '--project', 'a.b']).agents, 0);
});

test('empty root prints no transcripts and exits 0', () => {
  const d = fs.mkdtempSync(path.join(os.tmpdir(), 'usage-empty-'));
  const r = run(['--root', d]);
  assert.equal(r.code, 0);
  assert.match(r.out, /no transcripts/i);
  const missing = run(['--root', path.join(d, 'missing')]);
  assert.equal(missing.code, 0);
  assert.match(missing.out, /no transcripts/i);
  const j = JSON.parse(run(['--root', d, '--json']).out);
  assert.equal(j.agents, 0);
  fs.rmSync(d, { recursive: true });
});

test('default root is ~/.claude/projects under the home option', () => {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), 'usage-home-'));
  const r = run([], { home });
  assert.match(r.out, /no transcripts/i);
  assert.ok(r.out.includes(path.join(home, '.claude', 'projects')));
  fs.rmSync(home, { recursive: true });
  const dflt = usage.main(['--root', FX], { out() {}, err() {} });
  assert.equal(dflt, 0);
  assert.ok(usage.defaultRoot().endsWith(path.join('.claude', 'projects')));
});

test('--pricing adds cost columns', () => {
  const d = fs.mkdtempSync(path.join(os.tmpdir(), 'usage-price-'));
  const pf = path.join(d, 'p.json');
  fs.writeFileSync(pf, JSON.stringify(PRICING));
  const r = json(['--root', FX, '--pricing', pf]);
  const m = rows(r.byModel);
  assert.equal(m['claude-opus-5-5'].cost, 0.036666);
  assert.equal(m['claude-sonnet-5-5'].cost, 0.001799);
  assert.equal(r.totals.cost, 0.038465);
  assert.equal(rows(r.byPhase).implement.cost, 0.000895);
  const text = run(['--root', FX, '--pricing', pf]).out;
  assert.match(text, /Cost \(USD\)/);
  assert.match(text, /0\.0367/);
  assert.equal(json(['--root', FX]).totals.cost, undefined);
  // inline JSON, with an unpriced model
  const inline = JSON.stringify({ 'claude-opus-5-5': PRICING['claude-opus-5-5'] });
  const partial = json(['--root', FX, '--pricing', inline]);
  assert.deepEqual(partial.unpricedModels, ['claude-sonnet-5-5']);
  assert.match(run(['--root', FX, '--pricing', inline]).out, /Unpriced models: claude-sonnet-5-5/);
  assert.equal(json(['--root', FX, '--pricing', pf]).unpricedModels, undefined);
  fs.rmSync(d, { recursive: true });
});

test('--pricing errors', () => {
  const bad = run(['--root', FX, '--pricing', '{nope']);
  assert.equal(bad.code, 2);
  assert.match(bad.err, /pricing/i);
  const missing = run(['--root', FX, '--pricing']);
  assert.equal(missing.code, 2);
});

test('--gates reports rounds-to-pass', () => {
  const g = rows(json(['--root', FX, '--gates']).gates.summary);
  assert.deepEqual(
    [g['plan-review'].occurrences, g['plan-review'].totalRounds, g['plan-review'].avgRounds, g['plan-review'].firstRoundPass, g['plan-review'].maxRounds],
    [2, 3, 1.5, 1, 2],
  );
  assert.deepEqual(
    [g['design-review'].occurrences, g['design-review'].avgRounds, g['design-review'].firstRoundPass],
    [2, 1, 2],
  );
  assert.deepEqual([g['adversarial-review'].occurrences, g['adversarial-review'].avgRounds], [2, 1]);
  const occ = json(['--root', FX, '--gates']).gates.occurrences.filter((o) => o.gate === 'plan-review');
  assert.deepEqual(occ.map((o) => o.rounds).sort(), [1, 2]);
  const text = run(['--root', FX, '--gates']).out;
  assert.match(text, /Gate rounds-to-pass/);
  assert.match(text, /plan-review\s+2\s+1\s+1\s+0\s+1\.50/);
  assert.equal(json(['--root', FX]).gates, undefined);
});

test('--gates with no gate spawns, and --gap-minutes', () => {
  const r = json(['--root', FX, '--gates', '--project', 'nomatch']);
  assert.deepEqual(r.gates.summary, []);
  assert.match(run(['--root', FX, '--gates', '--project', 'nomatch']).out, /no transcripts/i);
  // 3 rounds: widen/narrow the gap threshold to prove it is honoured
  const narrow = rows(json(['--root', FX, '--gates', '--gap-minutes', '1']).gates.summary);
  assert.equal(narrow["plan-review"].totalRounds, 4);
  const wide = rows(json(['--root', FX, '--gates', '--gap-minutes', '60']).gates.summary);
  assert.equal(wide['plan-review'].totalRounds, 2);
  assert.equal(run(['--root', FX, '--gates', '--gap-minutes', 'x']).code, 2);
});

test('gate table buckets 3+ rounds', () => {
  const d = fs.mkdtempSync(path.join(os.tmpdir(), 'usage-g3-'));
  const sd = path.join(d, 'p', 's', 'subagents');
  fs.mkdirSync(sd, { recursive: true });
  [0, 10, 20].forEach((min, i) => {
    fs.writeFileSync(path.join(sd, `agent-${i}.meta.json`), JSON.stringify({ agentType: 'plan-reviewer' }));
    fs.writeFileSync(path.join(sd, `agent-${i}.jsonl`), JSON.stringify({ type: 'user', timestamp: `2026-01-01T10:${String(min).padStart(2, '0')}:00.000Z` }) + '\n');
  });
  const r = run(['--root', d, '--gates']);
  assert.match(r.out, /plan-review\s+1\s+0\s+0\s+1\s+3\.00/);
  fs.rmSync(d, { recursive: true });
});

test('CLI flags: help, unknown, missing values', () => {
  const h = run(['--help']);
  assert.equal(h.code, 0);
  assert.match(h.out, /Usage: metaswarm-usage/);
  const u = run(['--bogus']);
  assert.equal(u.code, 2);
  assert.match(u.err, /Unknown argument: --bogus/);
  assert.equal(run(['--root']).code, 2);
  assert.equal(run(['--project']).code, 2);
});

test('text report has the three tables', () => {
  const out = run(['--root', FX]).out;
  assert.match(out, /By agent type/);
  assert.match(out, /By model/);
  assert.match(out, /By phase/);
  assert.match(out, /plan-review\s+5\s+34\s+305\s+3006\s+157/);
});

test('process entrypoint wires argv and exit code', () => {
  const orig = { argv: process.argv, log: console.log, error: console.error, exit: process.exit };
  const logs = [];
  let code;
  process.argv = ['node', 'metaswarm-usage', '--root', FX];
  console.log = (s) => logs.push(s);
  process.exit = (c) => { code = c; };
  try { usage.cli(); } finally {
    process.argv = orig.argv; console.log = orig.log; console.error = orig.error; process.exit = orig.exit;
  }
  assert.equal(code, 0);
  assert.ok(logs.length > 0);
  const errs = [];
  console.error = (s) => errs.push(s);
  process.argv = ['node', 'metaswarm-usage', '--bogus'];
  process.exit = (c) => { code = c; };
  try { usage.cli(); } finally {
    process.argv = orig.argv; console.error = orig.error; process.exit = orig.exit;
  }
  assert.equal(code, 2);
  assert.equal(errs.length, 1);
});

test('sparse records: missing model, usage fields, bad timestamp, meta without type', () => {
  const d = fs.mkdtempSync(path.join(os.tmpdir(), 'usage-sparse-'));
  const sd = path.join(d, 'p', 's', 'subagents');
  fs.mkdirSync(sd, { recursive: true });
  fs.writeFileSync(path.join(sd, 'agent-x.meta.json'), '{}');
  fs.writeFileSync(
    path.join(sd, 'agent-x.jsonl'),
    [
      JSON.stringify({ type: 'user', timestamp: 'not-a-date' }),
      JSON.stringify({ type: 'assistant', message: { id: 'm1', usage: {} } }),
      JSON.stringify({ type: 'assistant', message: { id: 'm2', model: 'claude-x', usage: { output_tokens: 5 } } }),
      '',
    ].join('\n'),
  );
  const r = json(['--root', d, '--gates', '--pricing', JSON.stringify({ 'claude-x': { output: 1 }, unknown: { input: 1 } })]);
  assert.equal(r.byType[0].key, 'unknown');
  assert.deepEqual(rows(r.byModel).unknown.output, 0);
  assert.equal(rows(r.byModel)['claude-x'].output, 5);
  assert.equal(r.totals.cost, 0.000005);
  assert.deepEqual(r.gates.summary, []);
  fs.rmSync(d, { recursive: true });
});

test('rows with equal volume sort by key', () => {
  const d = fs.mkdtempSync(path.join(os.tmpdir(), 'usage-tie-'));
  const sd = path.join(d, 'p', 's', 'subagents');
  fs.mkdirSync(sd, { recursive: true });
  for (const t of ['bbb', 'aaa', 'ccc']) {
    fs.writeFileSync(path.join(sd, `agent-${t}.meta.json`), JSON.stringify({ agentType: t }));
    fs.writeFileSync(path.join(sd, `agent-${t}.jsonl`), '');
  }
  assert.deepEqual(json(['--root', d]).byType.map((r) => r.key), ['aaa', 'bbb', 'ccc']);
  assert.deepEqual(json(['--root', d]).byType.map((r) => r.key).reverse(), ['ccc', 'bbb', 'aaa']);
  fs.rmSync(d, { recursive: true });
});

test('executed directly as a script (shebang entrypoint)', () => {
  const bin = path.join(here, '..', '..', 'bin', 'metaswarm-usage');
  const r = spawnSync(process.execPath, [bin, '--root', FX, '--json'], { encoding: 'utf8' });
  assert.equal(r.status, 0);
  assert.equal(JSON.parse(r.stdout).agents, 25);
  const bad = spawnSync(process.execPath, [bin, '--bogus'], { encoding: 'utf8' });
  assert.equal(bad.status, 2);
});
