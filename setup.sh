#!/bin/sh
# Single-file setup for the tmux + Claude Code workflow.
# Run on a fresh Mac: sh setup.sh   (safe to re-run)
#
# Installs if missing: Homebrew, Oh My Zsh (+ zsh-autosuggestions, zsh-syntax-highlighting,
#   fast-syntax-highlighting), brew packages tmux fzf jq git gh node fnm terminal-notifier rustup (+ stable toolchain, LTS Node),
#   and the iTerm2 and Claude Code CLI casks.
#   Also sets iTerm2's Option keys to Esc+ in every profile
# Writes: a managed block at the end of ~/.zshrc (PATH, fzf, Option+arrow word jumps,
#   claude-<profile> functions; backup in ~/.zshrc.pre-setup), /ticket command in every profile's commands folder, ~/.config/cw/profiles (if missing), ~/.tmux.conf, ~/.config/tmux/cc-bell.sh, ~/.local/bin/cw
# Registers the alert hook in every profile's settings.json (backup kept as settings.json.bak)
# Also installs tmux plugins (tpm, resurrect, continuum), a status bar with alerts + git branch,
#   a session picker with preview, and macOS notifications (CW_NO_NOTIFY=1 silences them)
#
# Keys (prefix = Ctrl+b)
#   prefix r  reload config        prefix | / -  split side by side / stacked
#   prefix c  new window (asks for name), prefix C  new window named after folder
#   prefix ,  rename window        prefix f  fuzzy session switcher
#   prefix w  fuzzy window switcher (all sessions)
#   prefix t  popup shell, prefix Tab  previous session, prefix z  zoom pane
#   prefix H/J/K/L  resize pane, prefix [  scroll/copy (v select, y copy)
#   prefix f  also shows warning/check markers for sessions that need you / are done
#   Alt+h / Alt+l  prev/next window, Alt+j / Alt+k  next/prev session
#   prefix d  detach (tmux attach -t NAME to return)
# Workflow: run `cw <name>` inside a git repo -> pick a profile (arrows + enter) ->
#   new tmux session running `claude -w <name>` with that profile's login.
#   Skip the picker: `cw -p work <name>`. Profiles: ~/.config/cw/profiles
#   Claude makes the worktree at .claude/worktrees/<name>, branch worktree-<name>.
#   On exit Claude asks whether to keep or remove it.
#   Resume a kept one: cw <name> again, or `claude -w <name> --resume`.
#   New account: add `name=~/.claude-name` to ~/.config/cw/profiles and sign in once
#   with `CLAUDE_CONFIG_DIR=~/.claude-name claude`.
#   Copy gitignored files (.env) into worktrees: list them in a .worktreeinclude
#   file in the repo root (.gitignore syntax).
#   Inside Claude, `/ticket PROJ-123` (or a Jira URL, or no argument on a branch named
#   after the ticket) reads the ticket via Atlassian and proposes a plan before any edits.
#   Close a finished session: cw -d [session] (offers to remove its worktree + branch).
#   Reopen a past conversation from this repo: cw -r [-p profile] (pick from a list).
#   Check everything and get fixes for problems: cw doctor.
#   PR flow inside Claude: /pr (review + draft PR, asks before pushing), /pr-comments (review feedback).
#   Sound alerts (no permissions needed): preferences in ~/.config/cw/config (CW_SOUND=0 to mute).
#   Status bar: warning = needs you, check = finished, in other sessions; shows the git branch.
#   After a reboot continuum restores layouts and folders; run `claude --resume` in the pane.
set -e
SETUP_DIR="$(cd "$(dirname "$0")" && pwd)"

# 1a. Homebrew (installed if missing)
load_brew() {
  for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    if [ -x "$b" ]; then eval "$("$b" shellenv)"; return 0; fi
  done
  return 1
}
if ! command -v brew >/dev/null 2>&1; then load_brew || true; fi
if ! command -v brew >/dev/null 2>&1; then
  echo "Installing Homebrew (may ask for your password)..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  load_brew || { echo "Homebrew install failed" >&2; exit 1; }
fi

# 1b. Homebrew packages (only what is missing)
for pkg in tmux fzf jq git gh rustup node fnm terminal-notifier; do
  brew list --formula "$pkg" >/dev/null 2>&1 || brew install "$pkg"
done
# Apps: iTerm2 and the Claude Code CLI (skipped if already present, even if not from brew)
if [ ! -d /Applications/iTerm.app ]; then brew install --cask iterm2; fi
if ! command -v claude >/dev/null 2>&1; then brew install --cask claude-code; fi
# rustup is keg-only: pick a default toolchain once
RUSTUP_BIN="$(brew --prefix rustup)/bin"
"$RUSTUP_BIN/rustup" show active-toolchain >/dev/null 2>&1 || "$RUSTUP_BIN/rustup" default stable
# fnm (Node version manager): install the latest LTS as the default once.
# brew's `node` stays as the fallback for non-interactive shells (hooks, tmux sessions);
# interactive shells get fnm's version, and projects with .nvmrc/.node-version switch automatically.
if [ -z "$(ls "$HOME/.local/share/fnm/node-versions" 2>/dev/null)" ]; then
  fnm install --lts
  fnm default "$(fnm list | grep -o 'v[0-9][0-9.]*' | head -1)"
fi

# 1c. Oh My Zsh (installed if missing; keeps an existing ~/.zshrc, no shell switch)
if [ ! -d "$HOME/.oh-my-zsh" ]; then
  echo "Installing Oh My Zsh..."
  RUNZSH=no CHSH=no KEEP_ZSHRC=yes \
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
fi

# 1d. Zsh plugins
ZC="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
clone_plugin() { [ -d "$ZC/plugins/$1" ] || git clone --depth 1 "$2" "$ZC/plugins/$1"; }
clone_plugin zsh-autosuggestions        https://github.com/zsh-users/zsh-autosuggestions
clone_plugin zsh-syntax-highlighting    https://github.com/zsh-users/zsh-syntax-highlighting
clone_plugin fast-syntax-highlighting   https://github.com/zdharma-continuum/fast-syntax-highlighting
# A fresh Oh My Zsh ships `plugins=(git)`; swap in ours. Customised lines are left alone.
if [ -f ~/.zshrc ]; then
  sed -i '' 's/^plugins=(git)$/plugins=(git zsh-autosuggestions zsh-syntax-highlighting fast-syntax-highlighting)/' ~/.zshrc
fi

# 1e. iTerm2: both Option keys send Esc+ (needed for Option+arrow word jumps and tmux Alt keys)
ITERM_PLIST="${ITERM_PLIST:-$HOME/Library/Preferences/com.googlecode.iterm2.plist}"
if [ -f "$ITERM_PLIST" ]; then
  PB=/usr/libexec/PlistBuddy
  iterm_changed=0
  n=$("$PB" -c 'Print :"New Bookmarks"' "$ITERM_PLIST" 2>/dev/null | grep -c '^    Dict' || true)
  i=0
  while [ "$i" -lt "$n" ]; do
    for k in "Option Key Sends" "Right Option Key Sends"; do
      cur=$("$PB" -c "Print :'New Bookmarks':$i:'$k'" "$ITERM_PLIST" 2>/dev/null || true)
      if [ "$cur" != "2" ]; then
        "$PB" -c "Set :'New Bookmarks':$i:'$k' 2" "$ITERM_PLIST" 2>/dev/null \
          || "$PB" -c "Add :'New Bookmarks':$i:'$k' integer 2" "$ITERM_PLIST"
        iterm_changed=1
      fi
    done
    i=$((i + 1))
  done
  if [ "$iterm_changed" = 1 ]; then
    echo "iTerm2: Option keys set to Esc+. Quit iTerm2 completely (Cmd+Q) and reopen it to apply."
  fi
