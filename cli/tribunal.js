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

const TRIBUNAL_MARKER = '## tribunal';

// --- Platform-specific install functions ---

function installClaude() {
  console.log('\n  Installing for Claude Code...\n');
  try {
    console.log('  Running: claude plugin marketplace add jpeggdev/tribunal');
    execSync('claude plugin marketplace add jpeggdev/tribunal', { stdio: 'inherit' });
    console.log('  Running: claude plugin install tribunal');
    execSync('claude plugin install tribunal', { stdio: 'inherit' });
    info('Claude Code plugin installed');
    console.log('  Next: Open Claude Code and run /setup');
  } catch (e) {
    warn(`Claude Code install failed: ${e.message}`);
    console.log('  Try manually:');
    console.log('    claude plugin marketplace add jpeggdev/tribunal');
    console.log('    claude plugin install tribunal');
  }
}

function installCodex() {
  console.log('\n  Installing for Codex CLI...\n');
  const installDir = path.join(process.env.CODEX_HOME || path.join(os.homedir(), '.codex'), 'tribunal');
  const skillsDir = path.join(os.homedir(), '.agents', 'skills');

  // Validate installDir doesn't contain shell metacharacters
  if (/[;&|`$(){}]/.test(installDir)) {
    warn('Invalid characters in install directory path');
    return;
  }

  if (fs.existsSync(installDir)) {
    console.log(`  Updating existing installation at ${installDir}...`);
    try {
      execSync('git pull --rebase origin main', { cwd: installDir, stdio: 'inherit' });
      info('Updated tribunal');
    } catch (e) {
      warn(`git pull failed: ${e.message || e}`);
      return;
    }
  } else {
    console.log(`  Cloning tribunal to ${installDir}...`);
    mkdirp(path.dirname(installDir));
    try {
      execSync(`git clone https://github.com/jpeggdev/tribunal.git "${installDir}"`, { stdio: 'inherit' });
      info('Cloned tribunal');
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
      const linkName = `tribunal-${dir}`;
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
    console.log('  Running: gemini extensions install https://github.com/jpeggdev/tribunal.git');
    execSync('gemini extensions install https://github.com/jpeggdev/tribunal.git', { stdio: 'inherit' });
    info('Gemini CLI extension installed');
    console.log('  Next: In your project, run /tribunal:setup');
  } catch (e) {
    warn(`Gemini CLI install failed: ${e.message}`);
    console.log('  Try manually:');
    console.log('    gemini extensions install https://github.com/jpeggdev/tribunal.git');
  }
}

// --- Project-level setup ---

function setupProject(platformFlag) {
  console.log(`\ntribunal v${VERSION} — project setup\n`);

  const platforms = detectPlatforms();
  const targetPlatforms = [];

  if (platformFlag === 'all') {
    // Explicit --all: target all platforms regardless of install status
    targetPlatforms.push('claude', 'codex', 'gemini');
  } else if (!platformFlag) {
    // No flag: auto-detect which are installed
    for (const [key, p] of Object.entries(platforms)) {
      if (p.installed) targetPlatforms.push(key);
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
      if (existing.includes(TRIBUNAL_MARKER)) {
        skip(`${instrFile} (tribunal reference already present)`);
      } else if (fs.existsSync(appendTemplate)) {
        fs.appendFileSync(instrPath, '\n' + fs.readFileSync(appendTemplate, 'utf-8'));
        info(`${instrFile} (appended tribunal section)`);
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
tribunal v${VERSION} — Cross-platform installer

Usage:
  tribunal init [flags]        Install tribunal for detected CLI tools
  tribunal setup [flags]       Set up tribunal in the current project
  tribunal detect              Show which CLI tools are installed
  tribunal --help              Show this help
  tribunal --version           Show version

Init flags:
  --claude            Install for Claude Code only
  --codex             Install for Codex CLI only
  --gemini            Install for Gemini CLI only
  (no flag)           Auto-detect installed CLIs and install for all

Setup flags:
  --claude            Write CLAUDE.md only
  --codex             Write AGENTS.md only
  --gemini            Write GEMINI.md only
  --all               Write instruction files for all platforms
  (no flag)           Auto-detect installed CLIs

Examples:
  npx tribunal init            Auto-detect and install for all CLIs
  npx tribunal init --codex    Install for Codex CLI only
  npx tribunal setup           Set up project for detected CLIs
  npx tribunal detect          Show which CLIs are available
`);
}

function initCommand(args) {
  const flags = new Set(args);
  const platforms = detectPlatforms();

  console.log(`\ntribunal v${VERSION} — init\n`);
  console.log('  Detected CLI tools:\n');
  console.log(getSummary(platforms));
  console.log('');

  // Determine which platforms to install for
  const explicit = flags.has('--claude') || flags.has('--codex') || flags.has('--gemini');

  if (flags.has('--claude') || (!explicit && platforms.claude.installed)) {
    installClaude();
  }

  if (flags.has('--codex') || (!explicit && platforms.codex.installed)) {
    installCodex();
  }

  if (flags.has('--gemini') || (!explicit && platforms.gemini.installed)) {
    installGemini();
  }

  if (!explicit) {
    const installed = Object.values(platforms).filter(p => p.installed);
    if (installed.length === 0) {
      console.log('\n  No supported CLI tools detected.');
      console.log('  Install one of: claude, codex, gemini');
      console.log('  Then re-run: npx tribunal init\n');
    }
  }

  console.log('\n  Init complete! Next: run `npx tribunal setup` in your project.\n');
}

function detectCommand() {
  const platforms = detectPlatforms();
  console.log(`\ntribunal v${VERSION} — platform detection\n`);
  console.log(getSummary(platforms));
  console.log('');

  const installed = Object.entries(platforms).filter(([, p]) => p.installed);
  if (installed.length > 0) {
    console.log('  Install tribunal:');
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
  let platformFlag = null;
  if (flags.has('--claude')) platformFlag = 'claude';
  else if (flags.has('--codex')) platformFlag = 'codex';
  else if (flags.has('--gemini')) platformFlag = 'gemini';
  else if (flags.has('--all')) platformFlag = 'all';
  setupProject(platformFlag);
} else if (cmd === 'detect') {
  detectCommand();
} else if (cmd === '--version' || cmd === '-v') {
  console.log(VERSION);
} else {
  printHelp();
}
