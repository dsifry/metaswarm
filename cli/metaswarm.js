#!/usr/bin/env node

'use strict';

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');
const readline = require('readline');

const PKG_ROOT = path.resolve(__dirname, '..');
const CWD = process.cwd();
const VERSION = require(path.join(PKG_ROOT, 'package.json')).version;

// Deprecation notice
console.log('\n  ========================================');
console.log('  DEPRECATION NOTICE');
console.log('  ========================================');
console.log('  npx metaswarm init is deprecated.');
console.log('  Install via the Claude Code plugin marketplace instead:');
console.log('');
console.log('    claude plugin add dsifry/metaswarm');
console.log('');
console.log('  Then in Claude Code, run: /setup');
console.log('  ========================================\n');

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
const METASWARM_SETUP_MARKER = 'metaswarm-setup';

// --- Commands ---

function printHelp() {
  console.log(`
metaswarm v${VERSION}

Usage:
  metaswarm init [flags]      Bootstrap metaswarm (copies setup commands, creates CLAUDE.md)
  metaswarm install [flags]   Install all metaswarm components (agents, skills, rubrics, etc.)
  metaswarm --help            Show this help
  metaswarm --version         Show version

Init flags:
  --full              Run init + install in one step (legacy behavior)

Install flags:
  --with-husky        Initialize Husky + install pre-push hook

Recommended workflow:
  1. npx metaswarm init
  2. Open Claude Code and run: /metaswarm-setup

  Claude will detect your project, install components, and customize everything interactively.
`);
}

// =========================================================================
// init — Thin bootstrap: copies setup commands + CLAUDE.md reference
// =========================================================================
async function init(args) {
  const flags = new Set(args);
  const full = flags.has('--full');

  console.log(`\nmetaswarm v${VERSION} \u2014 init\n`);

  // Check git repo
  if (!fs.existsSync(path.join(CWD, '.git'))) {
    warn('Not a git repository. Continuing anyway.');
  }

  // --- Copy the two setup commands ---
  const commandsDir = path.join(CWD, '.claude', 'commands');

  copyFile(
    path.join(PKG_ROOT, 'commands', 'metaswarm-setup.md'),
    path.join(commandsDir, 'metaswarm-setup.md')
  );

  copyFile(
    path.join(PKG_ROOT, 'commands', 'metaswarm-update-version.md'),
    path.join(commandsDir, 'metaswarm-update-version.md')
  );

  // --- CLAUDE.md handling ---
  // Three-way:
  //   1. No CLAUDE.md → create minimal one pointing to /metaswarm-setup
  //   2. CLAUDE.md exists with metaswarm marker → skip
  //   3. CLAUDE.md exists without marker → ask to append reference
  const claudeMdPath = path.join(CWD, 'CLAUDE.md');
  if (!fs.existsSync(claudeMdPath)) {
    const minimalClaude = [
      '# Project Instructions',
      '',
      'This project uses [metaswarm](https://github.com/dsifry/metaswarm) for multi-agent orchestration.',
      '',
      '**First-time setup:** Run `/metaswarm-setup` in Claude Code to detect your project and configure everything.',
      '',
      '**Update metaswarm:** Run `/metaswarm-update-version` to check for and apply updates.',
      '',
    ].join('\n');
    fs.writeFileSync(claudeMdPath, minimalClaude);
    info('CLAUDE.md (created with metaswarm setup reference)');
  } else {
    const existing = fs.readFileSync(claudeMdPath, 'utf-8');
    if (existing.includes(METASWARM_MARKER) || existing.includes(METASWARM_SETUP_MARKER)) {
      skip('CLAUDE.md (metaswarm reference already present)');
    } else {
      console.log('');
      console.log('  Found existing CLAUDE.md. metaswarm needs to add a reference');
      console.log('  so Claude Code knows about the setup command.');
      console.log('');
      const answer = await askUser('  Add metaswarm reference to your CLAUDE.md? [Y/n] ');
      if (answer === '' || answer === 'y' || answer === 'yes') {
        const appendContent = [
          '',
          '## metaswarm',
          '',
          'This project uses [metaswarm](https://github.com/dsifry/metaswarm) for multi-agent orchestration.',
          '',
          '**Setup:** Run `/metaswarm-setup` to detect your project and configure metaswarm.',
          '',
          '**Update:** Run `/metaswarm-update-version` to update metaswarm.',
          '',
        ].join('\n');
        fs.appendFileSync(claudeMdPath, appendContent);
        info('CLAUDE.md (appended metaswarm reference)');
      } else {
        skip('CLAUDE.md (user declined)');
      }
    }
  }

  console.log('');

  // --- Full mode: also run install ---
  if (full) {
    console.log('  Running full install...\n');
    await install(args.filter(a => a !== '--full'));
    return;
  }

  // --- Summary for thin init ---
  console.log('Done! Next step:\n');
  console.log('  Open Claude Code and run:');
  console.log('');
  console.log('    /metaswarm-setup');
  console.log('');
  console.log('  Claude will detect your project, install components,');
  console.log('  and customize everything interactively.');
  console.log('');
  console.log('  Or run `npx metaswarm init --full` for non-interactive setup.');
  console.log('');
}

