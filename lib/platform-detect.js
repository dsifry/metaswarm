#!/usr/bin/env node
'use strict';

const { execSync } = require('child_process');
const path = require('path');
const os = require('os');

/**
 * Detect which AI CLI tools are installed and their config paths.
 * Returns an object with installed status and paths for each platform.
 */
function detectPlatforms() {
  return {
    claude: detectClaude(),
    codex: detectCodex(),
    gemini: detectGemini(),
  };
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

function detectClaude() {
  const installed = commandExists('claude');
  const configDir = path.join(os.homedir(), '.claude');
  const pluginCacheDir = path.join(configDir, 'plugins', 'cache');

  return {
    installed,
    name: 'Claude Code',
    command: 'claude',
    configDir,
    pluginCacheDir,
    installMethod: 'plugin',
    installCommand: 'claude plugin marketplace add dsifry/metaswarm-marketplace && claude plugin install metaswarm',
    setupCommand: '/metaswarm:setup',
    instructionFile: 'CLAUDE.md',
  };
}

function detectCodex() {
  const installed = commandExists('codex');
  const installDir = path.join(process.env.CODEX_HOME || path.join(os.homedir(), '.codex'), 'metaswarm');
  const skillsDir = path.join(os.homedir(), '.agents', 'skills');

  return {
    installed,
    name: 'Codex CLI',
    command: 'codex',
    installDir,
    skillsDir,
    installMethod: 'clone+symlink',
    installCommand: 'bash .codex/install.sh',
    setupCommand: '$setup',
    instructionFile: 'AGENTS.md',
  };
}

function detectGemini() {
  const installed = commandExists('gemini');
  const configDir = path.join(os.homedir(), '.gemini');

  return {
    installed,
    name: 'Gemini CLI',
    command: 'gemini',
    configDir,
    installMethod: 'extension',
    installCommand: 'gemini extensions install https://github.com/dsifry/metaswarm.git',
    setupCommand: '/metaswarm:setup',
    instructionFile: 'GEMINI.md',
  };
}

/**
 * Get a summary of detected platforms for display.
 */
function getSummary(platforms) {
  const lines = [];
  for (const [key, info] of Object.entries(platforms)) {
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
    console.log('Install one of: claude, codex, gemini');
  } else {
    console.log(`Found ${installed.length} tool(s). Ready for metaswarm init.`);
  }
  console.log('');
}
