# Tutorial: running several Claude sessions with tmux

About 15 minutes. You need `setup.sh` already run and a new terminal tab open.
The prefix key in tmux is `Ctrl+b`: press it, release it, then press the next key.

## 0. The idea in one minute

- **tmux** keeps terminals alive in the background and lets you jump between them.
  Structure: a **session** contains **windows**, which contain **panes**.
- **A git worktree** is an extra folder, on its own branch, that shares one repository.
  Two Claudes in two worktrees cannot overwrite each other's files.
- **`cw`** ties them together: one command makes a tmux session and starts Claude in a
  fresh worktree. You get one session per task.

## 1. Make a practice repo

```sh
mkdir -p ~/tmux-playground && cd ~/tmux-playground
git init -b main play && cd play
git commit --allow-empty -m "init"
```

## 2. tmux basics (3 minutes)

```sh
tmux new -s basics
```

1. `Ctrl+b` then `|` splits side by side, `Ctrl+b` then `-` splits top and bottom. Click a pane to focus it.
2. `Ctrl+b` then `z` zooms the current pane to full screen; press it again to restore.
3. `Ctrl+b` then `c` opens a new window and asks for a name. Type one and press Enter.
4. `Alt+h` and `Alt+l` move between windows.
5. `Ctrl+b` then `d` detaches. Everything keeps running. `tmux attach -t basics` brings it back.
6. `Ctrl+b` then `[` scrolls (arrow keys, `q` to leave). Press `v` to start selecting and `y` to copy.

Notice the colored bar at the bottom: the orange tab is the window you are in.
Clean up with `tmux kill-session -t basics`.

## 3. Your first Claude session with `cw` (4 minutes)

From inside `~/tmux-playground/play`:

```sh
cw hello
```

1. A picker lists your Claude profiles with the signed-in email. Use the arrow keys and press Enter.
2. First time in a folder, you may see "This folder is not trusted by this Claude profile yet."
   Press Enter, accept Claude's trust dialog, then type `/exit`. The real session starts right after.
3. You are now in a tmux session named `hello`, with Claude running in a worktree at
   `.claude/worktrees/hello/` on branch `worktree-hello`. The bottom left shows the session
   name and which profile and email you are using.

Ask Claude to create a file, for example "create notes.txt with three bullet points".
Then look from a second terminal tab: the file is in the worktree, not in your main folder.

```sh
git worktree list
```

When you quit Claude (`/exit`), it asks whether to keep or remove the worktree.
Choose keep for now, so you can try cleanup in step 6.

Skip the picker with `cw -p work hello` (use any profile name from `~/.config/cw/profiles`).

## 4. Two sessions and alerts (4 minutes)

1. Run `cw one` and give Claude something that takes a while, such as
   "read every file in this repo and write a detailed summary".
2. Without waiting, press `Ctrl+b` then `d` to detach (or just open a new terminal tab), then run `cw two`.
3. Stay in `two`. When `one` finishes or needs permission, the status bar at the bottom right
   shows a marker for it:
   - `⚠ one` means Claude needs you (permission or a question)
   - `✔ one` means Claude finished
   If iTerm2 is in the background you also hear a short sound (a different one for "done" and "needs you")
   and get a macOS notification; click it to jump to that session.
4. Press `Ctrl+b` then `f`. The picker lists every session, **needs-you first**, with a live
   preview of what each Claude is showing. Press Enter to jump. Switching clears that marker.
5. Faster: `Alt+j` and `Alt+k` cycle sessions, `Ctrl+b` then `Tab` jumps back to the last one.

## 5. Hand Claude a Jira ticket (1 minute)

Inside any Claude session in a real repo:

```
/ticket PROJ-123
```

Claude reads the ticket through the Atlassian connector (description, acceptance criteria,
comments, linked issues), explores the code, and returns a plan. It does not change files until you approve.
You can also paste a Jira URL, or run `/ticket` with no argument in a worktree whose branch
is named after the ticket (`cw PROJ-123` creates `worktree-PROJ-123`).

## 6. Come back to earlier work (1 minute)

Sessions end, but the conversations are kept. From inside the repo:

```sh
cw -r
```

Pick a profile, then pick from the list: newest first, showing the age, where it ran (a worktree name or
`(main)`) and your first prompt. Your choice reopens in the right folder as its own tmux session.

## 7. From ticket to pull request (2 minutes)

Inside Claude, in a worktree with some committed work:

```
/pr
```

Claude checks the branch, reviews the diff for leftovers, runs the project's tests, and shows you a draft
title and body. Nothing is pushed until you approve; then it pushes and opens a **draft** PR with `gh`
(run `gh auth login` once if it asks). After review comes in:

```
/pr-comments
```

It lists each open review comment with a proposed fix or reply, and waits for you before editing.

## 8. When something is off

```sh
cw doctor
```

It checks the tools, your shell, tmux, every Claude profile, alerts and iTerm, and prints the fix next to
anything wrong. Run it first whenever something stops working.

## 9. Clean up (1 minute)

From a different session than the one you are closing:

```sh
cw -d hello
```

It closes the session and shows the worktree. Answer `y` to remove the worktree and its branch.
Git refuses if there are uncommitted changes, and keeps the branch if it is unmerged; the
message tells you the exact command to force it.

## When to use `cw` and when not to

Use `cw` (a worktree per session) when:
- two or more sessions work in the same repo at the same time,
- a task is a branch you will review or merge separately,
- you want to throw the work away without touching your main checkout.

Plain `claude` in the main folder is fine when:
- you only ask questions or read code,
- it is the only session in that repo,
- the project needs files a fresh worktree lacks (dependencies, `.env`). Gitignored files
  are not copied unless you list them in a `.worktreeinclude` file in the repo root
  (`.gitignore` syntax, for example `.env`), and you still run installs per worktree.

Note that `claude -w` starts from the repo's default branch, not your current branch.

## Cheat sheet

| Do this | Keys or command |
|---|---|
| Start a task | `cw name` or `cw -p profile name` |
| Switch sessions | `Ctrl+b f` (picker), `Alt+j` / `Alt+k`, `Ctrl+b Tab` |
| Switch windows | `Alt+h` / `Alt+l`, `Ctrl+b w` (all sessions) |
| Split / zoom | `Ctrl+b \|`, `Ctrl+b -`, `Ctrl+b z` |
| Popup shell | `Ctrl+b t` |
| Scroll and copy | `Ctrl+b [`, then `v`, `y` |
| Detach / reattach | `Ctrl+b d` / `tmux attach -t name` |
| Reopen old work | `cw -r` |
| Close a task | `cw -d name` |
| Plan from a ticket | `/ticket KEY` inside Claude |
| Open / handle a PR | `/pr`, `/pr-comments` inside Claude |
| Check the setup | `cw doctor` |
| Reload tmux config | `Ctrl+b r` |

If something does not behave, see Troubleshooting in [README.md](README.md).
