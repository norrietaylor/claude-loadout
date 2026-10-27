# On attach: take what the host published since activation. Rebases the
# state clone onto origin/main (memory updates land through the -workbench
# symlink; pending memories survive) and copies in transcripts that are new
# or extend the session's copy byte for byte. Best effort; always exits 0.
export GIT_HTTP_LOW_SPEED_LIMIT=1000 GIT_HTTP_LOW_SPEED_TIME=15
cs=$HOME/.local/bin/claude-state
[ -x "$cs" ] && { timeout 110 "$cs" session-attach || echo "claude: claude-state session-attach failed"; }
exit 0
