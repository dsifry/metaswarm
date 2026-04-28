#!/usr/bin/env node
'use strict';

const { execSync } = require('child_process');
const { allPlatforms, resolvePlatform } = require('./platform-registry');

/**
 * Detect which AI CLI tools are installed and their config paths.
 *
 * The registry (lib/platform-registry.js) is the single source of truth
 * for per-platform metadata. This module just adds runtime detection
 * (is the binary on PATH?) on top of those static descriptors.
 *
 * Returns { <key>: { installed, ...registryFields }, ... }
 */
function detectPlatforms() {
  const result = {};
  for (const p of allPlatforms()) {
    const resolved = { ...resolvePlatform(p.key) };
    resolved.installed = commandExists(resolved.command);
    result[p.key] = resolved;
  }
  return result;
}

function commandExists(cmd) {
  const probe = process.platform === 'win32' ? `where ${cmd}` : `command -v ${cmd}`;
  try {
    execSync(probe, { stdio: 'ignore' });
    return true;
  } catch (e) {
    // command -v / where returns non-zero when command is not found — that's expected.
    if (e.status !== 1 && e.status !== 127) {
      console.error(`Warning: unexpected error checking for ${cmd}: ${e.message || e}`);
    }
    return false;
  }
}

/**
 * Get a summary of detected platforms for display.
 */
function getSummary(platforms) {
  const lines = [];
  for (const info of Object.values(platforms)) {
    const status = info.installed ? 'installed' : 'not found';
    lines.push(`  ${info.name} (${info.command}): ${status}`);
  }
  return lines.join('\n');
}

module.exports = { detectPlatforms, getSummary };

// CLI mode: run directly to see detection results
if (require.main === module) {
  const platforms = detectPlatforms();
  console.log('\nDetected AI CLI tools:\n');
  console.log(getSummary(platforms));
  console.log('');

  const installed = Object.entries(platforms).filter(([, p]) => p.installed);
  if (installed.length === 0) {
    console.log('No supported AI CLI tools found.');
    console.log('Install one of: claude, codex, gemini, opencode');
  } else {
    console.log(`Found ${installed.length} tool(s). Ready for metaswarm init.`);
  }
  console.log('');
}