else
  echo "iTerm2 has no preferences yet. Open iTerm2 once, then re-run setup.sh to set the Option keys."
fi

mkdir -p ~/.config/tmux ~/.local/bin

# 2. tmux config
rm -f ~/.tmux.conf
cat > ~/.tmux.conf <<'TMUX_CONF_EOF'
# Basics
set -g mouse on
set -g base-index 1
setw -g pane-base-index 1
set -g renumber-windows on
set -g history-limit 50000
set -g escape-time 10
set -g default-terminal "tmux-256color"
set -g set-clipboard on
set -g allow-passthrough on

# Reload config
bind r source-file ~/.tmux.conf \; display "Reloaded"

# Splits keep current directory
bind | split-window -h -c "#{pane_current_path}"
bind - split-window -v -c "#{pane_current_path}"
# New window: prompts for a name (c). Empty name falls back to the folder name (C skips the prompt)
set -g automatic-rename on
set -g automatic-rename-format "#{b:pane_current_path}"
bind c command-prompt -p "Window name:" "new-window -n '%%' -c '#{pane_current_path}'"
bind C new-window -c "#{pane_current_path}"

# Fuzzy session switcher with live preview and alert markers: prefix + f
bind f display-popup -E -w 85% -h 70% "~/.config/tmux/session-picker.sh '#{client_name}'"

# Fuzzy window switcher across all sessions: prefix + w
bind w display-popup -E -w 70% -h 60% \
  "tmux list-windows -a -F '#{session_name}:#{window_index} #{window_name}' | fzf --reverse --prompt='window> ' | cut -d' ' -f1 | xargs -I{} tmux switch-client -t '{}'"

# Quick tools: prefix + t = popup shell in the current folder, prefix + Tab = previous session,
# prefix + z = zoom pane (built in), prefix + H/J/K/L = resize pane
bind t display-popup -E -d "#{pane_current_path}" -w 80% -h 80%
bind Tab switch-client -l
bind -r H resize-pane -L 5
bind -r J resize-pane -D 5
bind -r K resize-pane -U 5
bind -r L resize-pane -R 5

# Copy mode: prefix + [ to scroll, v to select, y to copy to the macOS clipboard
setw -g mode-keys vi
bind -T copy-mode-vi v send -X begin-selection
bind -T copy-mode-vi y send -X copy-pipe-and-cancel "pbcopy"
bind -T copy-mode-vi MouseDragEnd1Pane send -X copy-pipe-and-cancel "pbcopy"

# Alt shortcuts (no prefix): Alt+h/l windows, Alt+j/k sessions
bind -n M-h previous-window
bind -n M-l next-window
bind -n M-j switch-client -n
bind -n M-k switch-client -p

# Alert when Claude needs you (bell from hooks)
set -g monitor-bell on
set -g bell-action other
set -g visual-bell off

# Clear a session's alert (see ~/.config/tmux/cc-bell.sh) when you switch to it
set-hook -g client-session-changed 'run-shell -b "rm -f ~/.cache/cw/alerts/#{q:session_name}; terminal-notifier -remove cw-#{q:session_name} >/dev/null 2>&1; true"'
set-hook -g client-attached        'run-shell -b "rm -f ~/.cache/cw/alerts/#{q:session_name}; terminal-notifier -remove cw-#{q:session_name} >/dev/null 2>&1; true"'

# Status bar
set -g status-position bottom
set -g status-style "bg=colour236,fg=colour250"
set -g status-left-length 80
set -g status-left "#[bg=colour39,fg=colour16,bold] #S #[default]#[fg=colour245] #{@account}#{?@rc,#[fg=colour39] RC#[fg=colour245],} "
set -g status-interval 2
set -g status-right-length 140
set -g status-right "#(~/.config/tmux/status.sh '#{session_name}' '#{pane_current_path}' '#{@cfgdir}')#[fg=colour245]%H:%M "
setw -g window-status-separator ""
setw -g window-status-format "#[fg=colour245] #I:#W "
setw -g window-status-current-format "#[bg=colour208,fg=colour16,bold] #I:#W "
setw -g window-status-bell-style "bg=colour196,fg=colour231,bold"

# Persistence across reboots: tmux-resurrect + continuum via TPM (layouts and folders come back;
# Claude itself is not restarted, run `claude --resume` in the pane). Keep this block LAST.
# Skipped when CW_NO_PLUGINS is set (used for isolated test servers).
set -g @plugin 'tmux-plugins/tpm'
set -g @plugin 'tmux-plugins/tmux-resurrect'
set -g @plugin 'tmux-plugins/tmux-continuum'
set -g @continuum-restore 'on'
set -g @continuum-save-interval '10'
set -g @resurrect-capture-pane-contents 'on'
if-shell '[ -z "$CW_NO_PLUGINS" ] && [ -x ~/.tmux/plugins/tpm/tpm ]' "run '~/.tmux/plugins/tpm/tpm'"
TMUX_CONF_EOF

# 2b. tmux plugins (TPM, resurrect, continuum), cloned if missing
mkdir -p ~/.tmux/plugins
for repo in tpm tmux-resurrect tmux-continuum; do
  [ -d ~/.tmux/plugins/$repo ] || git clone --depth 1 "https://github.com/tmux-plugins/$repo" ~/.tmux/plugins/$repo
done

# 3. Claude alert hook, status bar helper and session picker
rm -f ~/.config/tmux/cc-bell.sh ~/.config/tmux/status.sh ~/.config/tmux/session-picker.sh ~/.config/tmux/cc-statusline.sh
cat > ~/.config/tmux/cc-bell.sh <<'CC_BELL_EOF'
#!/bin/sh
# Claude Code hook (Stop, Notification, PermissionRequest, UserPromptSubmit, SessionEnd).
# - Flags this tmux session in ~/.cache/cw/alerts (done = checkmark, input = warning)
#   so the status bar of OTHER sessions shows it.
# - Rings the pane bell so tmux marks the window red (only while iTerm2 is in front).
# - Sends a macOS notification when iTerm2 is not the frontmost app. Clicking it focuses iTerm2
#   and switches tmux to this session (needs terminal-notifier; falls back to osascript).
# - Plays a short system sound (no permissions needed) in the same situation.
# Preferences go in ~/.config/cw/config (plain shell, all optional):
#   CW_SOUND=0                 turn the sound off
#   CW_SOUND_DONE=Glass        sound when Claude finishes  (any file name in /System/Library/Sounds)
#   CW_SOUND_INPUT=Funk        sound when Claude needs you
#   CW_NO_NOTIFY=1             turn macOS notifications off
[ -n "$TMUX_PANE" ] || exit 0
[ -f "$HOME/.config/cw/config" ] && . "$HOME/.config/cw/config"
input=$(cat)
ev=$(printf '%s' "$input" | jq -r '.hook_event_name // empty' 2>/dev/null)
sess=$(tmux display-message -p -t "$TMUX_PANE" '#{session_name}' 2>/dev/null) || exit 0
dir="$HOME/.cache/cw/alerts"
mkdir -p "$dir"

