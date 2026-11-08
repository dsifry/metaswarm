#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const ROOT = path.resolve(__dirname, '..');

// Mapping: authoritative source -> co-located destinations
// Rubrics co-located into skill directories that reference them
const RUBRIC_SYNC = [
  {
    src: 'rubrics/plan-review-rubric-adversarial.md',
    dests: [
      'skills/plan-review-gate/rubrics/plan-review-rubric-adversarial.md',
      'skills/start/rubrics/plan-review-rubric-adversarial.md'
    ]
  },
  {
    src: 'rubrics/adversarial-review-rubric.md',
    dests: [
      'skills/orchestrated-execution/rubrics/adversarial-review-rubric.md',
      'skills/start/rubrics/adversarial-review-rubric.md'
    ]
  },
  {
    src: 'rubrics/external-tool-review-rubric.md',
    dests: ['skills/external-tools/rubrics/external-tool-review-rubric.md']
  },
  {
    src: 'rubrics/security-review-rubric.md',
    dests: ['skills/start/rubrics/security-review-rubric.md']
  },
  {
    src: 'rubrics/plan-review-rubric.md',
    dests: ['skills/start/rubrics/plan-review-rubric.md']
  },
  {
    src: 'rubrics/code-review-rubric.md',
    dests: ['skills/start/rubrics/code-review-rubric.md']
  },
  {
    src: 'rubrics/ux-review-rubric.md',
    dests: [
      'skills/design-review-gate/rubrics/ux-review-rubric.md',
      'skills/start/rubrics/ux-review-rubric.md'
    ]
  },
];

// Guides co-located into skill directories that reference them
const GUIDE_SYNC = [
  {
    src: 'guides/agent-coordination.md',
    dests: [
      'skills/orchestrated-execution/guides/agent-coordination.md',
      'skills/design-review-gate/guides/agent-coordination.md',
      'skills/pr-shepherd/guides/agent-coordination.md',
      'skills/start/guides/agent-coordination.md'
    ]
  },
  {
    src: 'guides/delivery-scope.md',
    dests: [
      'skills/orchestrated-execution/guides/delivery-scope.md',
      'skills/plan-review-gate/guides/delivery-scope.md',
      'skills/design-review-gate/guides/delivery-scope.md',
      'skills/start/guides/delivery-scope.md',
      'skills/external-tools/guides/delivery-scope.md'
    ]
  },
  {
    src: 'guides/workflow-enforcement.md',
    dests: [
      'skills/brainstorming-extension/guides/workflow-enforcement.md',
      'skills/design-review-gate/guides/workflow-enforcement.md',
      'skills/plan-review-gate/guides/workflow-enforcement.md',
      'skills/start/guides/workflow-enforcement.md',
      'skills/orchestrated-execution/guides/workflow-enforcement.md'
    ]
  },
];

// Dynamic sync: entire directories into skills/setup/
// A file-system check failed for a reason other than "path is missing".
// Keeps the path, the original error code and the original error as `cause`.
class FileCheckError extends Error {
  constructor(filePath, cause) {
    super(`${filePath}: ${cause.message}`, { cause });
    this.name = 'FileCheckError';
    this.path = filePath;
    this.code = cause.code;
  }
}

// stat that treats only a missing path (ENOENT/ENOTDIR, including a broken symlink's
// target) as absence (null); any other fs error is raised as a FileCheckError.
function statOrNull(p, fsImpl = fs) {
  try {
    return fsImpl.statSync(p);
  } catch (err) {
    if (err.code === 'ENOENT' || err.code === 'ENOTDIR') return null;
    throw new FileCheckError(p, err);
  }
}

function isRegularFile(p, fsImpl = fs) {
  const st = statOrNull(p, fsImpl);
  return st !== null && st.isFile();
}

