#!/bin/sh
# Status line: dir, git branch, context use, model/effort, and a count of
# memories waiting for review.
input=$(cat)
j() { printf '%s' "$input" | jq -r "$1" 2>/dev/null; }

dir=$(j '.workspace.current_dir // ""')
model=$(j '.model.display_name // ""')
effort=$(j '.effort.level // ""')
pct=$(j '.context_window.used_percentage // empty')

branch=
[ -n "$dir" ] && branch=$(git -C "$dir" --no-optional-locks symbolic-ref --short HEAD 2>/dev/null)

pending=
if command -v claude-mem >/dev/null 2>&1; then
    n=$(cd "${dir:-.}" && claude-mem status --porcelain 2>/dev/null | wc -l | tr -d ' ')
    [ "${n:-0}" -gt 0 ] && pending=" ✎ $n pending (/memories)"
fi

printf '\033[33m%s\033[0m' "$dir"
[ -n "$branch" ] && printf ' \033[34m⎇ %s\033[0m' "$branch"
[ -n "$pct" ] && printf ' \033[35mctx %s%%\033[0m' "${pct%.*}"
[ -n "$model" ] && printf ' \033[2m· %s%s\033[0m' "$model" "${effort:+ · $effort}"
[ -n "$pending" ] && printf '\033[36m%s\033[0m' "$pending"
