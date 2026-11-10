#!/usr/bin/env node
'use strict';
// Scoring for evals/reviewer-rubric/run.sh.
//   score.js <meta.json> <trial.jsonl>   -> one trial's score as JSON
//   score.js --summary <score.json>...   -> per-scenario rates as JSON
//   score.js --report <label-dir>        -> markdown table over all scenarios
const fs = require('fs');
const path = require('path');

function events(text) {
  return text.split('\n').filter(Boolean).flatMap((l) => {
    try { return [JSON.parse(l)]; } catch { return []; }
  });
}

function toolUses(evs) {
  return evs
    .filter((e) => e.type === 'assistant' && e.message && Array.isArray(e.message.content))
    .flatMap((e) => e.message.content.filter((c) => c.type === 'tool_use')
      .map((c) => ({ name: c.name, input: c.input || {} })));
}

// "(?i)" / "(?is)" prefixes set JS flags; every pattern in a check must match.
function re(p) {
  const m = /^\(\?([a-z]+)\)/.exec(p);
  return m ? new RegExp(p.slice(m[0].length), m[1]) : new RegExp(p);
}
const hit = (patterns, text) => patterns.every((p) => re(p).test(text));

function score(meta, text) {
  const evs = events(text);
  const uses = toolUses(evs);
  const result = evs.filter((e) => e.type === 'result').pop() || {};
  const out = String(result.result || '');
  const inputs = uses.map((u) => JSON.stringify(u.input));
  const checks = {};
  for (const [name, patterns] of Object.entries(meta.checks)) checks[name] = hit(patterns, out);
  return {
    spawned: uses.some((u) => u.name === 'Agent' && u.input.subagent_type === meta.agent),
    readRubric: inputs.some((s) => s.includes(meta.rubric)),
    receipt: /^\s*(\*\*)?Criteria applied(\*\*)?:/im.test(out),
    checks,
    caughtAll: Object.values(checks).every(Boolean),
    costUsd: result.total_cost_usd || 0,
    error: result.is_error ? String(result.subtype || 'error') : null,
  };
}

function summary(scores) {
  const n = scores.length;
  const count = (f) => `${scores.filter(f).length}/${n}`;
  const s = { trials: n, spawned: count((x) => x.spawned), readRubric: count((x) => x.readRubric), receipt: count((x) => x.receipt) };
  const names = n ? Object.keys(scores[0].checks) : [];
  for (const k of names) s[k] = count((x) => x.checks[k]);
  s.caughtAll = count((x) => x.caughtAll);
  s.meanCostUsd = n ? Number((scores.reduce((a, x) => a + x.costUsd, 0) / n).toFixed(3)) : 0;
  return s;
}

function report(dir) {
  const rows = fs.readdirSync(dir).filter((d) => fs.existsSync(path.join(dir, d, 'summary.json'))).sort()
    .map((d) => [d, JSON.parse(fs.readFileSync(path.join(dir, d, 'summary.json'), 'utf8'))]);
  const lines = [`## ${path.basename(dir)}`, '', '| Scenario | Spawned | Read rubric | Receipt | Defect checks | All caught | Mean cost |', '|---|---|---|---|---|---|---|'];
  for (const [d, s] of rows) {
    const fixed = ['trials', 'spawned', 'readRubric', 'receipt', 'caughtAll', 'meanCostUsd'];
    const checks = Object.keys(s).filter((k) => !fixed.includes(k)).map((k) => `${k} ${s[k]}`).join(', ');
    lines.push(`| ${d} | ${s.spawned} | ${s.readRubric} | ${s.receipt} | ${checks} | ${s.caughtAll} | $${s.meanCostUsd} |`);
  }
  return lines.join('\n') + '\n';
}

function main(argv, io = { out: (s) => process.stdout.write(s) }) {
  if (argv[0] === '--summary') {
    const scores = argv.slice(1).map((p) => JSON.parse(fs.readFileSync(p, 'utf8')));
    io.out(JSON.stringify(summary(scores)) + '\n');
  } else if (argv[0] === '--report') {
    io.out(report(argv[1]));
  } else {
    const meta = JSON.parse(fs.readFileSync(argv[0], 'utf8'));
    io.out(JSON.stringify(score(meta, fs.readFileSync(argv[1], 'utf8'))) + '\n');
  }
  return 0;
}

module.exports = { score, summary, report, events, main };
if (require.main === module) process.exitCode = main(process.argv.slice(2));
