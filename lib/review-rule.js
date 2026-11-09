#!/usr/bin/env node
'use strict';
// Deterministic review-iteration rule (guides/delivery-scope.md).
// Usage: node lib/review-rule.js <review-history.json>
// Prints {line, action, signals:[{id, detail}], capHit} as JSON and exits 0.
// Bad input (unreadable file, invalid JSON, malformed rounds/findings) exits 2.
// ackFindings key (C1): `${canonicalTheme}:${assumption id}` for an assumption,
// otherwise `${canonicalTheme}:needs_user`; never the per-round finding id.
// Lines 4 and 5 need judgement; they arrive as per-round booleans.

const fs = require('fs');

const CAP = 10;

const RULE_LINES = [
  { line: 1, name: 'pass' },
  { line: 2, name: 'clarify' },
  { line: 3, name: 'cap' },
  { line: 4, name: 'recurring-or-disputed' },
  { line: 5, name: 'overengineering' },
  { line: 6, name: 'iterate-fixed-or-multi' },
  { line: 7, name: 'iterate' },
];

const isYes = (v) => v === 'yes' || v === true;
const themeOf = (f) => f.canonicalTheme || f.theme || null;
const findingsOf = (round) => round.findings || [];
const blockersOf = (round) => findingsOf(round).filter((f) => isYes(f.blocker));
const distinctOf = (round) => blockersOf(round).filter((f) => !f.mergedInto);

const isObject = (v) => v !== null && typeof v === 'object' && !Array.isArray(v);
// Same yes/true reading as isYes; anything else would be silently read as "no".
const BLOCKER_VALUES = ['yes', 'no', true, false, undefined];
const ROUND_FLAGS = ['recurring', 'disputed', 'overengineering'];
const FINDING_FLAGS = ['needs_user', 'fix_induced'];
const LIST_KEYS = ['confirmed', 'ackThemes', 'ackFindings'];

function validate(history) {
  if (!history || !Array.isArray(history.rounds) || history.rounds.length === 0) {
    throw new Error('review history must have a non-empty "rounds" array');
  }
  for (const key of LIST_KEYS) {
    const v = history[key];
    if (v !== undefined && !(Array.isArray(v) && v.every((x) => typeof x === 'string'))) {
      throw new Error(`"${key}" must be an array of strings`);
    }
  }
  let prev = 0;
  for (const r of history.rounds) {
    if (!isObject(r) || !Number.isInteger(r.round) || r.round < 1) {
      throw new Error('each round must be an object with an integer "round" >= 1');
    }
    if (r.round <= prev) throw new Error(`round ${r.round}: round numbers must be strictly increasing`);
    prev = r.round;
    for (const flag of ROUND_FLAGS) {
      if (!BLOCKER_VALUES.includes(r[flag])) {
        throw new Error(`round ${r.round}: "${flag}" must be yes, no, true or false`);
      }
    }
    const fcm = r.fixedCriticalMajor;
    if (fcm !== undefined && !(Number.isInteger(fcm) && fcm >= 0)) {
      throw new Error(`round ${r.round}: "fixedCriticalMajor" must be a non-negative integer`);
    }
    if (r.findings !== undefined && !Array.isArray(r.findings)) {
      throw new Error(`round ${r.round}: "findings" must be an array`);
    }
    for (const f of r.findings || []) {
      if (!isObject(f)) throw new Error(`round ${r.round}: each finding must be an object`);
      if (!BLOCKER_VALUES.includes(f.blocker)) {
        throw new Error(`round ${r.round}: "blocker" must be yes, no, true or false`);
      }
      for (const flag of FINDING_FLAGS) {
        if (!BLOCKER_VALUES.includes(f[flag])) {
          throw new Error(`round ${r.round}: "${flag}" must be yes, no, true or false`);
        }
      }
    }
    // A blocker merges only into another blocker of the same round; a blocker-vs-non-blocker
    // disagreement is the orchestrator's `disputed` flag, not a merge.
    const list = findingsOf(r);
    for (const f of list) {
      if (f.mergedInto === undefined) continue;
      const target = list.some((g) => g !== f && g.id === f.mergedInto && isYes(g.blocker));
      if (!target) {
        throw new Error(`round ${r.round}: "mergedInto" must name the id of another blocker in the same round`);
      }
    }
  }
}

function reviewerCounts(round) {
  const counts = new Map();
  for (const f of blockersOf(round)) {
    counts.set(f.reviewer, (counts.get(f.reviewer) || 0) + 1);
  }
  return counts;
}

