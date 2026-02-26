#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const ROOT = path.resolve(__dirname, '..');

// Mapping: authoritative source → co-located destinations
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

function check() {
  let drifted = 0;
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
  if (drifted > 0) {
    console.error(`\n${drifted} file(s) out of sync. Run: node lib/sync-resources.js --sync`);
    process.exit(1);
  }
  console.log('All co-located resources are in sync.');
}

function sync() {
  let synced = 0;
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
  console.log(`Synced ${synced} file(s).`);
}

const mode = process.argv[2];
if (mode === '--check') {
  check();
} else if (mode === '--sync') {
  sync();
} else {
  console.log('Usage: node lib/sync-resources.js [--check|--sync]');
  console.log('  --check   Verify co-located copies match authoritative sources');
  console.log('  --sync    Copy from authoritative sources to co-located destinations');
  process.exit(1);
}
