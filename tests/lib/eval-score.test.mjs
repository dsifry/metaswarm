// Unit tests for evals/reviewer-rubric/score.js (run: node --test tests/lib/eval-score.test.mjs).
// Synthetic stream-json only; no model calls.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const require = createRequire(import.meta.url);
const SCRIPT = path.join(here, '..', '..', 'evals', 'reviewer-rubric', 'score.js');
const sc = require(SCRIPT);

const META = {
  agent: 'metaswarm:design-reviewer',
  rubric: 'cto-agent',
  checks: { noTestPlan: ['(?i)test plan'], strict: ['Exact'] },
};
const line = (o) => JSON.stringify(o);
const agentCall = (subagent_type) => line({ type: 'assistant', message: { content: [{ type: 'tool_use', name: 'Agent', input: { subagent_type } }] } });
const readCall = (file_path) => line({ type: 'assistant', parent_tool_use_id: 'x', message: { content: [{ type: 'tool_use', name: 'Read', input: { file_path } }, { type: 'text', text: 'hi' }] } });
const result = (text, extra = {}) => line({ type: 'result', result: text, total_cost_usd: 0.5, ...extra });
const tmp = () => fs.mkdtempSync(path.join(os.tmpdir(), 'eval-score-'));

test('events: skips blank and malformed lines', () => {
  assert.deepEqual(sc.events('{"a":1}\n\nnot json\n{"b":2}\n'), [{ a: 1 }, { b: 2 }]);
});

test('score: full hit', () => {
  const log = [agentCall(META.agent), readCall('/p/agents/cto-agent.md'), result('Criteria applied: CTO — TDD\nNo TEST PLAN. Exact')].join('\n');
  assert.deepEqual(sc.score(META, log), {
    spawned: true, readRubric: true, receipt: true,
    checks: { noTestPlan: true, strict: true }, caughtAll: true, costUsd: 0.5, error: null,
  });
});

test('score: misses, case-sensitive pattern, bold receipt and error result', () => {
  const log = [agentCall('other'), result('**Criteria applied:** x\nexact', { is_error: true, subtype: 'error_max_budget_usd' })].join('\n');
  const s = sc.score(META, log);
  assert.equal(s.spawned, false);
  assert.equal(s.readRubric, false);
  assert.equal(s.receipt, true);
  assert.deepEqual(s.checks, { noTestPlan: false, strict: false });
  assert.equal(s.caughtAll, false);
  assert.equal(s.error, 'error_max_budget_usd');
});

test('score: no result event and an error without subtype', () => {
  const s = sc.score(META, agentCall(META.agent));
  assert.equal(s.costUsd, 0);
  assert.equal(s.receipt, false);
  assert.equal(sc.score(META, result('', { is_error: true, total_cost_usd: undefined })).error, 'error');
});

test('score: a tool_use with no input still counts', () => {
  const log = line({ type: 'assistant', message: { content: [{ type: 'tool_use', name: 'Agent' }] } });
  assert.equal(sc.score(META, log).spawned, false);
  assert.equal(sc.score(META, line({ type: 'assistant', message: {} })).spawned, false);
});

test('score: passed or N/A criteria-check rows are not detected defects', () => {
  const reply = [
    '## APPROVED',
    'Criteria applied: CTO — TDD readiness',
    '### Criteria check',
    '| Item | Result | Evidence |',
    '|---|---|---|',
    '| Test plan present | PASS | section 4 |',
    '| Exact numbers | **N/A** | none |',
    '"criteria_check": [{ "item": "Test plan present", "result": "PASS", "evidence": "s4" }],',
    'No findings.',
  ].join('\n');
  const s = sc.score(META, result(reply));
  assert.deepEqual(s.checks, { noTestPlan: false, strict: false });
  assert.equal(s.caughtAll, false);
});

test('score: the receipt line and criteria_applied field are not detected defects', () => {
  const reply = ['## APPROVED', '**Criteria applied:** CTO — test plan, Exact', '"criteria_applied": "CTO — test plan, Exact",', 'No findings.'].join('\n');
  assert.deepEqual(sc.score(META, result(reply)).checks, { noTestPlan: false, strict: false });
});

test('score: a JSON reply with a criteria_applied field has a receipt', () => {
  assert.equal(sc.score(META, result('{ "verdict": "APPROVED", "criteria_applied": "CTO — TDD readiness" }')).receipt, true);
  assert.equal(sc.score(META, result('{ "criteria_applied": "" }')).receipt, false);
});

