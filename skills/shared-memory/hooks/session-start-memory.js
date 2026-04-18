#!/usr/bin/env node
// SessionStart hook — inject recent shared-memory entries into the session context.
//
// Reads pinned + recent semantic/procedural entries from ~/.claude/shared-memory/learnings.db
// and emits them as additionalContext on stdout per Claude Code hook protocol.
//
// Keeps output small (≤ ~1.5KB) so it never dominates context. Honors SS_MEMORY_DISABLE=1.

const path = require('path');

function emit(additionalContext) {
  // Claude Code SessionStart protocol: JSON with additionalContext string.
  try {
    process.stdout.write(JSON.stringify({ hookSpecificOutput: { hookEventName: 'SessionStart', additionalContext } }));
  } catch (_) {}
  process.exit(0);
}

if (process.env.SS_MEMORY_DISABLE === '1') emit('');

let store;
try {
  const lib = process.env.SHARED_MEMORY_LIB || path.resolve(process.env.HOME, '.claude/shared-memory/lib');
  store = require(path.join(lib, 'store.js'));
} catch (e) {
  process.stderr.write(`[session-start-memory] store unavailable: ${e.message}\n`);
  emit('');
}

// Pull: top 3 pinned, top 5 recent procedural, top 5 recent semantic (global + current project).
let project = null;
try {
  const cfg = require(path.resolve(process.env.HOME, '.skrivstore/lib/config.js'));
  project = cfg.resolveTeamAndProject().project;
} catch (_) {}

const scopes = ['global'];
if (project) scopes.push(`project:${project}`);

function recentByType(type, limit) {
  try {
    return store.search({ query: '', scopes, types: [type], limit });
  } catch (_) { return []; }
}

let procedural = recentByType('procedural', 5);
let semantic = recentByType('semantic', 5);
let episodic = recentByType('episodic', 3);

// Pending handoffs addressed to current team
let team = null;
try {
  team = process.env.SS_SYNC_TEAM || require(path.resolve(process.env.HOME, '.skrivstore/lib/config.js')).resolveTeamAndProject().team;
} catch (_) {}
let handoffs = [];
try {
  handoffs = store.search({ query: 'handoff', scopes: ['global'], types: ['episodic'], limit: 50 })
    .filter((e) => e.key && e.key.startsWith('handoff:'))
    .map((e) => { try { return { e, b: JSON.parse(e.body) }; } catch { return null; } })
    .filter((x) => x && x.b.to === team && !x.b.ack)
    .slice(0, 5);
} catch (_) {}

// Reflexion — surface top-K relevant gotchas for current work (Q5)
// Scans ~/projects/skrivsikkert/.beads/knowledge/{gotchas,anti-patterns}.jsonl
let reflexions = [];
try {
  const rxPath = path.resolve(process.env.HOME, 'projects/skrivsikkert/agent_ops/scripts/lib/reflexion.js');
  if (require('fs').existsSync(rxPath)) {
    const { Reflexion } = require(rxPath);
    const rx = new Reflexion();
    // Without a specific task prompt, surface critical-severity items
    const all = [
      ...rx._readJsonl('anti-patterns.jsonl'),
      ...rx._readJsonl('gotchas.jsonl'),
    ];
    reflexions = all
      .filter((r) => r.severity === 'critical')
      .slice(-3);
  }
} catch (_) {}

// Recent completions (last 48h) — what the other team or I shipped
const projectBase = project ? path.basename(project) : null;
let completions = [];
try {
  const since = Date.now() - 48 * 3600 * 1000;
  completions = store.search({ query: 'completion', scopes: ['global'], types: ['episodic'], limit: 100 })
    .filter((e) => e.key && e.key.startsWith('completion:') && e.updated_at >= since)
    .map((e) => { try { return { e, b: JSON.parse(e.body) }; } catch { return null; } })
    .filter(Boolean)
    .filter((x) => {
      if (!projectBase || !x.b.project) return true;
      const bp = path.basename(x.b.project);
      return bp === projectBase;
    })
    .slice(0, 5);
} catch (_) {}

function fmt(list) {
  return list.map((e) => {
    const b = (e.body || '').replace(/\s+/g, ' ').slice(0, 180);
    return `- [${e.type}] ${e.title}${b ? ' — ' + b : ''}`;
  }).join('\n');
}

const parts = [];
if (handoffs.length) {
  const lines = handoffs.map(({ e, b }) => {
    const next = (b.next_steps || []).slice(0, 3).map((s) => '• ' + s).join('  ');
    return `- ${e.key} (${b.from}→${b.to}, phase=${b.phase}): ${e.title.replace(/^\[handoff [^\]]+\]\s*/, '')}${b.summary ? ' — ' + b.summary.slice(0, 120) : ''}${next ? '\n  next: ' + next : ''}`;
  }).join('\n');
  parts.push('### Pending handoffs for you (run `handoff ack <id>` to clear)\n' + lines);
}
if (completions.length) {
  const lines = completions.map(({ e, b }) => {
    const tag = b.pr ? `PR#${b.pr}` : b.issue || '';
    const age = Math.round((Date.now() - e.updated_at) / 60000);
    const next = (b.next_steps || []).slice(0, 2).map((s) => '• ' + s).join('  ');
    return `- [${b.team}${tag ? ' ' + tag : ''}, ${age}m ago, ${b.status}] ${e.title.replace(/^\[done [^\]]+\]\s*/, '')}${b.summary ? ' — ' + b.summary.slice(0, 100) : ''}${next ? '\n  next: ' + next : ''}`;
  }).join('\n');
  parts.push('### Recently shipped (last 48h)\n' + lines);
}
if (reflexions.length) {
  const lines = reflexions.map((r) => {
    const head = r.type === 'gotcha' ? r.heads_up : r.rule;
    const files = r.files && r.files.length ? ' (files: ' + r.files.slice(0, 2).join(', ') + ')' : '';
    return `- [${r.severity}] ${head}${files}`;
  }).join('\n');
  parts.push('### Critical gotchas from prior failures (Reflexion)\n' + lines);
}
if (procedural.length) parts.push('### Shared rules\n' + fmt(procedural));
if (semantic.length)   parts.push('### Shared facts\n' + fmt(semantic));
// exclude handoff and completion episodic entries (they're shown above)
episodic = episodic.filter((e) => !(e.key && (e.key.startsWith('handoff:') || e.key.startsWith('completion:'))));
if (episodic.length)   parts.push('### Recent incidents\n' + fmt(episodic));

if (!parts.length) emit('');

const ctx = [
  '## Shared cross-project memory',
  `(~/bin/memory find "<query>" for more; DB: ${store.DB_PATH})`,
  '',
  parts.join('\n\n'),
].join('\n');

// Cap at 3KB to accommodate completions + handoffs + rules
const CAP = 3072;
emit(ctx.length > CAP ? ctx.slice(0, CAP) + '\n…(truncated)' : ctx);