case "$ev" in
  UserPromptSubmit|SessionStart|SessionEnd) rm -f "$dir/$sess"; exit 0 ;;
  Stop) kind=done; msg="Finished, ready for you" ;;
  Notification|PermissionRequest) kind=input; msg="Needs your input" ;;
  *) exit 0 ;;
esac

# Only flag the session if nobody is looking at it right now
if ! tmux list-clients -F '#{client_session}' 2>/dev/null | grep -qx "$sess"; then
  echo "$kind" > "$dir/$sess"
fi

front=$(lsappinfo info -only name "$(lsappinfo front 2>/dev/null)" 2>/dev/null | sed -n '1s/^"\([^"]*\)".*/\1/p')

# Ring the pane bell so tmux marks the window red, but only while iTerm2 is in front: with iTerm2 in
# the background it would turn the bell into a second notification of its own.
if [ "$front" = "iTerm2" ]; then
  tty=$(tmux display-message -p -t "$TMUX_PANE" '#{pane_tty}' 2>/dev/null)
  [ -n "$tty" ] && printf '\a' > "$tty"
fi

if [ "$front" != "iTerm2" ]; then
  if [ "${CW_SOUND:-1}" != 0 ] && command -v afplay >/dev/null 2>&1; then
    case "$kind" in
      done) snd="${CW_SOUND_DONE:-Glass}" ;;
      *)    snd="${CW_SOUND_INPUT:-Funk}" ;;
    esac
    [ -f "/System/Library/Sounds/$snd.aiff" ] && afplay "/System/Library/Sounds/$snd.aiff" >/dev/null 2>&1 &
  fi
  if [ -z "$CW_NO_NOTIFY" ]; then
    safe=$(printf '%s' "$sess" | tr -d '"\\')
    if command -v terminal-notifier >/dev/null 2>&1; then
      # Clicking the notification focuses iTerm2 and switches the most recently active tmux
      # client to this session.
      q() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }
      client=$(tmux list-clients -F '#{client_activity} #{client_name}' 2>/dev/null | sort -rn | head -n 1 | cut -d' ' -f2-)
      sock=$(tmux display-message -p '#{socket_path}' 2>/dev/null)
      go=""
      if [ -n "$client" ] && [ -n "$sock" ]; then
        go="$(q "$(command -v tmux)") -S $(q "$sock") switch-client -c $(q "$client") -t $(q "=$sess")"
      fi
      # If macOS has not allowed terminal-notifier yet, fall back to a plain (non-clickable) one
      { terminal-notifier -title "Claude Code" -subtitle "$safe" -message "$msg" \
          -group "cw-$safe" -activate com.googlecode.iterm2 ${go:+-execute "$go"} \
        || osascript -e "display notification \"$msg\" with title \"Claude Code\" subtitle \"$safe\""
      } >/dev/null 2>&1 &
    else
      osascript -e "display notification \"$msg\" with title \"Claude Code\" subtitle \"$safe\"" >/dev/null 2>&1 &
    fi
  fi
