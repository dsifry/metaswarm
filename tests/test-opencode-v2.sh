#!/usr/bin/env bash
# tests/test-opencode-v2.sh
# OpenCode V2 regression tests:
#   1. opencode.json template uses a V2-valid MCP config (no ${workspace} cwd)
#   2. `setup --opencode` installs the session plugin and the BEADS MCP server
#   3. the plugin exports a V2 default definition (id + setup)
#   4. the plugin registers a compaction hook that injects BEADS state
#   5. the BEADS MCP server speaks MCP over stdio with zero npm dependencies
#   6. lib/setup-mandatory-files.sh --platform opencode installs plugin + MCP server
#
# Background: OpenCode V2 rejects V1 plugins ("Plugin must export a default
# definition with an id and an effect or setup function") and does not
# substitute ${workspace} in mcp.*.cwd ("NotFound: FileSystem.access").
#
# Usage: bash tests/test-opencode-v2.sh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMPDIR=$(mktemp -d /tmp/metaswarm-opencode-v2-XXXXXX)
trap "rm -rf '$TMPDIR'" EXIT

pass() { echo "  PASS: $1"; }
fail() { echo "  FAIL: $1"; exit 1; }

echo "=== Test: OpenCode V2 config, plugin and MCP server ==="
echo "Temp project: $TMPDIR"
echo ""

# --- 1. Template MCP config is V2-valid ----------------------------------
echo "--- [1/6] templates/opencode.json MCP config is V2-valid ---"
node -e '
const fs = require("fs");
const cfg = JSON.parse(fs.readFileSync("'"$ROOT"'/templates/opencode.json", "utf-8"));
const raw = JSON.stringify(cfg.mcp ?? {});
if (raw.includes("${")) {
  console.error("  FAIL: mcp config contains an unsubstituted ${...} placeholder: " + raw);
  process.exit(1);
}
const servers = cfg.mcp && (cfg.mcp.servers || cfg.mcp);
const beads = servers && servers.beads;
if (!beads) { console.error("  FAIL: mcp.beads entry missing"); process.exit(1); }
if (!Array.isArray(beads.command) || beads.command[0] !== "node") {
  console.error("  FAIL: mcp.beads.command must start with node (zero-dependency run): " + JSON.stringify(beads.command));
  process.exit(1);
}
if (beads.command[1] !== "scripts/beads-mcp-server.ts") {
  console.error("  FAIL: mcp.beads.command must run scripts/beads-mcp-server.ts: " + JSON.stringify(beads.command));
  process.exit(1);
}
console.log("  PASS: mcp.beads is V2-valid (node command, no ${...} placeholders)");
'
echo ""

# --- 2. setup --opencode installs plugin + MCP server ---------------------
echo "--- [2/6] setup --opencode installs plugin and MCP server ---"
PROJ="$TMPDIR/project"
mkdir -p "$PROJ"
(cd "$PROJ" && node "$ROOT/cli/metaswarm.js" setup --opencode >/dev/null)
fail=0
for f in .opencode/plugins/metaswarm-session.js scripts/beads-mcp-server.ts opencode.json; do
  if [ -f "$PROJ/$f" ]; then pass "$f created"; else echo "  FAIL: $f not created by setup --opencode"; fail=1; fi
done
[ "$fail" -eq 0 ] || exit 1
echo ""

# --- 3. Plugin exports a V2 default definition ---------------------------
echo "--- [3/6] plugin exports a V2 default definition ---"
node -e '
(async () => {
  const mod = await import("file://'"$PROJ"'/.opencode/plugins/metaswarm-session.js");
  const def = mod.default;
  if (!def) { console.error("  FAIL: no default export (OpenCode V2 requires one)"); process.exit(1); }
  if (typeof def.id !== "string" || !def.id) { console.error("  FAIL: default export has no id"); process.exit(1); }
  if (typeof def.setup !== "function" && typeof def.effect !== "function") {
    console.error("  FAIL: default export has no setup()/effect() function"); process.exit(1);
  }
  console.log("  PASS: default export has id=" + def.id + " and a setup() function");
})().catch((e) => { console.error("  FAIL: " + e.message); process.exit(1); });
'
echo ""

# --- 4. Plugin behavior: compaction hook injects BEADS state -------------
echo "--- [4/6] plugin registers a compaction hook that injects BEADS state ---"
node -e '
(async () => {
  const fs = require("fs");
  const path = require("path");
  const proj = "'"$PROJ"'";
  const mod = await import("file://" + path.join(proj, ".opencode/plugins/metaswarm-session.js"));
  const hooks = [];
  const ctx = {
    location: { directory: proj },
    session: { hook: async (name, cb) => { hooks.push({ name, cb }); return { dispose: async () => {} }; } },
  };
  await mod.default.setup(ctx);
  if (hooks.length !== 1 || hooks[0].name !== "compaction") {
    console.error("  FAIL: expected exactly one session compaction hook, got " + JSON.stringify(hooks.map(h => h.name)));
    process.exit(1);
  }
  // Missing mandatory files must not throw
  if (!fs.existsSync(path.join(proj, "opencode.json"))) {
    console.error("  FAIL: precondition: opencode.json should exist"); process.exit(1);
  }
  // With BEADS state present, the hook must push context into the compaction request
  fs.mkdirSync(path.join(proj, ".beads/plans"), { recursive: true });
  fs.writeFileSync(path.join(proj, ".beads/plans/active-plan.md"), "# Active Plan\n- keep this across compaction");
  const event = { system: [], messages: [] };
  await hooks[0].cb(event);
  const injected = event.system.map(p => p.text || "").join("\n");
  if (!injected.includes("keep this across compaction")) {
    console.error("  FAIL: compaction hook did not inject BEADS plan into event.system: " + JSON.stringify(event));
    process.exit(1);
  }
  // Hook must tolerate an event without a system array (never break compaction)
  await hooks[0].cb({ messages: [] });
  console.log("  PASS: compaction hook injects BEADS state and never throws");
})().catch((e) => { console.error("  FAIL: " + e.message); process.exit(1); });
'
echo ""

