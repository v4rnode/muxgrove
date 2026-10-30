# muxgrove

A tmux + Claude Code workflow for the Mac. One script sets up everything for running several
Claude Code sessions side by side:
one tmux session per task, each in its own git worktree, with alerts when a session
finishes or needs you, and support for more than one Claude login.

```
sh setup.sh        # safe to re-run at any time
```

New here? Read [TUTORIAL.md](TUTORIAL.md) (about 15 minutes, hands on).

## What it sets up

| Area | What you get |
|---|---|
| Tools | Homebrew, Oh My Zsh (+ autosuggestions and two syntax highlighters), `tmux`, `fzf`, `jq`, `git`, `gh`, `node`, `fnm`, `terminal-notifier`, `rustup`, iTerm2, Claude Code CLI. Only what is missing is installed. |
| Shell | A managed block at the end of `~/.zshrc`: PATH, fzf, fnm, Option+Left/Right word jumps, and a `claude-<profile>` command per profile. |
| iTerm2 | Both Option keys set to Esc+ (needed for word jumps and tmux Alt keys). |
| tmux | Config with fuzzy session and window switchers, Alt shortcuts, popup shell, copy mode, a colored status bar, and tmux-resurrect + continuum for restore after a restart. |
| `cw` | One command to start a task: picks a Claude profile, creates a tmux session, runs `claude -w <name>` (Claude makes the git worktree). Also `cw -r` to reopen a past conversation, `cw -d` to clean up, `cw doctor` to check the setup. |
| Usage | Claude's status line and the tmux bar show how much of the 5-hour and weekly usage limits you have used, with reset times (green, yellow from 50%, red from 80%). See "Remote Control and usage". |
| Alerts | Status bar markers for other sessions (`⚠` needs you, `✔` finished), a sound and a macOS notification when iTerm2 is in the background (click the notification to jump to that session), and a session picker with a live preview. |
| Slash commands | `/ticket` reads a Jira ticket and proposes a plan; `/pr` reviews the branch and opens a draft PR; `/pr-comments` works through review feedback. All ask before changing or pushing anything. |

## Daily use

```
cd ~/Projects/some-repo
cw login-fix              # pick a profile (arrows + enter), start Claude in a worktree
cw -p work login-fix       # skip the picker
cw --no-rc login-fix      # same, without Remote Control (it is on by default)
cw -r                     # reopen a past Claude conversation from this repo (pick from a list)
cw -d login-fix           # close the session, offer to remove its worktree and branch
cw doctor                 # check the whole setup, with a fix for anything wrong
```

Inside Claude:

| Command | What it does |
|---|---|
| `/ticket PROJ-123` | Reads the ticket (or a Jira URL, or the key from the branch name), explores the code, proposes a plan. No edits until you approve. |
| `/pr` | Checks the branch, reviews the diff, runs the project's tests, drafts a title and body, and waits for approval. Only then pushes and opens a **draft** PR with `gh`. Never touches the default branch, never force-pushes. |
| `/pr-comments` | Reads the review comments on the branch's PR, proposes a fix or reply for each, and waits for approval before editing. Never replies or resolves threads without showing you the text. |

The flow is: `cw` a task, `/ticket` to plan, implement, `/pr` to open it, `/pr-comments` after review.

`cw -r` lists the past Claude conversations for this repo (its main checkout and every worktree, newest
first, with the first prompt as a hint) for the profile you pick, and resumes the one you choose in the
folder it ran in. Conversations whose worktree no longer exists are skipped.

### Keys (tmux prefix is `Ctrl+b`)

| Key | Action |
|---|---|
| `prefix f` | Session picker with preview and alert markers |
| `prefix w` | Window picker across all sessions |
| `Alt+j` / `Alt+k` | Next / previous session |
| `Alt+h` / `Alt+l` | Previous / next window |
| `prefix Tab` | Jump back to the previous session |
| `prefix c` / `prefix C` | New window (asks for a name) / named after the folder |
| `prefix \|` / `prefix -` | Split side by side / stacked |
| `prefix z` | Zoom the current pane |
| `prefix H J K L` | Resize pane |
| `prefix t` | Popup shell in the current folder |
| `prefix [` | Scroll mode: `v` select, `y` copy to the macOS clipboard |
| `prefix r` | Reload `~/.tmux.conf` |
| `prefix d` | Detach (sessions keep running) |

