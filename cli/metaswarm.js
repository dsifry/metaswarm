#!/usr/bin/env node

'use strict';

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const PKG_ROOT = path.resolve(__dirname, '..');
const CWD = process.cwd();
const VERSION = require(path.join(PKG_ROOT, 'package.json')).version;

// --- Helpers ---

function warn(msg) {
  console.log(`  ⚠  ${msg}`);
}

function info(msg) {
  console.log(`  ✓  ${msg}`);
}

function skip(msg) {
  console.log(`  ·  ${msg} (already exists, skipped)`);
}

function which(cmd) {
  try {
    execSync(`command -v ${cmd}`, { stdio: 'ignore' });
    return true;
  } catch {
    return false;
  }
}

function mkdirp(dir) {
  fs.mkdirSync(dir, { recursive: true });
}

function copyFile(src, dest) {
  if (fs.existsSync(dest)) {
    skip(path.relative(CWD, dest));
    return false;
  }
  mkdirp(path.dirname(dest));
  fs.copyFileSync(src, dest);
  info(path.relative(CWD, dest));
  return true;
}

function copyDir(srcDir, destDir) {
  if (!fs.existsSync(srcDir)) return;
  const entries = fs.readdirSync(srcDir, { withFileTypes: true });
  for (const entry of entries) {
    const srcPath = path.join(srcDir, entry.name);
    const destPath = path.join(destDir, entry.name);
    if (entry.isDirectory()) {
      copyDir(srcPath, destPath);
    } else {
      copyFile(srcPath, destPath);
    }
  }
}

function chmodExec(dir) {
  if (!fs.existsSync(dir)) return;
  for (const f of fs.readdirSync(dir)) {
    if (f.endsWith('.sh')) {
      const fp = path.join(dir, f);
      fs.chmodSync(fp, 0o755);
    }
  }
}

// --- Commands ---

function printHelp() {
  console.log(`
metaswarm v${VERSION}

Usage:
  metaswarm init [flags]   Scaffold orchestration framework into current project
  metaswarm --help         Show this help
  metaswarm --version      Show version

Init flags:
  --with-coverage   Copy coverage-thresholds.json to project root
  --with-husky      Initialize Husky + install pre-push hook (implies --with-coverage)
  --with-ci         Create .github/workflows/coverage.yml (implies --with-coverage)
`);
}

