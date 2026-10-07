// metaswarm-session.js — session hooks for metaswarm on OpenCode (V2 plugin API).
//
// OpenCode V2 equivalent of Claude Code's session-start.sh:
//   - setup(): verify the mandatory metaswarm files exist and log a clear
//     warning when the project is not set up (runs at plugin load, once per
//     project — no prompt injection, OpenCode has no SessionStart context-parts
//     equivalent).
//   - session "compaction" hook: inject BEADS state (active plan, context
//     files) into the compaction request so work survives context compaction.
//
// OpenCode V2 requires `export default { id, setup }`; a named export (the V1
// plugin shape) is rejected with "Plugin must export a default definition with
// an id and an effect or setup function".

import { existsSync, readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";

const MANDATORY_FILES = ["opencode.json", ".opencode/OPENCODE.md"];
const BEADS_PLAN = ".beads/plans/active-plan.md";
const BEADS_CONTEXT_DIR = ".beads/context";
const MAX_PLAN_CHARS = 4000;
const MAX_CONTEXT_CHARS = 1500;
const MAX_CONTEXT_FILES = 3;

// Collect BEADS state to carry across compaction. Pure filesystem reads, never
// throws: a broken knowledge base must not break compaction.
function beadsState(directory) {
  const parts = [];

  const planPath = join(directory, BEADS_PLAN);
  if (existsSync(planPath)) {
    try {
      const plan = readFileSync(planPath, "utf-8");
      if (plan.trim()) {
        parts.push(`## Active Plan (from ${BEADS_PLAN})\n${plan.slice(0, MAX_PLAN_CHARS)}`);
      }
    } catch {
      /* unreadable plan: skip */
    }
  }

  const contextDir = join(directory, BEADS_CONTEXT_DIR);
  if (existsSync(contextDir)) {
    try {
      const files = readdirSync(contextDir).filter((f) => !f.startsWith(".")).sort();
      for (const file of files.slice(-MAX_CONTEXT_FILES)) {
        const content = readFileSync(join(contextDir, file), "utf-8");
        if (content.trim()) {
          parts.push(`## Context ${file}\n${content.slice(0, MAX_CONTEXT_CHARS)}`);
        }
      }
    } catch {
      /* unreadable context: skip */
    }
  }

  return parts;
}

export default {
  id: "metaswarm-session",
  async setup(ctx) {
    const directory = ctx.location.directory;

    // 1. Setup verification (equivalent of the session-start.sh warning).
    for (const file of MANDATORY_FILES) {
      if (!existsSync(join(directory, file))) {
        console.warn(
          `[metaswarm] not fully set up: missing ${file}. Run: npx metaswarm setup --opencode`
        );
      }
    }

    // 2. Keep BEADS state alive across context compaction.
    await ctx.session.hook("compaction", (event) => {
      const parts = beadsState(directory);
      if (parts.length === 0) return;

      if (!Array.isArray(event.system)) {
        console.warn("[metaswarm] compaction event has no system array; BEADS state not injected");
        return;
      }
      for (const part of parts) {
        event.system.push({ type: "text", text: part });
      }
    });
  },
};
