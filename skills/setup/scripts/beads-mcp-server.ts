#!/usr/bin/env node
/**
 * BEADS MCP Server — zero-dependency MCP stdio server.
 *
 * Exposes BEADS functionality as MCP (Model Context Protocol) tools and
 * resources. Works with OpenCode, Claude Code, and any MCP-compatible client.
 *
 * No npm packages are required: the protocol is implemented directly over
 * newline-delimited JSON-RPC on stdio, so this runs in projects that have no
 * package.json / node_modules (Node.js >= 22.18 runs .ts files natively).
 *
 * Usage:
 *   node scripts/beads-mcp-server.ts
 *   npx tsx scripts/beads-mcp-server.ts   # Node.js < 22.18
 *
 * Configure in opencode.json:
 *   "mcp": {
 *     "servers": {
 *       "beads": {
 *         "type": "local",
 *         "command": ["node", "scripts/beads-mcp-server.ts"]
 *       }
 *     }
 *   }
 *
 * NOTE: never write logs to stdout — stdout carries the MCP protocol.
 */

import { execFileSync } from "node:child_process";
import { existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { createInterface } from "node:readline";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const PROJECT_ROOT = join(__dirname, "..");

const SERVER_INFO = { name: "beads-mcp", version: "1.0.0" };
const DEFAULT_PROTOCOL_VERSION = "2024-11-05";
const JSONRPC = "2.0";

// =============================================================================
// Types
// =============================================================================

interface BeadsIssue {
  id: string;
  title: string;
  status: "open" | "in_progress" | "done" | "blocked";
  tags: string[];
  description: string;
  createdAt: string;
  updatedAt: string;
}

interface BeadsKnowledgeEntry {
  type: "pattern" | "gotcha" | "decision" | "api-behavior" | "codebase-fact" | "anti-pattern" | "fact";
  title: string;
  content: string;
  tags: string[];
  file?: string;
  line?: number;
}

interface PrimeResult {
  entries: BeadsKnowledgeEntry[];
  summary: string;
}

interface RpcMessage {
  jsonrpc: string;
  id?: number | string | null;
  method?: string;
  params?: Record<string, unknown>;
}

interface ToolSpec {
  name: string;
  description: string;
  inputSchema: Record<string, unknown>;
}

interface ResourceSpec {
  uri: string;
  name: string;
  description: string;
  mimeType: string;
}

type ToolResult = { content: Array<{ type: "text"; text: string }> };
type DispatchOk = { result: unknown };
type DispatchErr = { error: { code: number; message: string } };
type DispatchOutcome = DispatchOk | DispatchErr;

// =============================================================================
// BEADS CLI wrapper (no shell: execFileSync avoids quoting/injection issues)
// =============================================================================

function findBeadsBinary(): string | null {
  const fromPath = (process.env.PATH || "")
    .split(":")
    .filter(Boolean)
    .map((dir) => join(dir, "bd"))
    .find((candidate) => existsSync(candidate));
  if (fromPath) return fromPath;

  const candidates = [
    join(process.env.HOME || "", ".local", "bin", "bd"),
    join(process.env.HOME || "", ".cargo", "bin", "bd"),
    "/usr/local/bin/bd",
  ];
  return candidates.find((candidate) => existsSync(candidate)) || null;
}

function runBeads(args: string[]): string {
  const bdCmd = findBeadsBinary();
  if (!bdCmd) throw new Error("bd binary not found in PATH");

  try {
    return execFileSync(bdCmd, args, {
      cwd: PROJECT_ROOT,
      encoding: "utf-8",
      stdio: ["ignore", "pipe", "pipe"],
    }).trim();
  } catch (e) {
    // bd returns non-zero for some commands (e.g. `bd ready` with no results)
    const err = e as { stdout?: string };
    if (err.stdout) return err.stdout.toString().trim();
    throw e;
  }
}

function beadsReady(): BeadsIssue[] {
  try {
    const output = runBeads(["ready", "--json"]);
    if (!output) return [];
    return JSON.parse(output) as BeadsIssue[];
  } catch {
    return [];
  }
}

function beadsShow(id: string): BeadsIssue | null {
  try {
    const output = runBeads(["show", id, "--json"]);
    if (!output) return null;
    return JSON.parse(output) as BeadsIssue;
  } catch {
    return null;
  }
}

function beadsPrime(query?: string): PrimeResult {
  try {
    const args = query ? ["prime", query] : ["prime"];
    const output = runBeads(args);
    if (!output) return { entries: [], summary: "No relevant knowledge found" };
    return JSON.parse(output) as PrimeResult;
  } catch {
    return { entries: [], summary: "BEADS prime failed" };
  }
}

function beadsSync(): { pushed: number; pulled: number } {
  try {
    const output = runBeads(["sync", "--json"]);
    if (!output) return { pushed: 0, pulled: 0 };
    return JSON.parse(output) as { pushed: number; pulled: number };
  } catch {
    return { pushed: 0, pulled: 0 };
  }
}

function beadsKnowledgeList(type?: string): BeadsKnowledgeEntry[] {
  try {
    const args = type ? ["knowledge", "list", "--type", type] : ["knowledge", "list"];
    const output = runBeads(args);
    if (!output) return [];
    return JSON.parse(output) as BeadsKnowledgeEntry[];
  } catch {
    return [];
  }
}

// =============================================================================
// Tools & resources catalog
// =============================================================================

const TOOLS: ToolSpec[] = [
  {
    name: "bd_ready",
    description: "Find available work items (issues ready to be claimed)",
    inputSchema: { type: "object", properties: {} },
  },
  {
    name: "bd_show",
    description: "View detailed information about a specific issue",
    inputSchema: {
      type: "object",
      properties: { id: { type: "string", description: "Issue ID" } },
      required: ["id"],
    },
  },
  {
    name: "bd_prime",
    description: "Load relevant knowledge from BEADS knowledge base for a task",
    inputSchema: {
      type: "object",
      properties: { query: { type: "string", description: "Optional query to filter knowledge" } },
    },
  },
  {
    name: "bd_sync",
    description: "Sync BEADS knowledge base with remote",
    inputSchema: { type: "object", properties: {} },
  },
  {
    name: "bd_knowledge_list",
    description: "List knowledge base entries by type",
    inputSchema: {
      type: "object",
      properties: {
        type: {
          type: "string",
          enum: ["pattern", "gotcha", "decision", "api-behavior", "codebase-fact", "anti-pattern", "fact"],
          description: "Filter by knowledge type",
        },
      },
    },
  },
];

const RESOURCES: ResourceSpec[] = [
  {
    uri: "beads://issues/ready",
    name: "Available Issues",
    description: "List of issues ready to be worked on",
    mimeType: "application/json",
  },
  {
    uri: "beads://knowledge/patterns",
    name: "Patterns",
    description: "Coding patterns and best practices",
    mimeType: "application/json",
  },
  {
    uri: "beads://knowledge/gotchas",
    name: "Gotchas",
    description: "Common pitfalls and gotchas",
    mimeType: "application/json",
  },
  {
    uri: "beads://knowledge/decisions",
    name: "Decisions",
    description: "Architectural and technical decisions",
    mimeType: "application/json",
  },
];

function textResult(text: string): ToolResult {
  return { content: [{ type: "text", text }] };
}

function callTool(name: string, args: Record<string, unknown>): ToolResult {
  switch (name) {
    case "bd_ready": {
      const issues = beadsReady();
      return textResult(
        issues.length === 0
          ? "No available work items found. Run `bd sync` to fetch from remote."
          : JSON.stringify(issues, null, 2)
      );
    }
    case "bd_show": {
      const id = String(args.id ?? "");
      const issue = beadsShow(id);
      return textResult(issue ? JSON.stringify(issue, null, 2) : `Issue ${id} not found`);
    }
    case "bd_prime":
      return textResult(JSON.stringify(beadsPrime(args.query as string | undefined), null, 2));
    case "bd_sync": {
      const result = beadsSync();
      return textResult(`Synced: pushed ${result.pushed}, pulled ${result.pulled}`);
    }
    case "bd_knowledge_list":
      return textResult(JSON.stringify(beadsKnowledgeList(args.type as string | undefined), null, 2));
    default:
      throw Object.assign(new Error(`Unknown tool: ${name}`), { rpcCode: -32602 });
  }
}

function readResource(uri: string): { contents: Array<{ uri: string; mimeType: string; text: string }> } {
  let entries: unknown;
  if (uri === "beads://issues/ready") entries = beadsReady();
  else if (uri === "beads://knowledge/patterns") entries = beadsKnowledgeList("pattern");
  else if (uri === "beads://knowledge/gotchas") entries = beadsKnowledgeList("gotcha");
  else if (uri === "beads://knowledge/decisions") entries = beadsKnowledgeList("decision");
  else throw Object.assign(new Error(`Unknown resource: ${uri}`), { rpcCode: -32602 });

  return { contents: [{ uri, mimeType: "application/json", text: JSON.stringify(entries, null, 2) }] };
}

// =============================================================================
// JSON-RPC dispatch
// =============================================================================

async function dispatch(method: string, params: Record<string, unknown>): Promise<DispatchOutcome> {
  try {
    switch (method) {
      case "initialize":
        return {
          result: {
            protocolVersion: (params.protocolVersion as string) || DEFAULT_PROTOCOL_VERSION,
            capabilities: { tools: {}, resources: {} },
            serverInfo: SERVER_INFO,
          },
        };
      case "ping":
        return { result: {} };
      case "tools/list":
        return { result: { tools: TOOLS } };
      case "tools/call":
        return {
          result: callTool(String(params.name ?? ""), (params.arguments ?? {}) as Record<string, unknown>),
        };
      case "resources/list":
        return { result: { resources: RESOURCES } };
      case "resources/templates/list":
        // We expose plain URIs only: no URI templates.
        return { result: { resourceTemplates: [] } };
      case "resources/read":
        return { result: readResource(String(params.uri ?? "")) };
      default:
        return { error: { code: -32601, message: `Method not found: ${method}` } };
    }
  } catch (e) {
    const err = e as Error & { rpcCode?: number };
    return { error: { code: err.rpcCode ?? -32603, message: err.message || String(e) } };
  }
}

function send(payload: Record<string, unknown>): void {
  process.stdout.write(JSON.stringify(payload) + "\n");
}

// =============================================================================
// Stdio transport (newline-delimited JSON-RPC)
// =============================================================================

function start(): void {
  const rl = createInterface({ input: process.stdin, crlfDelay: Infinity });

  rl.on("line", (line: string) => {
    const trimmed = line.trim();
    if (!trimmed) return;

    let msg: RpcMessage;
    try {
      msg = JSON.parse(trimmed) as RpcMessage;
    } catch {
      send({ jsonrpc: JSONRPC, id: null, error: { code: -32700, message: "Parse error" } });
      return;
    }

    // Notifications (e.g. notifications/initialized) carry no id: nothing to answer.
    if (msg.id === undefined || msg.id === null) return;
    if (!msg.method) {
      send({ jsonrpc: JSONRPC, id: msg.id, error: { code: -32600, message: "Missing method" } });
      return;
    }

    void dispatch(msg.method, msg.params ?? {}).then((outcome) => {
      send({ jsonrpc: JSONRPC, id: msg.id, ...outcome });
    });
  });

  rl.on("close", () => process.exit(0));

  console.error("BEADS MCP Server running on stdio");
}

start();
