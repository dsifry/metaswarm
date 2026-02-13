#!/usr/bin/env npx tsx
/**
 * BEADS Conversation History Fetcher
 *
 * Extracts conversation history from Claude Code session files for self-reflection.
 * Parses ~/.claude/projects/{encoded-path}/*.jsonl files to find learning triggers:
 * - User corrections ("no, actually...", "that's wrong")
 * - Disagreements and clarifications
 * - Discovery moments ("it turns out...")
 * - Misconceptions that were corrected
 *
 * Usage:
 *   npx tsx scripts/beads-fetch-conversation-history.ts
 *   npx tsx scripts/beads-fetch-conversation-history.ts --days 7
 *   npx tsx scripts/beads-fetch-conversation-history.ts --project /path/to/project
 */

import { parseArgs } from "util";
import { writeFileSync, readFileSync, readdirSync, existsSync, mkdirSync } from "fs";
import { dirname, join, basename } from "path";
import { homedir } from "os";

// =============================================================================
// CLI Arguments
// =============================================================================

const { values: args } = parseArgs({
  options: {
    days: { type: "string", default: "7" },
    project: { type: "string" },
    output: { type: "string", default: ".beads/temp/conversation-history.json" },
    help: { type: "boolean", short: "h", default: false },
  },
});

if (args.help) {
  console.log(`
BEADS Conversation History Fetcher - Extract learnings from Claude Code sessions

Usage:
  npx tsx scripts/beads-fetch-conversation-history.ts [options]

Options:
  --days <n>       Number of days to look back (default: 7)
  --project <path> Project path (default: current directory)
  --output <path>  Output file path (default: .beads/temp/conversation-history.json)
  -h, --help       Show this help message

What it finds:
  - User corrections and disagreements
  - Misconceptions that were clarified
  - Discovery moments and insights
  - Architectural decisions discussed
`);
  process.exit(0);
}

// =============================================================================
// Types
// =============================================================================

interface ConversationMessage {
  type: "user" | "assistant";
  content: string;
  timestamp: string;
  sessionId: string;
}

interface LearningTrigger {
  type:
    | "correction"
    | "disagreement"
    | "clarification"
    | "discovery"
    | "decision"
    | "misconception";
  userMessage: string;
  assistantContext?: string;
  sessionId: string;
  sessionSummary: string;
  timestamp: string;
  confidence: "high" | "medium" | "low";
}

interface SessionIndex {
  version: number;
  entries: Array<{
    sessionId: string;
    fullPath: string;
    firstPrompt: string;
    summary: string;
    messageCount: number;
    created: string;
    modified: string;
    gitBranch: string;
    projectPath: string;
  }>;
  originalPath: string;
}

interface OutputData {
  fetchedAt: string;
  period: {
    since: string;
    until: string;
    days: number;
  };
  project: string;
  summary: {
    sessionsAnalyzed: number;
    messagesAnalyzed: number;
    triggersFound: number;
    byType: Record<string, number>;
  };
  triggers: LearningTrigger[];
}

// =============================================================================
// Trigger Detection Patterns
// =============================================================================

