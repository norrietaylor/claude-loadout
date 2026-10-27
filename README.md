# claude-loadout

A [Minimal](https://minimal.dev) loadout that sets up Claude Code in `min` sessions and syncs its state through one private git remote, the **state remote**. Nothing wraps `min`: loadout lifecycle hooks sync the session, and Claude Code hooks sync the host, so sessions started by any tool (`min`, `min-warp`, `min-cmux`, …) behave the same.

- **Memory.** Every project's auto memory lives in the state remote, so it survives a wiped `~/.claude`. Whatever Claude writes is *pending* until you review it:
  - `/memories` inside Claude.
  - The prompt shown when `claude` exits.
  - `claude-mem review` from a shell.

  `discard` deletes. On the host, `keep` commits (signed) and pushes. In a session, `keep` commits and sends the memory to the host on a `session/<name>` branch, along with anything still pending when the session detaches or is destroyed. The host puts what arrives in a review inbox, and only what you keep there is published.
- **History.** The remote keeps a capped set of recent transcripts per repo. A session gets them at activation and attach, so `/resume` and `claude --resume <id>` work there, and the transcripts it writes come back to the host.
- **Sandbox settings.** Settings with no host-only hooks or paths, permission mode `auto`, no onboarding prompt, and plugins installed from the marketplaces your settings name.

## Requirements

- Minimal ≥ 0.7, plus `git`, `jq`, `rsync` and an authenticated `gh` on the host.
- The `broker` loadout, stacked **before** this one. It supplies Claude auth and routes github.com through the host credential broker, which the state clone, push and plugin installs use.

## Install

```sh
git clone https://github.com/norrietaylor/claude-loadout ~/src/claude-loadout
~/src/claude-loadout/install.sh
```

`install.sh`:

1. Copies `loadout/` to `~/.config/minimal/loadouts/claude`. Re-run it after every edit.
2. Runs `claude-state init`, unless you pass `--no-init`. That creates the private repo `$CLAUDE_STATE_REPO` if it is missing, clones it to `$CLAUDE_STATE_DIR`, writes the remote URL to `~/.config/claude-loadout/remote`, and seeds it from `~/.claude/projects`.
3. Runs `claude-mem setup` if the clone's commits aren't signed yet. It uses an SSH key, `~/.ssh/id_ed25519.pub` by default. If it fails, run `claude-mem setup <key.pub>` and then re-run `install.sh`.
4. Links `claude-mem` and `claude-state` into `~/.local/bin` (or `$CLAUDE_LOADOUT_BIN_DIR`), so you can run them on the host. A file of that name it didn't create is left alone.
5. Adds the two host hooks to `~/.claude/settings.json`, or to `$CLAUDE_CONFIG_DIR/settings.json` if that is set. It writes a timestamped backup next to the file first. If the file is a symlink, the real file is edited in place. Re-running leaves one entry per event. Each hook checks that the script exists first, so a settings file shared with a machine without the loadout does nothing there.

`install.sh --uninstall` removes only those links and hook entries. The loadout, the clone and the remote stay.

Then:

```sh
min session activate --loadout broker --loadout claude
```

If your session shell is bash rather than zsh, or doesn't put `~/.local/bin` first on PATH, source `~/.config/claude-loadout/shellrc.sh` from its rc. Otherwise the exit-time review wrapper isn't picked up.

## How it works

### Remote layout (branch `main`)

```
index.json                              repo key -> host slugs and paths
repos/<key>/memory/*.md                 key = normalized origin, e.g. github.com/owner/repo
repos/<key>/transcripts/<uuid>.jsonl    (+ <uuid>/ sidecar dirs)
local/<slug>/memory/*.md                projects with no origin: backed up only
```

Clones of the same repo share one `repos/<key>`. On the host each project's `~/.claude/projects/<slug>/memory` is a symlink into the clone. A session finds its project by the origin of `/workbench`. A transcript keeps the cwd of whoever wrote it, and each reader rewrites it to its own path on import: `/workbench` in a session, the project path on the host.

### Hooks

| Side | Hook | Runs | Does |
|---|---|---|---|
| host | Claude Code `SessionStart` | `claude-state pull --hook` | Signed `claude-mem sync` of `main`. For each `session/*` branch: import its transcripts into the project's primary host slug, file its memories in the review inbox (`claude-mem recover`), and delete the branch. |
| host | Claude Code `SessionEnd` | `claude-state push --hook` | In the background, publish the transcripts of the project you were in to `repos/<key>/transcripts` within the caps. Then make a signed commit and run `claude-mem sync`. |
| session | `on_activate` | `claude-state session-activate` | Sparse clone of `repos/<key>` into `~/.claude-state`, link `-workbench/memory` to it, and copy in the transcripts. Also onboarding, opt-in trust and plugins. |
| session | `on_attach` | `claude-state session-attach` | Rebase the clone onto `origin/main` (pending memories survive), then copy in transcripts that are new or that extend the session's copy. |
| session | `on_detach`, `on_destroy` | `claude-state session-teardown` | Force-push one commit holding the session's memories (kept and pending) and transcripts to `session/<name>`. |

Host memories publish through `claude-mem keep`, as before.

### Trust boundary

A session gets the broker's GitHub credential, so it can push anywhere you can, including the state remote's `main`. Nothing on GitHub can tell its pushes from yours. The host therefore treats everything a session produces as untrusted:

- **`main`.** The host signs its commits. `claude-mem sync` refuses any upstream commit touching a checked-out path unless it is signed by a key in `~/.config/claude-loadout/allowed_signers`. That file lives only on the host. Add your other machines' keys there.
- **Session memories.** They arrive only through `recover`, which takes plain `*.md` blobs from `repos/<key>/memory/` and `local/<slug>/memory/` on `session/<name>` branches, never links or subdirectories. They land in `~/.local/state/claude-loadout/inbox/`. That inbox is outside every live memory dir, so host Claude never loads them before you review them. A session's `MEMORY.md` contributes only its new lines, each shown beside the memory it indexes.
- **Session transcripts.** `pull` takes only plain files, each capped at `CLAUDE_LOADOUT_FILE_MB`, and at most `CLAUDE_LOADOUT_PULL_MB` per branch. A transcript the host already has is accepted only when the session's copy extends it byte for byte. A transcript new to the host is still the session's own record, so read it before you resume it on the host.

## Configuration (host env vars)

| Var | Default | Meaning |
|---|---|---|
| `CLAUDE_STATE_REPO` | `<gh user>/claude-state` | GitHub repo (`owner/name`) that `claude-state init` creates, private. |
| `CLAUDE_STATE_DIR` | `~/.local/share/claude-state` | Host clone of the state remote. |
| `CLAUDE_LOADOUT_HISTORY_MAX` / `_MB` | `20` / `80` | Transcripts kept per repo key: newest first, whichever cap is hit first. |
| `CLAUDE_LOADOUT_FILE_MB` | `50` | Largest single transcript stored. GitHub refuses files over 100 MB. |
| `CLAUDE_LOADOUT_PULL_MB` | `512` | Most transcript data taken from one session branch. |
| `CLAUDE_LOADOUT_SETTINGS` | `.config/minimal/loadouts/claude/settings.default.json` | Session `settings.json`, relative to `$HOME`. |
| `CLAUDE_LOADOUT_SKILLS` | `.claude/skills` | Skills dir. Symlinks are not followed, so point this at the real directory if yours is a symlink farm. |
| `CLAUDE_LOADOUT_OUTPUT_STYLES` | `.claude/output-styles` | Output styles dir. |
| `CLAUDE_LOADOUT_CLAUDE_MD` | `.claude/CLAUDE.md` | User `CLAUDE.md`. |
| `CLAUDE_LOADOUT_TRUST_WORKBENCH` | unset | `1` pre-accepts the workspace trust prompt for `/workbench`. That lets the project's own `.claude` hooks and MCP servers run unprompted with the session's credentials, so set it only if you activate projects you trust. |
| `CLAUDE_LOADOUT_SIGNING_KEY` | `~/.ssh/id_ed25519.pub` | Default key for `claude-mem setup`. |

The `CLAUDE_LOADOUT_*` path vars reach the session when they are set in the environment `min` runs in. Plugins are installed at activation from your settings' `extraKnownMarketplaces` (GitHub sources only) and `enabledPlugins`. The `claude` package already ships the Minimal plugin, so leave it out of the list.

## Commands

| Command | Where | Does |
|---|---|---|
| `claude-mem status` / `diff` | both | Pending memories for this project, and on the host the session inbox. |
| `claude-mem review` | both | Interactive keep/discard over the inbox, then local changes. Each memory is shown in full, with control characters made visible. |
| `claude-mem keep <f>… \| --all` | both | Host: commit and publish. Session: commit and send to the host on `session/<name>`. `MEMORY.md` is a file like any other, kept only when you keep it. |
| `claude-mem discard <f>… \| --all` | both | Delete, and remove the file's line from `MEMORY.md`. |
| `claude-mem setup [<key.pub>]` | host | Sign commits with an SSH key and add it to the trusted signers. |
| `claude-mem sync` | host | Take upstream commits if they are signed by a trusted key, then push. |
| `claude-mem link [--commit] [<slug>\|--all]` | host | Move `~/.claude/projects/<slug>/memory` into the clone and symlink it back. |
| `claude-mem recover --session <name> \| --all` | host | Copy memories on `session/*` branches into the review inbox and delete the branches. |
| `claude-state init` / `seed` | host | Create and clone the state remote, then seed it from `~/.claude/projects`. |
| `claude-state pull` / `push` | host | What the host hooks run, for running by hand. |
| `claude-state key [<dir>]` | both | The repo key for a directory's origin. |

## Caveats

- `min stop`, a daemon shutdown or a crash runs no teardown hooks. That session's memories and transcripts stay in the box until you attach and detach, or destroy it.
- Projects without an origin are backed up under `local/<slug>`, but nothing is loaded for them in a session.
- `claude-state seed` takes a project only when one of its transcripts names a directory that still exists. Memory of a project with no transcripts left, or whose directory is gone, stays only in `~/.claude/projects`.
- `~/.claude/settings.json` may be a symlink into a config repo. `install.sh` edits the file it points to, so commit the hook change in that repo.
- Pending memories are untracked files in the clone, so `git clean` there deletes them.
- If `sync` refuses upstream, nothing is published until you resolve it. The message gives the commands for either case.
- Commits made elsewhere to checked-out paths, such as a GitHub web merge that touches a top-level file, are also unsigned. Merge them by hand after reading them.
