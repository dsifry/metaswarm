// Shared cross-project memory store.
// SQLite-backed. Namespaces: project:<name>, global.
// Types: semantic (facts), episodic (incidents with timestamp), procedural (rules).
//
// Consumers: ~/bin/memory CLI, panel API routes, SessionStart hook.
const path = require('path');
const fs = require('fs');

const SHARED_HOME = process.env.SHARED_MEMORY_HOME || path.resolve(process.env.HOME, '.claude/shared-memory');
const DB_PATH = path.join(SHARED_HOME, 'learnings.db');

// Reuse better-sqlite3 from the panel install (it's there; standalone CLI path)
function resolveBetterSqlite() {
  const candidates = [
    path.resolve(process.env.HOME, '.skrivstore-panel/node_modules/better-sqlite3'),
    path.resolve(process.env.HOME, '.skrivstore/node_modules/better-sqlite3'),
  ];
  for (const p of candidates) {
    try { return require(p); } catch (_) {}
  }
  try { return require('better-sqlite3'); } catch (_) {}
  throw new Error('better-sqlite3 not found. Run: cd ~/.skrivstore-panel && npm install');
}

let _db = null;
function getDb() {
  if (_db) return _db;
  fs.mkdirSync(SHARED_HOME, { recursive: true });
  const Database = resolveBetterSqlite();
  _db = new Database(DB_PATH);
  _db.pragma('journal_mode = WAL');
  _db.pragma('synchronous = NORMAL');
  _db.exec(`
    CREATE TABLE IF NOT EXISTS entry (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      scope TEXT NOT NULL,            -- 'project:<name>' or 'global'
      type TEXT NOT NULL,             -- semantic | episodic | procedural
      key TEXT,                       -- optional stable key for upsert
      title TEXT NOT NULL,
      body TEXT NOT NULL,
      tags TEXT,                      -- comma-separated
      team TEXT,                      -- team-1 | team-2 | (null)
      source TEXT,                    -- agent | cli | hook | panel
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      pinned INTEGER NOT NULL DEFAULT 0,
      archived INTEGER NOT NULL DEFAULT 0
    );
    CREATE INDEX IF NOT EXISTS idx_entry_scope ON entry(scope, archived);
    CREATE INDEX IF NOT EXISTS idx_entry_type ON entry(type, archived);
    CREATE INDEX IF NOT EXISTS idx_entry_key ON entry(scope, key) WHERE key IS NOT NULL;
    CREATE INDEX IF NOT EXISTS idx_entry_updated ON entry(updated_at DESC);
    CREATE VIRTUAL TABLE IF NOT EXISTS entry_fts USING fts5(title, body, tags, content='entry', content_rowid='id');
    CREATE TRIGGER IF NOT EXISTS entry_ai AFTER INSERT ON entry BEGIN
      INSERT INTO entry_fts(rowid, title, body, tags) VALUES (new.id, new.title, new.body, new.tags);
    END;
    CREATE TRIGGER IF NOT EXISTS entry_ad AFTER DELETE ON entry BEGIN
      INSERT INTO entry_fts(entry_fts, rowid, title, body, tags) VALUES('delete', old.id, old.title, old.body, old.tags);
    END;
    CREATE TRIGGER IF NOT EXISTS entry_au AFTER UPDATE ON entry BEGIN
      INSERT INTO entry_fts(entry_fts, rowid, title, body, tags) VALUES('delete', old.id, old.title, old.body, old.tags);
      INSERT INTO entry_fts(rowid, title, body, tags) VALUES (new.id, new.title, new.body, new.tags);
    END;
  `);
  return _db;
}

function normalizeScope(s) {
  if (!s) return 'global';
  if (s === 'global') return 'global';
  if (s.startsWith('project:')) return s;
  return `project:${s}`;
}