# --- 5. BEADS MCP server: stdio handshake, zero npm dependencies ----------
echo "--- [5/6] BEADS MCP server answers initialize/tools/resources over stdio ---"
cat > "$TMPDIR/handshake.mjs" <<'EOF'
import { spawn } from "node:child_process";

const [serverPath, cwd] = process.argv.slice(2);
const child = spawn(process.execPath, [serverPath], { cwd, stdio: ["pipe", "pipe", "pipe"] });
child.stderr.pipe(process.stderr);

let buf = "";
const pending = new Map();
child.stdout.on("data", (chunk) => {
  buf += chunk.toString();
  let idx;
  while ((idx = buf.indexOf("\n")) >= 0) {
    const line = buf.slice(0, idx);
    buf = buf.slice(idx + 1);
    if (!line.trim()) continue;
    let msg;
    try { msg = JSON.parse(line); } catch { continue; }
    if (msg.id !== undefined && pending.has(msg.id)) {
      pending.get(msg.id)(msg);
      pending.delete(msg.id);
    }
  }
});

let nextId = 1;
function request(method, params = {}) {
  const id = nextId++;
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      if (pending.has(id)) { pending.delete(id); reject(new Error(`timeout waiting for ${method}`)); }
    }, 10000);
    pending.set(id, (msg) => { clearTimeout(timer); resolve(msg); });
    child.stdin.write(JSON.stringify({ jsonrpc: "2.0", id, method, params }) + "\n");
  });
}
function notify(method, params = {}) {
  child.stdin.write(JSON.stringify({ jsonrpc: "2.0", method, params }) + "\n");
}

function assert(cond, msg) {
  if (!cond) { console.error("  FAIL: " + msg); child.kill(); process.exit(1); }
  console.log("  PASS: " + msg);
}

try {
  const init = await request("initialize", {
    protocolVersion: "2024-11-05",
    capabilities: {},
    clientInfo: { name: "metaswarm-test", version: "0.0.0" },
  });
  assert(init.result && init.result.serverInfo && init.result.serverInfo.name === "beads-mcp",
    "initialize → serverInfo.name = beads-mcp");

  notify("notifications/initialized");

  const tools = await request("tools/list");
  const names = ((tools.result && tools.result.tools) || []).map((t) => t.name);
  assert(names.includes("bd_ready") && names.includes("bd_show") && names.includes("bd_knowledge_list"),
    "tools/list → bd_ready, bd_show, bd_knowledge_list");

  const call = await request("tools/call", { name: "bd_ready", arguments: {} });
  const text = call.result && call.result.content && call.result.content[0] && call.result.content[0].text;
  assert(typeof text === "string" && text.length > 0, "tools/call bd_ready → text content");

  const resources = await request("resources/list");
  assert(Array.isArray(resources.result && resources.result.resources) && resources.result.resources.length > 0,
    "resources/list → resources");

  const templates = await request("resources/templates/list");
  assert(templates.result && Array.isArray(templates.result.resourceTemplates)
    && templates.result.resourceTemplates.length === 0,
    "resources/templates/list → empty list (no Method-not-found warning)");

  const unknown = await request("metaswarm/no-such-method");
  assert(unknown.error && unknown.error.code === -32601, "unknown method → JSON-RPC -32601");
} catch (e) {
  console.error("  FAIL: " + e.message);
  child.kill();
  process.exit(1);
}
child.kill();
EOF
# Run from the temp project: it has no package.json and no node_modules, so a
# dependency on @modelcontextprotocol/sdk (or any npm package) would fail here.
node "$TMPDIR/handshake.mjs" "$PROJ/scripts/beads-mcp-server.ts" "$PROJ"
echo ""

# --- 6. setup-mandatory-files.sh installs plugin + MCP server ------------
echo "--- [6/6] lib/setup-mandatory-files.sh --platform opencode installs plugin + MCP server ---"
SHTMP="$TMPDIR/shproj"
mkdir -p "$SHTMP"
bash "$ROOT/lib/setup-mandatory-files.sh" "$SHTMP" 100 "npm test" --platform opencode >/dev/null 2>&1
fail=0
for f in .opencode/plugins/metaswarm-session.js scripts/beads-mcp-server.ts opencode.json; do
  if [ -f "$SHTMP/$f" ]; then pass "$f created by shell setup"; else echo "  FAIL: $f missing from shell setup"; fail=1; fi
done
[ "$fail" -eq 0 ] || exit 1
echo ""

echo "=== All tests passed ==="
