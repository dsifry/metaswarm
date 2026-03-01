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
    dests: ['skills/plan-review-gate/rubrics/plan-review-rubric-adversarial.md']
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
];

// Dynamic sync: entire directories into skills/setup/
function buildDirSync(srcDir, destDir) {
  const srcPath = path.join(ROOT, srcDir);
  if (!fs.existsSync(srcPath)) return [];
  return fs.readdirSync(srcPath)
    .filter(f => {
      const full = path.join(srcPath, f);
      return fs.statSync(full).isFile();
    })
    .map(f => ({
      src: `${srcDir}/${f}`,
      dests: [`${destDir}/${f}`]
    }));
}

const SYNC_MAP = [
  ...RUBRIC_SYNC,
  ...GUIDE_SYNC,
  ...buildDirSync('templates', 'skills/setup/templates'),
  ...buildDirSync('knowledge', 'skills/setup/knowledge'),
  ...buildDirSync('bin', 'skills/setup/bin'),
  ...buildDirSync('scripts', 'skills/setup/scripts'),
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
    prompt: 'Invoke the metaswarm start-task skill. The user wants to begin tracked work.\n\nArguments provided by the user: {{args}}\n\nFollow the start-task workflow: Pre-Task Checklist, Task Assessment, route to Simple or Complex flow.'
  },
  'prime': {
    description: 'Load relevant knowledge from the BEADS knowledge base before starting work',
    prompt: 'Invoke the metaswarm prime skill. The user wants to prime their context with relevant knowledge.\n\nArguments provided by the user: {{args}}\n\nRun BEADS knowledge priming with any specified filters (--files, --keywords, --work-type).'
  },
  'review-design': {
    description: 'Trigger the parallel design review gate with 5 specialist reviewers',
    prompt: 'Invoke the metaswarm review-design skill. The user wants to run the design review gate.\n\nArguments provided by the user: {{args}}\n\nSpawn 5 review perspectives (PM, Architect, Designer, Security, CTO) to review the design. All must approve.'
  },
  'self-reflect': {
    description: 'Extract learnings from PR comments and session into the knowledge base',
    prompt: 'Invoke the metaswarm self-reflect skill. The user wants to capture learnings.\n\nArguments provided by the user: {{args}}\n\nFollow the 7-step reflection process: fetch PR comments, extract learnings, filter quality, get user approval, store to knowledge base.'
  },
  'pr-shepherd': {
    description: 'Monitor a PR through CI, review comments, and merge',
    prompt: 'Invoke the metaswarm pr-shepherd skill. The user wants to shepherd a PR to merge.\n\nArguments provided by the user: {{args}}\n\nMonitor CI status, handle review comments, resolve threads, report when ready to merge.'
  },
  'brainstorm': {
    description: 'Refine an idea through collaborative brainstorming before implementation',
    prompt: 'Invoke the metaswarm brainstorm skill. The user wants to brainstorm and refine an idea.\n\nArguments provided by the user: {{args}}\n\nRun the brainstorming workflow. IMPORTANT: After the design document is committed, STOP and run the design review gate before proceeding to planning.'
  },
  'setup': {
    description: 'Interactive guided setup — detects project, configures metaswarm',
    prompt: 'Invoke the metaswarm setup skill. The user wants to set up metaswarm for their project.\n\nArguments provided by the user: {{args}}\n\nDetect language, framework, test runner, linter, and CI system. Ask targeted questions. Create instruction files, coverage config, and command shims.'
  },
  'update': {
    description: 'Update metaswarm to the latest version',
    prompt: 'Invoke the metaswarm update skill. The user wants to update metaswarm.\n\nArguments provided by the user: {{args}}\n\nCheck for new versions, show changelog, and update all component files while preserving customizations.'
  },
  'status': {
    description: 'Run diagnostic checks on your metaswarm installation',
    prompt: 'Invoke the metaswarm status skill. The user wants to check their installation status.\n\nArguments provided by the user: {{args}}\n\nRun all 9 diagnostic checks: plugin version, project setup, command shims, legacy install, BEADS, bd CLI, external tools, coverage thresholds, Node.js.'
  },
  'handle-pr-comments': {
    description: 'Handle PR review comments with the full resolution workflow',
    prompt: 'Invoke the metaswarm handle-pr-comments skill. The user wants to address PR review comments.\n\nArguments provided by the user: {{args}}\n\nFetch inline comments and review bodies, handle "outside diff range" comments, resolve threads, iterate until all comments are addressed.'
  },
  'create-issue': {
    description: 'Create a well-structured GitHub Issue with TDD plan and acceptance criteria',
    prompt: 'Invoke the metaswarm create-issue skill. The user wants to create a GitHub issue.\n\nArguments provided by the user: {{args}}\n\nCreate a comprehensive issue with TDD plans, acceptance criteria, and agent instructions.'
  },
  'external-tools-health': {
    description: 'Check status of external AI tools (Codex CLI, Gemini CLI)',
    prompt: 'Invoke the metaswarm external-tools-health skill. The user wants to check external tool availability.\n\nArguments provided by the user: {{args}}\n\nCheck that Codex CLI and Gemini CLI are installed, authenticated, and responsive.'
  },
};

function generateTomlContent(name, def) {
  const escapedDesc = def.description.replace(/\\/g, '\\\\').replace(/"/g, '\\"');
  const escapedPrompt = def.prompt.replace(/\\/g, '\\\\').replace(/"/g, '\\"');
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
  const pluginPath = path.join(ROOT, '.claude-plugin', 'plugin.json');
  const geminiPath = path.join(ROOT, 'gemini-extension.json');

  const versions = {};
  const manifests = [
    ['package.json', pkgPath],
    ['plugin.json', pluginPath],
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

  // Check TOML commands
  drifted += checkTomlCommands();

  // Check cross-platform manifests
  drifted += validateManifests();

  if (drifted > 0) {
    console.error(`\n${drifted} issue(s) found.`);
    console.error('For drift/missing issues, run: node lib/sync-resources.js --sync');
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

  // Sync TOML commands
  const tomlSynced = syncTomlCommands();
  synced += tomlSynced;

  console.log(`Synced ${synced} file(s) (including ${tomlSynced} TOML commands).`);
}

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