test('score: only reading the rubric counts, not searching for it', () => {
  const tool = (name, input) => line({ type: 'assistant', message: { content: [{ type: 'tool_use', name, input }] } });
  const searches = [tool('Glob', { pattern: '**/cto-agent.md' }), tool('Grep', { pattern: 'x', path: 'agents/cto-agent.md' }),
    tool('Bash', { command: 'find . -name cto-agent.md' }), tool('Bash', { command: 'ls agents/cto-agent.md' })];
  assert.equal(sc.score(META, searches.join('\n')).readRubric, false);
  assert.equal(sc.score(META, tool('Bash', { command: 'cat agents/cto-agent.md' })).readRubric, true);
  assert.equal(sc.score(META, tool('Bash', { command: "sed -n '1,80p' /p/cto-agent.md" })).readRubric, true);
  assert.equal(sc.score(META, tool('Grep', { pattern: '^#', path: '/p/cto-agent.md', output_mode: 'content' })).readRubric, true);
  for (const command of ['grep -n . /plugin/agents/cto-agent.md', 'cd /plugin && cat agents/cto-agent.md', 'ls agents; head -50 agents/cto-agent.md',
    "sed -n '1,5p;7,10p' /p/agents/cto-agent.md", 'grep -E "TDD|test" /p/agents/cto-agent.md', 'grep -n "a\\"|b" /p/cto-agent.md', 'cat /p/cto-agent.md \\'])
    assert.equal(sc.score(META, tool('Bash', { command })).readRubric, true, command);
  for (const command of ['grep -l TDD agents/cto-agent.md', 'grep -c x agents/cto-agent.md', 'grep -q x agents/cto-agent.md && cat other.md', 'wc -l agents/cto-agent.md'])
    assert.equal(sc.score(META, tool('Bash', { command })).readRubric, false, command);
  assert.equal(sc.score(META, [tool('Read', {}), tool('Bash', {}), tool('Grep', { output_mode: 'content' })].join('\n')).readRubric, false);
});

test('score: failed criteria-check rows and findings still count', () => {
  const reply = ['| Test plan present | FAIL | no test plan section |', '{ "item": "Exact", "result": "FAIL", "evidence": "x" }'].join('\n');
  assert.deepEqual(sc.score(META, result(reply)).checks, { noTestPlan: true, strict: true });
});

test('summary: rates per check and mean cost', () => {
  const a = { spawned: true, readRubric: true, receipt: false, checks: { x: true }, caughtAll: true, costUsd: 0.4 };
  const b = { spawned: true, readRubric: false, receipt: true, checks: { x: false }, caughtAll: false, costUsd: 0.2 };
  assert.deepEqual(sc.summary([a, b]), {
    trials: 2, spawned: '2/2', readRubric: '1/2', receipt: '1/2', x: '1/2', caughtAll: '1/2', meanCostUsd: 0.3,
  });
  assert.deepEqual(sc.summary([]), { trials: 0, spawned: '0/0', readRubric: '0/0', receipt: '0/0', caughtAll: '0/0', meanCostUsd: 0 });
});

test('report: markdown table over scenario summaries, skipping dirs without one', () => {
  const dir = tmp();
  fs.mkdirSync(path.join(dir, 'b-scn'));
  fs.mkdirSync(path.join(dir, 'a-scn'));
  fs.mkdirSync(path.join(dir, 'empty'));
  const s = { trials: 3, spawned: '3/3', readRubric: '0/3', receipt: '0/3', x: '2/3', caughtAll: '2/3', meanCostUsd: 0.4 };
  fs.writeFileSync(path.join(dir, 'a-scn', 'summary.json'), JSON.stringify(s));
  fs.writeFileSync(path.join(dir, 'b-scn', 'summary.json'), JSON.stringify(s));
  const md = sc.report(dir);
  assert.match(md, new RegExp(`^## ${path.basename(dir)}\\n`));
  assert.match(md, /\| a-scn \| 3\/3 \| 0\/3 \| 0\/3 \| x 2\/3 \| 2\/3 \| \$0\.4 \|\n\| b-scn /);
  assert.doesNotMatch(md, /empty/);
});

test('main: score, --summary and --report modes write through io.out', () => {
  const dir = tmp();
  const meta = path.join(dir, 'meta.json');
  const log = path.join(dir, 't.jsonl');
  fs.writeFileSync(meta, JSON.stringify(META));
  fs.writeFileSync(log, [agentCall(META.agent), result('test plan')].join('\n'));
  let out = '';
  const io = { out: (s) => { out += s; } };
  assert.equal(sc.main([meta, log], io), 0);
  const one = JSON.parse(out);
  assert.equal(one.checks.noTestPlan, true);

  const scn = path.join(dir, 'res', 'scn');
  fs.mkdirSync(scn, { recursive: true });
  fs.writeFileSync(path.join(scn, 't.score.json'), JSON.stringify(one));
  out = '';
  assert.equal(sc.main(['--summary', path.join(scn, 't.score.json')], io), 0);
  assert.equal(JSON.parse(out).noTestPlan, '1/1');
  fs.writeFileSync(path.join(scn, 'summary.json'), out);
  out = '';
  assert.equal(sc.main(['--report', path.join(dir, 'res')], io), 0);
  assert.match(out, /\| scn \| 1\/1 \|/);
});

