#!/bin/sh
# Extract every file that setup.sh writes via heredoc into a directory, so each piece can be
# syntax-checked and tested on its own.   Usage: dev/extract.sh OUTDIR
# Result: OUTDIR/tmux.conf, cw, cc-bell.sh, status.sh, session-picker.sh, zshrc, ...
set -e
out="${1:?usage: dev/extract.sh OUTDIR}"
src="$(cd "$(dirname "$0")/.." && pwd)/setup.sh"
mkdir -p "$out"
awk -v out="$out" -v q="'" '
  /^[ \t]*cat >>? [^ ]+ <<.[A-Z_]+.$/ {
    split($0, a, " ")
    path = a[3]; delim = a[4]
    gsub(/<</, "", delim); gsub(q, "", delim)
    k = split(path, parts, "/"); name = parts[k]; sub(/^\./, "", name)
    if (name ~ /\$/) name = tolower(delim)
    file = out "/" name; printf "" > file; capturing = 1; next
  }
  capturing && $0 == delim { close(file); capturing = 0; next }
  capturing { print > file }
' "$src"