fi
exit 0
CC_BELL_EOF
cat > ~/.config/tmux/status.sh <<'STATUS_EOF'
#!/bin/sh
# tmux status-right helper. Usage: status.sh <current_session> <pane_path> <profile_config_dir>
# Shows other sessions that are done/need you, the profile's usage, then the git branch of the pane.
cur="$1"; path="$2"; cfg="$3"
dir="$HOME/.cache/cw/alerts"
out=""
if [ -d "$dir" ]; then
  for f in "$dir"/*; do
    [ -f "$f" ] || continue
    n=$(basename "$f")
    [ "$n" = "$cur" ] && continue
    tmux has-session -t "=$n" 2>/dev/null || { rm -f "$f"; continue; }
    label=$(printf '%s' "$n" | sed 's/#/##/g')
    case "$(cat "$f")" in
      input) out="$out#[fg=colour16,bg=colour196,bold] ⚠ $label #[default] " ;;
      *)     out="$out#[fg=colour16,bg=colour34,bold] ✔ $label #[default] " ;;
    esac
  done
fi
# Usage numbers written by cc-statusline.sh; a number whose window has already reset is shown as -
u="$HOME/.cache/cw/usage/$(printf '%s' "${cfg:-default}" | tr -c 'A-Za-z0-9._-' '_')"
if [ -f "$u" ] && IFS='|' read -r p5 r5 pw rw < "$u"; then
  now=$(date +%s)
  seg() {
    [ -n "$2" ] || return 0
    if [ -n "$3" ] && [ "$now" -ge "$3" ]; then out="$out#[fg=colour245]$1 - "; return 0; fi
    if [ "$2" -ge 80 ]; then c=196; elif [ "$2" -ge 50 ]; then c=178; else c=34; fi
    out="$out#[fg=colour$c]$1 $2%#[default] "
  }
  seg 5h "$p5" "$r5"
  seg wk "$pw" "$rw"
fi
if [ -n "$path" ] && b=$(git -C "$path" symbolic-ref --short -q HEAD 2>/dev/null || git -C "$path" rev-parse --short HEAD 2>/dev/null); then
  d=""
  [ -n "$(git -C "$path" status --porcelain -uno 2>/dev/null | head -n 1)" ] && d="*"
  b=$(printf '%s' "$b" | sed 's/#/##/g')
  out="$out#[fg=colour245] $b$d #[default]"
fi
printf '%s' "$out"
STATUS_EOF
cat > ~/.config/tmux/cc-statusline.sh <<'STATUSLINE_EOF'
#!/bin/sh
# Claude Code status line: model, then 5-hour and weekly usage with reset times.
# Also caches the numbers per profile (~/.cache/cw/usage/<key>) for the tmux status bar.
# The rate_limits shape is Claude's own, not a public API, so every field is optional.
input=$(cat)
row=$(printf '%s' "$input" | jq -r '
  def ts: if type == "number" then . elif type == "string" then (sub("\\.[0-9]+"; "") | try fromdateiso8601 catch null) else null end;
  def pct(w): (.rate_limits[w].used_percentage | if type == "number" then round else "" end);
  def rst(w): ((.rate_limits[w].resets_at | ts) // "");
  [(.model.display_name // ""), pct("five_hour"), rst("five_hour"), pct("seven_day"), rst("seven_day")]
  | map(tostring) | join("|")' 2>/dev/null)
IFS='|' read -r model p5 r5 pw rw <<EOF
$row
EOF
color() { if [ "$1" -ge 80 ]; then printf '\033[31m'; elif [ "$1" -ge 50 ]; then printf '\033[33m'; else printf '\033[32m'; fi; }
# seg <label> <pct> <reset epoch> <date format>
seg() {
  [ -n "$2" ] || return 0
  out="$out · $(color "$2")$1 $2%$(printf '\033[0m')"
  [ -n "$3" ] && out="$out (resets $(date -r "$3" "+$4" 2>/dev/null))"
}
out="${model:-Claude}"
seg 5h "$p5" "$r5" %H:%M
seg week "$pw" "$rw" %a
printf '%s\n' "$out"
if [ -n "$p5$pw" ]; then
  key=$(printf '%s' "${CLAUDE_CONFIG_DIR:-default}" | tr -c 'A-Za-z0-9._-' '_')
  mkdir -p "$HOME/.cache/cw/usage"
  f="$HOME/.cache/cw/usage/$key"
  # Several sessions of one profile write here, so replace the file atomically
  printf '%s|%s|%s|%s\n' "$p5" "$r5" "$pw" "$rw" > "$f.$$" && mv "$f.$$" "$f"
fi
STATUSLINE_EOF
cat > ~/.config/tmux/session-picker.sh <<'PICKER_EOF'
#!/bin/sh
# Fuzzy session picker with live preview. Usage: session-picker.sh <client_name>
# Sessions that need you (warning) sort first, then finished ones (checkmark).
client="$1"
dir="$HOME/.cache/cw/alerts"
tab=$(printf '\t')
sel=$(tmux list-sessions -F '#{session_name}|#{@account}' | while IFS='|' read -r n acct; do
    case "$(cat "$dir/$n" 2>/dev/null)" in
      (input) key=0; m="⚠" ;;
      (done)  key=1; m="✔" ;;
      (*)     key=2; m=" " ;;
    esac
    printf '%s\t%s\t%s %s\t%s\n' "$key" "$n" "$m" "$n" "$acct"
  done | sort -s -t "$tab" -k1,1 \
       | fzf --delimiter "$tab" --with-nth 3,4 --reverse --prompt='session> ' \
             --preview 'tmux capture-pane -p -t "={2}:" | grep -v "^[[:space:]]*$" | tail -40' \
             --preview-window 'right,60%,border-left' \
       | cut -f2)
[ -n "$sel" ] && tmux switch-client -c "$client" -t "=$sel"
exit 0
PICKER_EOF
chmod +x ~/.config/tmux/cc-bell.sh ~/.config/tmux/status.sh ~/.config/tmux/session-picker.sh ~/.config/tmux/cc-statusline.sh

# 4. cw helper (new tmux session running claude in its own git worktree)
rm -f ~/.local/bin/cw
cat > ~/.local/bin/cw <<'CW_EOF'
#!/bin/sh
# cw [-p <profile>] <name>      start a session
# cw -d [session]                close a session and offer to remove its worktree
# cw -r [-p <profile>]           reopen a past Claude conversation from this repo
# cw doctor                      check the whole setup and say how to fix problems
# cw --no-rc <name>              start without Remote Control (it is on by default; -R forces it on
#                                when CW_REMOTE_CONTROL=0 in ~/.config/cw/config turned it off)
# Start Claude in an isolated git worktree (claude -w <name>) inside its own
# tmux session. Run from inside a git repo.
#   cw login-fix             pick a profile with up/down + enter
#   cw -p work login-fix      skip the picker
# Profiles live in ~/.config/cw/profiles, one `name=config_dir` per line
# (empty config_dir = Claude's default login). If the session already exists,
# cw just switches to it.
PROFILES="${CW_PROFILES:-$HOME/.config/cw/profiles}"
usage() { echo "usage: cw [--no-rc] [-p <profile>] <name> | cw [--no-rc] -r [-p <profile>] | cw -d [session] | cw doctor"; exit 1; }
[ -f "$HOME/.config/cw/config" ] && . "$HOME/.config/cw/config"
remote=1; [ "${CW_REMOTE_CONTROL:-1}" = 0 ] && remote=

[ "$1" = doctor ] && [ $# -eq 1 ] && exec "$(dirname "$0")/cw-doctor"

# cw -d [session]: remove a finished session, and offer to remove its worktree + branch
if [ "$1" = "-d" ]; then
  target="$2"
  if [ -z "$target" ]; then
    target=$(tmux list-sessions -F '#{session_name}' | fzf --reverse --prompt='remove session> ') || exit 1
  fi
  tmux has-session -t "=$target" 2>/dev/null || { echo "cw: no session '$target'"; exit 1; }
  if [ -n "$TMUX" ] && [ "$(tmux display-message -p '#{session_name}')" = "$target" ]; then
    echo "cw: you are inside '$target'. Switch to another session (Alt+j) and run cw -d again."
    exit 1
  fi
  path=$(tmux display-message -p -t "=$target:" '#{session_path}')
  prof=$(tmux show-options -qv -t "=$target:" @profile)
  base="$target"
  [ -n "$prof" ] && [ "$prof" != default ] && base="${target%-$prof}"
  wt=""
  [ -d "$path" ] && wt=$(git -C "$path" worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p' | grep "/\.claude/worktrees/$base\$" | head -1)
  tmux kill-session -t "=$target"
  rm -f "$HOME/.cache/cw/alerts/$target"
  echo "Session '$target' closed."
  if [ -n "$wt" ]; then
    echo "Worktree: $wt"
    git -C "$wt" status --short | head -5
    printf "Remove this worktree and its branch 'worktree-%s'? [y/N] " "$base"
    read -r a
    if [ "$a" = y ]; then
      git -C "$path" worktree remove "$wt" \
        && { git -C "$path" branch -d "worktree-$base" || echo "Branch kept (not merged). Delete with: git branch -D worktree-$base"; } \
        || echo "Worktree not removed (uncommitted changes?). Force with: git worktree remove --force $wt"
    fi
  fi
  exit 0
fi
[ -f "$PROFILES" ] || { echo "cw: no profiles file at $PROFILES"; exit 1; }
names=$(grep -v '^[[:space:]]*\(#\|$\)' "$PROFILES" | cut -d= -f1)

profile=; resume=
while [ $# -gt 0 ]; do
  case "$1" in
    -p) [ -n "$2" ] || usage; profile="$2"; shift 2 ;;
    -r) resume=1; shift ;;
    -R) remote=1; shift ;;
    --no-rc) remote=; shift ;;
    *) break ;;
  esac
done
[ -n "$resume" ] || [ -n "$1" ] || usage
git rev-parse --show-toplevel >/dev/null 2>&1 || { echo "cw: not in a git repo"; exit 1; }
name="${1:-resume}"

# Signed-in email for a profile (read from its .claude.json)
profile_dir() {
  d=$(grep "^$1=" "$PROFILES" | head -1 | cut -d= -f2-)
  printf '%s' "$d" | sed "s#^~#$HOME#"
}
profile_email() {
  d=$(profile_dir "$1")
  f="${d:-$HOME}/.claude.json"
  e=$(jq -r '.oauthAccount.emailAddress // empty' "$f" 2>/dev/null)
  echo "${e:-not signed in}"
}

if [ -z "$profile" ]; then
  if [ "$(echo "$names" | wc -l)" -eq 1 ]; then
    profile="$names"
  else
    profile=$(echo "$names" | while read -r p; do
        printf '%-12s %s\n' "$p" "$(profile_email "$p")"
      done | fzf --reverse --height=~10 --prompt="profile for '$name'> " | awk '{print $1}') || exit 1
    [ -n "$profile" ] || exit 1
  fi
fi
echo "$names" | grep -qx "$profile" || { echo "cw: unknown profile '$profile'. Have: $(echo $names)"; exit 1; }

dir=$(profile_dir "$profile")

# Has this profile accepted Claude's trust dialog for $PWD or a parent folder?
# (`claude -w` refuses to run in an untrusted folder.)
is_trusted() {
  f="${1:-$HOME}/.claude.json"
  p="$PWD"
  while :; do
    t=$(jq -r --arg p "$p" '.projects[$p].hasTrustDialogAccepted // false' "$f" 2>/dev/null)
    [ "$t" = true ] && return 0
    [ "$p" = / ] && return 1
    p=$(dirname "$p")
  done
}

# cw -r: reopen a past Claude conversation from this repo (its main checkout or any worktree).
# Reads the profile's session files (~/.claude/projects/*/<id>.jsonl) and resumes the chosen one
# in the folder it ran in, as its own tmux session.
resume_flow() {
  gc=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
  root=${gc%/.git}
  # Claude may have recorded the folder by a symlinked path (for example /tmp vs /private/tmp),
  # so also match the path as typed in this shell, minus any worktree suffix.
  root2=${PWD%%/.claude/worktrees/*}
  projects="${dir:-$HOME/.claude}/projects"
  [ -d "$projects" ] || { echo "cw: no past sessions for profile '$profile'"; exit 1; }
  tab=$(printf '\t'); now=$(date +%s); tmp=$(mktemp)
  ls -t "$projects"/*/*.jsonl 2>/dev/null | head -n 300 > "$tmp.files"
  while IFS= read -r f; do
    # -R/-s then fromjson?: tolerate any malformed line instead of dropping the whole session
    row=$(head -n 80 "$f" | jq -rRs --arg root "$root" --arg root2 "$root2" '
      (split("\n") | map(fromjson?)) as $all
      | ([$all[] | select(.cwd != null)][0]) as $c
      | ([$all[] | select(.type == "user" and (.isSidechain | not))
          | (.message.content | if type == "string" then . else ([.[]? | select(.type == "text") | .text][0] // "") end)
          | select(startswith("<") | not) | select(length > 0)][0] // "") as $p
      | if $c == null then empty
        elif ([$root, $root2] | any(. as $r | $c.cwd == $r or ($c.cwd | startswith($r + "/"))))
        then [$c.sessionId, $c.cwd, ($p | gsub("[\\s]+"; " ") | .[0:90])] | @tsv
        else empty end' 2>/dev/null) || continue
    [ -n "$row" ] || continue
    sid=$(printf '%s' "$row" | cut -f1); cwd=$(printf '%s' "$row" | cut -f2); first=$(printf '%s' "$row" | cut -f3)
    [ -d "$cwd" ] || continue
    d=$((now - $(stat -f %m "$f")))
    if [ "$d" -lt 3600 ]; then age="$((d / 60))m"; elif [ "$d" -lt 86400 ]; then age="$((d / 3600))h"; else age="$((d / 86400))d"; fi
    where=$(basename "$cwd"); [ "$cwd" = "$root" ] || [ "$cwd" = "$root2" ] && where="(main)"
    printf '%s\t%s\t%-4s %-24s %s\n' "$sid" "$cwd" "$age" "$where" "$first"
  done < "$tmp.files" > "$tmp"
  rm -f "$tmp.files"
  if [ ! -s "$tmp" ]; then echo "cw: no past sessions for this repo under profile '$profile'"; rm -f "$tmp"; exit 1; fi
  pick=$(fzf --delimiter "$tab" --with-nth 3 --reverse --prompt="resume ($profile)> " < "$tmp") || { rm -f "$tmp"; exit 1; }
  rm -f "$tmp"
  sid=$(printf '%s' "$pick" | cut -f1); cwd=$(printf '%s' "$pick" | cut -f2)
  where=$(basename "$cwd")
  sess=$(printf '%s' "$where" | tr './: ' '----')
  [ "$profile" = "default" ] || sess="$sess-$(printf '%s' "$profile" | tr './: ' '----')"
  if ! tmux has-session -t "=$sess" 2>/dev/null; then
    RWRAP='
if [ -n "$2" ]; then claude --resume "$1" --remote-control "$2"; else claude --resume "$1"; fi
rc=$?
if [ "$rc" -ne 0 ]; then
  echo
  echo "claude exited with status $rc. Press Enter to close this session."
  read -r _
fi
exit "$rc"'
    set -- sh -c "$RWRAP" _ "$sid" "${remote:+$sess}"
    if [ -n "$dir" ]; then
      tmux new-session -d -s "$sess" -n "$profile" -c "$cwd" -e "CLAUDE_CONFIG_DIR=$dir" "$@"
    else
      tmux new-session -d -s "$sess" -n "$profile" -c "$cwd" "$@"
    fi
    tmux set-option -t "=$sess:" @account "$profile: $(profile_email "$profile")"
    tmux set-option -t "=$sess:" @profile "$profile"
    tmux set-option -t "=$sess:" @cfgdir "$dir"
    [ -n "$remote" ] && tmux set-option -t "=$sess:" @rc 1
    rm -f "$HOME/.cache/cw/alerts/$sess"
  fi
  if [ -n "$TMUX" ]; then tmux switch-client -t "=$sess"; else tmux attach -t "=$sess"; fi
  exit 0
}
[ -n "$resume" ] && resume_flow

sess=$(printf '%s' "$name" | tr './: ' '----')
[ "$profile" = "default" ] || sess="$sess-$(printf '%s' "$profile" | tr './: ' '----')"

if ! tmux has-session -t "=$sess" 2>/dev/null; then
  trusted=yes
  is_trusted "$dir" || trusted=no
  # Runs inside the new session. Untrusted folder: let Claude show its trust dialog
  # first. A failing Claude keeps the pane open so the error stays readable.
  WRAP='
if [ "$2" = no ]; then
  echo "This folder is not trusted by this Claude profile yet."
  echo "Press Enter: Claude opens, accept the trust dialog, then type /exit."
  echo "The worktree session starts right after."
  read -r _
  claude
  clear
fi
if [ -n "$3" ]; then claude -w "$1" --remote-control "$3"; else claude -w "$1"; fi
rc=$?
if [ "$rc" -ne 0 ]; then
  echo
  echo "claude exited with status $rc. Press Enter to close this session."
  read -r _
fi
exit "$rc"'
  set -- sh -c "$WRAP" _ "$name" "$trusted" "${remote:+$sess}"
  if [ -n "$dir" ]; then
    tmux new-session -d -s "$sess" -n "$profile" -c "$PWD" -e "CLAUDE_CONFIG_DIR=$dir" "$@"
  else
    tmux new-session -d -s "$sess" -n "$profile" -c "$PWD" "$@"
  fi
  # Shown in the tmux status bar (see status-left in ~/.tmux.conf)
  tmux set-option -t "=$sess:" @account "$profile: $(profile_email "$profile")"
  tmux set-option -t "=$sess:" @profile "$profile"
  tmux set-option -t "=$sess:" @cfgdir "$dir"
  [ -n "$remote" ] && tmux set-option -t "=$sess:" @rc 1
  rm -f "$HOME/.cache/cw/alerts/$sess"
fi

if [ -n "$TMUX" ]; then tmux switch-client -t "=$sess"; else tmux attach -t "=$sess"; fi
CW_EOF
chmod +x ~/.local/bin/cw

rm -f ~/.local/bin/cw-doctor
cat > ~/.local/bin/cw-doctor <<'CW_DOCTOR_EOF'
#!/bin/sh
# cw doctor: check the whole setup and say how to fix what is wrong.
# Exit status 1 if anything FAILs (warnings do not fail).
PROFILES="${CW_PROFILES:-$HOME/.config/cw/profiles}"
SETUP="re-run setup.sh from your muxgrove checkout"
fails=0; warns=0
# Colors only on a terminal; NO_COLOR turns them off, CW_COLOR=always forces them (for testing).
if [ "$CW_COLOR" = always ] || { [ -t 1 ] && [ -z "$NO_COLOR" ]; }; then
  G=$(printf '\033[32m'); Y=$(printf '\033[33m'); R=$(printf '\033[31m')
  D=$(printf '\033[2m'); B=$(printf '\033[1m'); Z=$(printf '\033[0m')
else
  G=; Y=; R=; D=; B=; Z=
fi
ok()      { printf '  %s%-9s%s %s\n' "$G" healthy "$Z" "$1"; }
warn()    { printf '  %s%-9s%s %s\n        fix: %s\n' "$Y" warning "$Z" "$1" "$2"; warns=$((warns + 1)); }
bad()     { printf '  %s%-9s%s %s\n        fix: %s\n' "$R" unhealthy "$Z" "$1" "$2"; fails=$((fails + 1)); }
note()    { printf '  %s%-9s%s %s\n' "$D" note "$Z" "$1"; }
section() { printf '\n%s%s%s\n' "$B" "$1" "$Z"; }
# One stable color per profile (by its position in the profiles file). None of them are
# green, yellow or red, so a profile color is never mistaken for a status.
pcolor() {
  [ -n "$B" ] || return 0
  case $(($1 % 6)) in
    0) c='36' ;; 1) c='35' ;; 2) c='38;5;208' ;; 3) c='94' ;; 4) c='38;5;205' ;; *) c='38;5;37' ;;
  esac
  printf '\033[1;%sm' "$c"
}