## Claude profiles (multiple logins)

Profiles live in `~/.config/cw/profiles`, one `name=config_dir` per line:

```
default=
work=~/.claude-work
```

An empty directory means Claude's default login. To add an account, add a line such as
`work=~/.claude-work`, then sign in once with `CLAUDE_CONFIG_DIR=~/.claude-work claude`.
After that it shows up in the `cw` picker (with the signed-in email) and as a
`claude-work` shell command. `setup.sh` never overwrites this file, and it installs the
alert hook and `/ticket` into every profile listed here. Logins themselves are yours to
manage; the script does not touch credentials.

## Keeping your own settings out of git

Nothing personal lives in this repo. Per-machine values stay in files that git ignores:

- `profiles.local`: put your own Claude profiles here (same `name=config_dir` format as above).
  On a fresh machine `setup.sh` copies it to `~/.config/cw/profiles` if that file does not exist yet.
  Without it you get a generic `default` profile and a commented example.
- Credentials are never read or stored by this repo. Each profile's login lives in its own
  Claude config folder, and you sign in to it yourself.

Anything matching `*.local` or `.env` is in `.gitignore`. Check `git status` before committing.

## How it fits together

- `setup.sh` is the single source of truth. It writes everything else from heredocs
  (`~/.tmux.conf`, `~/.local/bin/cw`, `~/.config/tmux/*.sh`, the `/ticket` command).
  Edit the heredoc in `setup.sh` and re-run it; do not edit the installed copies.
- The Claude hook `cc-bell.sh` runs on `Stop`, `Notification`, `PermissionRequest`,
  `UserPromptSubmit` and `SessionEnd`. It records state in `~/.cache/cw/alerts/<session>`,
  which `status.sh` (status bar) and `session-picker.sh` read.
- tmux sessions started by `cw` are named after the task (plus `-<profile>` for non-default
  profiles). Their status-bar label shows the profile and signed-in email.

## Preferences

Optional file `~/.config/cw/config` (plain shell, never overwritten by `setup.sh`):

```sh
CW_SOUND=0              # mute the sound alert
CW_SOUND_DONE=Glass     # sound when Claude finishes (any name in /System/Library/Sounds)
CW_SOUND_INPUT=Funk     # sound when Claude needs you
CW_NO_NOTIFY=1          # no macOS notifications
CW_REMOTE_CONTROL=0     # Remote Control is on by default; 0 turns it off (cw -R forces it on for one session)
```

The sound needs no macOS permission, so it works on any Mac right after `setup.sh`. It plays only when
iTerm2 is not the frontmost app, the same rule as notifications.

## Remote Control and usage

Every `cw` session starts Claude with `--remote-control <name>`, so it shows up in the Claude app and on the
web under the same name as the tmux session (also for `cw -r`). The tmux status bar shows a blue `RC` tag.
Turn it off for one session with `cw --no-rc <name>`, or for good with `CW_REMOTE_CONTROL=0`.

Usage: `setup.sh` installs `~/.config/tmux/cc-statusline.sh` as each profile's Claude status line (only if the
profile has none of its own). It prints the model plus `5h` and `wk` usage with reset times, and caches the
numbers per profile so the tmux status bar shows the same line without the model name.
Only subscription logins report these limits.

```
5h 34% ↻16:00 · wk 61% ↻Tue
```

| Shown | Meaning |
|---|---|
| `5h 34%` | Share of the rolling 5-hour usage limit already used. |
| `wk 61%` | Share of the 7-day usage limit already used. |
| `↻16:00`, `↻Tue` | When that window resets (a time for 5h, a weekday for wk). |
| Green, yellow, red | Under 50%, 50 to 79%, 80% or more. |
| `5h -` | That window has already reset and Claude has not reported a new value yet. |

