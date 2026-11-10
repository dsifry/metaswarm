// Unit tests for lib/review-rule.js (run: node --test tests/lib/review-rule.test.mjs)
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
const rule = require('../../lib/review-rule.js');
const SCRIPT = path.join(here, '..', '..', 'lib', 'review-rule.js');

// n distinct blockers from reviewer `rev`, with unique ids and optional overrides.
let seq = 0;
const blockers = (n, rev = 'A', extra = {}) =>
  Array.from({ length: n }, () => ({ reviewer: rev, blocker: 'yes', id: `f${++seq}`, ...extra }));
const rnd = (round, findings, extra = {}) => ({ round, findings, ...extra });
const hist = (rounds, extra = {}) => ({ gate: 'plan', reviewers: 1, rounds, ...extra });
const ids = (out) => out.signals.map((s) => s.id).sort();
// Unthemed padding that keeps the total converging (4, 2, 0 extra) so C2 stays quiet.
const pad = (n) => blockers(Math.max(0, 6 - 2 * n));
const totals = (counts) => counts.map((n, i) => rnd(i + 1, blockers(n)));

test('RULE_LINES: seven named lines', () => {
  assert.deepEqual(rule.RULE_LINES.map((l) => l.line), [1, 2, 3, 4, 5, 6, 7]);
  assert.deepEqual(rule.RULE_LINES.map((l) => l.name), [
    'pass', 'clarify', 'cap', 'recurring-or-disputed', 'overengineering',
    'iterate-fixed-or-multi', 'iterate',
  ]);
});

test('case study: 10,4,5,6 fires C2 at round 4 but not round 3', () => {
  const h = hist(totals([10, 4, 5, 6]));
  const at4 = rule.evaluate(h);
  assert.equal(at4.line, 2);
  assert.equal(at4.action, 'clarify');
  assert.deepEqual(ids(at4), ['C2']);
  const at3 = rule.evaluate(hist(h.rounds.slice(0, 3)));
  assert.notEqual(at3.line, 2);
});

test('converging 10,4,1 never clarifies', () => {
  const out = rule.evaluate(hist(totals([10, 4, 1])));
  assert.ok(out.line === 6 || out.line === 7);
  assert.equal(out.action, 'iterate');
  assert.deepEqual(out.signals, []);
});

test('D4-style divergence fires C2', () => {
  const h = hist([
    rnd(1, [...blockers(2, 'A'), ...blockers(3, 'B')]),
    rnd(2, blockers(7, 'A')),
  ], { reviewers: 2 });
  // B (known reviewer) has 0 in the last round; A rose 2 -> 7.
  const out = rule.evaluate(h);
  assert.deepEqual(ids(out), ['C2']);
  assert.match(out.signals[0].detail, /diverg/i);
});

test('divergence: unseen reviewer counts as zero; needs a previous round; needs a rise', () => {
  const two = { reviewers: 2 };
  // only A ever appears, but 2 reviewers declared: the other is at 0
  assert.deepEqual(ids(rule.evaluate(hist([rnd(1, blockers(1)), rnd(2, blockers(3))], two))), ['C2']);
  // no previous round: no divergence
  assert.deepEqual(rule.evaluate(hist([rnd(1, blockers(3))], two)).signals, []);
  // A flat 3 -> 3, B at 0: no rise
  const flat = hist([rnd(1, [...blockers(3, 'A'), ...blockers(1, 'B')]), rnd(2, blockers(3, 'A'))], two);
  assert.deepEqual(rule.evaluate(flat).signals, []);
  // everyone has blockers: no zero reviewer
  const all = hist([rnd(1, [...blockers(1, 'A'), ...blockers(1, 'B')]), rnd(2, [...blockers(3, 'A'), ...blockers(1, 'B')])], two);
  assert.deepEqual(rule.evaluate(all).signals, []);
  // reviewer absent from previous round counts as 0 there
  const absent = hist([rnd(1, blockers(1, 'A')), rnd(2, [...blockers(1, 'B'), ...blockers(1, 'C')])], { reviewers: 3 });
  assert.deepEqual(ids(rule.evaluate(absent)), ['C2']);
});

const many = (spec) => Object.entries(spec).flatMap(([rev, n]) => blockers(n, rev));

test('divergence needs the total not to fall: 6 reviewers, totals 10, 4, 1, a different one rising each round', () => {
  const six = { reviewers: 6 };
  const r1 = many({ R1: 2, R2: 2, R3: 2, R4: 2, R5: 1, R6: 1 });
  const r2 = many({ R1: 3, R2: 1 }); // R1 rose 2 -> 3, R3-R6 at 0, total 4
  const r3 = many({ R4: 1 }); // R4 rose 0 -> 1, the rest at 0, total 1
  const two = rule.evaluate(hist([rnd(1, r1), rnd(2, r2)], six));
  assert.deepEqual(two.signals, []);
  assert.equal(two.line, 6);
  const three = rule.evaluate(hist([rnd(1, r1), rnd(2, r2), rnd(3, r3)], six));
  assert.deepEqual(three.signals, []);
  assert.ok([6, 7].includes(three.line)); // round 3 has a single reporting reviewer
});

test('divergence: a flat total with one reviewer at 0 and another rising still fires (PM drops, Designer rises)', () => {
  const h = hist([
    rnd(1, many({ PM: 3, Designer: 1, Architect: 1 })),
    rnd(2, many({ PM: 0, Designer: 3, Architect: 2 })),
  ], { reviewers: 3 });
  const out = rule.evaluate(h);
  assert.deepEqual(ids(out), ['C2']);
  assert.match(out.signals[0].detail, /diverg/i);
});

test('divergence: a falling total never fires, even with a zero reviewer and a rising one', () => {
  const h = hist([
    rnd(1, many({ A: 4, B: 3 })),
    rnd(2, many({ A: 5 })), // total 7 -> 5, B at 0, A rose
  ], { reviewers: 2 });
  assert.deepEqual(rule.evaluate(h).signals, []);
});

