# External Tools Setup Guide

This guide helps you install and configure external AI CLI tools for use with
metaswarm's cross-model delegation and adversarial review system.

## Overview

metaswarm can delegate implementation and review tasks to external AI models,
enabling cost savings and cross-model adversarial review. Two tools are
supported in v1:

| Tool | Cost | Best For |
|------|------|----------|
| **OpenAI Codex CLI** | ChatGPT Plus ($20/mo), Pro ($200/mo), or API key (pay-per-token) | Fast implementation with structured JSON output, strong at single-file TypeScript/Python tasks |
| **Google Gemini CLI** | Free with Google login (1,000 req/day, 60/min on Gemini 2.5 Pro) or API key (free tier: 250 req/day, Flash only) | Cost-effective review and implementation, large context window, zero-cost entry point |

You can install **one or both**. metaswarm adapts automatically based on what is
available:

- **Both installed**: Full escalation chain (Model A -> Model B -> Claude -> You). Cross-model adversarial review with three different models.
- **One installed**: Reduced chain (Model A -> Claude -> You). Cross-model review with two models.
- **Neither installed**: Pure metaswarm behavior, unchanged. No external tools are invoked.

---

## 1. Install OpenAI Codex CLI

### Install

```bash
npm install -g @openai/codex
```

### Verify installation

```bash
codex --version
# Expected: codex-cli 0.101.0 (or higher)
```

### Authentication (choose one)

**Option A: API Key (recommended for scripting and CI)**

```bash
# Add to your shell profile (~/.zshrc or ~/.bashrc):
export OPENAI_API_KEY="sk-your-key-here"

# Get a key at: https://platform.openai.com/api-keys
# Requires a funded OpenAI account with API access.
```

**Option B: ChatGPT Subscription Login (recommended for individual developers)**

```bash
codex login --device-auth
# Follow the browser prompts to log in with your ChatGPT account.
# Works with Plus ($20/mo) or Pro ($200/mo) subscriptions.
```

### Verify auth

```bash
codex login status
# Exit code 0 means logged in. Non-zero means auth is missing or expired.
```

### Smoke test

```bash
codex exec "print hello world in python" --ephemeral
# Expected: Codex generates and runs a Python hello-world script.
# The --ephemeral flag prevents saving history.
```

### Troubleshooting

| Problem | Cause | Solution |
|---------|-------|----------|
| `command not found: codex` | npm global bin directory is not in PATH | Run `npm bin -g` to find the path, then add it to your shell profile: `export PATH="$(npm bin -g):$PATH"` |
| `rate_limit_exceeded` or 429 errors | Free/Go API tier has low rate limits | Upgrade your OpenAI plan, or switch to ChatGPT subscription auth (Option B) which has higher limits |
| Codex hangs indefinitely | Known issue with some rate-limit responses; CLI waits instead of erroring | Press Ctrl+C, then update to the latest version: `npm update -g @openai/codex`. The metaswarm adapter wraps all invocations with a timeout to prevent hangs. |
| `OPENAI_API_KEY` is set but auth fails | Key may be revoked, expired, or from a different org | Verify at https://platform.openai.com/api-keys. Generate a new key if needed. |

---

## 2. Install Google Gemini CLI

### Install

```bash
npm install -g @google/gemini-cli
```

### Verify installation

```bash
gemini --version
# Expected: 0.28.2 (or higher)
```

### Authentication (choose one)

**Option A: Google Account Login (recommended -- free, high limits)**

```bash
gemini
# On first run, select "Login with Google" and complete the browser OAuth flow.
# This gives you access to Gemini 2.5 Pro with:
#   - 1,000 requests/day
#   - 60 requests/minute
# No API key needed. No credit card needed.
```

**Option B: API Key**

```bash
# Add to your shell profile (~/.zshrc or ~/.bashrc):
export GEMINI_API_KEY="AIza-your-key-here"

# Get a key at: https://aistudio.google.com/app/apikey
# Note: The free API key tier is more limited than Google login:
#   - 250 requests/day (vs 1,000 with login)
#   - Flash model only (vs Pro with login)
# For most users, Option A (Google login) is the better choice.
```

### Smoke test

```bash
gemini "print hello world in python" --output-format json | jq .response
# Expected: A JSON response containing Python code that prints hello world.
# If jq is not installed: gemini "print hello world in python" --output-format json
```

### Troubleshooting

| Problem | Cause | Solution |
|---------|-------|----------|
| `command not found: gemini` | npm global bin directory is not in PATH | Run `npm bin -g` to find the path, then add it to your shell profile: `export PATH="$(npm bin -g):$PATH"` |
| Rate limit loop (CLI freezes or retries endlessly) | Exceeded daily or per-minute quota | Press Ctrl+C, wait a few minutes, and try again. Check your quota at https://aistudio.google.com/. The metaswarm adapter wraps invocations with a timeout to prevent infinite loops. |
| Node.js version error | Gemini CLI requires Node.js 20 or higher | Check your version: `node --version`. Upgrade if below v20. Use `nvm install 20` if you use nvm. |
| Google login credentials not found | OAuth tokens may have expired or `~/.gemini/` was deleted | Run `gemini` interactively and re-authenticate with "Login with Google". |