const CORRECTION_PATTERNS = [
  /^no[,.]?\s+/i, // Starts with "No, " - strong signal of correction
  /\bno[,.]?\s+(that's|thats|it's|its|actually|wait|make|don't|do|use|I)\b/i,
  /\bthat's\s+(wrong|incorrect|not right|not what)\b/i,
  /\bactually[,.]?\s+(it|the|you|we|I)\b/i,
  /\byou\s+(misunderstood|missed|got it wrong|are wrong)\b/i,
  /\bthat's\s+not\s+(what|how|correct)\b/i,
  /\bI\s+(meant|mean|was asking|wanted)\b/i,
  /\blet me clarify\b/i,
  /\bto be clear\b/i,
  /\bnot quite\b/i,
  /\binstead[,.]?\s+(use|do|try|make)\b/i,
  /\bdon't\s+(do|use|make)\s+that\b/i,
];

const DISAGREEMENT_PATTERNS = [
  /\bI\s+disagree\b/i,
  /\bI\s+don't\s+think\s+(that's|so)\b/i,
  /\bthat\s+doesn't\s+(seem|sound|make sense)\b/i,
  /\bI'd\s+prefer\b/i,
  /\bI\s+think\s+we\s+should\b/i,
  /\bwhy\s+(not|would|wouldn't)\b/i,
  /\bbut\s+what\s+about\b/i,
];

const CLARIFICATION_PATTERNS = [
  /\bwhat\s+I\s+(mean|meant)\s+is\b/i,
  /\bto\s+clarify\b/i,
  /\bmore\s+specifically\b/i,
  /\bin\s+other\s+words\b/i,
  /\bwhat\s+I'm\s+(asking|looking for|trying)\b/i,
];

const DISCOVERY_PATTERNS = [
  /\bit\s+turns\s+out\b/i,
  /\bI\s+(found|discovered|realized|noticed)\b/i,
  /\bwe\s+(found|discovered|realized|noticed)\b/i,
  /\bthe\s+problem\s+(was|is|turned out)\b/i,
  /\bthe\s+(issue|bug|error)\s+(was|is)\b/i,
  /\binteresting(ly)?\b/i,
  /\bturns\s+out\b/i,
  /\bthe\s+lesson[:\s]/i,
  /\bkey\s+(detail|insight|learning)\b/i,
];

const DECISION_PATTERNS = [
  /\blet's\s+(go|use|do|try)\s+with\b/i,
  /\bwe('ll| will| should)\s+(use|go|do)\b/i,
  /\bI('ve| have)\s+decided\b/i,
  /\bthe\s+decision\s+is\b/i,
  /\blet's\s+proceed\s+with\b/i,
];

// =============================================================================
// Helper Functions
// =============================================================================

function encodeProjectPath(projectPath: string): string {
  return projectPath.replace(/\//g, "-");
}

function getClaudeProjectsDir(): string {
  return join(homedir(), ".claude", "projects");
}

function extractTextContent(content: unknown): string {
  if (typeof content === "string") {
    return content;
  }

  if (Array.isArray(content)) {
    return content
      .filter((item): item is { type: string; text?: string } => typeof item === "object" && item !== null)
      .filter(item => item.type === "text" && item.text)
      .map(item => item.text)
      .join("\n");
  }

  return "";
}

function detectTriggerType(
  text: string
): { type: LearningTrigger["type"]; confidence: "high" | "medium" | "low" } | null {
  const lowerText = text.toLowerCase();

  // Check for corrections (high value)
  for (const pattern of CORRECTION_PATTERNS) {
    if (pattern.test(text)) {
      return { type: "correction", confidence: "high" };
    }
  }

  // Check for disagreements
  for (const pattern of DISAGREEMENT_PATTERNS) {
    if (pattern.test(text)) {
      return { type: "disagreement", confidence: "medium" };
    }
  }

  // Check for clarifications
  for (const pattern of CLARIFICATION_PATTERNS) {
    if (pattern.test(text)) {
      return { type: "clarification", confidence: "medium" };
    }
  }

  // Check for discoveries
  for (const pattern of DISCOVERY_PATTERNS) {
    if (pattern.test(text)) {
      return { type: "discovery", confidence: "high" };
    }
  }

  // Check for decisions
  for (const pattern of DECISION_PATTERNS) {
    if (pattern.test(text)) {
      return { type: "decision", confidence: "medium" };
    }
  }

  return null;
}

function parseConversationFile(
  filePath: string,
  sessionId: string,
  sessionSummary: string,
  sinceDateMs: number
): LearningTrigger[] {
  const triggers: LearningTrigger[] = [];
  const content = readFileSync(filePath, "utf-8");
  const lines = content.split("\n").filter(line => line.trim());

  let lastAssistantContent = "";

  for (const line of lines) {
    try {
      const entry = JSON.parse(line);

      // Track assistant messages for context
      if (entry.type === "assistant" && entry.message?.content) {
        const content = entry.message.content;
        if (Array.isArray(content)) {
          const textContent = content.find(
            (c: { type: string; text?: string }) => c.type === "text" && c.text
          );
          if (textContent) {
            lastAssistantContent = textContent.text.slice(0, 500);
          }
        }
      }

      // Analyze user messages
      if (entry.type === "user" && entry.userType === "external") {
        const timestamp = entry.timestamp;

        // Skip if older than our date range
        if (timestamp && new Date(timestamp).getTime() < sinceDateMs) {
          continue;
        }

        const textContent = extractTextContent(entry.message?.content || entry.data);

        if (!textContent || textContent.length < 10) {
          continue;
        }

        // Skip messages that are mostly whitespace (formatted/structured text)
        const trimmedContent = textContent.replace(/\s+/g, " ").trim();
        if (trimmedContent.length < textContent.length * 0.5) {
          continue;
        }

        const triggerDetection = detectTriggerType(textContent);

        if (triggerDetection) {
          triggers.push({
            type: triggerDetection.type,
            userMessage: textContent.slice(0, 1000),
            assistantContext: lastAssistantContent || undefined,
            sessionId,
            sessionSummary,
            timestamp: timestamp || new Date().toISOString(),
            confidence: triggerDetection.confidence,
          });
        }
      }
    } catch {
      // Skip malformed lines
      continue;
    }
  }

  return triggers;
}

// =============================================================================
// Main
// =============================================================================

async function main() {
  console.log("BEADS Conversation History Fetcher\n");

  const DAYS = parseInt(args.days || "7", 10);
  const OUTPUT_PATH = args.output || ".beads/temp/conversation-history.json";
  const projectPath = args.project || process.cwd();

  console.log(`Project: ${projectPath}`);
  console.log(`Looking back: ${DAYS} days`);
  console.log(`Output: ${OUTPUT_PATH}\n`);

  const since = new Date();
  since.setDate(since.getDate() - DAYS);
  const sinceDateMs = since.getTime();

  // Find the Claude projects directory for this project
  const claudeProjectsDir = getClaudeProjectsDir();
  const encodedPath = encodeProjectPath(projectPath);

  const projectDir = join(claudeProjectsDir, encodedPath);

  if (!existsSync(projectDir)) {
    console.log(`No Claude Code sessions found for: ${projectPath}`);
    console.log(`Expected directory: ${projectDir}`);
    process.exit(0);
  }

  // Read sessions index
  const indexPath = join(projectDir, "sessions-index.json");
  if (!existsSync(indexPath)) {
    console.log("No sessions-index.json found");
    process.exit(0);
  }

  const indexContent = readFileSync(indexPath, "utf-8");
  const sessionIndex: SessionIndex = JSON.parse(indexContent);

  console.log(`Found ${sessionIndex.entries.length} sessions\n`);

  const allTriggers: LearningTrigger[] = [];
  const byType: Record<string, number> = {};
  let messagesAnalyzed = 0;
  let sessionsAnalyzed = 0;

  for (const entry of sessionIndex.entries) {
    // Skip sessions older than our date range
    const modifiedDate = new Date(entry.modified);
    if (modifiedDate.getTime() < sinceDateMs) {
      continue;
    }

    const sessionFile = entry.fullPath;
    if (!existsSync(sessionFile)) {
      continue;
    }

    console.log(`Analyzing: ${entry.summary || entry.sessionId.slice(0, 8)}...`);
    sessionsAnalyzed++;

    // Count messages
    const content = readFileSync(sessionFile, "utf-8");
    const lineCount = content.split("\n").filter(l => l.trim()).length;
    messagesAnalyzed += lineCount;

    const triggers = parseConversationFile(
      sessionFile,
      entry.sessionId,
      entry.summary || entry.firstPrompt.slice(0, 100),
      sinceDateMs
    );

    for (const trigger of triggers) {
      byType[trigger.type] = (byType[trigger.type] || 0) + 1;
    }

    allTriggers.push(...triggers);
  }

  // Sort by timestamp (newest first)
  allTriggers.sort((a, b) => new Date(b.timestamp).getTime() - new Date(a.timestamp).getTime());

  // Prepare output
  const output: OutputData = {
    fetchedAt: new Date().toISOString(),
    period: {
      since: since.toISOString(),
      until: new Date().toISOString(),
      days: DAYS,
    },
    project: projectPath,
    summary: {
      sessionsAnalyzed,
      messagesAnalyzed,
      triggersFound: allTriggers.length,
      byType,
    },
    triggers: allTriggers,
  };

  // Ensure output directory exists
  const dir = dirname(OUTPUT_PATH);
  if (!existsSync(dir)) {
    mkdirSync(dir, { recursive: true });
  }

  // Write output
  writeFileSync(OUTPUT_PATH, JSON.stringify(output, null, 2));

  console.log(`\n=== Summary ===`);
  console.log(`Sessions analyzed: ${sessionsAnalyzed}`);
  console.log(`Messages analyzed: ${messagesAnalyzed}`);
  console.log(`Learning triggers found: ${allTriggers.length}`);
  console.log(`\nBy type:`);
  for (const [type, count] of Object.entries(byType).sort((a, b) => b[1] - a[1])) {
    console.log(`  ${type}: ${count}`);
  }
  console.log(`\nOutput written to: ${OUTPUT_PATH}`);
  console.log("\nNext: Run '/self-reflect' to analyze with Claude Code");
}

main().catch(error => {
  console.error("Error:", error.message);
  process.exit(1);
});
