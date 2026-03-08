#!/usr/bin/env node
// lib/agent-scorer.js
// Scores CLI tools for task assignment using weighted decay and failure pattern matching.

const fs = require("fs");
const path = require("path");

/**
 * Parse --key value CLI args into an object.
 */
function parseArgs(argv) {
  const args = {};
  for (let i = 0; i < argv.length; i++) {
    if (argv[i].startsWith("--")) {
      const key = argv[i].slice(2);
      const val = argv[i + 1];
      args[key] = val;
      i++;
    }
  }
  return args;
}

/**
 * Read JSONL file and return array of parsed entries.
 * Returns [] if file is missing or empty.
 */
function loadStats(statsPath) {
  if (!statsPath || !fs.existsSync(statsPath)) return [];
  const content = fs.readFileSync(statsPath, "utf8").trim();
  if (!content) return [];
  return content
    .split("\n")
    .filter((line) => line.trim())
    .map((line) => JSON.parse(line));
}

/**
 * Calculate days between a timestamp string and now.
 */
function daysBetween(dateStr, now) {
  const then = new Date(dateStr).getTime();
  const nowMs = now instanceof Date ? now.getTime() : new Date(now).getTime();
  return Math.max(0, (nowMs - then) / (1000 * 60 * 60 * 24));
}

/**
 * Calculate fraction of taskTags that appear in entryTags (0 to 1).
 */
function tagOverlap(taskTags, entryTags) {
  if (!taskTags || taskTags.length === 0) return 0;
  if (!entryTags || entryTags.length === 0) return 0;
  const entrySet = new Set(entryTags);
  const matches = taskTags.filter((t) => entrySet.has(t)).length;
  return matches / taskTags.length;
}

/**
 * Main scoring logic.
 *
 * For each available tool:
 *   - Filter stats to matching tool + task_type
 *   - If fewer than minSamples: use static priority position as score
 *   - Otherwise: weighted decay score = sum(outcome * e^(-lambda * age)) / sum(e^(-lambda * age))
 *   - Apply failure pattern penalty for failures in last 14 days with >50% tag overlap
 *
 * Returns ranking array sorted by score descending.
 */
function scoreTools(
  stats,
  taskType,
  available,
  staticPriority,
  minSamples,
  decayRate,
  taskTags
) {
  const now = new Date();
  const ranking = [];

  for (const tool of available) {
    const toolStats = stats.filter(
      (s) => s.tool === tool && s.task_type === taskType
    );

    if (toolStats.length < minSamples) {
      // Use static priority: higher position (lower index) = higher score
      const idx = staticPriority.indexOf(tool);
      const total = staticPriority.length;
      const score =
        idx >= 0 ? (total - idx) / total : 0;
      ranking.push({ tool, score, basis: "static", samples: toolStats.length });
      continue;
    }

    // Weighted decay score
    let weightedSum = 0;
    let weightTotal = 0;

    for (const entry of toolStats) {
      const age = daysBetween(entry.timestamp, now);
      const weight = Math.exp(-decayRate * age);
      const outcome = entry.success ? 1 : 0;
      weightedSum += outcome * weight;
      weightTotal += weight;
    }

    // Blend toward 0.5 baseline when effective weight is low (old/decayed data).
    // Confidence = weightTotal / (weightTotal + 1). With recent data weight ~1.0 each,
    // 3 recent samples give confidence ~0.75. With old decayed data weight is small,
    // confidence drops and score regresses toward 0.5.
    const rawScore = weightTotal > 0 ? weightedSum / weightTotal : 0.5;
    const confidence = weightTotal / (weightTotal + 1);
    let score = confidence * rawScore + (1 - confidence) * 0.5;

    // Failure pattern penalty: look at failures in last 14 days with >50% tag overlap
    if (taskTags && taskTags.length > 0) {
      const recentFailures = toolStats.filter((entry) => {
        if (entry.success) return false;
        const age = daysBetween(entry.timestamp, now);
        if (age > 14) return false;
        const overlap = tagOverlap(taskTags, entry.tags || []);
        return overlap > 0.5;
      });

      if (recentFailures.length > 0) {
        const penalty = Math.max(0.3, 1.0 - recentFailures.length * 0.15);
        score *= penalty;
      }
    }

    ranking.push({
      tool,
      score,
      basis: "weighted_decay",
      samples: toolStats.length,
    });
  }

  ranking.sort((a, b) => b.score - a.score);
  return ranking;
}

// CLI entry point
if (require.main === module) {
  const args = parseArgs(process.argv.slice(2));

  const statsPath = args.stats;
  const taskType = args["task-type"];
  const available = (args.available || "").split(",").filter(Boolean);
  const staticPriority = (args["static-priority"] || "").split(",").filter(Boolean);
  const minSamples = parseInt(args["min-samples"] || "3", 10);
  const decayRate = parseFloat(args["decay-rate"] || "0.1");
  const taskTags = args["task-tags"]
    ? args["task-tags"].split(",").filter(Boolean)
    : [];

  const stats = loadStats(statsPath);
  const ranking = scoreTools(
    stats,
    taskType,
    available,
    staticPriority,
    minSamples,
    decayRate,
    taskTags
  );

  const output = { ranking, task_type: taskType, timestamp: new Date().toISOString() };
  process.stdout.write(JSON.stringify(output, null, 2) + "\n");
}

module.exports = { scoreTools, loadStats, tagOverlap, daysBetween, parseArgs };
