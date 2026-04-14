#!/usr/bin/env bash
# install.sh – symlink bin/* into a directory on $PATH
set -euo pipefail
PREFIX="${1:-$HOME/.local/bin}"
mkdir -p "$PREFIX"
for f in "$(dirname "$0")"/bin/*; do
  name="$(basename "$f")"
  ln -sf "$(realpath "$f")" "$PREFIX/$name"
  printf 'Linked %s -> %s/%s\n' "$f" "$PREFIX" "$name"
done
printf '\nAdd %s to PATH if not already present:\n  export PATH="%s:$PATH"\n' "$PREFIX" "$PREFIX"
