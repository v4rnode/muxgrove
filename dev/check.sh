#!/bin/sh
# Static checks plus an isolated tmux smoke test. Changes nothing on your real setup.
# Usage: dev/check.sh
set -e
root="$(cd "$(dirname "$0")/.." && pwd)"
t=$(mktemp -d /tmp/cwchk.XXXX)   # keep this path short: tmux sockets have a length limit
trap 'TMUX_TMPDIR=$t tmux kill-server 2>/dev/null; rm -rf "$t"' EXIT
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }

sh -n "$root/setup.sh" && ok "setup.sh syntax" || bad "setup.sh syntax"
sh "$root/dev/extract.sh" "$t/files"

for f in cw cw-doctor cc-bell.sh status.sh session-picker.sh cc-statusline.sh; do
  if [ -s "$t/files/$f" ]; then sh -n "$t/files/$f" && ok "$f syntax" || bad "$f syntax"; else bad "$f was not extracted"; fi
done
for f in ticket_eof pr_eof pr_comments_eof; do
  if [ "$(head -n 1 "$t/files/$f" 2>/dev/null)" = "---" ] && grep -q "^description:" "$t/files/$f"; then ok "$f has frontmatter"; else bad "$f frontmatter missing"; fi
done
zsh -n "$t/files/zshrc" && ok "zshrc block syntax" || bad "zshrc block syntax"

# tmux config loads without errors (plugins skipped via CW_NO_PLUGINS)
if out=$(TMUX_TMPDIR=$t CW_NO_PLUGINS=1 tmux -f "$t/files/tmux.conf" new-session -d -s chk 'sleep 20' 2>&1) \
   && out=$(TMUX_TMPDIR=$t CW_NO_PLUGINS=1 tmux source-file "$t/files/tmux.conf" 2>&1) && [ -z "$out" ]; then
  ok "tmux.conf loads"
else
  bad "tmux.conf loads: $out"
fi

sh "$root/dev/leak-check.sh" >/dev/null 2>&1 && ok "leak check" || bad "leak check (run dev/leak-check.sh)"

[ "$fail" = 0 ] && echo "All checks passed." || { echo "Some checks failed."; exit 1; }
