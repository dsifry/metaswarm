#!/usr/bin/env node

'use strict';

const fs = require('fs');
const path = require('path');
const os = require('os');
const { execSync } = require('child_process');

const PKG_ROOT = path.resolve(__dirname, '..');
const CWD = process.cwd();
const VERSION = require(path.join(PKG_ROOT, 'package.json')).version;

const { detectPlatforms, getSummary } = require(path.join(PKG_ROOT, 'lib', 'platform-detect'));
const { platformKeys, resolvePlatform } = require(path.join(PKG_ROOT, 'lib', 'platform-registry'));

// --- Helpers ---

function warn(msg) {
  console.log(`  \u26a0  ${msg}`);
}

function info(msg) {
  console.log(`  \u2713  ${msg}`);
}

function skip(msg) {
  console.log(`  \u00b7  ${msg} (already exists, skipped)`);
}

function mkdirp(dir) {
  fs.mkdirSync(dir, { recursive: true });
}

const METASWARM_MARKER = '## metaswarm';

// --- Platform-specific install functions ---

function installClaude() {
  console.log('\n  Installing for Claude Code...\n');
  try {
    console.log('  Running: claude plugin marketplace add dsifry/metaswarm-marketplace');
    execSync('claude plugin marketplace add dsifry/metaswarm-marketplace', { stdio: 'inherit' });
    console.log('  Running: claude plugin install metaswarm');
    execSync('claude plugin install metaswarm', { stdio: 'inherit' });
    info('Claude Code plugin installed');
    console.log('  Next: Open Claude Code and run /setup');
  } catch (e) {
    warn(`Claude Code install failed: ${e.message}`);
    console.log('  Try manually:');
    console.log('    claude plugin marketplace add dsifry/metaswarm-marketplace');
    console.log('    claude plugin install metaswarm');
  }
}

function installCodex() {
  console.log('\n  Installing for Codex CLI...\n');
  const codex = resolvePlatform('codex');
  const installDir = codex.installDir;
  const skillsDir = codex.skillsDir;

  if (fs.existsSync(installDir)) {
    console.log(`  Updating existing installation at ${installDir}...`);
    try {
      execSync('git pull --rebase origin main', { cwd: installDir, stdio: 'inherit' });
      info('Updated metaswarm');
    } catch (e) {
      warn(`git pull failed: ${e.message || e}`);
      return;
    }
  } else {
    console.log(`  Cloning metaswarm to ${installDir}...`);
    mkdirp(path.dirname(installDir));
    try {
      execSync(`git clone https://github.com/dsifry/metaswarm.git "${installDir}"`, { stdio: 'inherit' });
      info('Cloned metaswarm');
    } catch (e) {
      warn(`Clone failed: ${e.message}`);
      return;
    }
  }

  // Symlink skills
  mkdirp(skillsDir);
  const skillsPath = path.join(installDir, 'skills');
  if (fs.existsSync(skillsPath)) {
    let linked = 0;
    for (const dir of fs.readdirSync(skillsPath)) {
      const srcDir = path.join(skillsPath, dir);
      if (!fs.statSync(srcDir).isDirectory()) continue;
      const linkName = `metaswarm-${dir}`;
      const linkPath = path.join(skillsDir, linkName);

      try {
        if (fs.lstatSync(linkPath).isSymbolicLink()) {
          fs.unlinkSync(linkPath);
        } else if (fs.existsSync(linkPath)) {
          warn(`${linkPath} exists as a directory, skipping`);
          continue;
        }
      } catch (e) {
        if (e.code !== 'ENOENT') warn(`Unexpected error checking ${linkPath}: ${e.message}`);
      }

      fs.symlinkSync(srcDir, linkPath);
      linked++;
    }
    info(`Linked ${linked} skills into ${skillsDir}`);
  }
  console.log('  Next: In your project, run $setup');
}

function installGemini() {
  console.log('\n  Installing for Gemini CLI...\n');
  try {
    console.log('  Running: gemini extensions install https://github.com/dsifry/metaswarm.git');
    execSync('gemini extensions install https://github.com/dsifry/metaswarm.git', { stdio: 'inherit' });
    info('Gemini CLI extension installed');
    console.log('  Next: In your project, run /metaswarm:setup');
  } catch (e) {
    warn(`Gemini CLI install failed: ${e.message}`);
    console.log('  Try manually:');
    console.log('    gemini extensions install https://github.com/dsifry/metaswarm.git');
  }
}