// =========================================================================
// install — Copy all metaswarm components to the project
// =========================================================================
async function install(args) {
  const flags = new Set(args);
  const withHusky = flags.has('--with-husky');

  console.log(`\nmetaswarm v${VERSION} \u2014 install\n`);

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

  // --- Copy all component directories ---
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

  // CLAUDE.md — if init was run first, CLAUDE.md already exists with a minimal reference.
  // If install is run standalone (or via --full), use the full template handling.
  const claudeMdPath = path.join(CWD, 'CLAUDE.md');
  if (!fs.existsSync(claudeMdPath)) {
    copyFile(
      path.join(PKG_ROOT, 'templates', 'CLAUDE.md'),
      claudeMdPath
    );
  } else {
    const existing = fs.readFileSync(claudeMdPath, 'utf-8');
    if (existing.includes(METASWARM_MARKER)) {
      skip('CLAUDE.md (metaswarm section already present)');
    } else if (existing.includes(METASWARM_SETUP_MARKER)) {
      // Minimal init was run — replace with full template
      // But only if the file is still the minimal version (< 500 chars)
      if (existing.length < 500) {
        fs.writeFileSync(claudeMdPath, fs.readFileSync(
          path.join(PKG_ROOT, 'templates', 'CLAUDE.md'), 'utf-8'
        ));
        info('CLAUDE.md (upgraded from minimal to full template)');
      } else {
        // User has added content — append instead
        const appendPath = path.join(PKG_ROOT, 'templates', 'CLAUDE-append.md');
        if (fs.existsSync(appendPath)) {
          const appendContent = fs.readFileSync(appendPath, 'utf-8');
          fs.appendFileSync(claudeMdPath, '\n' + appendContent);
          info('CLAUDE.md (appended metaswarm section)');
        }
      }
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

  // .coverage-thresholds.json
  copyFile(
    path.join(PKG_ROOT, 'templates', 'coverage-thresholds.json'),
    path.join(CWD, '.coverage-thresholds.json')
  );

  // .gitignore
  const gitignorePath = path.join(CWD, '.gitignore');
  if (!fs.existsSync(gitignorePath)) {
    copyFile(
      path.join(PKG_ROOT, 'templates', 'gitignore'),
      gitignorePath
    );
  } else {
    const gitignoreContent = fs.readFileSync(gitignorePath, 'utf-8');
    if (!gitignoreContent.includes('.env')) {
      warn('.gitignore does not ignore .env files \u2014 secret keys could be accidentally committed!');
      warn('Add ".env" to your .gitignore to protect secrets.');
    } else {
      skip('.gitignore');
    }
  }

  // .env.example
  copyFile(
    path.join(PKG_ROOT, 'templates', '.env.example'),
    path.join(CWD, '.env.example')
  );

  // SERVICE-INVENTORY.md
  copyFile(
    path.join(PKG_ROOT, 'templates', 'SERVICE-INVENTORY.md'),
    path.join(CWD, 'SERVICE-INVENTORY.md')
  );

  // .metaswarm/external-tools.yaml
  const extToolsDest = path.join(CWD, '.metaswarm', 'external-tools.yaml');
  if (fs.existsSync(extToolsDest)) {
    skip('.metaswarm/external-tools.yaml');
  } else {
    const extToolsSrc = path.join(PKG_ROOT, 'templates', 'external-tools.yaml');
    if (fs.existsSync(extToolsSrc)) {
      mkdirp(path.join(CWD, '.metaswarm'));
      let extToolsContent = fs.readFileSync(extToolsSrc, 'utf-8');
      extToolsContent = extToolsContent.replace(/enabled: true/g, 'enabled: false');
      fs.writeFileSync(extToolsDest, extToolsContent);
      info('.metaswarm/external-tools.yaml (adapters disabled by default)');
    }
  }

  // .github/workflows/ci.yml
  if (hasExistingWorkflows()) {
    skip('.github/workflows/ci.yml (existing CI workflows detected \u2014 see .claude/templates/ci.yml to merge manually)');
  } else {
    copyFile(
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
    }
  } else if (fs.existsSync(huskyDir)) {
    const prePushDest = path.join(huskyDir, 'pre-push');
    if (!fs.existsSync(prePushDest)) {
      const prePushSrc = path.join(PKG_ROOT, 'templates', 'pre-push');
      fs.copyFileSync(prePushSrc, prePushDest);
      fs.chmodSync(prePushDest, 0o755);
      info('.husky/pre-push (coverage enforcement hook installed)');
    } else {
      skip('.husky/pre-push');
    }
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
  console.log('\nInstall complete!\n');
  console.log('  Run /metaswarm-setup in Claude Code to customize for your project.');
  console.log('');
}

// --- Main ---

const args = process.argv.slice(2);
const cmd = args[0];

if (cmd === 'init') {
  init(args.slice(1));
} else if (cmd === 'install') {
  install(args.slice(1));
} else if (cmd === '--version' || cmd === '-v') {
  console.log(VERSION);
} else {
  printHelp();
}
