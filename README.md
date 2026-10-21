# claude-loadout

A [Minimal](https://minimal.dev) loadout that sets up Claude Code in `min` sessions and syncs its state in both directions:

- **History.** The project's recent Claude transcripts are copied into the session, so `/resume` and `claude --resume <id>` work there. Transcripts the session writes are pulled back to the host on detach and destroy.
- **Memory.** Auto memory is backed by a git repo you choose. Whatever Claude writes is *pending* until you review it:
  - `/memories` inside Claude.
  - The prompt shown when `claude` exits.
  - `claude-mem review` from a shell.

  `discard` deletes. On the host, `keep` commits (signed) and pushes. In a session, `keep` commits locally and sends the memory to the host on `pending/<session>/<slug>`, along with anything still unreviewed when the session detaches or is destroyed. The host puts what arrives in a review inbox, and only what you keep there is published.
- **Sandbox settings.** Settings with no host-only hooks or paths, permission mode `auto`, no onboarding prompt, and plugins installed from the marketplaces your settings name.

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

Once, to sign the host's memory commits (an SSH key; `~/.ssh/id_ed25519.pub` by default):

```sh
claude-mem setup [<key.pub>]
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
| `CLAUDE_LOADOUT_PULL_MB` | `512` | Largest transcript archive taken back from a session. |
| `CLAUDE_LOADOUT_TRUST_WORKBENCH` | unset | `1` pre-accepts the workspace trust prompt for `/workbench`. That lets the project's own `.claude` hooks and MCP servers run unprompted with the session's credentials, so set it only if you activate projects you trust. |
| `CLAUDE_LOADOUT_SIGNING_KEY` | `~/.ssh/id_ed25519.pub` | Default key for `claude-mem setup`. |

Plugins are installed at activation from your settings' `extraKnownMarketplaces` (GitHub sources only) and `enabledPlugins`. The `claude` package already ships the Minimal plugin, so leave it out of the list.

## Commands

| Command | Where | Does |
|---|---|---|
| `claude-mem status` / `diff` | both | Pending memories for this project, and on the host the session inbox. |
| `claude-mem review` | both | Interactive keep/discard over the inbox, then local changes. Each memory is shown in full, with control characters made visible. |
| `claude-mem keep <f>… \| --all` | both | Host: commit and publish. Session: commit and send to the host. `MEMORY.md` is a file like any other; it is kept only when you keep it. |
| `claude-mem discard <f>… \| --all` | both | Delete, and remove the file's line from `MEMORY.md`. |
| `claude-mem setup [<key.pub>]` | host | Sign memory commits with an SSH key and add it to the trusted signers. |
| `claude-mem sync` | host | Take upstream commits if they are signed by a trusted key, then push. |
| `claude-mem link [--commit] [<slug>\|--all]` | host | Move `~/.claude/projects/<slug>/memory` into the repo and symlink it back. The existing memories arrive pending, or committed with `--commit`. |
| `claude-mem recover --session <name> \| --all` | host | Copy `pending/*` branches into the review inbox and delete them. |
| `claude-sessions stage <path>` | host | Stage transcripts for activation. |
| `claude-sessions pull [<session>\|--all]` | host | Copy session transcripts back. |

`host.zsh` runs these for you:

| On | It runs |
|---|---|
| `min session activate` | stage, link, sync |
| return from `min session attach` | pull, sync, recover |
| `min session destroy` | pull, destroy, sync, recover |

## How it works

```
host                                              session
~/.claude/projects/<slug>/*.jsonl  ─stage─▶  ~/.claude/projects/-workbench/*.jsonl  (cwd → /workbench)
                                   ◀─pull──  (min session exec … tar; cwd → host path)
~/.claude/projects/<slug>/memory ─symlink─▶ $MEMORY_REPO/memory/projects/<slug>/
   signed commits ⇄ origin/main ─clone─▶ ~/.claude-memory  (session)
   review inbox ◀─recover── origin pending/<session>/<slug> ◀─keep/stash──
~/.claude/projects/-workbench/memory ─symlink─▶ ~/.claude-memory/memory/projects/<slug>/
```

### Trust boundary

A session gets the broker's GitHub credential, so it can push anywhere you can, including the memory repo's main branch. Nothing on GitHub can tell its pushes from yours. The host therefore treats everything a session produces as untrusted:

- **Memory repo.** The host signs its memory commits. `claude-mem sync` refuses any upstream commit touching a checked-out path (the sparse set and top-level files) unless it is signed by a key in `~/.config/claude-loadout/allowed_signers`. That file lives only on the host. Add your other machines' keys there.
- **Session memories.** They arrive only through `recover`, which takes plain `*.md` blobs, never links or subdirectories, into `~/.local/state/claude-loadout/inbox/`. That inbox is outside every live memory dir, so host Claude never loads them before you review them. A session's `MEMORY.md` contributes only its new lines, each shown beside the memory it indexes.
- **Transcripts.** `claude-sessions pull` takes only plain files, capped at `CLAUDE_LOADOUT_PULL_MB`. A transcript the host already has is accepted only when the session's copy extends it byte for byte. A transcript new to the host is still the session's own record: read it before resuming it on the host.

## Caveats

- `min stop`, a daemon shutdown or a crash runs no teardown hooks. After one, run `claude-sessions pull --all`.
- Unreviewed memory from such a session stays in the session until you attach and review it.
- A host memory that is unreviewed at activation is not visible in the session. The `min` wrapper warns about it.
- Pending memories are untracked files in the memory repo, so `git clean` there deletes them.
- If `sync` refuses upstream, nothing is published until you resolve it. The message gives the commands for either case.
- Commits made elsewhere to checked-out paths, such as a GitHub web merge that touches a top-level file, are also unsigned. Merge them by hand after reading them.
