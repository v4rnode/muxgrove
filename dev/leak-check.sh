#!/bin/sh
# Blocks work-related or personal content from being committed to this public repo.
# Scans every line of every file in the git index for:
#   - generic patterns: email addresses, home paths (/Users/<name>), ticket keys like ABC-123
#   - your own patterns from dev/leak-patterns.local (git-ignored, one extended regex per line,
#     case-insensitive): names, employer, clients, internal project names, internal domains
# Usage: dev/leak-check.sh        (exit 1 and list file:line if anything is found)
# Enforced on every commit by dev/hooks/pre-commit (git config core.hooksPath dev/hooks).
root=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "leak-check: not a git repo"; exit 0; }
cd "$root" || exit 1

# Placeholders that are fine to keep. They are removed from a line before it is checked.
ALLOW='noreply@anthropic\.com|git@github\.com|PROJ-123|/Users/<name>|UTF-8|SHA-[0-9]+'

gen=$(mktemp); loc=$(mktemp)
cat > "$gen" <<'PATTERNS_EOF'
[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+\.[A-Za-z]{2,}
/Users/[A-Za-z0-9._-]+
[^A-Za-z0-9][A-Z][A-Z0-9]{1,9}-[0-9]{1,6}([^A-Za-z0-9]|$)
PATTERNS_EOF
if [ -f dev/leak-patterns.local ]; then
  grep -v '^[[:space:]]*\(#\|$\)' dev/leak-patterns.local > "$loc"
fi

# This file is skipped: its own pattern definitions would match themselves. It holds no private terms
# (those live in dev/leak-patterns.local, which git ignores).
found=$(git grep --cached -nI '' -- . ':!dev/leak-check.sh' | awk -v allow="$ALLOW" -v genfile="$gen" -v locfile="$loc" '
  BEGIN {
    while ((getline line < genfile) > 0) g[++ng] = line          # case-sensitive
    while ((getline line < locfile) > 0) l[++nl] = tolower(line) # your terms: case-insensitive
  }
  {
    i = index($0, ":"); rest = substr($0, i + 1); j = index(rest, ":")
    where = substr($0, 1, i + j - 1); content = substr(rest, j + 1)
    check = content
    gsub(allow, "", check)
    low = tolower(check)
    hit = 0
    for (k = 1; k <= ng && !hit; k++) if (check ~ g[k]) hit = 1
    for (k = 1; k <= nl && !hit; k++) if (low ~ l[k]) hit = 1
    if (hit) print where
  }')

rm -f "$gen" "$loc"
if [ -n "$found" ]; then
  echo "leak-check: possible work-related or personal content (see CLAUDE.md):"
  echo "$found" | sed 's/^/  /'
  exit 1
fi
echo "leak-check: clean"