section "Tools"
for t in brew tmux fzf jq git fnm claude; do
  if command -v "$t" >/dev/null 2>&1; then ok "$t"; else bad "$t not found" "$SETUP"; fi
done
# Hooks run in a plain /bin/sh without your zshrc, so node must be on the system PATH
if /bin/sh -c 'command -v node' >/dev/null 2>&1; then ok "node (visible to Claude hooks)"
else bad "node is not visible to hooks (project hooks that call node fail)" "$SETUP (installs node via Homebrew)"; fi
if command -v gh >/dev/null 2>&1; then
  if gh auth status >/dev/null 2>&1; then ok "gh (logged in)"; else warn "gh is not logged in (/pr needs it)" "gh auth login"; fi
else warn "gh not found (/pr needs it)" "$SETUP"; fi

section "Shell"
case ":$PATH:" in *":$HOME/.local/bin:"*) ok "~/.local/bin is on PATH" ;; *) bad "~/.local/bin is not on PATH (cw not found)" "open a new terminal tab; if it persists, $SETUP" ;; esac
n=$(grep -c '^# >>> setup.sh managed block' "$HOME/.zshrc" 2>/dev/null)
if [ "${n:-0}" = 1 ]; then ok "managed block in ~/.zshrc"
elif [ "${n:-0}" = 0 ]; then bad "managed block missing from ~/.zshrc" "$SETUP"
else bad "managed block appears $n times in ~/.zshrc" "delete the duplicates, then $SETUP"; fi
[ -d "$HOME/.oh-my-zsh" ] && ok "Oh My Zsh" || warn "Oh My Zsh not installed" "$SETUP"

