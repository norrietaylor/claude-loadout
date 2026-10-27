#!/bin/sh
# Install (or update) the `claude` loadout and its host side.
#
#   install.sh [--no-init]   copy loadout/ into Minimal's loadouts dir, set up
#                            the state remote (claude-state init, unless
#                            --no-init), sign memory commits (claude-mem
#                            setup, if not yet), and register the host Claude
#                            Code hooks in settings.json
#   install.sh --uninstall   remove those hooks only; the loadout stays
#
# The loadout target must be a real directory: Minimal refuses hook scripts
# reached through a symlink. Loadouts are read at activation, so re-run this
# after every edit and re-activate.
set -eu

init=1 uninstall=
for a in "$@"; do
    case $a in
        --no-init) init= ;;
        --uninstall) uninstall=1 ;;
        *) echo "usage: install.sh [--no-init | --uninstall]" >&2; exit 2 ;;
    esac
done

here=$(cd "$(dirname "$0")" && pwd)
dest=${XDG_CONFIG_HOME:-$HOME/.config}/minimal/loadouts/claude
settings=${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json

# settings.json is often a symlink into a config repo: edit the real file in
# place, so the link survives and the change shows up in that repo.
real=$settings
while [ -L "$real" ]; do
    t=$(readlink "$real")
    case $t in
        /*) real=$t ;;
        *) real=$(dirname "$real")/$t ;;
    esac
done

# Merge the host hooks into settings.json. Entries whose command names
# claude-state are ours: they are removed from every event (and an event list
# that leaves empty is dropped), then on install one fresh entry per event is
# appended, so a re-run leaves exactly one of each. Everything else is kept.
merge_hooks() {    # $1 = install | uninstall
    created=
    if [ ! -s "$real" ]; then
        [ "$1" = uninstall ] && { echo "no $settings; no hooks to remove"; return 0; }
        mkdir -p "$(dirname "$real")"
        printf '{}\n' > "$real"
        echo "created $real"
        created=1
    fi
    if ! jq -e 'type == "object"' "$real" >/dev/null 2>&1; then
        echo "$real is not a JSON object; fix it and re-run (hooks not changed)" >&2
        return 1
    fi
    # settings.json may be shared across machines through a config repo, so
    # the command names the script relative to $HOME and does nothing where
    # the loadout is not installed.
    # shellcheck disable=SC2016  # $HOME is expanded by the hook's shell, not here
    case $dest in
        "$HOME"/*) cs='$HOME'${dest#"$HOME"}/bin/claude-state ;;
        *) cs=$dest/bin/claude-state ;;
    esac
    tmp=$(mktemp)
    jq --arg mode "$1" --arg cs "c=\"$cs\"; [ -x \"\$c\" ] && \"\$c\"" '
        def ours: (.command? // "") | tostring | test("claude-state");
        def strip: map(if any(.hooks[]?; ours)
                       then (.hooks |= map(select(ours | not))) | select(.hooks | length > 0)
                       else . end);
        .hooks as $orig
        | .hooks = reduce (($orig // {}) | keys[]) as $e (($orig // {});
              (.[$e] | strip) as $kept
              | if ($kept | length) == 0 and (.[$e] | length) > 0 then del(.[$e]) else .[$e] = $kept end)
        | if $mode == "install" then
              .hooks.SessionStart = (.hooks.SessionStart // [])
                  + [{hooks: [{type: "command", command: "\($cs) pull --hook || true", timeout: 30}]}]
              | .hooks.SessionEnd = (.hooks.SessionEnd // [])
                  + [{hooks: [{type: "command", command: "\($cs) push --hook || true", timeout: 15}]}]
          elif .hooks == {} and $orig != {} then del(.hooks)
          else . end
    ' "$real" > "$tmp" || { rm -f "$tmp"; return 1; }
    if cmp -s "$tmp" "$real"; then
        rm -f "$tmp"
        echo "hooks in $settings already up to date"
        return 0
    fi
    if [ -z "$created" ]; then
        backup=$real.bak.$(date +%Y%m%d%H%M%S)
        [ -e "$backup" ] && backup=$backup.$$
        cp -p "$real" "$backup"
        echo "backed up $real to $backup"
    fi
    cat "$tmp" > "$real"
    rm -f "$tmp"
    if [ "$1" = install ]; then
        echo "hooks in $settings: SessionStart -> claude-state pull, SessionEnd -> claude-state push"
    else
        echo "removed the claude-state hooks from $settings"
    fi
    [ "$real" = "$settings" ] || echo "note: $settings links to $real; commit the change there"
}

if [ -n "$uninstall" ]; then
    merge_hooks uninstall
    echo "loadout left in place at $dest"
    exit 0
fi

[ -L "$dest" ] && { echo "$dest is a symlink; remove it first" >&2; exit 1; }
mkdir -p "$dest"
dest=$(cd "$dest" && pwd)
rsync -a --delete "$here/loadout/" "$dest/"
echo "installed $dest"

if [ -n "$init" ]; then
    "$dest/bin/claude-state" init
fi

# Host commits to main must be signed: the trust boundary rests on it. The
# same checks claude-mem's signing_ready makes, against the state clone.
repo=${CLAUDE_LOADOUT_MEMORY_REPO:-${CLAUDE_STATE_DIR:-$HOME/.local/share/claude-state}}
signers=${XDG_CONFIG_HOME:-$HOME/.config}/claude-loadout/allowed_signers
if [ -d "$repo/.git" ]; then
    if [ "$(git -C "$repo" config gpg.format || true)" = ssh ] \
        && [ -n "$(git -C "$repo" config user.signingkey || true)" ] \
        && [ "$(git -C "$repo" config --bool commit.gpgsign || true)" = true ] \
        && [ "$(git -C "$repo" config gpg.ssh.allowedSignersFile || true)" = "$signers" ] \
        && [ -s "$signers" ]; then
        echo "commits in $repo are signed"
    else
        "$dest/bin/claude-mem" setup
    fi
fi

merge_hooks install
command -v min >/dev/null && min loadout list 2>&1 | grep -E '^ *claude ' || true
