# Activation for the `claude` loadout. POSIX sh, no shebang. Every step is
# guarded and the script always exits 0: a failing on_activate costs the
# whole session, and none of this is worth that. Output lands in the
# activation log.
set -u

say() { echo "claude: $*"; }
SLUG=${CLAUDE_LOADOUT_SLUG:-none}
SUB=${CLAUDE_LOADOUT_MEMORY_SUBDIR:-memory}
REMOTE=${CLAUDE_LOADOUT_MEMORY_REMOTE:-}
MEM=$HOME/.claude-memory
WB=$HOME/.claude/projects/-workbench
SEED=$HOME/.config/claude-loadout/seed-memory
mkdir -p "$WB"

# Abort a stalled transfer instead of holding activation until the timeout.
export GIT_HTTP_LOW_SPEED_LIMIT=1000 GIT_HTTP_LOW_SPEED_TIME=15

# --- memory: a sparse clone of the memory repo, linked as this project's
# auto-memory dir, so whatever Claude writes is a git change to review.
linked=
if [ -n "$REMOTE" ] && [ "$SLUG" != none ]; then
    if [ ! -d "$MEM/.git" ]; then
        rm -rf "$MEM"
        git clone -q --filter=blob:none --no-checkout "$REMOTE" "$MEM" \
            && git -C "$MEM" sparse-checkout set "$SUB" \
            && git -C "$MEM" checkout -q \
            || { rm -rf "$MEM"; say "memory clone of $REMOTE failed; memories will not sync"; }
    fi
    if [ -d "$MEM/.git" ]; then
        target=$MEM/$SUB/projects/$SLUG
        mkdir -p "$target"
        [ -L "$WB/memory" ] || rm -rf "$WB/memory"
        ln -sfn "$target" "$WB/memory" && linked=1
        git -C "$MEM" config user.email >/dev/null 2>&1 || git config --global user.email >/dev/null 2>&1 \
            || say "no git identity in the session; claude-mem keep will fail until one is set"
        say "memory: $SUB/projects/$SLUG ($(ls "$target" 2>/dev/null | wc -l | tr -d ' ') files) synced with $REMOTE"
    fi
fi
if [ -z "$linked" ]; then
    mkdir -p "$WB/memory"
    [ -d "$SEED" ] && cp -p "$SEED"/*.md "$WB/memory/" 2>/dev/null
    say "memory: local copy only (set CLAUDE_LOADOUT_MEMORY_REMOTE on the host to sync)"
fi

# --- onboarding, and workspace trust only when asked for: trusting
# /workbench runs the project's own .claude hooks and MCP servers without a
# prompt, with this session's credentials. Merged into whatever is there
# (the broker loadout may already have registered MCP servers in this file).
cj=$HOME/.claude.json
[ -s "$cj" ] || echo '{}' > "$cj"
ver=$(claude --version 2>/dev/null | awk '{print $1}')
if jq --arg v "${ver:-0}" --arg trust "${CLAUDE_LOADOUT_TRUST_WORKBENCH:-}" '
    .hasCompletedOnboarding = true
    | .lastOnboardingVersion = (.lastOnboardingVersion // $v)
    | .projects["/workbench"].hasCompletedProjectOnboarding = true
    | if $trust == "1" then .projects["/workbench"].hasTrustDialogAccepted = true else . end
' "$cj" > "$cj.tmp"; then
    mv "$cj.tmp" "$cj"
else
    rm -f "$cj.tmp"; say "could not update $cj"
fi

# --- plugins named in settings.json. enabledPlugins alone does not install
# anything on a fresh machine, so add each marketplace and install here.
settings=$HOME/.claude/settings.json
if [ -f "$settings" ] && command -v claude >/dev/null 2>&1; then
    jq -r '.extraKnownMarketplaces // {} | to_entries[]
           | .value.source | select(.source == "github") | .repo' "$settings" 2>/dev/null \
    | while read -r repo; do
        claude plugin marketplace add "$repo" >/dev/null 2>&1 || say "marketplace $repo: add failed"
    done
    jq -r '.enabledPlugins // {} | to_entries[] | select(.value == true) | .key' "$settings" 2>/dev/null \
    | while read -r p; do
        if claude plugin install "$p" --scope user >/dev/null 2>&1; then
            say "plugin $p installed"
        else
            say "plugin $p: install failed"
        fi
    done
fi

exit 0