function c1(history, last) {
  const confirmed = history.confirmed || [];
  const acked = new Set(history.ackFindings || []);
  // C1 scans every blocker, merged duplicates included; only C2-C4 count once.
  const hits = blockersOf(last).filter((f) => {
    const needsUser = isYes(f.needs_user);
    const unconfirmed = f.origin === 'assumption' && !confirmed.includes(f.assumption);
    if (!needsUser && !unconfirmed) return false;
    const key = `${themeOf(f) || ''}:${f.assumption || 'needs_user'}`;
    return !acked.has(key);
  });
  return hits.length
    ? { id: 'C1', detail: `${hits.length} blocker(s) need the user or rest on an unconfirmed assumption` }
    : null;
}

function divergence(history, windowed) {
  const last = windowed[windowed.length - 1];
  if (!(history.reviewers >= 2) || windowed.length < 2) return null;
  const prev = reviewerCounts(windowed[windowed.length - 2]);
  const now = reviewerCounts(last);
  const known = new Set();
  for (const r of windowed) for (const f of findingsOf(r)) known.add(f.reviewer);
  const hasZero = known.size < history.reviewers || [...known].some((r) => !now.get(r));
  if (!hasZero) return null;
  const rising = [...now].some(([r, n]) => n > (prev.get(r) || 0));
  return rising ? 'reviewers diverge: one reports no blockers while another rises' : null;
}

function c2(history, rounds) {
  const windowStart = history.windowStart || 1;
  const windowed = rounds.filter((r) => r.round >= windowStart);
  if (windowed.length >= 3) {
    const [a, b, c] = windowed.slice(-3).map((r) => distinctOf(r).length);
    if (a <= b && b <= c) {
      return { id: 'C2', detail: `blockers not converging over the last 3 rounds (${a}, ${b}, ${c})` };
    }
  }
  const div = divergence(history, windowed);
  return div ? { id: 'C2', detail: div } : null;
}

function c3(history, last) {
  if (last.round < (history.windowStart || 1)) return null;
  const n = distinctOf(last).filter((f) => isYes(f.fix_induced)).length;
  return n >= 2 ? { id: 'C3', detail: `${n} blockers were induced by the previous fix` } : null;
}

function c4(history, rounds) {
  const acked = new Set(history.ackThemes || []);
  const seen = new Map();
  for (const r of rounds) {
    for (const theme of new Set(distinctOf(r).map(themeOf))) {
      if (theme && !acked.has(theme)) seen.set(theme, (seen.get(theme) || 0) + 1);
    }
  }
  const themes = [...seen].filter(([, n]) => n >= 3).map(([t]) => t);
  return themes.length ? { id: 'C4', detail: `theme(s) in 3+ rounds: ${themes.join(', ')}` } : null;
}

function signalsFor(history, rounds, last) {
  return [c1(history, last), c2(history, rounds), c3(history, last), c4(history, rounds)].filter(Boolean);
}

function evaluate(history) {
  validate(history);
  const rounds = history.rounds;
  const last = rounds[rounds.length - 1];
  const capHit = last.round >= CAP;
  if (history.status === 'closed') {
    return { line: null, action: 'closed', signals: [], capHit };
  }
  const signals = signalsFor(history, rounds, last);
  if (history.status === 'clarify-pending') {
    return { line: 2, action: 're-ask', signals, capHit };
  }
  const pick = (line, action) => ({ line, action, signals, capHit });
  if (blockersOf(last).length === 0) return pick(1, 'pass');
  if (signals.length) return pick(2, 'clarify');
  if (capHit) return pick(3, 'escalate');
  if (isYes(last.recurring) || isYes(last.disputed)) return pick(4, 'escalate');
  if (isYes(last.overengineering)) return pick(5, 'overengineering-check');
  const reviewers = reviewerCounts(last).size;
  if (last.fixedCriticalMajor >= 1 || reviewers >= 2) return pick(6, 'iterate');
  return pick(7, 'iterate');
}

function main(argv, io = {}) {
  const out = io.out || ((s) => process.stdout.write(s));
  const err = io.err || ((s) => process.stderr.write(s));
  if (argv.length < 1) {
    err('usage: review-rule.js <review-history.json>');
    return 2;
  }
  let text;
  try {
    text = fs.readFileSync(argv[0], 'utf8');
  } catch (e) {
    err(`review-rule: cannot read ${argv[0]}: ${e.message}`);
    return 2;
  }
  let history;
  try {
    history = JSON.parse(text);
  } catch (e) {
    err(`review-rule: invalid JSON in ${argv[0]}: ${e.message}`);
    return 2;
  }
  try {
    out(JSON.stringify(evaluate(history)));
  } catch (e) {
    err(`review-rule: ${e.message}`);
    return 2;
  }
  return 0;
}

module.exports = { evaluate, main, RULE_LINES };

if (require.main === module) {
  process.exitCode = main(process.argv.slice(2));
}