test('divergence: a flat total with a reviewer at 0 but nobody rising does not fire', () => {
  const h = hist([rnd(1, many({ A: 3 })), rnd(2, many({ A: 3 }))], { reviewers: 2 });
  assert.deepEqual(rule.evaluate(h).signals, []);
});

test('divergence: a rising total with no reviewer at 0 is not divergence (non-convergence may still apply)', () => {
  const rounds = [rnd(1, many({ A: 1, B: 1 })), rnd(2, many({ A: 2, B: 1 })), rnd(3, many({ A: 3, B: 1 }))];
  const two = rule.evaluate(hist(rounds.slice(0, 2), { reviewers: 2 }));
  assert.deepEqual(two.signals, []);
  const three = rule.evaluate(hist(rounds, { reviewers: 2 }));
  assert.deepEqual(ids(three), ['C2']);
  assert.match(three.signals[0].detail, /not converging/i);
});

test('single reviewer never fires divergence', () => {
  const h = hist([rnd(1, blockers(2)), rnd(2, blockers(7))]);
  assert.deepEqual(rule.evaluate(h).signals, []);
});

test('merged duplicate still counts once per reviewer for divergence', () => {
  const kept = { reviewer: 'A', blocker: 'yes', id: 'k' };
  const dupe = { reviewer: 'B', blocker: 'yes', id: 'd', mergedInto: 'k' };
  const h = hist([
    rnd(1, [...blockers(2, 'C')]),
    rnd(2, [kept, dupe, ...blockers(2, 'A')]),
  ], { reviewers: 3 });
  // B reported only a duplicate (counted for B), C has 0 now; A rose 0 -> 3.
  assert.deepEqual(ids(rule.evaluate(h)), ['C2']);
  // and B's merged duplicate prevents a "zero" reviewer when all others reported
  const h2 = hist([
    rnd(1, [...blockers(1, 'A')]),
    rnd(2, [kept, dupe]),
  ], { reviewers: 2 });
  // A has 1 (kept), B has 1 (dupe): nobody at 0
  assert.deepEqual(rule.evaluate(h2).signals, []);
});

test('C3: two fix_induced blockers fire; one does not; duplicates count once', () => {
  const two = rule.evaluate(hist([rnd(1, blockers(2, 'A', { fix_induced: 'yes' }))]));
  assert.deepEqual(ids(two), ['C3']);
  assert.equal(two.line, 2);
  assert.deepEqual(rule.evaluate(hist([rnd(1, blockers(1, 'A', { fix_induced: 'yes' }))])).signals, []);
  const kept = { reviewer: 'A', blocker: 'yes', id: 'k', fix_induced: 'yes' };
  const dupe = { reviewer: 'B', blocker: 'yes', id: 'd', fix_induced: 'yes', mergedInto: 'k' };
  const out = rule.evaluate(hist([rnd(1, [kept, dupe])], { reviewers: 2 }));
  assert.deepEqual(out.signals, []);
});

test('C4: one canonical theme in 3 rounds fires; 2 rounds does not', () => {
  const t = (n) => rnd(n, [...pad(n), ...blockers(1, 'A', { canonicalTheme: 'x' })]);
  assert.deepEqual(ids(rule.evaluate(hist([t(1), t(2), t(3)]))), ['C4']);
  assert.deepEqual(rule.evaluate(hist([t(1), t(2)])).signals, []);
});

test('C4: theme falls back; no theme counts toward none; merged duplicates count once', () => {
  const th = (n) => rnd(n, [...pad(n), ...blockers(1, 'A', { theme: 'y' })]);
  assert.deepEqual(ids(rule.evaluate(hist([th(1), th(2), th(3)]))), ['C4']);
  const none = (n) => rnd(n, pad(n).concat(blockers(1)));
  assert.deepEqual(rule.evaluate(hist([none(1), none(2), none(3)])).signals.filter((s) => s.id === 'C4'), []);
  // same theme twice in one round (two findings) is still one round
  const dbl = (n) => rnd(n, blockers(2, 'A', { canonicalTheme: 'z' }));
  assert.deepEqual(rule.evaluate(hist([dbl(1), dbl(2)])).signals.filter((s) => s.id === 'C4'), []);
  // merged duplicate in a round does not add a round
  const dup = { reviewer: 'B', blocker: 'yes', id: 'd', canonicalTheme: 'q', mergedInto: 'a3' };
  const rounds = [
    rnd(1, [{ reviewer: 'A', blocker: 'yes', id: 'a1', canonicalTheme: 'q' }]),
    rnd(2, [{ reviewer: 'A', blocker: 'yes', id: 'a2', canonicalTheme: 'q' }]),
    rnd(3, [{ reviewer: 'A', blocker: 'yes', id: 'a3', canonicalTheme: 'other' }, dup]),
  ];
  assert.deepEqual(rule.evaluate(hist(rounds, { reviewers: 2 })).signals.filter((s) => s.id === 'C4'), []);
});

test('C1: needs_user at round 1; assumption confirmed vs unconfirmed vs missing id', () => {
  const nu = rule.evaluate(hist([rnd(1, blockers(1, 'A', { needs_user: 'yes' }))]));
  assert.deepEqual(ids(nu), ['C1']);
  const asm = (a) => blockers(1, 'A', { origin: 'assumption', ...(a ? { assumption: a } : {}) });
  assert.deepEqual(rule.evaluate(hist([rnd(1, asm('a1'))], { confirmed: ['a1'] })).signals, []);
  assert.deepEqual(ids(rule.evaluate(hist([rnd(1, asm('a2'))], { confirmed: ['a1'] }))), ['C1']);
  assert.deepEqual(ids(rule.evaluate(hist([rnd(1, asm(null))], { confirmed: ['a1'] }))), ['C1']);
  assert.deepEqual(ids(rule.evaluate(hist([rnd(1, asm('a2'))]))), ['C1']);
});