function put({ scope = 'global', type, key = null, title, body = '', tags = [], team = null, source = 'cli', pinned = false }) {
  if (!title) throw new Error('title required');
  if (!['semantic', 'episodic', 'procedural'].includes(type)) throw new Error('type must be semantic|episodic|procedural');
  const db = getDb();
  const now = Date.now();
  const tagStr = Array.isArray(tags) ? tags.join(',') : String(tags || '');
  scope = normalizeScope(scope);

  if (key) {
    const existing = db.prepare('SELECT id FROM entry WHERE scope = ? AND key = ? AND archived = 0').get(scope, key);
    if (existing) {
      db.prepare(`UPDATE entry SET title=?, body=?, tags=?, team=COALESCE(?, team), source=?, updated_at=?, pinned=? WHERE id=?`)
        .run(title, body, tagStr, team, source, now, pinned ? 1 : 0, existing.id);
      return { ok: true, id: existing.id, updated: true };
    }
  }
  const r = db.prepare(`INSERT INTO entry(scope,type,key,title,body,tags,team,source,created_at,updated_at,pinned)
                         VALUES (?,?,?,?,?,?,?,?,?,?,?)`)
    .run(scope, type, key, title, body, tagStr, team, source, now, now, pinned ? 1 : 0);
  return { ok: true, id: r.lastInsertRowid, updated: false };
}

function get({ id = null, scope = null, key = null }) {
  const db = getDb();
  if (id) return db.prepare('SELECT * FROM entry WHERE id = ?').get(id);
  if (scope && key) return db.prepare('SELECT * FROM entry WHERE scope = ? AND key = ? AND archived = 0').get(normalizeScope(scope), key);
  return null;
}

function search({ query, scopes = null, types = null, limit = 20, includeArchived = false }) {
  const db = getDb();
  const clauses = [];
  const params = [];

  if (query && query.trim()) {
    // Use FTS5. Quote to handle punctuation.
    const safeQ = query.replace(/"/g, '""');
    clauses.push('e.id IN (SELECT rowid FROM entry_fts WHERE entry_fts MATCH ?)');
    params.push(`"${safeQ}"`);
  }
  if (Array.isArray(scopes) && scopes.length) {
    clauses.push(`e.scope IN (${scopes.map(() => '?').join(',')})`);
    scopes.forEach((s) => params.push(normalizeScope(s)));
  }
  if (Array.isArray(types) && types.length) {
    clauses.push(`e.type IN (${types.map(() => '?').join(',')})`);
    types.forEach((t) => params.push(t));
  }
  if (!includeArchived) clauses.push('e.archived = 0');

  const where = clauses.length ? 'WHERE ' + clauses.join(' AND ') : '';
  const sql = `SELECT e.* FROM entry e ${where} ORDER BY e.pinned DESC, e.updated_at DESC LIMIT ?`;
  params.push(limit);
  return db.prepare(sql).all(...params);
}

function recent({ scope = null, limit = 10 } = {}) {
  const db = getDb();
  if (scope) {
    return db.prepare('SELECT * FROM entry WHERE scope = ? AND archived = 0 ORDER BY pinned DESC, updated_at DESC LIMIT ?')
      .all(normalizeScope(scope), limit);
  }
  return db.prepare('SELECT * FROM entry WHERE archived = 0 ORDER BY pinned DESC, updated_at DESC LIMIT ?').all(limit);
}

function archive(id) {
  const db = getDb();
  const r = db.prepare('UPDATE entry SET archived = 1, updated_at = ? WHERE id = ?').run(Date.now(), id);
  return { ok: r.changes === 1 };
}

function stats() {
  const db = getDb();
  const total = db.prepare('SELECT COUNT(*) AS n FROM entry WHERE archived = 0').get().n;
  const byType = db.prepare('SELECT type, COUNT(*) AS n FROM entry WHERE archived = 0 GROUP BY type').all();
  const byScope = db.prepare('SELECT scope, COUNT(*) AS n FROM entry WHERE archived = 0 GROUP BY scope').all();
  return { total, byType, byScope, dbPath: DB_PATH };
}

module.exports = { put, get, search, recent, archive, stats, SHARED_HOME, DB_PATH };
