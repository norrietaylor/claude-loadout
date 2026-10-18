# claude-loadout

A [Minimal](https://minimal.dev) loadout that sets up Claude Code in `min` sessions and syncs its state in both directions:

- **History.** The project's recent Claude transcripts are copied into the session, so `/resume` and `claude --resume <id>` work there. Transcripts the session writes are pulled back to the host on detach and destroy.
- **Memory.** Auto memory is backed by a git repo you choose. Whatever Claude writes is *pending* until you review it:
  - `/memories` inside Claude.
  - The prompt shown when `claude` exits.
  - `claude-mem review` from a shell.

  `keep` commits and pushes; `discard` deletes. Anything still unreviewed when a session detaches or is destroyed is pushed to `pending/<session>-<slug>` and comes back to the host as pending.
- **Sandbox settings.** Settings with no host-only hooks or paths, permission mode `auto`, no onboarding or trust prompts, and plugins installed from the marketplaces your settings name.

## Requirements

- Minimal ≥ 0.7, plus `jq`, `perl` and `rsync` on the host.
- The `broker` loadout, stacked **before** this one. It supplies Claude auth and routes github.com through the host credential broker, which the memory clone, push and plugin installs use.

## Install

```sh
git clone https://github.com/norrietaylor/claude-loadout ~/src/claude-loadout
~/src/claude-loadout/install.sh          # copies loadout/ to ~/.config/minimal/loadouts/claude (re-run after edits)
```

In `~/.zshrc`:

```sh
source ~/src/claude-loadout/my.env        # your vars (see examples/norrie.env)
source ~/src/claude-loadout/host.zsh      # wraps `min`
```

Then:

```sh
min session activate --loadout broker --loadout claude
```

If your session shell is bash rather than zsh, or doesn't put `~/.local/bin` first on PATH, source `~/.config/claude-loadout/shellrc.sh` from its rc. Otherwise the exit-time review wrapper isn't picked up.

## Configuration (host env vars)

| Var | Default | Meaning |
|---|---|---|
| `CLAUDE_LOADOUT_MEMORY_REPO` | unset (memory sync off) | Absolute path to a host clone of your memory repo. Its `origin` is what sessions clone. Use a dedicated clone on the default branch, so branch work never moves memory files. |
| `CLAUDE_LOADOUT_MEMORY_SUBDIR` | `memory` | Tree inside that repo; memories go in `<subdir>/projects/<slug>/`. |
| `CLAUDE_LOADOUT_SETTINGS` | `.config/minimal/loadouts/claude/settings.default.json` | Session `settings.json` (relative to `$HOME`). |
| `CLAUDE_LOADOUT_SKILLS` | `.claude/skills` | Skills dir. Symlinks are not followed, so point this at the real directory if yours is a symlink farm. |
| `CLAUDE_LOADOUT_OUTPUT_STYLES` | `.claude/output-styles` | Output styles dir. |
| `CLAUDE_LOADOUT_CLAUDE_MD` | `.claude/CLAUDE.md` | User `CLAUDE.md`. |
| `CLAUDE_LOADOUT_HISTORY_MAX` / `_MB` | `20` / `80` | Transcript import caps: newest first, whichever cap is hit first. |

Plugins are installed at activation from your settings' `extraKnownMarketplaces` (GitHub sources only) and `enabledPlugins`. The `claude` package already ships the Minimal plugin, so leave it out of the list.

## Commands

| Command | Where | Does |
|---|---|---|
| `claude-mem status` / `diff` | both | Pending memories for this project. |
| `claude-mem review` | both | Interactive keep/discard. |
| `claude-mem keep <f>… \| --all` | both | Commit and push. `MEMORY.md` is committed with the last kept file. |
| `claude-mem discard <f>… \| --all` | both | Delete, and remove the file's line from `MEMORY.md`. |
| `claude-mem link [<slug>\|--all]` | host | Move `~/.claude/projects/<slug>/memory` into the repo and symlink it back. Existing memories are committed as an import. |
| `claude-mem recover [<session>]` | host | Restore stashed `pending/*` memories as pending. |
| `claude-sessions stage <path>` | host | Stage transcripts for activation. |
| `claude-sessions pull [<session>\|--all]` | host | Copy session transcripts back. |

`host.zsh` runs these for you:

| On | It runs |
|---|---|
| `min session activate` | stage, link, push |
| return from `min session attach` | pull, memory pull |
| `min session destroy` | pull, destroy, memory pull, recover |

## How it works

```
host                                              session
~/.claude/projects/<slug>/*.jsonl  ─stage─▶  ~/.claude/projects/-workbench/*.jsonl  (cwd → /workbench)
                                   ◀─pull──  (min session exec … tar; cwd → host path)
~/.claude/projects/<slug>/memory ─symlink─▶ $MEMORY_REPO/memory/projects/<slug>/
                                   git push/pull ⇅ origin ⇅ git (via broker)
~/.claude/projects/-workbench/memory ─symlink─▶ ~/.claude-memory/memory/projects/<slug>/
```

Sessions can't write to the host. Transcripts come back only when the host pulls them, and memories only travel through the git remote.

## Caveats

- `min stop`, a daemon shutdown or a crash runs no teardown hooks. After one, run `claude-sessions pull --all`.
- Unreviewed memory from such a session stays in the session until you attach and review it.
- A host memory that is unreviewed at activation is not visible in the session. The `min` wrapper warns about it.
- Pending memories are untracked files in the memory repo, so `git clean` there deletes them.
