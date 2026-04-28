'use strict';

/**
 * Platform Registry — single source of truth for metaswarm-supported CLI tools.
 *
 * To add a new CLI host:
 *   1. Add an entry to PLATFORMS below.
 *   2. Add command-format generator if it needs a non-existing format
 *      (claude-md, gemini-toml, opencode-md are built in).
 *   3. Add tests under tests/<key>/.
 *
 * Every other consumer (cli/metaswarm.js, lib/platform-detect.js,
 * lib/sync-resources.js, docs templates) reads from here.
 */

const path = require('path');
const os = require('os');

const HOMEDIR = os.homedir();

const PLATFORMS = {
  claude: {
    key: 'claude',
    name: 'Claude Code',
    command: 'claude',
    instructionFile: 'CLAUDE.md',
    setupCommand: '/metaswarm:setup',
    installMethod: 'plugin',
    installCommand: 'claude plugin marketplace add dsifry/metaswarm-marketplace && claude plugin install metaswarm',
    // Where commands live for this CLI (relative to repo / project)
    commandsDir: 'commands',
    // Claude commands are authored by hand (one .md per command) — not
    // generated from TOML_COMMAND_MAP. Leaving commandFormat null tells
    // sync-resources.js to skip code generation for Claude.
    commandFormat: null,
    // Subagent / parallel dispatch capability
    parallelDispatch: 'full',
    // Description used in tables
    summary: 'Plugin marketplace; native /<command> shorthand; full parallel Task() dispatch.',
    // Detection paths
    configDir: () => path.join(HOMEDIR, '.claude'),
    pluginCacheDir: () => path.join(HOMEDIR, '.claude', 'plugins', 'cache'),
  },

  codex: {
    key: 'codex',
    name: 'Codex CLI',
    command: 'codex',
    instructionFile: 'AGENTS.md',
    setupCommand: '$setup',
    installMethod: 'clone+symlink',
    installCommand: 'bash .codex/install.sh',
    commandsDir: null,           // no slash commands; uses $name skill invocation
    commandFormat: null,
    parallelDispatch: 'sequential',
    summary: 'Clone+symlink under ~/.codex/metaswarm; skills under ~/.agents/skills/; sequential dispatch.',
    configDir: () => path.join(process.env.CODEX_HOME || path.join(HOMEDIR, '.codex')),
    installDir: () => path.join(process.env.CODEX_HOME || path.join(HOMEDIR, '.codex'), 'metaswarm'),
    skillsDir: () => path.join(HOMEDIR, '.agents', 'skills'),
  },

  gemini: {
    key: 'gemini',
    name: 'Gemini CLI',
    command: 'gemini',
    instructionFile: 'GEMINI.md',
    setupCommand: '/metaswarm:setup',
    installMethod: 'extension',
    installCommand: 'gemini extensions install https://github.com/dsifry/metaswarm.git',
    commandsDir: 'commands/metaswarm',
    commandFormat: 'gemini-toml',
    parallelDispatch: 'experimental',
    summary: 'Native extension; /metaswarm:<command> namespaced; experimental sub-agents.',
    configDir: () => path.join(HOMEDIR, '.gemini'),
  },

  opencode: {
    key: 'opencode',
    name: 'OpenCode',
    command: 'opencode',
    instructionFile: 'AGENTS.md',  // shared with Codex
    setupCommand: '/setup',
    installMethod: 'auto-discovery',
    installCommand: 'npx metaswarm init --opencode',
    commandsDir: '.opencode/commands',
    commandFormat: 'opencode-md',
    parallelDispatch: 'full',
    summary: 'Auto-discovers SKILL.md from ~/.agents/skills/ (reuses Codex install path). Full @-mention dispatch.',
    configDir: () => path.join(HOMEDIR, '.config', 'opencode'),
  },
};

/**
 * Get an array of platform keys in canonical order.
 * Used to keep --claude / --codex / --gemini / --opencode flag order
 * consistent across CLI help, init, and setup.
 */
function platformKeys() {
  return ['claude', 'codex', 'gemini', 'opencode'];
}

/**
 * Get a platform descriptor by key.
 * Throws if unknown — callers should use platformKeys() to enumerate.
 */
function getPlatform(key) {
  if (!PLATFORMS[key]) {
    throw new Error(`Unknown platform: ${key}. Known: ${platformKeys().join(', ')}`);
  }
  return PLATFORMS[key];
}

/**
 * Get all platforms as an ordered array.
 */
function allPlatforms() {
  return platformKeys().map(k => PLATFORMS[k]);
}

/**
 * Resolve any function-valued fields on a platform descriptor.
 * Returns a frozen plain object suitable for serialization.
 */
function resolvePlatform(key) {
  const p = getPlatform(key);
  const resolved = { ...p };
  for (const [field, value] of Object.entries(resolved)) {
    if (typeof value === 'function') {
      resolved[field] = value();
    }
  }
  return Object.freeze(resolved);
}

module.exports = {
  PLATFORMS,
  platformKeys,
  getPlatform,
  allPlatforms,
  resolvePlatform,
};
