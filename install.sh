#!/usr/bin/env bash
#
# Installs dotserve by symlinking it onto PATH.
#
# A symlink rather than a copy, because dotserve reads templates/server.cfg relative
# to its own resolved location: a copied script would find no template and fail on the
# first run of a fresh install, which is the one run that has to work.

set -euo pipefail

readonly ROOT="$(cd "$(dirname "$0")" && pwd)"
PREFIX="${PREFIX:-$HOME/.local/bin}"

while [ $# -gt 0 ]; do
  case "$1" in
    --prefix) PREFIX="${2:-}"; shift 2 ;;
    -h|--help)
      printf 'usage: install.sh [--prefix DIR]   (default: $HOME/.local/bin)\n'
      exit 0 ;;
    *) printf 'unknown option: %s\n' "$1" >&2; exit 2 ;;
  esac
done

mkdir -p "$PREFIX"
ln -sf "$ROOT/dotserve" "$PREFIX/dotserve"

printf 'Installed %s -> %s\n' "$PREFIX/dotserve" "$ROOT/dotserve"

case ":$PATH:" in
  *":$PREFIX:"*) ;;
  *) printf '\nwarning: %s is not on your PATH.\n' "$PREFIX" >&2 ;;
esac
