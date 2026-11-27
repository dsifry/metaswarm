# Waiting-On Convention

How agents tell the human what is blocked on whom, and how the human asks for an explanation with a single keystroke.

## End-of-turn status line

While work is in progress, end every turn with a `WAITING-ON:` line listing everything the work is waiting on.

- Put items the **human** must act on first, each prefixed `YOU:`. These are decisions, approvals, commands to run, logins and answers.
- Then list the agent's own background work (running tests, subagents, CI, deploys) without a prefix.
- Keep each item to one short line. Detail comes later, on request.
- If nothing is waiting, say `WAITING-ON: nothing`.

Example:

```text
WAITING-ON:
YOU: choose the retry policy (3 options)
YOU: run `gh auth login` for the release account
CI on PR #42; reviewer subagent for unit 2
```

## The "E" shortcut

When the user's whole prompt is `E` (or `e`), explain the items waiting on them, one at a time. The `hooks/explain-waiting.sh` UserPromptSubmit hook injects these instructions on that prompt; any agent should follow them even without the hook.

1. Take the latest `WAITING-ON:` line. On the first `E`, explain its first `YOU:` item. Each further `E` in a row moves to the next item.
2. Explain the item in plain language:
   - what it is and why it is needed;
   - for a decision: the options, lettered A, B, C under numbered questions, recommended first (see Decision requests in `delivery-scope.md`), each with pros and cons;
   - for an action: the exact command or step;
   - what happens if the human does nothing.
3. End with `Item k of n - type E for the next.`
4. After the last item, say so and restate the full `YOU:` list briefly.
5. If there are no `YOU:` items, say `Nothing is waiting on you.`
6. **An explanation turn does not reset the sequence.** The `Item k of n - type E for the next.` ending replaces the `WAITING-ON:` line for that turn only; the cursor stays on the latest real `WAITING-ON:` line, so the next `E` moves to item k+1. A new `WAITING-ON:` line published by a normal work turn restarts the sequence at item 1.
7. **Never treat `E` as an answer** to a pending question or approval. It only asks for an explanation.