function buildDirSync(srcDir, destDir, exclude = []) {
  const srcPath = path.join(ROOT, srcDir);
  if (!fs.existsSync(srcPath)) return [];
  return fs.readdirSync(srcPath)
    .filter(f => !exclude.includes(f))
    .filter(f => isRegularFile(path.join(srcPath, f)))
    .map(f => ({
      src: `${srcDir}/${f}`,
      dests: [`${destDir}/${f}`]
    }));
}

// Project commands: unprefixed /commands in this repo load from .claude/commands/
// (the plugin's are /metaswarm:*), so commands/ is mirrored there to dogfood the
// working tree (issue #61). Excluded: status.md would shadow Claude Code's built-in
// /status; metaswarm-setup/-update-version are npm-era legacy commands.
const COMMAND_MIRROR = {
  src: 'commands',
  dest: '.claude/commands',
  exclude: ['status.md', 'metaswarm-setup.md', 'metaswarm-update-version.md'],
};

// Orphaned command mirrors (#64): a .md file in the mirror folder with no source in
// commands/ and not on the exclusion list (e.g. left behind by a rename or delete).
// Root, mirror settings and fs are parameters so tests can point it at a fixture.
// A broken symlink counts as an orphan; a source must be a regular file.
function findOrphanedCommandMirrors(root = ROOT, mirror = COMMAND_MIRROR, fsImpl = fs) {
  const destPath = path.join(root, mirror.dest);
  if (statOrNull(destPath, fsImpl) === null) return [];
  const isFile = p => isRegularFile(p, fsImpl);
  return fsImpl.readdirSync(destPath)
    .filter(f => f.endsWith('.md'))
    .filter(f => !mirror.exclude.includes(f))
    .filter(f => {
      const full = path.join(destPath, f);
      return isFile(full) || fsImpl.lstatSync(full).isSymbolicLink();
    })
    .filter(f => !isFile(path.join(root, mirror.src, f)))
    .map(f => `${mirror.dest}/${f}`);
}

const SYNC_MAP = [
  ...RUBRIC_SYNC,
  ...GUIDE_SYNC,
  ...buildDirSync('templates', 'skills/setup/templates'),
  ...buildDirSync('knowledge', 'skills/setup/knowledge'),
  ...buildDirSync('bin', 'skills/setup/bin'),
  ...buildDirSync('scripts', 'skills/setup/scripts'),
  ...buildDirSync(COMMAND_MIRROR.src, COMMAND_MIRROR.dest, COMMAND_MIRROR.exclude),
];

function hashFile(filepath) {
  const content = fs.readFileSync(filepath, 'utf-8')
    .replace(/\r\n/g, '\n')     // LF normalize
    .replace(/[ \t]+$/gm, '');  // strip trailing whitespace
  return crypto.createHash('sha256').update(content).digest('hex');
}

// --- TOML command generation ---
// Generate Gemini TOML commands from Claude markdown commands