test('C1: boolean true blocker/needs_user accepted; merged duplicate still scanned; non-blockers ignored', () => {
  const f = { reviewer: 'A', blocker: true, id: 'b', needs_user: 'yes' };
  assert.deepEqual(ids(rule.evaluate(hist([rnd(1, [f])]))), ['C1']);
  const dupe = { reviewer: 'B', blocker: 'yes', id: 'd', needs_user: 'yes', mergedInto: 'k' };
  const kept = { reviewer: 'A', blocker: 'yes', id: 'k' };
  assert.deepEqual(ids(rule.evaluate(hist([rnd(1, [kept, dupe])], { reviewers: 2 }))), ['C1']);
  const nb = { reviewer: 'A', blocker: 'no', id: 'n', needs_user: 'yes' };
  assert.equal(rule.evaluate(hist([rnd(1, [nb, kept])])).signals.length, 0);
});

test('C1: kept finding needs_user no, merged duplicate needs_user yes -> C1 line 2', () => {
  const kept = { reviewer: 'A', blocker: 'yes', id: 'k', needs_user: 'no' };
  const dupe = { reviewer: 'B', blocker: 'yes', id: 'd', needs_user: 'yes', mergedInto: 'k' };
  const out = rule.evaluate(hist([rnd(1, [kept, dupe])], { reviewers: 2 }));
  assert.equal(out.line, 2);
  assert.deepEqual(ids(out), ['C1']);
  const asm = { reviewer: 'B', blocker: 'yes', id: 'd2', origin: 'assumption', assumption: 'x', mergedInto: 'k' };
  assert.deepEqual(ids(rule.evaluate(hist([rnd(1, [kept, asm])], { reviewers: 2 }))), ['C1']);
});

test('missing needs_user and origin trigger nothing', () => {
  const out = rule.evaluate(hist([rnd(1, [{ reviewer: 'A', blocker: 'yes' }])]));
  assert.equal(out.action, 'iterate');
  assert.deepEqual(out.signals, []);
});

test('acknowledgement: window move requires 3 new rounds for C2', () => {
  const base = totals([10, 4, 5, 6]);
  const moved = hist(base, { windowStart: 5 });
  assert.notEqual(rule.evaluate(moved).line, 2);
  const six = hist(totals([10, 4, 5, 6, 7, 8]), { windowStart: 5 });
  assert.notEqual(rule.evaluate(six).line, 2); // only rounds 5,6
  const seven = hist(totals([10, 4, 5, 6, 7, 8, 9]), { windowStart: 5 });
  assert.deepEqual(ids(rule.evaluate(seven)), ['C2']);
});

test('acknowledgement: C4 ignores acked themes but other themes keep counting', () => {
  const r = (n) => rnd(n, [
    ...pad(n),
    { reviewer: 'A', blocker: 'yes', id: `a${n}`, canonicalTheme: 'acked' },
    { reviewer: 'A', blocker: 'yes', id: `b${n}`, canonicalTheme: 'live' },
  ]);
  const out = rule.evaluate(hist([r(1), r(2), r(3)], { ackThemes: ['acked'], windowStart: 3 }));
  const c4 = out.signals.find((s) => s.id === 'C4');
  assert.ok(c4);
  assert.match(c4.detail, /live/);
  assert.doesNotMatch(c4.detail, /acked/);
  const both = rule.evaluate(hist([r(1), r(2), r(3)], { ackThemes: ['acked', 'live'] }));
  assert.deepEqual(both.signals, []);
});

test('acknowledgement: new needs_user still fires; acknowledged finding key does not', () => {
  const f = (a) => ({ reviewer: 'A', blocker: 'yes', id: 'n1', needs_user: 'yes', canonicalTheme: 't', ...a });
  const h = (extra) => hist([rnd(1, [f()]), rnd(2, [f({ id: 'n2' })])], extra);
  assert.deepEqual(ids(rule.evaluate(h({ ackFindings: ['t:other'], windowStart: 2 }))), ['C1']);
  assert.deepEqual(rule.evaluate(hist([rnd(1, [f()])], { ackFindings: ['t:needs_user'] })).signals, []);
  const asm = { reviewer: 'A', blocker: 'yes', id: 'z', theme: 'tt', origin: 'assumption', assumption: 'as1' };
  assert.deepEqual(rule.evaluate(hist([rnd(1, [asm])], { ackFindings: ['tt:as1'] })).signals, []);
  // no theme: a themed key does not match, and the empty-theme key never counts as acknowledged
  const bare = { reviewer: 'A', blocker: 'yes', id: 'q', needs_user: 'yes' };
  assert.deepEqual(ids(rule.evaluate(hist([rnd(1, [bare])], { ackFindings: ['t:needs_user'] }))), ['C1']);
  assert.deepEqual(ids(rule.evaluate(hist([rnd(1, [bare])], { ackFindings: [':needs_user'] }))), ['C1']);
});

test('acknowledgement: key is theme:needs_user, independent of finding id and round', () => {
  const f = (id) => ({ reviewer: 'A', blocker: 'yes', id, needs_user: 'yes', canonicalTheme: 'owner' });
  const ack = { ackFindings: ['owner:needs_user'] };
  assert.deepEqual(rule.evaluate(hist([rnd(1, [f('x1')])], ack)).signals, []);
  assert.deepEqual(rule.evaluate(hist([rnd(1, [f('x1')]), rnd(2, [f('zzz')])], { ...ack, windowStart: 2 })).signals, []);
});

test('acknowledgement: windowStart bounds divergence (reviewers and rounds)', () => {
  const two = { reviewers: 2 };
  // (a) window starts after the last round: no C2
  const a = hist([rnd(1, blockers(1, 'A')), rnd(2, blockers(3, 'A'))], { ...two, windowStart: 3 });
  assert.ok([6, 7].includes(rule.evaluate(a).line));
  // (b) only one round in the window: no C2
  const b = hist([rnd(1, blockers(1, 'A')), rnd(2, blockers(1, 'A')), rnd(3, blockers(3, 'A'))], { ...two, windowStart: 3 });
  assert.deepEqual(rule.evaluate(b).signals, []);
  // (c) two diverging rounds in the window: C2
  const c = hist([rnd(1, blockers(1, 'A')), rnd(2, blockers(1, 'A')), rnd(3, blockers(1, 'A')), rnd(4, blockers(3, 'A'))], { ...two, windowStart: 3 });
  assert.deepEqual(ids(rule.evaluate(c)), ['C2']);
  // (d) window = rounds 3-4. Both A and B report blockers in round 4, so no reviewer is at zero:
  // no C2, even though B rises 0 -> 1 and B's round-1 blocker lies outside the window.
  const d = hist([rnd(1, blockers(1, 'B')), rnd(2, blockers(1, 'A')), rnd(3, blockers(1, 'A')), rnd(4, [...blockers(1, 'A'), ...blockers(1, 'B')])], { ...two, windowStart: 3 });
  assert.deepEqual(rule.evaluate(d).signals, []);
});