function installOpenCode() {
  // OpenCode auto-discovers SKILL.md from .claude/skills/, .agents/skills/, and
  // .opencode/skills/. The simplest path: ensure a metaswarm install populates
  // one of those locations. We reuse installCodex(), which symlinks all 13
  // skills into ~/.agents/skills/metaswarm-<name>/ — those are immediately
  // discoverable by OpenCode without any further configuration.
  console.log('\n  Installing for OpenCode...\n');
  console.log('  OpenCode auto-discovers metaswarm skills from ~/.agents/skills/');
  console.log('  and reads AGENTS.md for project context. Reusing the Codex install path.');
  installCodex();
  console.log('');
  console.log('  Slash commands (/start-task, /brainstorm, /review-design, etc.) live in');
  console.log('  the metaswarm checkout under .opencode/commands/ and are checked into');
  console.log('  this repository. Downstream projects do not get per-project command files;');
  console.log('  invoke skills via @-mention or the @metaswarm-<skill> shorthand instead.');
  console.log('  Next: In your project, run npx metaswarm setup --opencode');
}

// --- Install dispatch ---
//
// Map each registry key to its installer function. To add a new CLI:
//   1) Add it to lib/platform-registry.js
//   2) Add an installX() above
//   3) Register it here
// initCommand() and setupProject() then iterate over platformKeys()
// automatically — no per-platform branches to update.

const INSTALLERS = {
  claude: installClaude,
  codex: installCodex,
  gemini: installGemini,
  opencode: installOpenCode,
};

function installFor(key) {
  const fn = INSTALLERS[key];
  if (!fn) {
    warn(`No installer registered for platform: ${key}`);
    return;
  }
  fn();
}

// Parse a --<platform> / --all flag set into a list of platform keys.
// Returns { keys: string[], explicit: boolean, all: boolean }.
function parsePlatformFlags(flags) {
  const keys = platformKeys();
  const selected = keys.filter(k => flags.has(`--${k}`));
  const all = flags.has('--all');
  return {
    keys: all ? keys.slice() : selected,
    explicit: selected.length > 0 || all,
    all,
  };
}

// --- Project-level setup ---

function setupProject(platformFlag) {
  console.log(`\nmetaswarm v${VERSION} — project setup\n`);

  const platforms = detectPlatforms();
  const allKeys = platformKeys();
  const targetPlatforms = [];

  // platformFlag is either:
  //   - 'all'      → every registered platform
  //   - null       → auto-detect installed CLIs (default)
  //   - a string   → single platform key (e.g. 'claude')
  //   - an array   → explicit list of platform keys (e.g. ['claude','codex'])
  if (platformFlag === 'all') {
    targetPlatforms.push(...allKeys);
  } else if (Array.isArray(platformFlag) && platformFlag.length > 0) {
    targetPlatforms.push(...platformFlag);
  } else if (!platformFlag) {
    for (const key of allKeys) {
      if (platforms[key].installed) targetPlatforms.push(key);
    }
    if (targetPlatforms.length === 0) {
      targetPlatforms.push('claude'); // default
    }
  } else {
    targetPlatforms.push(platformFlag);
  }

  console.log(`  Setting up for: ${targetPlatforms.join(', ')}\n`);

  for (const plat of targetPlatforms) {
    const p = platforms[plat];
    const instrFile = p.instructionFile;
    const instrPath = path.join(CWD, instrFile);
    const templateDir = path.join(PKG_ROOT, 'templates');
    const fullTemplate = path.join(templateDir, instrFile);
    const appendTemplate = path.join(templateDir, `${path.basename(instrFile, '.md')}-append.md`);

    if (!fs.existsSync(instrPath)) {
      if (fs.existsSync(fullTemplate)) {
        fs.copyFileSync(fullTemplate, instrPath);
        info(`${instrFile} (written from template)`);
      } else {
        warn(`${instrFile} template not found`);
      }
    } else {
      const existing = fs.readFileSync(instrPath, 'utf-8');
      if (existing.includes(METASWARM_MARKER) || existing.includes('metaswarm')) {
        skip(`${instrFile} (metaswarm reference already present)`);
      } else if (fs.existsSync(appendTemplate)) {
        fs.appendFileSync(instrPath, '\n' + fs.readFileSync(appendTemplate, 'utf-8'));
        info(`${instrFile} (appended metaswarm section)`);
      }
    }
  }

  // Coverage thresholds
  const coveragePath = path.join(CWD, '.coverage-thresholds.json');
  const coverageTemplate = path.join(PKG_ROOT, 'templates', 'coverage-thresholds.json');
  if (!fs.existsSync(coveragePath) && fs.existsSync(coverageTemplate)) {
    fs.copyFileSync(coverageTemplate, coveragePath);
    info('.coverage-thresholds.json');
  } else if (fs.existsSync(coveragePath)) {
    skip('.coverage-thresholds.json');
  }

  console.log('\n  Project setup complete!');
  for (const plat of targetPlatforms) {
    const p = platforms[plat];
    console.log(`  ${p.name}: Run ${p.setupCommand} for full interactive configuration`);
  }
  console.log('');
}

