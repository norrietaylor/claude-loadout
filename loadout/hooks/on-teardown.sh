# Teardown safety net: nobody is attached to review, so push whatever memory
# is still pending to pending/<session> on the memory remote. Best effort;
# teardown never blocks on it.
m=$HOME/.local/bin/claude-mem
[ -x "$m" ] && [ -d "$HOME/.claude-memory/.git" ] && timeout 40 "$m" stash
exit 0
