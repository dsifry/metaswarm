#!/usr/bin/env node
// lib/resolve-config.js — Layered config resolution for tribunal.yaml
// Usage: node resolve-config.js <path-to-tribunal.yaml> <tool-name>
// Outputs: merged JSON config to stdout

'use strict';

/**
 * Minimal YAML parser — supports:
 *   - key: value pairs (scalars, quoted strings, booleans, numbers, null)
 *   - Nested objects (indentation-based)
 *   - Array items (- value)
 *   - Comments (# ...)
 *   - Empty lines
 *
 * Does NOT support: anchors, tags, multi-line strings, flow syntax {}/[]
 */
function parseYaml(text) {
  const lines = text.split('\n');

  // Pre-process: strip comments, skip blanks, record indent + content
  const entries = [];
  for (const raw of lines) {
    const line = stripComment(raw);
    const trimmed = line.trim();
    if (trimmed === '') continue;
    entries.push({ indent: line.search(/\S/), content: trimmed, raw: line });
  }

  return parseBlock(entries, 0, entries.length);
}

/**
 * Parse a block of YAML entries into an object, from index start to end,
 * where all entries are at least minIndent deep.
 */
function parseBlock(entries, start, end) {
  const result = {};
  let i = start;

  while (i < end) {
    const entry = entries[i];
    const { indent, content } = entry;

    if (content.startsWith('- ')) {
      // Shouldn't hit arrays at object level — skip
      i++;
      continue;
    }

    const colonIdx = content.indexOf(':');
    if (colonIdx === -1) { i++; continue; }

    const key = content.slice(0, colonIdx).trim();
    const rest = content.slice(colonIdx + 1).trim();

    if (rest !== '') {
      // Scalar value
      result[key] = parseScalar(rest);
      i++;
    } else {
      // Find the child block: all subsequent entries with indent > current indent
      const childStart = i + 1;
      let childEnd = childStart;
      while (childEnd < end && entries[childEnd].indent > indent) {
        childEnd++;
      }

      if (childStart < childEnd) {
        // Peek first child to determine if array or object
        if (entries[childStart].content.startsWith('- ')) {
          result[key] = parseArray(entries, childStart, childEnd, entries[childStart].indent);
        } else {
          result[key] = parseBlock(entries, childStart, childEnd);
        }
      } else {
        result[key] = null;
      }

      i = childEnd;
    }
  }

  return result;
}

/**
 * Parse a block of array entries.
 */
function parseArray(entries, start, end, arrayIndent) {
  const result = [];
  let i = start;

  while (i < end) {
    const { indent, content } = entries[i];

    if (content.startsWith('- ')) {
      const itemContent = content.slice(2).trim();

      // Note: array items containing colons (e.g., "- name: foo") are treated as
      // scalar strings, not objects. This parser only supports scalar arrays.
      result.push(parseScalar(itemContent));
      i++;
    } else {
      i++;
    }
  }

  return result;
}

/**
 * Strip inline comments, respecting quoted strings
 */
function stripComment(line) {
  let inSingle = false;
  let inDouble = false;
  for (let i = 0; i < line.length; i++) {
    const ch = line[i];
    if (ch === "'" && !inDouble) inSingle = !inSingle;
    else if (ch === '"' && !inSingle) inDouble = !inDouble;
    else if (ch === '#' && !inSingle && !inDouble) {
      if (i === 0 || line[i - 1] === ' ' || line[i - 1] === '\t') {
        return line.slice(0, i);
      }
    }
  }
  return line;
}

/**
 * Parse a scalar value from a YAML string
 */
function parseScalar(value) {
  if (value === '' || value === 'null' || value === '~') return null;
  if (value === 'true') return true;
  if (value === 'false') return false;

  // Quoted strings
  if ((value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))) {
    return value.slice(1, -1);
  }

  // Numbers
  if (/^-?\d+$/.test(value)) return parseInt(value, 10);
  if (/^-?\d+\.\d+$/.test(value)) return parseFloat(value);

  return value;
}

/**
 * Deep-merge two objects.
 * - Scalars: source wins
 * - Objects: recursively merged
 * - Arrays: source replaces entirely
 */
function deepMerge(target, source) {
  if (source === null || source === undefined) return target;
  if (target === null || target === undefined) return source;

  const result = {};

  // Copy all keys from target
  for (const key of Object.keys(target)) {
    result[key] = target[key];
  }

  // Merge/override with source
  for (const key of Object.keys(source)) {
    const tVal = result[key];
    const sVal = source[key];

    if (Array.isArray(sVal)) {
      // Arrays: replace entirely
      result[key] = sVal;
    } else if (sVal !== null && typeof sVal === 'object' && !Array.isArray(sVal) &&
               tVal !== null && typeof tVal === 'object' && !Array.isArray(tVal)) {
      // Both are objects: recursive merge
      result[key] = deepMerge(tVal, sVal);
    } else {
      // Scalar: source wins
      result[key] = sVal;
    }
  }

  return result;
}

/**
 * Resolve config for a specific tool by deep-merging common with tool-specific block.
 * @param {string} yamlText - Raw YAML content
 * @param {string} toolName - Tool name (e.g., "claude", "gemini", "codex")
 * @returns {object} Resolved config
 */
function resolveConfig(yamlText, toolName) {
  const parsed = parseYaml(yamlText);
  const common = parsed.common || {};
  const toolBlock = parsed[toolName] || {};
  return deepMerge(common, toolBlock);
}

// --- CLI entry point ---
if (require.main === module) {
  const fs = require('fs');
  const args = process.argv.slice(2);

  if (args.length < 2) {
    console.error('Usage: node resolve-config.js <path-to-tribunal.yaml> <tool-name>');
    process.exit(1);
  }

  const [yamlPath, toolName] = args;
  if (!fs.existsSync(yamlPath)) {
    console.error(`Error: config file not found: ${yamlPath}`);
    process.exit(1);
  }
  const yamlText = fs.readFileSync(yamlPath, 'utf8');
  const config = resolveConfig(yamlText, toolName);
  console.log(JSON.stringify(config, null, 2));
}

module.exports = { resolveConfig, deepMerge, parseYaml };