---

## 3. Configure metaswarm

### Copy the config template

```bash
mkdir -p .metaswarm
cp templates/external-tools.yaml .metaswarm/external-tools.yaml
```

If you cloned metaswarm into a different location, use the full path:

```bash
cp /path/to/metaswarm/templates/external-tools.yaml .metaswarm/external-tools.yaml
```

### Key settings

Edit `.metaswarm/external-tools.yaml` to customize:

```yaml
adapters:
  codex:
    enabled: true                # Set to false to disable Codex
    model: "gpt-5.3-codex"      # Model for Codex CLI invocations
    timeout_seconds: 300         # Max seconds per invocation (5 min default)
    sandbox: none                # docker | platform | none
    auth_env_var: "OPENAI_API_KEY"
  gemini:
    enabled: true                # Set to false to disable Gemini
    model: "pro"                 # Model alias: pro | flash | flash-lite
    timeout_seconds: 300
    sandbox: none
    auth_env_var: "GEMINI_API_KEY"

routing:
  # How to pick the implementer for a task:
  #   cheapest-available  — prefer the cheapest tool that passes health check
  #   round-robin         — alternate between tools
  #   codex / gemini      — always use a specific tool
  default_implementer: "cheapest-available"

  # Order for escalation when a tool fails after max retries
  escalation_order: ["codex", "gemini", "claude"]

budget:
  per_task_usd: 2.00             # Max spend per task before alerting the user
  per_session_usd: 20.00         # Max total spend per session
```

**Important**: If `.metaswarm/external-tools.yaml` is absent, metaswarm works
normally without any external tool invocations. The config file is entirely
optional -- you only need it if you want to customize defaults.

---

## 4. Verify Setup

Run health checks for all installed tools:

```bash
# From your metaswarm installation directory:
skills/external-tools/adapters/codex.sh health | jq .
skills/external-tools/adapters/gemini.sh health | jq .
```

**Expected output for a ready tool:**

```json
{
  "tool": "codex",
  "status": "ready",
  "version": "0.101.0",
  "auth_valid": true,
  "model": "gpt-5.3-codex"
}
```

```json
{
  "tool": "gemini",
  "status": "ready",
  "version": "0.28.2",
  "auth_valid": true,
  "model": "pro"
}
```

Both should show `"status": "ready"`. If a tool shows `"status": "unavailable"`,
check the `auth_valid` field and revisit the authentication steps above.

You can also run the full verification script:

```bash
bin/external-tools-verify.sh
```

This validates adapter syntax, health commands, JSON output, helper functions,
and config template existence.

---

## 5. How It Works

Once external tools are installed and authenticated, the metaswarm orchestrator
automatically handles everything. Here is what happens behind the scenes:

### Automatic routing

When the orchestrator receives a work unit, it:

1. **Checks availability** -- runs `health` on each adapter to see which tools
   are ready (auth can expire mid-session, so this is checked per task).
2. **Picks the cheapest available tool** as the implementer (configurable via
   `routing.default_implementer`).
3. **Packages context** into a self-contained prompt file with acceptance
   criteria, relevant source code, coding standards, and test expectations.

### Cross-model adversarial review

After implementation, the output is reviewed by **different** models:

| Writer | Reviewer 1 | Reviewer 2 |
|--------|------------|------------|
| Codex | Gemini | Claude |
| Gemini | Codex | Claude |
| Claude | Codex | Gemini |

The writer never reviews its own output. This catches model-specific blind spots
that same-model review would miss.

### Escalation

If a tool fails after retries, the orchestrator escalates to the next tool in
the chain:

```
Cheapest tool (2 attempts)
  -> Other tool (2 attempts)
    -> Claude (1 attempt)
      -> Alert user with all branches, findings, and CI results
```

Worst case: 5 attempts before you are asked to intervene. With one external tool,
the chain is shorter (3 attempts max).

### What you do NOT need to do

- You do not need to manually invoke adapters -- the orchestrator calls them.
- You do not need to write prompt files -- context packaging is automatic.
- You do not need to merge branches -- the orchestrator handles worktree
  lifecycle and branch management.
- You do not need to monitor costs -- budget circuit breakers are enforced
  automatically per the config.

---

## 6. Further Reading

- **Design document**: `docs/plans/2026-02-14-external-tools-design.md`
- **Orchestration skill**: `skills/external-tools/SKILL.md`
- **Review rubric**: `.claude/rubrics/external-tool-review-rubric.md`
- **Config template**: `templates/external-tools.yaml`
- **Health check command**: `/external-tools-health`
