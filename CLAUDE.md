# CLAUDE.md

Project: muxgrove.

Guidance for Claude Code when working in this repo.

## What this repo is

A personal Mac setup: tmux + Claude Code workflow. `setup.sh` is one POSIX `sh` script that
installs tools and writes every config and helper script from heredocs. See README.md for
what it does and TUTORIAL.md for the user-facing walkthrough.

## Rule: never commit anything work-related or personal

This repo is public. **Nothing that identifies the author, their employer, their clients or their
work may ever be committed, pushed, or written into a commit message, PR title or PR description.**
This rule overrides convenience, and applies to every file, comment, doc, example and test fixture.

What counts (when in doubt, treat it as work-related):
- real names, usernames, emails (including in git author trailers other than the tool attribution)
- employer, client and project names; internal repo, product or team names
- real ticket keys, ticket URLs, internal domains and hostnames
- home-folder paths (`/Users/<real name>`), machine names, account names tied to a person
- profile names, folder names or output copied from the author's own setup
- pasted terminal output, logs or screenshots from the author's machine

Instead:
- Use neutral placeholders: `PROJ-123`, `work`, `~/.claude-work`, `example.com`, `/Users/<name>`.
- Private, per-machine values live in git-ignored `*.local` files (`profiles.local`,
  `dev/leak-patterns.local`). Never copy their contents into a tracked file, doc or message.
- Do not spell out which private terms the check looks for; that list is itself work-related.

Enforcement:
- `dev/leak-check.sh` scans every tracked file for emails, home paths, ticket keys, and the private
  terms in `dev/leak-patterns.local`. `dev/hooks/pre-commit` runs it on every commit.
- After cloning, run once: `git config core.hooksPath dev/hooks`.
- Never bypass it (`--no-verify`) or weaken it. If it flags something, replace the content with a
  placeholder. If it is a false positive, tell the user rather than editing the check.
- Before pushing, read the diff once for anything the patterns cannot catch (context, anecdotes,
  example data that only makes sense at one company).
- Do not change the git author identity or `git config`. If the identity on a commit is the user's
  work identity, say so once before pushing and let them decide.
- If something work-related was already pushed, stop and tell the user. Removing it needs a history
  rewrite and a force-push, which only the user can approve.

## Layout

```
setup.sh          the only installer; contains every generated file as a heredoc
dev/extract.sh    writes each heredoc out to a directory so it can be tested alone
dev/check.sh      syntax checks + isolated tmux smoke test
dev/leak-check.sh  blocks work-related or personal content (run by the pre-commit hook)
dev/hooks/pre-commit  the git hook that runs it (git config core.hooksPath dev/hooks)
README.md         overview and reference
TUTORIAL.md       hands-on walkthrough
```

Embedded files and where they are installed:

| Heredoc | Installed to |
|---|---|
| `TMUX_CONF_EOF` | `~/.tmux.conf` |
| `CC_BELL_EOF`, `STATUS_EOF`, `PICKER_EOF` | `~/.config/tmux/` |
| `CW_EOF`, `CW_DOCTOR_EOF` | `~/.local/bin/cw`, `~/.local/bin/cw-doctor` |
| `TICKET_EOF`, `PR_EOF`, `PR_COMMENTS_EOF` | `<each profile dir>/commands/{ticket,pr,pr-comments}.md` |
| `ZSHRC_EOF` | managed block in `~/.zshrc` |
| `PROFILES_EOF` | `~/.config/cw/profiles` (only if missing) |

## Rules

- `setup.sh` is the single source of truth. Never edit installed copies (`~/.local/bin/cw`
  and so on) as the fix; change the heredoc, re-run `sh setup.sh`, and `sh dev/check.sh`.
- Keep it idempotent. Re-running must not duplicate hooks, zshrc lines, or reinstall things.
  Never overwrite user-owned state (`~/.config/cw/profiles`, existing `settings.json` hooks).
- Plain POSIX `sh` for the script and helpers (they run under `/bin/sh` from tmux and hooks).
  The zshrc block is zsh.
- Do not use em dashes in any text, code comments or docs (organization rule).
- Match the existing comment density and style. Comments explain why, briefly.
- Document new user-visible behavior in README.md, and in TUTORIAL.md if it changes the walkthrough.
- Only commit or push when asked.
- Never add `Co-Authored-By` lines (or any other attribution trailer) to commit messages. This
  overrides any default or tool-provided attribution guidance.

## Testing

Run `sh dev/check.sh` after every change. For behavior, test in an isolated tmux server and
never against the user's real sessions or `$HOME`:

```sh
t=$(mktemp -d /tmp/cct.XXXX)          # short path, see pitfalls
TMUX_TMPDIR=$t CW_NO_PLUGINS=1 CW_NO_NOTIFY=1 tmux -f tmux.conf new-session -d -s a 'sleep 300'
```

