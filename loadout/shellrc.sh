# Sourced from your session shell rc (bash or zsh): puts the loadout's
# commands, including the `claude` wrapper that offers memory review on exit,
# ahead of the packaged claude.
case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) PATH=$HOME/.local/bin:$PATH; export PATH ;;
esac