test('main: file access goes through injected io, so no real files are needed', () => {
  const files = {
    '/m.json': JSON.stringify(META),
    '/t.jsonl': result('test plan'),
    '/r/scn/summary.json': JSON.stringify({ trials: 1, spawned: '1/1', readRubric: '0/1', receipt: '0/1', caughtAll: '0/1', meanCostUsd: 0 }),
  };
  let out = '';
  const io = {
    out: (s) => { out += s; },
    readFile: (p) => { if (!(p in files)) throw new Error(`ENOENT ${p}`); return files[p]; },
    readdir: (d) => (d === '/r' ? ['scn', 'nosummary'] : []),
    exists: (p) => p in files,
  };
  assert.equal(sc.main(['/m.json', '/t.jsonl'], io), 0);
  assert.equal(JSON.parse(out).checks.noTestPlan, true);
  out = '';
  assert.equal(sc.main(['--report', '/r'], io), 0);
  assert.match(out, /\| scn \| 1\/1 \|/);
  assert.doesNotMatch(out, /nosummary/);
  assert.throws(() => sc.main(['--summary', '/missing.json'], io), /ENOENT \/missing\.json/);
});

test('scenarios: each has a fixture, a prompt and a meta.json whose checks compile', () => {
  const dir = path.join(here, '..', '..', 'evals', 'reviewer-rubric', 'scenarios');
  const names = fs.readdirSync(dir);
  assert.ok(names.length >= 14, `expected at least 14 scenarios, found ${names.length}`);
  for (const n of names) {
    for (const f of ['fixture.sh', 'prompt.txt', 'meta.json']) assert.ok(fs.existsSync(path.join(dir, n, f)), `${n}/${f}`);
    const meta = JSON.parse(fs.readFileSync(path.join(dir, n, 'meta.json'), 'utf8'));
    assert.match(meta.agent, /^metaswarm:/, `${n}: agent`);
    assert.ok(meta.rubric, `${n}: rubric`);
    const checks = Object.entries(meta.checks);
    assert.ok(checks.length > 0, `${n}: checks`);
    for (const [k, patterns] of checks) {
      assert.ok(patterns.length > 0, `${n}.${k}: patterns`);
      // Every pattern compiles, not just those score() reaches before one misses.
      for (const p of patterns) assert.doesNotThrow(() => sc.compile(p), `${n}.${k}: ${p}`);
      // An unrelated reply must not satisfy a check.
      assert.equal(sc.score(meta, result('## APPROVED\nNo findings.')).checks[k], false, `${n}.${k} matches an empty review`);
    }
  }
});

test('compile: honours (?i)/(?is) prefixes and throws on an invalid pattern', () => {
  assert.equal(sc.compile('(?i)abc').test('ABC'), true);
  assert.equal(sc.compile('(?is)a.c').test('A\nC'), true);
  assert.throws(() => sc.compile('(?i)(unclosed'));
});

// Replies that mention a check's topic without reporting the defect must not count.
const scenarioMeta = (n) => JSON.parse(fs.readFileSync(path.join(here, '..', '..', 'evals', 'reviewer-rubric', 'scenarios', n, 'meta.json'), 'utf8'));
const negatives = {
  'code-review': { anyHigh: ['- MEDIUM — `any` should be narrowed to `string`.\n- HIGH — `toBeDefined()` only checks presence.'] },
  'design-ux': {
    uiStates: ['## UX review — APPROVED\nEmpty states and loading states look fine; error states are clear.'],
    integration: ['## UX review — APPROVED\nThe app shell wiring and the route are well described.'],
  },
  'design-security': {
    idor: ['## Security review — APPROVED\nThe ownership check is in place, so no other customer can read an invoice.'],
    secretsInLogs: ['## Security review — APPROVED\nTokens are never logged; the logging config redacts the Authorization header.'],
  },
};

test('scenarios: replies that mention a topic but report no defect do not count', () => {
  for (const [n, byCheck] of Object.entries(negatives)) {
    const meta = scenarioMeta(n);
    for (const [k, replies] of Object.entries(byCheck))
      for (const r of replies) assert.equal(sc.score(meta, result(r)).checks[k], false, `${n}.${k}: ${r}`);
  }
});

test('CLI: runs as a script and prints to stdout', () => {
  const dir = tmp();
  const meta = path.join(dir, 'meta.json');
  const log = path.join(dir, 't.jsonl');
  fs.writeFileSync(meta, JSON.stringify(META));
  fs.writeFileSync(log, result('nothing'));
  const r = spawnSync(process.execPath, [SCRIPT, meta, log], { encoding: 'utf8' });
  assert.equal(r.status, 0);
  assert.equal(JSON.parse(r.stdout).caughtAll, false);
});