const TOML_COMMAND_MAP = {
  'start-task': {
    description: 'Begin tracked work on a task with complexity assessment',
    prompt: 'Follow the metaswarm /start-task command: read `commands/start-task.md` in the metaswarm extension directory (usually ~/.gemini/extensions/metaswarm/) and carry out its steps. Set PLUGIN_ROOT to that directory first, so its snippets find bin/ and lib/ in the extension. The user wants to begin tracked work.\n\nArguments provided by the user: {{args}}\n\nIts workflow: Pre-Task Checklist, Task Assessment, route to Simple or Complex flow.'
  },
  'prime': {
    description: 'Load relevant knowledge from the BEADS knowledge base before starting work',
    prompt: 'Follow the metaswarm /prime command: read `commands/prime.md` in the metaswarm extension directory (usually ~/.gemini/extensions/metaswarm/) and carry out its steps. Set PLUGIN_ROOT to that directory first, so its snippets find bin/ and lib/ in the extension. The user wants to prime their context with relevant knowledge.\n\nArguments provided by the user: {{args}}\n\nLoad metaswarm knowledge-base facts from .beads/knowledge/*.jsonl (skip # comment lines, then filter with jq): match the keyword against each fact and its tags, the file against its affected files, and the work type against its fact type.'
  },
  'review-design': {
    description: 'Trigger the parallel design review gate with 6 specialist reviewers',
    prompt: 'Invoke the metaswarm design-review-gate skill. The user wants to run the design review gate.\n\nArguments provided by the user: {{args}}\n\nSpawn 6 review perspectives (PM, Architect, Designer, Security, UX Reviewer, CTO) to review the design. All must approve.'
  },
  'self-reflect': {
    description: 'Extract learnings from PR comments and session into the knowledge base',
    prompt: 'Follow the metaswarm /self-reflect command: read `commands/self-reflect.md` in the metaswarm extension directory (usually ~/.gemini/extensions/metaswarm/) and carry out its steps. Set PLUGIN_ROOT to that directory first, so its snippets find bin/ and lib/ in the extension. The user wants to capture learnings.\n\nArguments provided by the user: {{args}}\n\nFollow the 7-step reflection process: fetch PR comments, extract learnings, filter quality, get user approval, store to knowledge base.'
  },
  'handoff': {
    description: "Analyze the session and write a self-contained handoff doc for a fresh agent — outputs a single 'Read XXX.md and do YYY.' sentence",
    prompt: 'Invoke the metaswarm handoff skill. The user wants a session handoff so a fresh agent can resume the work with zero context loss.\n\nArguments / focus hints provided by the user: {{args}}\n\nFollow the handoff workflow: reconstruct the objective and Definition of Done; load persisted state (if bd is installed, `bd prime` for bd context; then read .beads/plans/active-plan.md and .beads/context/*.md; then /prime for knowledge); establish current status and the real working-tree state (git status, recent commits, uncommitted/unpushed changes); identify all required reading (specs, designs, plans, code file:line anchors, tests) with why each matters; write a self-contained document to docs/handoffs/handoff-<YYYY-MM-DD-HHmm>.md; then emit exactly one closing sentence: `Read docs/handoffs/handoff-<...>.md and do <concrete next action>.`'
  },
  'pr-shepherd': {
    description: 'Monitor a PR through CI, review comments, and merge',
    prompt: 'Invoke the metaswarm pr-shepherd skill. The user wants to shepherd a PR to merge.\n\nArguments provided by the user: {{args}}\n\nMonitor CI status, handle review comments, resolve threads, report when ready to merge.'
  },
  'brainstorm': {
    description: 'Refine an idea through collaborative brainstorming before implementation',
    prompt: 'Follow the metaswarm /brainstorm command: read `commands/brainstorm.md` in the metaswarm extension directory (usually ~/.gemini/extensions/metaswarm/) and carry out its steps. Set PLUGIN_ROOT to that directory first, so its snippets find bin/ and lib/ in the extension. The user wants to brainstorm and refine an idea.\n\nArguments provided by the user: {{args}}\n\nRun the brainstorming workflow. IMPORTANT: If brainstorming writes and commits a project-sized design doc (see the metaswarm plugin\'s guides/workflow-enforcement.md), STOP and run the design review gate before proceeding to planning. Quick tasks, chat-only designs and short design docs for small changes skip the gate.'
  },
  'setup': {
    description: 'Interactive guided setup — detects project, configures metaswarm',
    prompt: 'Invoke the metaswarm setup skill. The user wants to set up metaswarm for their project.\n\nArguments provided by the user: {{args}}\n\nDetect language, framework, test runner, linter, and CI system. Ask targeted questions. Create instruction files, coverage config, and command shims.'
  },
  'update': {
    description: 'Update metaswarm to the latest version',
    prompt: 'On Gemini CLI, update the extension with `gemini extensions update metaswarm`. Then follow the metaswarm /update command for the project steps: read `commands/update.md` in the metaswarm extension directory (usually ~/.gemini/extensions/metaswarm/), with PLUGIN_ROOT set to that directory; skip its Claude plugin-update steps. The user wants to update metaswarm.\n\nArguments provided by the user: {{args}}\n\nCheck for new versions, show changelog, and update all component files while preserving customizations.'
  },
  'status': {
    description: 'Run diagnostic checks on your metaswarm installation',
    prompt: 'Invoke the metaswarm status skill. The user wants to check their installation status.\n\nArguments provided by the user: {{args}}\n\nRun the platform-aware diagnostic checks: plugin version, project setup, platform install state, command shims where applicable, legacy install, BEADS, bd CLI, gtg CLI, external tools, coverage thresholds, Node.js.'
  },
  'handle-pr-comments': {
    description: 'Handle PR review comments with the full resolution workflow',
    prompt: 'Invoke the metaswarm handling-pr-comments skill. The user wants to address PR review comments.\n\nArguments provided by the user: {{args}}\n\nFetch inline comments and review bodies, handle "outside diff range" comments, resolve threads, iterate until all comments are addressed.'
  },
  'create-issue': {
    description: 'Create a well-structured GitHub Issue with TDD plan and acceptance criteria',
    prompt: 'Invoke the metaswarm create-issue skill. The user wants to create a GitHub issue.\n\nArguments provided by the user: {{args}}\n\nCreate a comprehensive issue with TDD plans, acceptance criteria, and agent instructions.'
  },
  'external-tools-health': {
    description: 'Check status of external AI tools (Codex CLI, Gemini CLI)',
    prompt: 'Follow the metaswarm /external-tools-health command: read `commands/external-tools-health.md` in the metaswarm extension directory (usually ~/.gemini/extensions/metaswarm/) and carry out its steps. Set PLUGIN_ROOT to that directory first, so its snippets find bin/ and lib/ in the extension. The user wants to check external tool availability.\n\nArguments provided by the user: {{args}}\n\nCheck that Codex CLI and Gemini CLI are installed, authenticated, and responsive.'
  },
};