// --- Commands ---

function printHelp() {
  console.log(`
metaswarm v${VERSION} — Cross-platform installer

Usage:
  metaswarm init [flags]        Install metaswarm for detected CLI tools
  metaswarm setup [flags]       Set up metaswarm in the current project
  metaswarm detect              Show which CLI tools are installed
  metaswarm --help              Show this help
  metaswarm --version           Show version

Init flags:
  --claude            Install for Claude Code only
  --codex             Install for Codex CLI only
  --gemini            Install for Gemini CLI only
  --opencode          Install for OpenCode only (reuses Codex install path;
                      OpenCode auto-discovers skills from ~/.agents/skills/)
  (no flag)           Auto-detect installed CLIs and install for all

Setup flags:
  --claude            Write CLAUDE.md only
  --codex             Write AGENTS.md only
  --gemini            Write GEMINI.md only
  --opencode          Write AGENTS.md only (shared with Codex)
  --all               Write instruction files for all platforms
  (no flag)           Auto-detect installed CLIs

Examples:
  npx metaswarm init               Auto-detect and install for all CLIs
  npx metaswarm init --codex       Install for Codex CLI only
  npx metaswarm init --opencode    Install for OpenCode (reuses Codex path)
  npx metaswarm setup              Set up project for detected CLIs
  npx metaswarm detect             Show which CLIs are available
`);
}

async function initCommand(args) {
  const flags = new Set(args);
  const platforms = detectPlatforms();

  console.log(`\nmetaswarm v${VERSION} — init\n`);
  console.log('  Detected CLI tools:\n');
  console.log(getSummary(platforms));
  console.log('');

  // Determine which platforms to install for using the registry.
  const { keys: requested, explicit } = parsePlatformFlags(flags);
  const targets = explicit
    ? requested
    : platformKeys().filter(k => platforms[k].installed);

  for (const key of targets) {
    installFor(key);
  }

  if (!explicit && targets.length === 0) {
    console.log('\n  No supported CLI tools detected.');
    console.log(`  Install one of: ${platformKeys().join(', ')}`);
    console.log('  Then re-run: npx metaswarm init\n');
  }

  console.log('\n  Init complete! Next: run `npx metaswarm setup` in your project.\n');
}

function detectCommand() {
  const platforms = detectPlatforms();
  console.log(`\nmetaswarm v${VERSION} — platform detection\n`);
  console.log(getSummary(platforms));
  console.log('');

  const installed = Object.entries(platforms).filter(([, p]) => p.installed);
  if (installed.length > 0) {
    console.log('  Install metaswarm:');
    for (const [, p] of installed) {
      console.log(`    ${p.name}: ${p.installCommand}`);
    }
  }
  console.log('');
}

// --- Main ---

const args = process.argv.slice(2);
const cmd = args[0];

if (cmd === 'init') {
  initCommand(args.slice(1));
} else if (cmd === 'setup') {
  const flags = new Set(args.slice(1));
  const { keys, all } = parsePlatformFlags(flags);
  // Pass the full key list so multi-flag invocations like
  // `metaswarm setup --claude --codex` set up every requested platform.
  // 'all' takes precedence; an empty list means "auto-detect" (null).
  let platformFlag = null;
  if (all) platformFlag = 'all';
  else if (keys.length > 0) platformFlag = keys;
  setupProject(platformFlag);
} else if (cmd === 'detect') {
  detectCommand();
} else if (cmd === '--version' || cmd === '-v') {
  console.log(VERSION);
} else {
  printHelp();
}