test('acknowledgement: C3 does not fire for a round before windowStart', () => {
  const h = hist([rnd(1, blockers(2, 'A', { fix_induced: 'yes' }))], { windowStart: 2 });
  assert.deepEqual(rule.evaluate(h).signals, []);
});

test('precedence: pass > clarify > cap > recurring/disputed > overengineering > iterate', () => {
  // 1 beats 2: no blockers, even with a round >= 10 and flags
  const pass = rule.evaluate(hist([rnd(10, [{ reviewer: 'A', blocker: 'no' }], { recurring: true })]));
  assert.equal(pass.line, 1);
  assert.equal(pass.action, 'pass');
  assert.equal(pass.capHit, true);
  // 2 beats 3
  const c = rule.evaluate(hist([rnd(10, blockers(1, 'A', { needs_user: 'yes' }))]));
  assert.equal(c.line, 2);
  assert.equal(c.capHit, true);
  // 3 beats 4
  const cap = rule.evaluate(hist([rnd(10, blockers(1), { recurring: true })]));
  assert.equal(cap.line, 3);
  assert.equal(cap.action, 'escalate');
  assert.equal(cap.capHit, true);
  // 4 beats 5 (recurring and disputed each)
  assert.equal(rule.evaluate(hist([rnd(1, blockers(1), { recurring: true, overengineering: true })])).line, 4);
  const dis = rule.evaluate(hist([rnd(1, blockers(1), { disputed: true, overengineering: true })]));
  assert.equal(dis.line, 4);
  assert.equal(dis.action, 'escalate');
  // 5 beats 6
  const oe = rule.evaluate(hist([rnd(1, blockers(1), { overengineering: true, fixedCriticalMajor: 2 })]));
  assert.equal(oe.line, 5);
  assert.equal(oe.action, 'overengineering-check');
});

test('lines 6 and 7: fixedCriticalMajor, multiple reviewers, otherwise iterate', () => {
  const six = rule.evaluate(hist([rnd(1, blockers(1), { fixedCriticalMajor: 1 })]));
  assert.deepEqual([six.line, six.action, six.capHit], [6, 'iterate', false]);
  const multi = rule.evaluate(hist([rnd(1, [...blockers(1, 'A'), ...blockers(1, 'B')])], { reviewers: 2 }));
  assert.equal(multi.line, 6);
  const seven = rule.evaluate(hist([rnd(1, blockers(1))]));
  assert.equal(seven.line, 7);
  // reviewer B only has a merged duplicate: still two reviewers with blockers
  const kept = { reviewer: 'A', blocker: 'yes', id: 'k' };
  const dupe = { reviewer: 'B', blocker: 'yes', id: 'd', mergedInto: 'k' };
  assert.equal(rule.evaluate(hist([rnd(1, [kept, dupe])], { reviewers: 2 })).line, 6);
});

test('status closed and clarify-pending', () => {
  const closed = rule.evaluate(hist(totals([10, 4, 5, 6]), { status: 'closed' }));
  assert.equal(closed.line, null);
  assert.equal(closed.action, 'closed');
  assert.deepEqual(closed.signals, []);
  assert.equal(closed.capHit, false);
  const pending = rule.evaluate(hist(totals([10, 4, 5, 6]), { status: 'clarify-pending' }));
  assert.equal(pending.line, 2);
  assert.equal(pending.action, 're-ask');
  assert.deepEqual(ids(pending), ['C2']);
  const pendingBare = rule.evaluate(hist(totals([1]), { status: 'clarify-pending' }));
  assert.equal(pendingBare.action, 're-ask');
  assert.deepEqual(pendingBare.signals, []);
});

test('capHit is true at round >= 10 whichever line wins, false below', () => {
  assert.equal(rule.evaluate(hist([rnd(9, blockers(1))])).capHit, false);
  assert.equal(rule.evaluate(hist([rnd(11, blockers(1))])).capHit, true);
});

test('windowStart defaults to 1; findings default to empty', () => {
  assert.equal(rule.evaluate(hist([rnd(1, undefined)])).line, 1);
  assert.equal(rule.evaluate({ rounds: [{ round: 1 }] }).line, 1);
});

test('bad input: strict validation throws', () => {
  const bad = (h) => assert.throws(() => rule.evaluate(h));
  bad({ rounds: [1] });
  bad({ rounds: [null] });
  bad({ rounds: [{ findings: [] }] });
  bad({ rounds: [{ round: 0 }] });
  bad({ rounds: [{ round: 1.5 }] });
  bad({ rounds: [{ round: '1' }] });
  bad({ rounds: [{ round: 1, findings: 'x' }] });
  bad({ rounds: [{ round: 1, findings: [1] }] });
  bad({ rounds: [{ round: 1, findings: [null] }] });
  bad({ rounds: [{ round: 1, findings: [{ blocker: 'Yes' }] }] });
  bad({ rounds: [{ round: 1, findings: [{ blocker: 1 }] }] });
  for (const v of ['yes', 'no', true, false, undefined]) {
    assert.doesNotThrow(() => rule.evaluate({ rounds: [{ round: 1, findings: [{ blocker: v }] }] }));
  }
});

test('C2: flat totals (6, 6, 6) and plateaus at either end fire (<=, not <)', () => {
  assert.deepEqual(ids(rule.evaluate(hist(totals([6, 6, 6])))), ['C2']);
  assert.deepEqual(ids(rule.evaluate(hist(totals([5, 6, 6])))), ['C2']);
  assert.deepEqual(ids(rule.evaluate(hist(totals([6, 6, 7])))), ['C2']);
  assert.deepEqual(rule.evaluate(hist(totals([7, 6, 6]))).signals, []);
});

