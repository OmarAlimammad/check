#!/bin/sh
# Put `check`, `build` and `run` on PATH by symlinking them from this checkout,
# then print the remaining setup steps. Touches nothing else: no shell rc
# files, no services.
#
#   ./install.sh                         # -> ~/.local/bin/{check,build,run}
#   PREFIX=/usr/local/bin ./install.sh   # -> /usr/local/bin/{check,build,run}
set -eu

repo=$(cd "$(dirname "$0")" && pwd -P)
dest=${PREFIX:-$HOME/.local/bin}
cmds="check build run"

mkdir -p "$dest"

# Replace old symlinks, but never overwrite a real file someone put there.
# Checked for all three up front so a conflict doesn't leave a partial install.
for cmd in $cmds; do
  if [ -e "$dest/$cmd" ] && [ ! -L "$dest/$cmd" ]; then
    printf 'install.sh: %s exists and is not a symlink; remove it first\n' "$dest/$cmd" >&2
    exit 1
  fi
done
for cmd in $cmds; do
  chmod +x "$repo/$cmd"
  ln -sfn "$repo/$cmd" "$dest/$cmd"
  printf 'linked %s -> %s\n' "$dest/$cmd" "$repo/$cmd"
done

case ":$PATH:" in
  (*":$dest:"*) ;;
  (*) printf '\nnote: %s is not on your PATH; add it in your shell rc file.\n' "$dest" ;;
esac

cat <<EOF

Next steps:
  1. Install Competitive Companion in your browser:
       https://github.com/jmerle/competitive-companion
  2. Start the listener, and have it start on login (see README,
     "Competitive Companion setup"):
       check listen
  3. Click the extension on a problem page, then:
       check a.cpp
     build/run also work on their own: build a.cpp, run - a.cpp
EOF