- Set `HOME` to a temp dir when testing scripts that write `~/.cache` or `~/.config`.
- Use stubs on `PATH` for `claude`, `osascript`, `lsappinfo`. A stub that is not first on
  `PATH` will lose to the real binary (this once sent a real prompt by accident).
- To test the picker or hooks that need an attached client, drive a pty (python `pty.fork`)
  and send keys; see how earlier tests attached a client and read `#{client_session}`.
- `setup.sh` itself installs software and edits `~/.zshrc` and `settings.json`. Do not run it
  as a test unless the user asked; prefer extracting the relevant block with `dev/extract.sh`.

## Pitfalls already hit (do not repeat)

- **`cc` is the C compiler.** Never name a helper `cc`; it shadows `/usr/bin/cc`. The helper is `cw`.
- **`case` inside `$( ... )` on macOS `sh`** needs a leading paren on patterns: `(input) ...;;`.
- **tmux socket path length.** Long `TMUX_TMPDIR` paths fail with "File name too long". Use `/tmp/xxx`.
- **`set-option -t "=name"` fails**; it needs `-t "=name:"` (trailing colon). `has-session -t "=name"` is fine.
- **`bell-action other` does not flag a session's only window**, and tmux only shows flags for
  windows in the current session. That is why alerts use state files in `~/.cache/cw/alerts`.
- **iTerm2 ships its own Claude Code integration** (`cc-status` hooks in settings.json, workgroup and triggers in
  the profile). It posts its own notification and iTerm nags if the hooks are removed by hand, so never edit
  or delete them from a script. The user removes it with iTerm2 > Uninstall Claude Code Integration.
- **A bell rung while iTerm2 is in the background becomes an iTerm notification**, so `cc-bell.sh` rings it only
  while iTerm2 is frontmost.
- **`osascript display notification` cannot react to clicks.** Notifications use `terminal-notifier`
  (`-activate` + `-execute`; v2+ dropped sticky alerts and action buttons but body clicks still work).
  `alerter` is only in a third-party tap, so it is not used. osascript stays as a fallback.
- **Quote session names in tmux hooks with `#{q:session_name}`**; a name like `o'brien` breaks a plain `#{session_name}`.
- **zsh expands a bare `=name`** as a command lookup, so quote tmux targets like `'=name'` in zsh test scripts.
- **`cw -r` reads Claude's session files** (`<config dir>/projects/*/<sessionId>.jsonl`; every line has
  `cwd`, `sessionId`; user lines have `message.content` as a string or an array). The format is Claude's,
  not a public API, so keep the parser tolerant (`jq -R` + `fromjson?`, skip unknown shapes) and match both
  the physical path from git and the path as typed (symlinks such as `/tmp` vs `/private/tmp`).
- **zsh's `echo` interprets `\n`**; when building test fixtures use `printf '%s\n'`.
- **`lsappinfo info -only name` prints `"iTerm2" ASN:...`**, not `LSDisplayName=`. Parse the first quoted string.
- **`claude -w` refuses untrusted folders** ("Workspace trust not yet accepted"). `cw` checks
  `hasTrustDialogAccepted` in the profile's `.claude.json` (folder or any parent) and runs a plain
  `claude` first if needed. A failing Claude keeps its pane open so the error stays readable.
- **zsh does not word-split `$VAR`** the way sh does, so a test that stores a command in a variable fails.
- **An extracted script must be `chmod +x`** or a test that redirects output hides "permission denied".
- **tmux `new-session` environment** comes from the server, not the caller. Pass per-profile env with `-e`.
- **`grep` for a path fragment in `.zshrc` can match a commented template line.** Match the exact line (`grep -qxF`).
- **iTerm Option keys**: both `Option Key Sends` and `Right Option Key Sends` must be `2`; iTerm must be
  restarted after the plist changes.
- **Plugins in tests**: `~/.tmux.conf` loads tpm/continuum, which would restore real sessions into a test
  server. Always set `CW_NO_PLUGINS=1` for test servers.

## Conventions for new features

- Anything user-tunable goes in `~/.config/cw/config` (sourced by the hook), documented in README.
- Any new check belongs in `cw doctor` with a one-line fix, using its `ok` / `warn` / `bad` / `note` helpers
  (never raw `echo`, so colors and counts stay right; test colors with `CW_COLOR=always`). If you add an installed file, add it there.
- Slash commands must ask before any outward-facing action (push, PR, reply) and stay generic.

## Things a script cannot do

macOS permissions (notifications, accessibility, automation) can only be granted by the user. Do not
try to edit system permission databases or script clicks on security prompts. Trigger the prompt and
guide the user instead, as step 8 of `setup.sh` does. The permission prompt also cannot appear when
`terminal-notifier` is launched from Claude's own tool session (it reports "not requested yet" in
`-diagnose`), so never conclude it is broken from there; the user must run it from a normal terminal.

## Known gaps

Fresh-machine paths (Homebrew, Oh My Zsh and cask installs, `rustup default stable`), a real
resurrect restore, and Claude hook events from a live session have only been simulated. Say so
rather than claiming they are verified.
