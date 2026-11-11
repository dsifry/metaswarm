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

// A criteria-check row that passed (or was N/A) names the item without reporting
// a defect, so drop those rows before matching. FAIL rows and findings stay.
const PASSED_ROW = /^\s*\|.*\|\s*(\*\*)?(PASS|N\/A)(\*\*)?\s*\|.*$/gim;
const PASSED_JSON = /\{[^{}\n]*"result"\s*:\s*"(PASS|N\/A)"[^{}\n]*\}/g;
// The receipt names the criteria applied, not defects found.
const RECEIPT = /^\s*(\*\*)?Criteria applied(\*\*)?:.*$|"criteria_applied"\s*:\s*"[^"\n]*"/gim;
const findingsText = (out) => out.replace(PASSED_ROW, '').replace(PASSED_JSON, '').replace(RECEIPT, '');

// Reading the file's text counts (Read, cat/sed/..., Grep in content mode);
// Glob, file-listing Grep, find and ls only locate it. A Bash command reads it
// when any segment (split on && || ; |) starts with a reader and names the
// file; grep counts unless it only lists, counts or tests (-l -L -c -q).
const READS_FILE = /^\s*(cat|head|tail|sed|awk|less|grep)\b/;
const GREP_NO_TEXT = /^\s*grep\b.*\s-[a-zA-Z]*[lLcq]/;
// Split a shell command at unquoted ; | && || (quotes and backslash escapes respected).
function segments(cmd) {
  const out = [''];
  let q = null;
  for (let i = 0; i < cmd.length; i++) {
    const c = cmd[i];
    if (q !== "'" && c === '\\') { out[out.length - 1] += c + (cmd[i + 1] || ''); i++; continue; }
    if (q) { if (c === q) q = null; out[out.length - 1] += c; continue; }
    if (c === "'" || c === '"') { q = c; out[out.length - 1] += c; continue; }
    if (c === ';' || c === '|' || (c === '&' && cmd[i + 1] === '&')) { if (cmd[i + 1] === c) i++; out.push(''); continue; }
    out[out.length - 1] += c;
  }
  return out;
}

function readsRubric(u, rubric) {
  const has = (v) => String(v || '').includes(rubric);
  if (u.name === 'Read') return has(u.input.file_path);
  if (u.name === 'Bash') {
    return segments(String(u.input.command || ''))
      .some((seg) => READS_FILE.test(seg) && !GREP_NO_TEXT.test(seg) && has(seg));
  }
  return u.name === 'Grep' && u.input.output_mode === 'content' && has(u.input.path);
}

function score(meta, text) {
  const evs = events(text);
  const uses = toolUses(evs);
  const result = evs.filter((e) => e.type === 'result').pop() || {};
  const out = String(result.result || '');
  const checks = {};
  const findings = findingsText(out);
  for (const [name, patterns] of Object.entries(meta.checks)) checks[name] = hit(patterns, findings);
  return {
    spawned: uses.some((u) => u.name === 'Agent' && u.input.subagent_type === meta.agent),
    readRubric: uses.some((u) => readsRubric(u, meta.rubric)),
    receipt: /^\s*(\*\*)?Criteria applied(\*\*)?:|"criteria_applied"\s*:\s*"[^"\n]+"/im.test(out),
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

// File access is injected; the real implementation is the default.
const realIo = {
  out: (s) => process.stdout.write(s),
  readFile: (p) => fs.readFileSync(p, 'utf8'),
  readdir: (d) => fs.readdirSync(d),
  exists: (p) => fs.existsSync(p),
};

function report(dir, io = realIo) {
  const rows = io.readdir(dir).filter((d) => io.exists(path.join(dir, d, 'summary.json'))).sort()
    .map((d) => [d, JSON.parse(io.readFile(path.join(dir, d, 'summary.json')))]);
  const lines = [`## ${path.basename(dir)}`, '', '| Scenario | Spawned | Read rubric | Receipt | Defect checks | All caught | Mean cost |', '|---|---|---|---|---|---|---|'];
  for (const [d, s] of rows) {
    const fixed = ['trials', 'spawned', 'readRubric', 'receipt', 'caughtAll', 'meanCostUsd'];
    const checks = Object.keys(s).filter((k) => !fixed.includes(k)).map((k) => `${k} ${s[k]}`).join(', ');
    lines.push(`| ${d} | ${s.spawned} | ${s.readRubric} | ${s.receipt} | ${checks} | ${s.caughtAll} | $${s.meanCostUsd} |`);
  }
  return lines.join('\n') + '\n';
}

function main(argv, ioOverrides = {}) {
  const io = { ...realIo, ...ioOverrides };
  if (argv[0] === '--summary') {
    const scores = argv.slice(1).map((p) => JSON.parse(io.readFile(p)));
    io.out(JSON.stringify(summary(scores)) + '\n');
  } else if (argv[0] === '--report') {
    io.out(report(argv[1], io));
  } else {
    const meta = JSON.parse(io.readFile(argv[0]));
    io.out(JSON.stringify(score(meta, io.readFile(argv[1]))) + '\n');
  }
  return 0;
}

module.exports = { score, summary, report, events, main };
if (require.main === module) process.exitCode = main(process.argv.slice(2));