section "tmux"
[ -f "$HOME/.tmux.conf" ] && ok "~/.tmux.conf" || bad "~/.tmux.conf missing" "$SETUP"
for f in cc-bell.sh status.sh session-picker.sh cc-statusline.sh; do
  if [ -x "$HOME/.config/tmux/$f" ]; then ok "$f"; else bad "~/.config/tmux/$f missing or not executable" "$SETUP"; fi
done
for p in tpm tmux-resurrect tmux-continuum; do
  [ -d "$HOME/.tmux/plugins/$p" ] && ok "plugin $p" || warn "plugin $p not installed" "$SETUP"
done
if tmux info >/dev/null 2>&1; then
  tmux show -gv status-right 2>/dev/null | grep -q 'status.sh' && ok "running tmux has the status bar" || warn "running tmux has an old config" "press prefix + r to reload"
  tmux show-hooks -g 2>/dev/null | grep -q 'client-session-changed' && ok "running tmux clears alerts on switch" || warn "running tmux lacks the alert-clearing hook" "press prefix + r to reload"
else
  ok "tmux server not running (config is read on next start)"
fi

section "Claude profiles"
if [ ! -f "$PROFILES" ]; then
  bad "no profiles file at $PROFILES" "$SETUP"
else
  list=$(mktemp)
  grep -v '^[[:space:]]*\(#\|$\)' "$PROFILES" > "$list"
  idx=0
  while IFS= read -r line; do
    pc=$(pcolor "$idx"); idx=$((idx + 1))
    name=${line%%=*}; dir=${line#*=}
    dir=$(printf '%s' "$dir" | sed "s#^~#$HOME#"); cfg="${dir:-$HOME/.claude}"
    printf '\n  %s\342\226\240 %s%s  %s%s%s\n' "$pc" "$name" "$Z" "$D" "$cfg" "$Z"
    if [ ! -d "$cfg" ]; then bad "folder missing" "CLAUDE_CONFIG_DIR=$cfg claude   (sign in once)"; continue; fi
    cj="${dir:-$HOME}/.claude.json"
    email=$(jq -r '.oauthAccount.emailAddress // empty' "$cj" 2>/dev/null)
    if [ -n "$email" ]; then ok "signed in as ${pc}${email}${Z}"; else warn "not signed in" "CLAUDE_CONFIG_DIR=$cfg claude   (sign in once)"; fi
    missing=""
    for e in Notification PermissionRequest Stop UserPromptSubmit SessionEnd; do
      jq -e --arg e "$e" --arg c "$HOME/.config/tmux/cc-bell.sh" '[.hooks[$e][]?.hooks[]?.command] | index($c)' "$cfg/settings.json" >/dev/null 2>&1 || missing="$missing $e"
    done
    if [ -z "$missing" ]; then ok "alert hook registered for all 5 events"; else bad "alert hook missing for:$missing" "$SETUP"; fi
    sl=$(jq -r '.statusLine.command // empty' "$cfg/settings.json" 2>/dev/null)
    if [ "$sl" = "$HOME/.config/tmux/cc-statusline.sh" ]; then ok "usage status line installed"
    elif [ -n "$sl" ]; then note "this profile has its own status line, so usage shows in Claude only if it does (and in tmux not at all)"
    else warn "usage status line not installed" "$SETUP"; fi
    if grep -q 'cc-status' "$cfg/settings.json" 2>/dev/null; then
      note "iTerm2's own Claude Code integration is installed here and posts its own notification."
      echo "            To keep only muxgrove's: iTerm2 menu > Uninstall Claude Code Integration."
    fi
    miss=""; for c in ticket pr pr-comments; do [ -f "$cfg/commands/$c.md" ] || miss="$miss /$c"; done
    if [ -z "$miss" ]; then ok "slash commands /ticket /pr /pr-comments"; else bad "slash commands missing:$miss" "$SETUP"; fi
    if git rev-parse --show-toplevel >/dev/null 2>&1; then
      p="$PWD"; trusted=no
      while :; do
        [ "$(jq -r --arg p "$p" '.projects[$p].hasTrustDialogAccepted // false' "$cj" 2>/dev/null)" = true ] && { trusted=yes; break; }
        [ "$p" = / ] && break; p=$(dirname "$p")
      done
      if [ "$trusted" = yes ]; then ok "this folder is trusted"; else warn "this folder is not trusted yet (cw will walk you through it)" "just run cw here"; fi
    fi
  done < "$list"
  rm -f "$list"
fi

section "Alerts"
if [ -f "$HOME/.config/cw/config" ]; then ok "preferences file ~/.config/cw/config"; else ok "no ~/.config/cw/config (defaults: sound on)"; fi
command -v afplay >/dev/null 2>&1 && ok "sound available (afplay)" || warn "afplay not found, no sound alerts" "macOS only feature"
front=$(lsappinfo info -only name "$(lsappinfo front 2>/dev/null)" 2>/dev/null | sed -n '1s/^"\([^"]*\)".*/\1/p')
[ -n "$front" ] && ok "can detect the frontmost app ($front)" || warn "cannot detect the frontmost app, so alerts may fire while you look at iTerm" "check lsappinfo works"
if command -v terminal-notifier >/dev/null 2>&1; then
  auth=$(terminal-notifier -diagnose 2>/dev/null | sed -n 's/^  authorization *//p')
  case "$auth" in
    *"not requested"*|*denied*|*"not allowed"*|"") warn "native notifications unavailable ($auth); sounds and the status bar still work" "allow notifications for iTerm2 in System Settings > Notifications" ;;
    *) ok "native notifications: $auth" ;;
  esac