test('C2: a merged duplicate counts once (distinct 3,2,1 converges although totals are 3,3,3)', () => {
  const dupes = (n, to) => Array.from({ length: n }, () => ({ reviewer: 'A', blocker: 'yes', id: `d${++seq}`, mergedInto: to }));
  const round = (n, distinct) => {
    const kept = blockers(distinct);
    return rnd(n, [...kept, ...dupes(3 - distinct, kept[0].id)]);
  };
  const out = rule.evaluate(hist([round(1, 3), round(2, 2), round(3, 1)]));
  assert.deepEqual(out.signals, []);
});

test('canonicalTheme beats theme for C4', () => {
  const same = (n) => rnd(n, [...pad(n), ...blockers(1, 'A', { canonicalTheme: 'same', theme: `t${n}` })]);
  assert.ok(ids(rule.evaluate(hist([same(1), same(2), same(3)]))).includes('C4'));
  const differ = (n) => rnd(n, [...pad(n), ...blockers(1, 'A', { canonicalTheme: `c${n}`, theme: 'same' })]);
  assert.ok(!ids(rule.evaluate(hist([differ(1), differ(2), differ(3)]))).includes('C4'));
});

test('precedence: pass beats clarify when a signal is active and the last round is clean', () => {
  const x = (n) => rnd(n, blockers(1, 'A', { canonicalTheme: 'x' }));
  const out = rule.evaluate(hist([x(1), x(2), x(3), rnd(4, [])]));
  assert.ok(ids(out).includes('C4'));
  assert.equal(out.line, 1);
  assert.equal(out.action, 'pass');
});

test('line 1 never passes while any blocker exists, merged duplicates included', () => {
  // a is merged into b: one distinct blocker remains, and two blockers exist.
  const a = { reviewer: 'A', blocker: 'yes', id: 'a', mergedInto: 'b' };
  const b = { reviewer: 'A', blocker: 'yes', id: 'b' };
  const out = rule.evaluate(hist([rnd(1, [a, b])]));
  assert.notEqual(out.line, 1);
  assert.equal(out.action, 'iterate');
});

test('mergedInto must name another blocker in the same round', () => {
  const k = { reviewer: 'A', blocker: 'yes', id: 'k' };
  const minor = { reviewer: 'A', blocker: 'no', id: 'm' };
  const dup = (to, extra = {}) => ({ reviewer: 'B', blocker: 'yes', id: 'd', mergedInto: to, ...extra });
  const two = { reviewers: 2 };
  const bad = (rounds) => assert.throws(() => rule.evaluate(hist(rounds, two)), /mergedInto/);
  bad([rnd(1, [minor, dup('m')])]); // blocker merged into a non-blocker
  bad([rnd(1, [k, dup('nope')])]); // dangling id
  bad([rnd(1, [dup('d')])]); // self-merge
  bad([rnd(1, [k]), rnd(2, [dup('k')])]); // target in another round
  assert.doesNotThrow(() => rule.evaluate(hist([rnd(1, [k, dup('k')])], two)));
  const r = run([tmpFile(JSON.stringify(hist([rnd(1, [minor, dup('m')])], two)))]);
  assert.equal(r.code, 2);
  assert.match(r.err, /mergedInto/);
});

test('round flags accept yes/no/true/false/absent only', () => {
  for (const flag of ['recurring', 'disputed', 'overengineering']) {
    for (const v of ['maybe', 'Yes', 'true', 1, 0, null, {}]) {
      assert.throws(() => rule.evaluate(hist([rnd(1, blockers(1), { [flag]: v })])), new RegExp(flag), `${flag}=${JSON.stringify(v)}`);
    }
    for (const v of ['yes', 'no', true, false, undefined]) {
      assert.doesNotThrow(() => rule.evaluate(hist([rnd(1, blockers(1), { [flag]: v })])));
    }
  }
});

test('round flags read through isYes: "no" does not escalate, "yes" does', () => {
  const all = rule.evaluate(hist([rnd(1, blockers(1), { recurring: 'no', disputed: 'no', overengineering: 'no' })]));
  assert.deepEqual([all.line, all.action], [7, 'iterate']);
  const oe = rule.evaluate(hist([rnd(1, blockers(1), { overengineering: 'no' })]));
  assert.equal(oe.line, 7);
  const rec = rule.evaluate(hist([rnd(1, blockers(1), { recurring: 'no' })]));
  assert.equal(rec.line, 7);
  const dis = rule.evaluate(hist([rnd(1, blockers(1), { disputed: 'yes' })]));
  assert.deepEqual([dis.line, dis.action], [4, 'escalate']);
  assert.equal(rule.evaluate(hist([rnd(1, blockers(1), { overengineering: 'yes' })])).line, 5);
});

test('finding flags needs_user and fix_induced accept yes/no/true/false/absent only', () => {
  for (const flag of ['needs_user', 'fix_induced']) {
    for (const v of ['maybe', 'Yes', 'true', 1, 0, null, {}]) {
      const f = { reviewer: 'A', blocker: 'yes', id: 'x', [flag]: v };
      assert.throws(() => rule.evaluate(hist([rnd(1, [f])])), new RegExp(flag), `${flag}=${JSON.stringify(v)}`);
    }
    for (const v of ['yes', 'no', true, false, undefined]) {
      const f = { reviewer: 'A', blocker: 'yes', id: 'x', [flag]: v };
      assert.doesNotThrow(() => rule.evaluate(hist([rnd(1, [f])])));
    }
  }
});

test('fixedCriticalMajor is a non-negative integer or absent', () => {
  for (const v of [-1, 1.5, '2', null, true, NaN]) {
    assert.throws(() => rule.evaluate(hist([rnd(1, blockers(1), { fixedCriticalMajor: v })])), /fixedCriticalMajor/);
  }
  for (const v of [0, 3, undefined]) {
    assert.doesNotThrow(() => rule.evaluate(hist([rnd(1, blockers(1), { fixedCriticalMajor: v })])));
  }
});