function init(args) {
  const flags = new Set(args);
  const withHusky = flags.has('--with-husky');
  const withCi = flags.has('--with-ci');
  const withCoverage = flags.has('--with-coverage') || withHusky || withCi;

  console.log(`\nmetaswarm v${VERSION} — init\n`);

  // Check git repo
  if (!fs.existsSync(path.join(CWD, '.git'))) {
    warn('Not a git repository. Continuing anyway.');
  }

  // Check prerequisites
  const hasBd = which('bd');
  const hasGh = which('gh');
  if (!hasBd) warn('bd CLI not found — BEADS integration will be skipped');
  if (!hasGh) warn('gh CLI not found — GitHub operations won\'t be available');

  console.log('');

  // Copy mapping: [packageDir, projectDestDir]
  const COPIES = [
    ['agents', '.claude/plugins/metaswarm/skills/beads/agents'],
    ['skills', '.claude/plugins/metaswarm/skills'],
    ['commands', '.claude/commands'],
    ['rubrics', '.claude/rubrics'],
    ['knowledge', '.beads/knowledge'],
    ['scripts', 'scripts'],
    ['bin', 'bin'],
    ['templates', '.claude/templates'],
  ];

  for (const [src, dest] of COPIES) {
    copyDir(path.join(PKG_ROOT, src), path.join(CWD, dest));
  }

  // ORCHESTRATION.md → SKILL.md
  copyFile(
    path.join(PKG_ROOT, 'ORCHESTRATION.md'),
    path.join(CWD, '.claude/plugins/metaswarm/skills/beads/SKILL.md')
  );

  // Generate plugin.json
  const pluginJsonPath = path.join(CWD, '.claude/plugins/metaswarm/.claude-plugin/plugin.json');
  if (fs.existsSync(pluginJsonPath)) {
    skip(path.relative(CWD, pluginJsonPath));
  } else {
    mkdirp(path.dirname(pluginJsonPath));
    const pluginJson = {
      name: 'metaswarm',
      version: VERSION,
      description: 'Multi-agent orchestration framework for Claude Code',
      skills: ['skills/beads/SKILL.md'],
    };
    fs.writeFileSync(pluginJsonPath, JSON.stringify(pluginJson, null, 2) + '\n');
    info(path.relative(CWD, pluginJsonPath));
  }

  // chmod +x bin/*.sh
  chmodExec(path.join(CWD, 'bin'));

  // --- Flag-driven setup ---

  // --with-coverage: copy thresholds to project root
  if (withCoverage) {
    console.log('');
    copyFile(
      path.join(PKG_ROOT, 'templates', 'coverage-thresholds.json'),
      path.join(CWD, '.coverage-thresholds.json')
    );
  }

  // --with-husky: initialize husky + install pre-push hook
  const huskyDir = path.join(CWD, '.husky');
  let huskyHookInstalled = false;
  if (withHusky) {
    console.log('');
    if (!fs.existsSync(huskyDir)) {
      if (!fs.existsSync(path.join(CWD, 'package.json'))) {
        warn('No package.json found — husky requires an npm project. Run `npm init` first.');
      } else {
        try {
          execSync('npx husky init', { cwd: CWD, stdio: 'inherit' });
          info('Husky initialized');
        } catch {
          warn('npx husky init failed — install husky manually');
        }
      }
    }
    if (fs.existsSync(huskyDir)) {
      const prePushSrc = path.join(PKG_ROOT, 'templates', 'pre-push');
      const prePushDest = path.join(huskyDir, 'pre-push');
      if (copyFile(prePushSrc, prePushDest)) {
        fs.chmodSync(prePushDest, 0o755);
      }
      huskyHookInstalled = true;
    }
  } else if (fs.existsSync(huskyDir)) {
    // Auto-install pre-push hook if husky already exists
    const prePushDest = path.join(huskyDir, 'pre-push');
    if (!fs.existsSync(prePushDest)) {
      const prePushSrc = path.join(PKG_ROOT, 'templates', 'pre-push');
      fs.copyFileSync(prePushSrc, prePushDest);
      fs.chmodSync(prePushDest, 0o755);
      info('.husky/pre-push (coverage enforcement hook installed)');
    } else {
      skip('.husky/pre-push');
    }
  } else {
    warn('No .husky/ directory found. Run `metaswarm init --with-husky` to set up Husky with coverage enforcement.');
  }

  // --with-ci: create GitHub Actions coverage workflow
  if (withCi) {
    console.log('');
    copyFile(
      path.join(PKG_ROOT, 'templates', 'ci-coverage-job.yml'),
      path.join(CWD, '.github', 'workflows', 'coverage.yml')
    );
  }

  // Run bd init if available
  if (hasBd) {
    console.log('');
    try {
      execSync('bd init', { cwd: CWD, stdio: 'inherit' });
      info('bd init completed');
    } catch {
      warn('bd init failed — you can run it manually later');
    }
  }

  // Summary
  const extras = [];
  if (withCoverage) extras.push('coverage thresholds (.coverage-thresholds.json)');
  if (huskyHookInstalled) extras.push('Husky pre-push hook');
  if (withCi) extras.push('CI coverage workflow (.github/workflows/coverage.yml)');

  console.log(`
Done! Next steps:

  1. Review the scaffolded files
  2. Add to .gitignore if needed
  3. Run: claude /project:orchestrate
  4. See GETTING_STARTED.md in the metaswarm package for details
`);
  if (extras.length) {
    console.log(`  Set up: ${extras.join(', ')}\n`);
  }
}

// --- Main ---

const args = process.argv.slice(2);
const cmd = args[0];

if (cmd === 'init') {
  init(args.slice(1));
} else if (cmd === '--version' || cmd === '-v') {
  console.log(VERSION);
} else {
  printHelp();
}
