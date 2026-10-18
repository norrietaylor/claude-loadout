# Host side of the `claude` Minimal loadout. Source it from ~/.zshrc.
#
# Wraps `min` so that:
#   min session activate   stages the project's recent transcripts, links its
#                          memory dir into the memory repo, and hands the
#                          loadout its vars (CLAUDE_LOADOUT_SLUG, _MEMORY_REMOTE)
#   min session attach     pulls new transcripts and memories back when you
#                          detach
#   min session destroy    pulls transcripts first, then recovers memories the
#                          session stashed unreviewed (as pending, here)
#
# Memory sync is on when CLAUDE_LOADOUT_MEMORY_REPO names a local clone of
# your memory repo; its origin becomes the remote the session clones.

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

_claude_loadout_memory_pull() {
    [[ -n ${CLAUDE_LOADOUT_MEMORY_REPO:-} ]] || return 0
    git -C "$CLAUDE_LOADOUT_MEMORY_REPO" pull -q --rebase --autostash 2>/dev/null \
        || print -u2 "claude-loadout: could not pull $CLAUDE_LOADOUT_MEMORY_REPO"
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
                remote=$(git -C "$CLAUDE_LOADOUT_MEMORY_REPO" remote get-url origin 2>/dev/null)
                _claude_loadout_memory_pull
                git -C "$CLAUDE_LOADOUT_MEMORY_REPO" push -q 2>/dev/null
                local n=$(CLAUDE_LOADOUT_SLUG=$slug claude-mem status --porcelain 2>/dev/null | wc -l)
                (( n > 0 )) && print -u2 "claude-loadout: ${n// /} unreviewed host memories for this project stay on the host (claude-mem review)"
            fi
            CLAUDE_LOADOUT_SLUG=$slug CLAUDE_LOADOUT_MEMORY_REMOTE=$remote command min "$@"
            ;;
        attach)
            command min "$@"; rc=$?
            claude-sessions pull "$(_claude_loadout_session "${@:3}")"
            _claude_loadout_memory_pull
            return $rc
            ;;
        destroy)
            local s= name= prefix=
            if [[ " ${*:3} " == *" --all "* ]]; then
                claude-sessions pull --all
            else
                s=$(_claude_loadout_session "${@:3}")
                if [[ -n $s ]]; then
                    claude-sessions pull "$s"
                    name=$(command min session list --json 2>/dev/null | jq -r --arg q "$s" \
                        '[.sessions[] | select(.name == $q or (.id | startswith($q)))][0].name // empty')
                    prefix=${name:+$name-}
                fi
            fi
            command min "$@"; rc=$?
            # The destroy hook stashed whatever was never reviewed; bring it
            # back here as pending.
            if (( rc == 0 )) && [[ -n ${CLAUDE_LOADOUT_MEMORY_REPO:-} ]]; then
                _claude_loadout_memory_pull
                [[ -n $name || " ${*:3} " == *" --all "* ]] && claude-mem recover "$prefix"
            fi
            return $rc
            ;;
        *)
            command min "$@"
            ;;
    esac
}