test('confirmed, ackThemes and ackFindings are arrays of strings when present', () => {
  for (const key of ['confirmed', 'ackThemes', 'ackFindings']) {
    for (const v of ['x', [1], [null], null, {}, ['a', 2]]) {
      assert.throws(() => rule.evaluate(hist([rnd(1, blockers(1))], { [key]: v })), new RegExp(key), `${key}=${JSON.stringify(v)}`);
    }
    for (const v of [[], ['a'], undefined]) {
      assert.doesNotThrow(() => rule.evaluate(hist([rnd(1, blockers(1))], { [key]: v })));
    }
  }
});

test('round numbers must be strictly increasing', () => {
  const at = (...ns) => hist(ns.map((n) => rnd(n, blockers(1))));
  assert.throws(() => rule.evaluate(at(1, 1)), /increasing/);
  assert.throws(() => rule.evaluate(at(2, 1)), /increasing/);
  assert.throws(() => rule.evaluate(at(1, 3, 2)), /increasing/);
  assert.doesNotThrow(() => rule.evaluate(at(1, 3)));
});

test('bad input: validate throws', () => {
  assert.throws(() => rule.evaluate({}), /rounds/);
  assert.throws(() => rule.evaluate({ rounds: [] }), /rounds/);
  assert.throws(() => rule.evaluate(null), /rounds/);
});

function tmpFile(content) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'review-rule-'));
  const p = path.join(dir, 'h.json');
  fs.writeFileSync(p, content);
  return p;
}
function run(args) {
  let out = '';
  let err = '';
  const code = rule.main(args, { out: (s) => { out += s + '\n'; }, err: (s) => { err += s + '\n'; } });
  return { code, out, err };
}

test('validate: tightened optional fields exit 2 when malformed', () => {
  const bad = [
    { reviewers: 0 }, { reviewers: 1.5 }, { reviewers: '2' },
    { windowStart: 0 }, { windowStart: 'x' }, { windowStart: 1.2 },
    { status: 'open' }, { status: 3 },
  ];
  for (const extra of bad) {
    assert.throws(() => rule.evaluate(hist(totals([1]), extra)), /must be/, JSON.stringify(extra));
  }
  for (const f of [{ origin: 'guess' }, { reviewer: 7 }]) {
    const h = hist([rnd(1, [{ blocker: 'yes', id: 'x', reviewer: 'A', ...f }])]);
    assert.throws(() => rule.evaluate(h), /must be/, JSON.stringify(f));
  }
});

test('validate: accepted values for the tightened fields', () => {
  for (const status of ['active', 'clarify-pending', 'closed']) {
    assert.doesNotThrow(() => rule.evaluate(hist(totals([1]), { status, reviewers: 2, windowStart: 1 })));
  }
  for (const origin of ['implementation', 'requirement', 'assumption']) {
    const h = hist([rnd(1, [{ blocker: 'yes', id: 'x', reviewer: 'PM', origin, assumption: 'A1' }])]);
    assert.doesNotThrow(() => rule.evaluate(h));
  }
});

test('mergedInto: null is treated as unmerged', () => {
  const f = [
    { reviewer: 'A', blocker: 'yes', id: 'a', fix_induced: 'yes', mergedInto: null },
    { reviewer: 'B', blocker: 'yes', id: 'b', fix_induced: 'yes', mergedInto: null },
  ];
  assert.deepEqual(ids(rule.evaluate(hist([rnd(1, f)], { reviewers: 2 }))), ['C3']);
});

test('reviewers: 1 with findings from two reviewer names never reports divergence', () => {
  const r1 = [...blockers(2, 'PM'), ...blockers(2, 'Architect')];
  const r2 = [...blockers(3, 'PM')];
  const out = rule.evaluate(hist([rnd(1, r1), rnd(2, r2)], { reviewers: 1 }));
  assert.ok(!ids(out).includes('C2'));
});

test('main: prints JSON and exits 0', () => {
  const p = tmpFile(JSON.stringify(hist(totals([10, 4, 5, 6]))));
  const r = run([p]);
  assert.equal(r.code, 0);
  const o = JSON.parse(r.out);
  assert.equal(o.line, 2);
  assert.deepEqual(Object.keys(o).sort(), ['action', 'capHit', 'line', 'signals']);
});

test('main: bad input exits 2 with stderr message', () => {
  assert.equal(run([]).code, 2);
  assert.match(run([]).err, /usage/i);
  const missing = run(['/no/such/file.json']);
  assert.equal(missing.code, 2);
  assert.match(missing.err, /cannot read/i);
  const bad = run([tmpFile('{nope')]);
  assert.equal(bad.code, 2);
  assert.match(bad.err, /invalid json/i);
  const norounds = run([tmpFile('{"gate":"plan"}')]);
  assert.equal(norounds.code, 2);
  assert.match(norounds.err, /rounds/);
  for (const body of ['{"rounds":[1]}', '{"rounds":[{"findings":[]}]}', '{"rounds":[{"round":1,"findings":[{"blocker":"Yes"}]}]}']) {
    assert.equal(run([tmpFile(body)]).code, 2, body);
  }
});

test('main: default io writes to process streams (spawnSync)', () => {
  const p = tmpFile(JSON.stringify(hist(totals([1]))));
  const ok = spawnSync(process.execPath, [SCRIPT, p], { encoding: 'utf8' });
  assert.equal(ok.status, 0);
  assert.equal(JSON.parse(ok.stdout).line, 7);
  const bad = spawnSync(process.execPath, [SCRIPT, '/no/such.json'], { encoding: 'utf8' });
  assert.equal(bad.status, 2);
  assert.match(bad.stderr, /cannot read/i);
});

// Guide parity: the guide's rule block and the helper's RULE_LINES must agree.
const GUIDE_KEYWORDS = {
  pass: /PASS/,
  clarify: /Clarify/,
  cap: /SAFETY_CAP/,
  'recurring-or-disputed': /recurs/,
  overengineering: /overengineering signal/,
  'iterate-fixed-or-multi': /≥2 independent/,
  iterate: /otherwise/,
};

