# Detach and destroy: nobody may come back to review, so send this session's
# memories (kept and still pending) and transcripts to session/<name> on the
# state remote, where the host's next `claude-state pull` picks them up.
# Best effort; teardown never blocks on it.
export GIT_HTTP_LOW_SPEED_LIMIT=1000 GIT_HTTP_LOW_SPEED_TIME=15
cs=$HOME/.local/bin/claude-state
[ -x "$cs" ] && { timeout 40 "$cs" session-teardown || echo "claude: claude-state session-teardown failed"; }
exit 0
