#!/bin/sh
# Put `check` on PATH by symlinking it from this checkout, then print the
# remaining setup steps. Touches nothing else: no shell rc files, no services.
#
#   ./install.sh                         # -> ~/.local/bin/check
#   PREFIX=/usr/local/bin ./install.sh   # -> /usr/local/bin/check
set -eu

repo=$(cd "$(dirname "$0")" && pwd -P)
dest=${PREFIX:-$HOME/.local/bin}
link=$dest/check

mkdir -p "$dest"

# Replace an old symlink, but never overwrite a real file someone put there.
if [ -e "$link" ] && [ ! -L "$link" ]; then
  printf 'install.sh: %s exists and is not a symlink; remove it first\n' "$link" >&2
  exit 1
fi
ln -sfn "$repo/check" "$link"
chmod +x "$repo/check"
printf 'linked %s -> %s\n' "$link" "$repo/check"

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
  3. Optional, to use build/run by hand, add to ~/.bashrc or ~/.zshrc:
       . "$repo/cp.sh"
  4. Click the extension on a problem page, then:
       check a.cpp
EOF