else
  warn "terminal-notifier not installed" "$SETUP"
fi
dir="$HOME/.cache/cw/alerts"
if [ -d "$dir" ]; then
  stale=""
  for f in "$dir"/*; do [ -f "$f" ] || continue; n=$(basename "$f"); tmux has-session -t "=$n" 2>/dev/null || stale="$stale $n"; done
  if [ -z "$stale" ]; then ok "no stale alert markers"; else warn "stale alert markers for sessions that no longer exist:$stale" "they clear themselves in the status bar; or rm ~/.cache/cw/alerts/*"; fi
fi

section "iTerm2"
P="$HOME/Library/Preferences/com.googlecode.iterm2.plist"
if [ -f "$P" ]; then
  l=$(/usr/libexec/PlistBuddy -c "Print :'New Bookmarks':0:'Option Key Sends'" "$P" 2>/dev/null)
  r=$(/usr/libexec/PlistBuddy -c "Print :'New Bookmarks':0:'Right Option Key Sends'" "$P" 2>/dev/null)
  if [ "$l" = 2 ] && [ "$r" = 2 ]; then ok "Option keys send Esc+"; else warn "Option keys are not Esc+ (Option+Arrow will print characters)" "$SETUP, then quit and reopen iTerm2"; fi
else
  warn "iTerm2 preferences not found" "open iTerm2 once, then $SETUP"
fi

printf '\n'
if [ "$fails" -gt 0 ]; then
  printf '%s%d unhealthy%s, %d warning(s).\n' "$R" "$fails" "$Z" "$warns"; exit 1
elif [ "$warns" -gt 0 ]; then
  printf '%sHealthy%s, with %d warning(s).\n' "$G" "$Z" "$warns"
else
  printf '%sEverything is healthy.%s\n' "$G" "$Z"
fi
CW_DOCTOR_EOF
chmod +x ~/.local/bin/cw-doctor

# Profiles (one per Claude login; cw shows each one's signed-in email). Only created if missing, so your edits stay.
# Format: name=config_dir   (empty config_dir = Claude's default login)
# To add a login: add a line here, then run `CLAUDE_CONFIG_DIR=<dir> claude` once to sign in.
mkdir -p ~/.config/cw
if [ ! -f ~/.config/cw/profiles ]; then
  if [ -f "$SETUP_DIR/profiles.local" ]; then
    # Your private profiles, kept next to this script and out of git (see .gitignore)
    cp "$SETUP_DIR/profiles.local" ~/.config/cw/profiles
  else
    cat > ~/.config/cw/profiles <<'PROFILES_EOF'
# name=config_dir   (empty = default Claude login)
default=
# More logins: add a line, then sign in once with CLAUDE_CONFIG_DIR=<dir> claude
# work=~/.claude-work
PROFILES_EOF
  fi
fi

# 4b. Slash commands (/ticket, /pr, /pr-comments), installed into every profile's config dir
# (each profile has its own commands folder; default profile = ~/.claude)
TICKET_MD=$(mktemp)
cat > "$TICKET_MD" <<'TICKET_EOF'
---
description: Read a Jira ticket and come back with an implementation plan
argument-hint: [TICKET-KEY or Jira URL]
---

Ticket: $ARGUMENTS

If no ticket was given above, take the Jira key from the current git branch name
(for example `worktree-PROJ-123` means PROJ-123). If you cannot find one, ask me.
If a URL was given, use the key after `/browse/`.

1. Use the Atlassian tools to read the ticket in full: summary, description,
   acceptance criteria, comments, linked issues, and any linked Confluence pages.
2. Explore the relevant code in this repo to see what the ticket touches.
3. Work in plan mode: do not edit any files or run anything that changes state.
4. Come back with:
   - a two or three line summary of what the ticket asks for
   - open questions or assumptions, if the ticket is unclear
   - a step-by-step plan, naming the files you expect to change
   - how it will be tested or verified
   - risks or anything out of scope
5. Wait for my approval before making any change.
TICKET_EOF
PR_MD=$(mktemp)
cat > "$PR_MD" <<'PR_EOF'
---
description: Review this branch, then open a pull request (asks before pushing anything)
argument-hint: [base branch, optional]
---

Open a pull request for the current branch. Base branch: $ARGUMENTS
(if empty, use the repository's default branch).

Rules for this whole task:
- Never commit to or push the default branch. Never force-push.
- Open the PR as a draft unless I say otherwise.
- Do not push or create anything until I approve the draft in step 4.

1. Check the state: `git status`, the current branch, and the base branch
   (`gh repo view --json defaultBranchRef`). If this is the default branch, or there are no
   commits ahead of the base, stop and tell me. If there are uncommitted changes, show them
   and ask whether to commit them first.
2. Review the full change against the base (`git log <base>..HEAD`, `git diff <base>...HEAD`).
   Look for leftover debug code, secrets or credentials, unrelated changes, new TODOs, and
   missing tests. Find and run the project's tests, lint and build (check the README,
   package.json, Makefile and similar) and report the results. Do not hide failing checks.
3. Draft the PR. Title: if the branch name or commits contain a ticket key such as PROJ-123,
   start the title with it. Body: Summary (what and why), Changes, How to test, Risks or
   follow-ups, and a link to the ticket if there is one.
4. Show me the draft and your review findings, then wait for my approval.
5. After approval: `git push -u origin HEAD`, then
   `gh pr create --draft --base <base> --title "<title>" --body-file <file>`.
   Print the PR URL.
PR_EOF
PRC_MD=$(mktemp)
cat > "$PRC_MD" <<'PR_COMMENTS_EOF'
---
description: Read the review comments on this branch's PR and propose fixes
---

Handle review feedback on the pull request for the current branch.

1. Find the PR: `gh pr view --json number,url,title,reviewDecision,headRefName`.
   If there is none, say so and stop.
2. Collect all feedback: conversation comments (`gh pr view --comments`), inline review
   comments (`gh api repos/{owner}/{repo}/pulls/<number>/comments`) and review verdicts
   (`gh api repos/{owner}/{repo}/pulls/<number>/reviews`). Skip comments that are already
   resolved or outdated when you can tell.
3. Group by file. For each open comment: quote it in one line, say whether you agree, and
   propose the specific change, or a reply if it is a question or you disagree.
4. Present this as a checklist and wait for my approval before editing anything.
5. After approval: make the changes, run the tests, and commit with a message that references
   the feedback. Do not push until I say so.
6. Never post a reply or resolve a thread without showing me the exact text first.
PR_COMMENTS_EOF
grep -v '^[[:space:]]*\(#\|$\)' ~/.config/cw/profiles | cut -d= -f2- | while read -r pdir; do
  pdir=$(printf '%s' "$pdir" | sed "s#^~#$HOME#")
  pdir="${pdir:-$HOME/.claude}"
  mkdir -p "$pdir/commands"
  cp "$TICKET_MD" "$pdir/commands/ticket.md"
  cp "$PR_MD" "$pdir/commands/pr.md"
  cp "$PRC_MD" "$pdir/commands/pr-comments.md"
done
rm -f "$TICKET_MD" "$PR_MD" "$PRC_MD"

# 5. Shell setup: a managed block at the end of ~/.zshrc (rewritten on every run)
touch ~/.zshrc
[ -f ~/.zshrc.pre-setup ] || cp ~/.zshrc ~/.zshrc.pre-setup
# Remove lines this script used to add on their own, and the old block
sed -i '' -e '/^export PATH="\$HOME\/\.local\/bin:\$PATH"$/d' -e '/^source <(fzf --zsh)$/d' \
  -e '/^export PATH=\/opt\/homebrew\/opt\/rustup\/bin:\$PATH$/d' \
  -e '/^export PATH="\/opt\/homebrew\/opt\/rustup\/bin:\$PATH"$/d' \
  ~/.zshrc
sed -i '' '/^# >>> setup.sh managed block/,/^# <<< setup.sh managed block/d' ~/.zshrc
cat >> ~/.zshrc <<'ZSHRC_EOF'
# >>> setup.sh managed block (edit setup.sh, not this) >>>
if [ -x /opt/homebrew/bin/brew ]; then eval "$(/opt/homebrew/bin/brew shellenv)"
elif [ -x /usr/local/bin/brew ]; then eval "$(/usr/local/bin/brew shellenv)"; fi
export PATH="$HOME/.local/bin:$PATH"
# rustup (Homebrew keeps it out of PATH by default)
for _r in /opt/homebrew/opt/rustup/bin /usr/local/opt/rustup/bin; do
  [ -d "$_r" ] && export PATH="$_r:$PATH"
done; unset _r
command -v fzf >/dev/null 2>&1 && source <(fzf --zsh)
command -v fnm >/dev/null 2>&1 && eval "$(fnm env --use-on-cd --shell zsh)"

# Option+Left / Option+Right jump between words (iTerm and tmux send these)
bindkey '^[[1;3D' backward-word
bindkey '^[[1;3C' forward-word
bindkey '^[^[[D'  backward-word
bindkey '^[^[[C'  forward-word
bindkey '^[[1;9D' backward-word
bindkey '^[[1;9C' forward-word

# One claude-<profile> command per entry in ~/.config/cw/profiles (e.g. claude-work)
if [ -f ~/.config/cw/profiles ]; then
  while IFS='=' read -r _n _d; do
    case "$_n" in ''|'#'*|default) continue ;; esac
    eval "claude-$_n() { CLAUDE_CONFIG_DIR=\"${_d/#\~/$HOME}\" claude \"\$@\"; }"
  done < ~/.config/cw/profiles
  unset _n _d
fi
# <<< setup.sh managed block <<<
ZSHRC_EOF

# 6. Register the alert hook in EVERY profile's settings.json (idempotent, keeps existing hooks)
CMD="$HOME/.config/tmux/cc-bell.sh"
grep -v '^[[:space:]]*\(#\|$\)' ~/.config/cw/profiles | cut -d= -f2- | while read -r pdir; do
  pdir=$(printf '%s' "$pdir" | sed "s#^~#$HOME#")
  pdir="${pdir:-$HOME/.claude}"
  S="$pdir/settings.json"
  [ -f "$S" ] || { mkdir -p "$pdir"; echo '{}' > "$S"; }
  cp "$S" "$S.bak"
  jq --arg cmd "$CMD" '
    reduce ("Notification","PermissionRequest","Stop","UserPromptSubmit","SessionEnd") as $e (.;
      if ([.hooks[$e][]?.hooks[]?.command] | index($cmd))
      then . else .hooks[$e] += [{"hooks":[{"type":"command","command":$cmd}]}] end)
  ' "$S.bak" | jq --arg sl "$HOME/.config/tmux/cc-statusline.sh" '
    # usage status line, unless the profile already has its own
    if .statusLine then . else .statusLine = {"type":"command","command":$sl} end
  ' > "$S"
done

# 7. Reload if tmux is running
tmux source-file ~/.tmux.conf 2>/dev/null || true

# 8. Notification permission. macOS only lets the user grant it (no script can). Try once to
# trigger the prompt; if it is refused, print guidance and open Settings only the FIRST time.
# (terminal-notifier is ad-hoc signed and macOS 27 refuses it outright; the hook then falls back
# to a plain notification. iTerm2 itself, installed above, is the app to allow.)
mkdir -p ~/.cache/cw
if [ ! -f ~/.cache/cw/notify-ok ]; then
  if terminal-notifier -title "Claude Code" -group cw-setup \
       -message "Setup done. If macOS asks, click Allow so Claude alerts reach you." >/dev/null 2>&1; then
    touch ~/.cache/cw/notify-ok
  elif [ ! -f ~/.cache/cw/notify-hint-shown ]; then
    touch ~/.cache/cw/notify-hint-shown
    echo "Notifications: macOS only lets you grant this. In System Settings > Notifications, allow"
    echo "iTerm2 (and terminal-notifier if it is listed). Opening that page now (shown once)."
    open "x-apple.systempreferences:com.apple.Notifications-Settings.extension" 2>/dev/null || true
  fi
fi

echo "Done. Open a new terminal tab (and restart iTerm2 if it said so above)."