function generateTomlContent(name, def) {
  // Description is a basic string — escape backslashes and quotes
  const escapedDesc = def.description.replace(/\\/g, '\\\\').replace(/"/g, '\\"');
  // Prompt uses multiline basic string (""") — single quotes don't need escaping
  const escapedPrompt = def.prompt.replace(/\\/g, '\\\\');
  return `description = "${escapedDesc}"\nprompt = """${escapedPrompt}\n"""\n`;
}

function syncTomlCommands() {
  const tomlDir = path.join(ROOT, 'commands', 'metaswarm');
  fs.mkdirSync(tomlDir, { recursive: true });
  let synced = 0;

  for (const [name, def] of Object.entries(TOML_COMMAND_MAP)) {
    const tomlPath = path.join(tomlDir, `${name}.toml`);
    const content = generateTomlContent(name, def);
    fs.writeFileSync(tomlPath, content);
    synced++;
  }
  return synced;
}

function checkTomlCommands() {
  const tomlDir = path.join(ROOT, 'commands', 'metaswarm');
  let issues = 0;

  for (const [name, def] of Object.entries(TOML_COMMAND_MAP)) {
    const tomlPath = path.join(tomlDir, `${name}.toml`);
    if (!fs.existsSync(tomlPath)) {
      console.error(`MISSING: commands/metaswarm/${name}.toml`);
      issues++;
    } else {
      const content = fs.readFileSync(tomlPath, 'utf-8');
      const expected = generateTomlContent(name, def);
      if (content !== expected) {
        console.error(`DRIFT: commands/metaswarm/${name}.toml content mismatch`);
        issues++;
      }
    }
  }
  return issues;
}

// --- Cross-platform validation ---

function validateManifests() {
  let issues = 0;
  const pkgPath = path.join(ROOT, 'package.json');
  const claudePluginPath = path.join(ROOT, '.claude-plugin', 'plugin.json');
  const codexPluginPath = path.join(ROOT, '.codex-plugin', 'plugin.json');
  const geminiPath = path.join(ROOT, 'gemini-extension.json');
  const codexMarketplacePath = path.join(ROOT, '.agents', 'plugins', 'marketplace.json');

  const versions = {};
  const manifests = [
    ['package.json', pkgPath],
    ['.claude-plugin/plugin.json', claudePluginPath],
    ['.codex-plugin/plugin.json', codexPluginPath],
    ['gemini-extension.json', geminiPath],
  ];

  for (const [label, filePath] of manifests) {
    if (!fs.existsSync(filePath)) continue;
    try {
      versions[label] = JSON.parse(fs.readFileSync(filePath, 'utf-8')).version;
    } catch (e) {
      console.error(`MALFORMED: ${label} — ${e.message}`);
      issues++;
    }
  }

  const uniqueVersions = [...new Set(Object.values(versions))];
  if (uniqueVersions.length > 1) {
    console.error('VERSION MISMATCH across manifests:');
    for (const [file, ver] of Object.entries(versions)) {
      console.error(`  ${file}: ${ver}`);
    }
    issues++;
  }

  if (!fs.existsSync(codexPluginPath)) {
    console.error('MISSING: .codex-plugin/plugin.json');
    issues++;
  } else {
    try {
      const codexPlugin = JSON.parse(fs.readFileSync(codexPluginPath, 'utf-8'));
      if (codexPlugin.name !== 'metaswarm') {
        console.error(`INVALID: .codex-plugin/plugin.json name must be "metaswarm" (found ${JSON.stringify(codexPlugin.name)})`);
        issues++;
      }
      if (codexPlugin.skills !== './skills/') {
        console.error(`INVALID: .codex-plugin/plugin.json skills must be "./skills/" (found ${JSON.stringify(codexPlugin.skills)})`);
        issues++;
      }
    } catch (e) {
      // Already reported by manifest parsing above; keep this guard local.
    }
  }

  if (!fs.existsSync(codexMarketplacePath)) {
    console.error('MISSING: .agents/plugins/marketplace.json');
    issues++;
  } else {
    try {
      const marketplace = JSON.parse(fs.readFileSync(codexMarketplacePath, 'utf-8'));
      const entry = Array.isArray(marketplace.plugins)
        ? marketplace.plugins.find(plugin => plugin && plugin.name === 'metaswarm')
        : null;
      if (!entry) {
        console.error('INVALID: .agents/plugins/marketplace.json must include a metaswarm plugin entry');
        issues++;
      } else {
        if (!entry.source || entry.source.source !== 'url' || entry.source.url !== 'https://github.com/dsifry/metaswarm.git') {
          console.error('INVALID: metaswarm Codex marketplace source must point at the metaswarm repository root URL');
          issues++;
        }
        const allowedInstallation = new Set(['NOT_AVAILABLE', 'AVAILABLE', 'INSTALLED_BY_DEFAULT']);
        const allowedAuthentication = new Set(['ON_INSTALL', 'ON_USE']);
        const allowedCategories = new Set(['Coding', 'Productivity', 'Engineering']);
        if (!entry.policy || !allowedInstallation.has(entry.policy.installation)) {
          console.error(`INVALID: metaswarm Codex marketplace policy.installation must be one of ${[...allowedInstallation].join(', ')}`);
          issues++;
        }
        if (!entry.policy || !allowedAuthentication.has(entry.policy.authentication)) {
          console.error(`INVALID: metaswarm Codex marketplace policy.authentication must be one of ${[...allowedAuthentication].join(', ')}`);
          issues++;
        }
        if (typeof entry.category !== 'string' || !allowedCategories.has(entry.category)) {
          console.error(`INVALID: metaswarm Codex marketplace category must be one of ${[...allowedCategories].join(', ')}`);
          issues++;
        }
      }
    } catch (e) {
      console.error(`MALFORMED: .agents/plugins/marketplace.json — ${e.message}`);
      issues++;
    }
  }

  // Check template files exist
  const requiredTemplates = ['AGENTS.md', 'AGENTS-append.md', 'GEMINI.md', 'GEMINI-append.md', 'CLAUDE.md', 'CLAUDE-append.md'];
  for (const tmpl of requiredTemplates) {
    const tmplPath = path.join(ROOT, 'templates', tmpl);
    if (!fs.existsSync(tmplPath)) {
      console.error(`MISSING: templates/${tmpl}`);
      issues++;
    }
  }

  // Check root instruction files exist
  const rootFiles = ['AGENTS.md', 'GEMINI.md', 'gemini-extension.json'];
  for (const f of rootFiles) {
    if (!fs.existsSync(path.join(ROOT, f))) {
      console.error(`MISSING: ${f} (root)`);
      issues++;
    }
  }

  return issues;
}

// --- Main operations ---

function check() {
  let drifted = 0;

  // Check co-located resource sync
  for (const { src, dests } of SYNC_MAP) {
    const srcPath = path.join(ROOT, src);
    if (!fs.existsSync(srcPath)) continue;
    const srcHash = hashFile(srcPath);
    for (const dest of dests) {
      const destPath = path.join(ROOT, dest);
      if (!fs.existsSync(destPath)) {
        console.error(`MISSING: ${dest} (source: ${src})`);
        drifted++;
      } else {
        const destHash = hashFile(destPath);
        if (srcHash !== destHash) {
          console.error(`DRIFT: ${dest} differs from ${src}`);
          drifted++;
        }
      }
    }
  }

  // Check for orphaned command mirrors
  for (const orphan of findOrphanedCommandMirrors()) {
    console.error(`ORPHAN: ${orphan} has no source in ${COMMAND_MIRROR.src}/ (--sync removes it)`);
    drifted++;
  }

  // Check TOML commands
  drifted += checkTomlCommands();

  // Check cross-platform manifests
  drifted += validateManifests();

  if (drifted > 0) {
    console.error(`\n${drifted} issue(s) found.`);
    console.error('For drift/missing/orphan issues, run: node lib/sync-resources.js --sync');
    console.error('For version mismatches or malformed files, fix the source files manually.');
    process.exit(1);
  }
  console.log('All resources are in sync.');
}

function sync() {
  let synced = 0;

  // Sync co-located resources
  for (const { src, dests } of SYNC_MAP) {
    const srcPath = path.join(ROOT, src);
    if (!fs.existsSync(srcPath)) continue;
    for (const dest of dests) {
      const destPath = path.join(ROOT, dest);
      fs.mkdirSync(path.dirname(destPath), { recursive: true });
      fs.copyFileSync(srcPath, destPath);
      synced++;
    }
  }

  // Remove orphaned command mirrors
  for (const orphan of findOrphanedCommandMirrors()) {
    fs.unlinkSync(path.join(ROOT, orphan));
    console.log(`Removed orphan: ${orphan}`);
  }

  // Sync TOML commands
  const tomlSynced = syncTomlCommands();
  synced += tomlSynced;

  console.log(`Synced ${synced} file(s) (including ${tomlSynced} TOML commands).`);
}

module.exports = { findOrphanedCommandMirrors, COMMAND_MIRROR, FileCheckError };

if (require.main === module) {
  const mode = process.argv[2];
  if (mode === '--check') {
    check();
  } else if (mode === '--sync') {
    sync();
  } else {
    console.log('Usage: node lib/sync-resources.js [--check|--sync]');
    console.log('  --check   Verify co-located copies, TOML commands, and manifests are in sync');
    console.log('  --sync    Copy from authoritative sources and regenerate TOML commands');
    process.exit(1);
  }
}