Each profile has its own limits; the tmux bar shows the ones for the current session's profile.

## The one manual step

macOS lets only you grant notification permission. At the end of the run, `setup.sh` triggers the
prompt (click Allow) or, if it was refused before, opens System Settings > Notifications so you
can switch `terminal-notifier` on. Nothing else needs a click, apart from signing in to your
Claude profiles and accepting each project's trust dialog the first time.

## Safety

- Backups: `~/.zshrc.pre-setup` (first run only) and `<profile>/settings.json.bak` (each run).
- Existing hooks in `settings.json` are kept; only the alert hook is added, once per event.
- `~/.config/cw/profiles` is created only if missing.
- Worktree removal (`cw -d`) always asks, and git refuses to remove a worktree with
  uncommitted changes.

## Troubleshooting

Start with `cw doctor`. It checks tools, shell, tmux, each profile (sign-in, alert hook, slash
commands, folder trust), alerts, notifications and iTerm, and prints a fix for every problem.
Statuses are colored: green `healthy`, yellow `warning`, red `unhealthy`. Each profile gets its own
color (never green, yellow or red) so several profiles are easy to tell apart. Colors appear only on a
terminal; `NO_COLOR=1` turns them off. The exit status is 1 if anything is unhealthy.

| Symptom | Cause and fix |
|---|---|
| `cw: command not found` | Open a new terminal tab (PATH is set by the managed zshrc block). |
| Session closes right away | Claude needs the folder trusted before it can make a worktree. `cw` now walks you through the trust dialog. If it still fails, the pane stays open with the error. |
| Two notifications for one event | iTerm2 has its own Claude Code integration (its `cc-status` hooks) that posts a separate notification, and it cannot switch tmux sessions. To keep only muxgrove's, use **iTerm2 > Uninstall Claude Code Integration** (this also removes iTerm's Claude status display). `cw doctor` tells you when it finds those hooks. Do not delete the hooks by hand; iTerm warns when they go missing. |
| `/pr` says `gh` not found or not logged in | `setup.sh` installs `gh`; then run `gh auth login` once. |
| `/bin/sh: node: command not found` in a hook | Node is missing. `setup.sh` installs it; re-run it. |
| Option+Arrow prints `;3D` | Quit iTerm2 completely (Cmd+Q) and reopen it so the Esc+ setting applies. |
| No notifications | System Settings > Notifications, allow "terminal-notifier". Silence on purpose with `CW_NO_NOTIFY=1`. |
| `terminal-notifier` is not in System Settings > Notifications | macOS lists an app only after it has asked once. Run `terminal-notifier -title test -message hi` in a normal iTerm2 tab (not from inside Claude or another app) and click Allow. `terminal-notifier -diagnose` explains the current state. |
| Clicking a notification does nothing | It focuses iTerm2 and switches tmux to that session. That needs a tmux client attached; if you detached, only iTerm2 is focused. |
| No usage numbers | Needs a subscription login and at least one message sent in a session started after `setup.sh`. A profile with its own status line is left alone; `cw doctor` says so. |
| Alert markers never appear | The session must have been started after the hooks were installed. Restart Claude in it. |

## Development

```
sh dev/check.sh            # syntax checks + isolated tmux config smoke test (touches nothing real)
sh dev/extract.sh OUTDIR   # write each embedded file out for testing on its own
sh dev/leak-check.sh       # refuse emails, home paths, ticket keys and your own private terms
git config core.hooksPath dev/hooks   # run that check on every commit (once per clone)
```

The leak check keeps the repo free of anything personal or work-related. Your own private terms go in
`dev/leak-patterns.local` (git-ignored, one regex per line).

See [CLAUDE.md](CLAUDE.md) for the rules and pitfalls when changing this repo.

## Status

Tested on one Mac where most tools already existed. The paths that install Homebrew,
Oh My Zsh and the casks from scratch, and a real restore after a restart, have not been
exercised end to end. Expect to watch the first run on a fresh machine.
