# Host side of the `claude` Minimal loadout. Source it from ~/.zshrc.
#
# Wraps `min` so that:
#   min session activate   stages the project's recent transcripts, links its
#                          memory dir into the memory repo, and hands the
#                          loadout its vars (CLAUDE_LOADOUT_SLUG, _MEMORY_REMOTE)
#   min session attach     pulls new transcripts back when you detach, and
#                          moves memories the session sent into the review
#                          inbox (claude-mem review)
#   min session destroy    the same, around the destroy
#
# Memory sync is on when CLAUDE_LOADOUT_MEMORY_REPO names a local clone of
# your memory repo; its origin becomes the remote the session clones.
# Nothing a session pushes is taken without a check: `claude-mem sync` takes
# only signed upstream commits, and `recover` lands in the inbox.

: ${CLAUDE_LOADOUT_BIN:=${XDG_CONFIG_HOME:-$HOME/.config}/minimal/loadouts/claude/bin}
path=("$CLAUDE_LOADOUT_BIN" ${path:#$CLAUDE_LOADOUT_BIN})

# The project dir an activate command line refers to: -C/--repo-dir, else
# the first positional, else $PWD.
_claude_loadout_project() {
    local dir= a skip=
    for a in "$@"; do
        if [[ -n $skip ]]; then
            [[ $skip == dir ]] && dir=$a
            skip=; continue
        fi
        case $a in
            -C|--repo-dir) skip=dir ;;
            -n|--name|--sync|--network|--ingress|--dynamic-ingress|--dynamic-range|\
            --allow-subnets|--allow-dns-hosts|--allow-protocols|--deny-subnets|\
            --loadout|--minimal-dir|--config-dir|--provider) skip=1 ;;
            -*) ;;
            *) [[ -z $dir ]] && dir=$a ;;
        esac
    done
    (cd "${dir:-$PWD}" 2>/dev/null && pwd -P) || pwd -P
}

# First positional argument (a session name/id) of attach/destroy, if any.
_claude_loadout_session() {
    local a skip=
    for a in "$@"; do
        [[ -n $skip ]] && { skip=; continue; }
        case $a in
            -C|--repo-dir|--minimal-dir|--config-dir|--provider) skip=1 ;;
            -*) ;;
            *) print -r -- "$a"; return ;;
        esac
    done
}

# The session's name, for a name or id prefix.
_claude_loadout_session_name() {
    [[ -n $1 ]] || return 0
    command min session list --json 2>/dev/null | jq -r --arg q "$1" \
        '[.sessions[] | select(.name == $q or (.id | startswith($q)))][0].name // empty'
}

# Take signed memory commits, publish ours, and move what the session sent
# into the inbox: after attach returns (detach sent it) and after destroy.
_claude_loadout_memory_in() {
    [[ -n ${CLAUDE_LOADOUT_MEMORY_REPO:-} ]] || return 0
    claude-mem sync
    [[ -n $1 ]] && claude-mem recover "$@"
}

min() {
    if [[ $1 != session ]]; then
        command min "$@"; return
    fi
    local rc
    case $2 in
        activate)
            local proj=$(_claude_loadout_project "${@:3}")
            local slug=${proj//[^a-zA-Z0-9]/-}
            local remote=
            claude-sessions stage "$proj"
            if [[ -n ${CLAUDE_LOADOUT_MEMORY_REPO:-} ]]; then
                CLAUDE_LOADOUT_SLUG=$slug claude-mem link "$slug" >/dev/null
                # Never hand the session credentials embedded in the URL.
                remote=$(git -C "$CLAUDE_LOADOUT_MEMORY_REPO" remote get-url origin 2>/dev/null \
                    | sed -E 's#^([A-Za-z][A-Za-z0-9+.-]*://)[^/@]*@#\1#')
                claude-mem sync
                local n=$(CLAUDE_LOADOUT_SLUG=$slug claude-mem status --porcelain 2>/dev/null | wc -l)
                (( n > 0 )) && print -u2 "claude-loadout: ${n// /} unreviewed host memories for this project stay on the host (claude-mem review)"
            fi
            CLAUDE_LOADOUT_SLUG=$slug CLAUDE_LOADOUT_MEMORY_REMOTE=$remote command min "$@"
            ;;
        attach)
            local s=$(_claude_loadout_session "${@:3}")
            command min "$@"; rc=$?
            claude-sessions pull "$s"
            local name=$(_claude_loadout_session_name "$s")
            _claude_loadout_memory_in ${name:+--session} $name
            return $rc
            ;;
        destroy)
            local s= name= all=
            if [[ " ${*:3} " == *" --all "* ]]; then
                all=1
                claude-sessions pull --all
            else
                s=$(_claude_loadout_session "${@:3}")
                if [[ -n $s ]]; then
                    claude-sessions pull "$s"
                    name=$(_claude_loadout_session_name "$s")
                fi
            fi
            command min "$@"; rc=$?
            # The destroy hook sent whatever was never reviewed.
            if (( rc == 0 )); then
                if [[ -n $all ]]; then
                    _claude_loadout_memory_in --all
                else
                    _claude_loadout_memory_in ${name:+--session} $name
                fi
            fi
            return $rc
            ;;
        *)
            command min "$@"
            ;;
    esac
}
