---
name: memories
description: Review the auto memories written for this project that are not yet saved to the memory repo, and keep or discard each one.
disable-model-invocation: true
allowed-tools: Bash(claude-mem:*), Bash(~/.local/bin/claude-mem:*)
---

Review pending memories with the `claude-mem` CLI (on PATH, or at `~/.local/bin/claude-mem`).

1. Run `claude-mem status --porcelain`. Each line is `<A|M|D> <file>` (new, modified, deleted). If there are none, say so and stop.
2. Run `claude-mem diff` to read every pending change.
3. Ask the user with AskUserQuestion, one question per memory (batch up to 4 per call), options: **Keep**, **Discard**, **Leave pending**. In each question give the memory's name and a one-line summary of what it says or what changed. Flag any memory that looks wrong, stale, duplicated by another memory, or that contains a secret, and recommend Discard for it.
4. Apply the answers in two commands: `claude-mem discard <files...>` then `claude-mem keep <files...>` (keep commits and pushes). Skip a command with no files.
5. Report what was kept, discarded and left pending, and whether the push succeeded. If the push failed, say that the commits are local and `claude-mem push` retries.

Never edit memory files yourself in this flow, and never keep a memory the user did not choose.
