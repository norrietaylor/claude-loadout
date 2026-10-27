# Activation for the `claude` loadout. POSIX sh, no shebang. Every step is
# guarded and the script always exits 0: a failing on_activate costs the
# whole session, and none of this is worth that. Output lands in the
# activation log.
set -u

say() { echo "claude: $*"; }

# Abort a stalled transfer instead of holding activation until the timeout.
export GIT_HTTP_LOW_SPEED_LIMIT=1000 GIT_HTTP_LOW_SPEED_TIME=15

# --- state: clone the state remote, link this project's memories as
# -workbench/memory and copy in its recent transcripts (cwd -> /workbench).
# claude-state logs its own one-line reason when there is nothing to load.
cs=$HOME/.local/bin/claude-state
if [ -x "$cs" ]; then
    "$cs" session-activate || say "claude-state session-activate failed; the session starts without synced state"
else
    say "$cs missing; the session starts without synced state"
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