function guideRuleLines() {
  const guide = fs.readFileSync(path.join(here, '..', '..', 'guides', 'delivery-scope.md'), 'utf8');
  const block = guide.match(/```text\n(after each review round[\s\S]*?)```/);
  assert.ok(block, 'guide has the iteration rule block');
  // A rule line starts with "  N. "; continuation lines are indented further and belong to it.
  const lines = [];
  for (const raw of block[1].split('\n')) {
    const m = raw.match(/^ {2}(\d)\. (.*)$/);
    if (m) lines.push({ line: Number(m[1]), text: m[2] });
    else if (lines.length && /^ {3,}\S/.test(raw)) lines[lines.length - 1].text += ` ${raw.trim()}`;
  }
  return lines;
}

test('guide parity: the rule block matches RULE_LINES (numbers, order, names)', () => {
  const parsed = guideRuleLines();
  assert.deepEqual(parsed.map((l) => l.line), rule.RULE_LINES.map((l) => l.line));
  for (const [i, def] of rule.RULE_LINES.entries()) {
    assert.match(parsed[i].text, GUIDE_KEYWORDS[def.name], `guide line ${def.line} should be "${def.name}"`);
  }
});

test('guide parity: line actions agree with the helper actions', () => {
  const parsed = guideRuleLines();
  const text = (n) => parsed.find((l) => l.line === n).text;
  assert.match(text(1), /PASS/);
  assert.match(text(2), /stop/i);
  assert.match(text(3), /escalate/);
  assert.match(text(4), /escalate/);
  assert.match(text(5), /escalate|downgrade/);
  assert.match(text(6), /FRESH review/);
  assert.match(text(7), /FRESH review/);
  assert.match(text(2), /Clarification report/);
});

