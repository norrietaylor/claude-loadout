#!/bin/sh
# Install (or update) the `claude` loadout into Minimal's loadouts dir. The
# target must be a real directory: Minimal refuses hook scripts reached
# through a symlink. Loadouts are read at activation, so re-run this after
# every edit and re-activate.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
dest=${XDG_CONFIG_HOME:-$HOME/.config}/minimal/loadouts/claude
[ -L "$dest" ] && { echo "$dest is a symlink; remove it first" >&2; exit 1; }
mkdir -p "$dest"
rsync -a --delete "$here/loadout/" "$dest/"
echo "installed $dest"
command -v min >/dev/null && min loadout list 2>&1 | grep -E '^ *claude ' || true
