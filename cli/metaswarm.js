#!/usr/bin/env node

'use strict';

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');
const readline = require('readline');

const PKG_ROOT = path.resolve(__dirname, '..');
const CWD = process.cwd();
const VERSION = require(path.join(PKG_ROOT, 'package.json')).version;

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

function hasExistingWorkflows() {
  const workflowDir = path.join(CWD, '.github', 'workflows');
  if (!fs.existsSync(workflowDir)) return false;
  const files = fs.readdirSync(workflowDir);
  return files.some(f => f.endsWith('.yml') || f.endsWith('.yaml'));
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

function askUser(question) {
  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
  return new Promise(resolve => {
    rl.question(question, answer => {
      rl.close();
      resolve(answer.trim().toLowerCase());
    });
  });
}

const METASWARM_MARKER = '## metaswarm';

// --- Commands ---

function printHelp() {
  console.log(`
metaswarm v${VERSION}

Usage:
  metaswarm init [flags]   Scaffold orchestration framework into current project
  metaswarm --help         Show this help
  metaswarm --version      Show version

Init flags:
  --with-husky      Initialize Husky + install pre-push hook
`);
}

async function init(args) {
  const flags = new Set(args);
  const withHusky = flags.has('--with-husky');

  console.log(`\nmetaswarm v${VERSION} \u2014 init\n`);

  // Check git repo
  if (!fs.existsSync(path.join(CWD, '.git'))) {
    warn('Not a git repository. Continuing anyway.');
  }

  // Check prerequisites
  const hasBd = which('bd');
  const hasGh = which('gh');
  if (!hasBd) warn('bd CLI not found \u2014 BEADS integration will be skipped');
  if (!hasGh) warn('gh CLI not found \u2014 GitHub operations won\'t be available');

  console.log('');

  // Copy mapping: [packageDir, projectDestDir]
  const COPIES = [
    ['agents', '.claude/plugins/metaswarm/skills/beads/agents'],
    ['skills', '.claude/plugins/metaswarm/skills'],
    ['guides', '.claude/guides'],
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

  // CLAUDE.md — three-way handling:
  //   1. No CLAUDE.md → create full template
  //   2. CLAUDE.md exists with metaswarm section → skip (idempotent)
  //   3. CLAUDE.md exists without metaswarm section → ask to append
  const claudeMdPath = path.join(CWD, 'CLAUDE.md');
  if (!fs.existsSync(claudeMdPath)) {
    // Fresh project — create full template
    copyFile(
      path.join(PKG_ROOT, 'templates', 'CLAUDE.md'),
      claudeMdPath
    );
  } else {
    const existing = fs.readFileSync(claudeMdPath, 'utf-8');
    if (existing.includes(METASWARM_MARKER)) {
      skip('CLAUDE.md (metaswarm section already present)');
    } else {
      console.log('');
      console.log('  Found existing CLAUDE.md. metaswarm needs to add its workflow');
      console.log('  instructions so Claude Code knows about the orchestration framework.');
      console.log('');
      const answer = await askUser('  Add metaswarm section to your CLAUDE.md? [Y/n] ');
      if (answer === '' || answer === 'y' || answer === 'yes') {
        const appendContent = fs.readFileSync(
          path.join(PKG_ROOT, 'templates', 'CLAUDE-append.md'), 'utf-8'
        );
        fs.appendFileSync(claudeMdPath, '\n' + appendContent);
        info('CLAUDE.md (appended metaswarm section)');
      } else {
        skip('CLAUDE.md (user declined \u2014 see .claude/templates/CLAUDE.md for reference)');
      }
    }
  }

  // .coverage-thresholds.json — 100% coverage enforcement
  // copyFile already skips if file exists; safe for existing projects
  const createdThresholds = copyFile(
    path.join(PKG_ROOT, 'templates', 'coverage-thresholds.json'),
    path.join(CWD, '.coverage-thresholds.json')
  );

  // .gitignore — standard ignores for Node.js/TypeScript projects
  const gitignorePath = path.join(CWD, '.gitignore');
  if (!fs.existsSync(gitignorePath)) {
    copyFile(
      path.join(PKG_ROOT, 'templates', '.gitignore'),
      gitignorePath
    );
  } else {
    // Safety check: warn if .env is not ignored (Issue #8)
    const gitignoreContent = fs.readFileSync(gitignorePath, 'utf-8');
    if (!gitignoreContent.includes('.env')) {
      warn('.gitignore does not ignore .env files — secret keys could be accidentally committed!');
      warn('Add ".env" to your .gitignore to protect secrets.');
    } else {
      skip('.gitignore');
    }
  }

  // .env.example — environment variable documentation template
  copyFile(
    path.join(PKG_ROOT, 'templates', '.env.example'),
    path.join(CWD, '.env.example')
  );

  // SERVICE-INVENTORY.md — tracks services and factories across work units
  copyFile(
    path.join(PKG_ROOT, 'templates', 'SERVICE-INVENTORY.md'),
    path.join(CWD, 'SERVICE-INVENTORY.md')
  );

  // .github/workflows/ci.yml — CI pipeline
  // Only create if no existing workflows — don't add a second CI pipeline
  let createdCi = false;
  if (hasExistingWorkflows()) {
    skip('.github/workflows/ci.yml (existing CI workflows detected \u2014 see .claude/templates/ci.yml to merge manually)');
  } else {
    createdCi = copyFile(
      path.join(PKG_ROOT, 'templates', 'ci.yml'),
      path.join(CWD, '.github', 'workflows', 'ci.yml')
    );
  }

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

  // --with-husky: initialize husky + install pre-push hook
  const huskyDir = path.join(CWD, '.husky');
  let huskyHookInstalled = false;
  if (withHusky) {
    console.log('');
    if (!fs.existsSync(huskyDir)) {
      if (!fs.existsSync(path.join(CWD, 'package.json'))) {
        warn('No package.json found \u2014 husky requires an npm project. Run `npm init` first.');
      } else {
        try {
          execSync('npx husky init', { cwd: CWD, stdio: 'inherit' });
          info('Husky initialized');
        } catch {
          warn('npx husky init failed \u2014 install husky manually');
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

  // Run bd init if available
  if (hasBd) {
    console.log('');
    try {
      execSync('bd init', { cwd: CWD, stdio: 'inherit' });
      info('bd init completed');
    } catch {
      warn('bd init failed \u2014 you can run it manually later');
    }
  }

  // Summary
  console.log('\nDone! Next steps:\n');
  console.log('  1. Review CLAUDE.md and customize for your project');
  if (createdThresholds) {
    console.log('  2. Review .coverage-thresholds.json \u2014 defaults to 100% coverage.');
    console.log('     Update enforcement.command for your test runner and adjust thresholds if needed.');
  }
  if (createdCi) {
    console.log('  3. Review .github/workflows/ci.yml and adjust for your build tools');
  }
  console.log('  4. Add your API keys/secrets to .env (see .env.example for required vars)');
  console.log('  5. Run: claude /project:start-task');
  console.log('  6. See GETTING_STARTED.md in the metaswarm package for details');
  console.log('');
  if (huskyHookInstalled) {
    console.log('  Set up: Husky pre-push hook\n');
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