test('guide parity: documented helper actions equal the actions the helper can emit', () => {
  const guide = fs.readFileSync(path.join(here, '..', '..', 'guides', 'delivery-scope.md'), 'utf8');
  const para = guide.split('\n').find((l) => l.startsWith('The actions are'));
  assert.ok(para, 'guide lists the actions');
  const documented = [...para.matchAll(/`([a-z-]+)` \(/g)].map((m) => m[1]).sort();
  const src = fs.readFileSync(SCRIPT, 'utf8');
  const emitted = new Set([...src.matchAll(/(?:pick\(\d, |action: )'([a-z-]+)'/g)].map((m) => m[1]));
  assert.deepEqual(documented, [...emitted].sort());
  // and each one is actually reachable
  const seen = new Set([
    rule.evaluate(hist(totals([0]))).action,
    rule.evaluate(hist([rnd(1, blockers(1, 'A', { needs_user: 'yes' }))])).action,
    rule.evaluate(hist([rnd(10, blockers(1))])).action,
    rule.evaluate(hist([rnd(1, blockers(1), { overengineering: 'yes' })])).action,
    rule.evaluate(hist(totals([1]))).action,
    rule.evaluate(hist(totals([1]), { status: 'clarify-pending' })).action,
    rule.evaluate(hist(totals([1]), { status: 'closed' })).action,
  ]);
  assert.deepEqual([...seen].sort(), documented);
});

test('ackFindings key: assumption id whenever assumption is set, whatever the origin', () => {
  const f = { reviewer: 'A', blocker: 'yes', id: 'x', theme: 'T', origin: 'implementation', assumption: 'A9', needs_user: 'yes' };
  assert.deepEqual(ids(rule.evaluate(hist([rnd(1, [f])]))), ['C1']);
  assert.deepEqual(ids(rule.evaluate(hist([rnd(1, [f])], { ackFindings: ['T:A9'] }))), []);
  assert.deepEqual(ids(rule.evaluate(hist([rnd(1, [f])], { ackFindings: ['T:needs_user'] }))), ['C1']);
  const bare = { reviewer: 'A', blocker: 'yes', id: 'y', needs_user: 'yes' };
  assert.deepEqual(ids(rule.evaluate(hist([rnd(1, [bare])], { ackFindings: [':needs_user'] }))), ['C1']);
});

test('ack granularity: an acknowledged needs_user key clears only re-raises of the same question', () => {
  const ack = { ackFindings: ['auth:needs_user'] };
  const same = { reviewer: 'A', blocker: 'yes', id: 'a', canonicalTheme: 'auth', needs_user: 'yes', title: 'which IdP?' };
  const newQuestion = { ...same, id: 'b', canonicalTheme: 'auth-idp' };
  const r1 = rnd(1, blockers(1, 'A', { needs_user: 'yes', canonicalTheme: 'auth' }));
  assert.deepEqual(ids(rule.evaluate(hist([r1, rnd(2, [same])], ack))), []);
  assert.deepEqual(ids(rule.evaluate(hist([r1, rnd(2, [newQuestion])], ack))), ['C1']);
  // a new assumption id under an acknowledged theme also fires
  const asm = { reviewer: 'A', blocker: 'yes', id: 'c', canonicalTheme: 'auth', origin: 'assumption', assumption: 'A7' };
  assert.deepEqual(ids(rule.evaluate(hist([r1, rnd(2, [asm])], { ackFindings: ['auth:A6'] }))), ['C1']);
  assert.deepEqual(ids(rule.evaluate(hist([r1, rnd(2, [asm])], { ackFindings: ['auth:A7'] }))), []);
});

test('re-ask returns line 2 with the current signals; divergence needs 2 rounds in the window', () => {
  const f = blockers(1, 'A', { needs_user: 'yes' });
  const out = rule.evaluate(hist([rnd(1, f)], { status: 'clarify-pending' }));
  assert.equal(out.line, 2);
  assert.deepEqual(ids(out), ['C1']);
  // After option 2 moves the window to round 3, a divergent round 3 alone cannot fire C2.
  const r = [rnd(1, blockers(1, 'A')), rnd(2, blockers(1, 'A')), rnd(3, [...blockers(2, 'A'), ...blockers(0, 'B')])];
  assert.ok(!ids(rule.evaluate(hist(r, { reviewers: 2, windowStart: 3 }))).includes('C2'));
});

test('option 2 re-entry: line 2 holds until every fired C1 key is answered or acknowledged', () => {
  const trust = { reviewer: 'A', blocker: 'yes', id: 't', canonicalTheme: 'trust', needs_user: 'yes' };
  const rounds = [rnd(1, blockers(2)), rnd(2, blockers(2)), rnd(3, [trust, ...blockers(1)])];
  // windowStart moved to the next round (4) by the acknowledgement of C2; C1 key still unanswered.
  const before = rule.evaluate(hist(rounds, { windowStart: 4, ackFindings: [] }));
  assert.equal(before.line, 2);
  assert.equal(before.action, 'clarify');
  assert.deepEqual(ids(before), ['C1']);
  // Once the key is acknowledged and nothing else fires, review continues past line 2.
  const after = rule.evaluate(hist(rounds, { windowStart: 4, ackFindings: ['trust:needs_user'] }));
  assert.ok([6, 7].includes(after.line), `line ${after.line}`);
  assert.deepEqual(ids(after), []);
  // An unacknowledged C4 theme also keeps line 2 until it is in ackThemes.
  const t = (n) => rnd(n, blockers(1, 'A', { canonicalTheme: 'perf' }));
  const c4 = [t(1), t(2), t(3)];
  assert.deepEqual(ids(rule.evaluate(hist(c4, { windowStart: 4 }))), ['C4']);
  assert.deepEqual(ids(rule.evaluate(hist(c4, { windowStart: 4, ackThemes: ['perf'] }))), []);
});

test('validate: merge cycles, empty assumption', () => {
  const chain = [
    { reviewer: 'A', blocker: 'yes', id: 'a', mergedInto: 'b' },
    { reviewer: 'B', blocker: 'yes', id: 'b', mergedInto: 'c' },
    { reviewer: 'C', blocker: 'yes', id: 'c' },
  ];
  assert.throws(() => rule.evaluate(hist([rnd(1, chain)])), /mergedInto/);
  const cycle = [
    { reviewer: 'A', blocker: 'yes', id: 'a', mergedInto: 'b' },
    { reviewer: 'B', blocker: 'yes', id: 'b', mergedInto: 'a' },
  ];
  assert.throws(() => rule.evaluate(hist([rnd(1, cycle)])), /mergedInto/);
  const empty = [{ reviewer: 'A', blocker: 'yes', id: 'a', origin: 'assumption', assumption: '' }];
  assert.throws(() => rule.evaluate(hist([rnd(1, empty)])), /assumption/);
});

test('validate: windowStart beyond the last round is accepted', () => {
  assert.doesNotThrow(() => rule.evaluate(hist(totals([1, 1]), { windowStart: 9 })));
});

test('guide parity: action-to-line mapping equals the helper pick() calls', () => {
  const guide = fs.readFileSync(path.join(here, '..', '..', 'guides', 'delivery-scope.md'), 'utf8');
  const para = guide.split('\n').find((l) => l.startsWith('The actions are'));
  const documented = {};
  for (const m of para.matchAll(/`([a-z-]+)` \(lines? (\d+)(?: and (\d+))?\)/g)) {
    documented[m[1]] = [Number(m[2]), ...(m[3] ? [Number(m[3])] : [])].sort();
  }
  const src = fs.readFileSync(SCRIPT, 'utf8');
  const emitted = {};
  for (const m of src.matchAll(/pick\((\d), '([a-z-]+)'\)/g)) {
    (emitted[m[2]] ||= []).push(Number(m[1]));
  }
  for (const k of Object.keys(emitted)) emitted[k].sort();
  assert.deepEqual(documented, emitted);
});

test('needs_user with a confirmed assumption id still fires; only ackFindings clears it', () => {
  const nu = { reviewer: 'A', blocker: 'yes', id: 'n', canonicalTheme: 'idp', needs_user: 'yes', origin: 'assumption', assumption: 'A1' };
  assert.deepEqual(ids(rule.evaluate(hist([rnd(1, [nu])], { confirmed: ['A1'] }))), ['C1']);
  assert.deepEqual(ids(rule.evaluate(hist([rnd(1, [nu])], { confirmed: ['A1'], ackFindings: ['idp:A1'] }))), []);
  // confirmed clears an assumption blocker that does not need the user
  const plain = { reviewer: 'A', blocker: 'yes', id: 'p', canonicalTheme: 'idp', origin: 'assumption', assumption: 'A1' };
  assert.deepEqual(ids(rule.evaluate(hist([rnd(1, [plain])], { confirmed: ['A1'] }))), []);
  assert.deepEqual(ids(rule.evaluate(hist([rnd(1, [plain])], { confirmed: [] }))), ['C1']);
});

test('empty-theme backstop: an empty-theme key never counts as acknowledged', () => {
  const noTheme = { reviewer: 'A', blocker: 'yes', id: 'n', needs_user: 'yes' };
  assert.deepEqual(ids(rule.evaluate(hist([rnd(1, [noTheme])], { ackFindings: [':needs_user'] }))), ['C1']);
  const noThemeAsm = { reviewer: 'A', blocker: 'yes', id: 'm', origin: 'assumption', assumption: 'A2' };
  assert.deepEqual(ids(rule.evaluate(hist([rnd(1, [noThemeAsm])], { ackFindings: [':A2'] }))), ['C1']);
  // with a theme the same acknowledgement sticks
  const themed = { ...noThemeAsm, theme: 'x' };
  assert.deepEqual(ids(rule.evaluate(hist([rnd(1, [themed])], { ackFindings: ['x:A2'] }))), []);
});

test('validate: assumption must be a non-empty string; null exits 2', () => {
  for (const assumption of [null, '', 7]) {
    const f = [{ reviewer: 'A', blocker: 'yes', id: 'a', origin: 'assumption', assumption }];
    assert.throws(() => rule.evaluate(hist([rnd(1, f)])), /assumption/, String(assumption));
  }
});
