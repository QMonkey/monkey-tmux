# monkey-tmux

A tmux configuration focused on functional completeness, performance, Vim-like keybindings, and TTY compatibility.

## Screenshot

![tmux](pictures/tmux.png "tmux")

## Features

- **Session persistence**: auto-save/restore via `tmux-resurrect` + `tmux-continuum`
- **Vim-style copy mode**: `v/V/C-v` for selection, `H/L` for line nav, `h/j/k/l` for movement
- **Fuzz copy**: `tmux-fingers` provides vimium-style hint-based copy/paste
- **Pane/window management**: standard keybindings + `tmux-pain-control` + `tmux-sessionist`
- **fzf integration**: prefix+Q for fuzzy session/window/pane/command/keybinding search
- **Search**: `tmux-copycat` for regex, urls, files, git hashes
- **Clipboard**: `tmux-yank` for system clipboard, `tmux-open` for opening files/urls
- **Logging**: `tmux-logging` for saving pane output
- **Status bar**: custom Sonokai andromeda theme with session, hostname, time, battery
- **AI agent monitoring**: `tmux-scout` status widget + fzf picker for tracking AI coding agent sessions
- **AI session persistence**: `tmux-assistant-resurrect` restores AI coding assistant sessions (Claude Code, OpenCode, etc.) across tmux restarts
- **Mouse support**: `tmux-better-mouse-mode` for responsive mouse
- **Modal indicator**: mode indicator (prefix/copy/normal) in status bar
- **TTY-safe**: no powerline glyphs, pure block separators, works in any terminal

## Requirements

- tmux >= 3.2
- [fzf](https://github.com/junegunn/fzf) >= 0.51 (required for `tmux-fzf` and `tmux-scout`)
- [Node.js](https://nodejs.org/) >= 16 (required for `tmux-scout`)
- [jq](https://jqlang.github.io/jq/) (required for `tmux-assistant-resurrect`)
- xclip or xsel (Linux, for clipboard)

### Install fzf

```bash
# Ubuntu/Debian
sudo apt-get install fzf

# macOS
brew install fzf

# From source
git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
~/.fzf/install
```

## Installation

```bash
git clone https://github.com/QMonkey/monkey-tmux.git ~/monkey-tmux
ln -s $(pwd)/.tmux.conf ~/.tmux.conf
```

Start tmux, then press `prefix + I` to install plugins.

### Dependency check

Run `checkhealth.sh` to verify all dependencies are installed:

```bash
./checkhealth.sh
```

To auto-install missing packages:

```bash
./checkhealth.sh --install
```

### Install tmux-scout agent hooks

`tmux-scout` tracks AI coding agent sessions via hooks written into each
agent CLI's config. The plugin loads these hooks once per agent — they are not
re-run on every tmux start. After `prefix + I`, run this once to wire up all
installed agents (Claude Code, OpenCode, Cursor, Codex, Gemini, Kimi, Copilot
CLI, etc.):

```bash
eval "$(tmux show-env -g SCOUT_DIR)" && "$SCOUT_DIR/scripts/setup.sh" install
```

To install hooks for a single agent, or to inspect/clean up:

```bash
eval "$(tmux show-env -g SCOUT_DIR)" && "$SCOUT_DIR/scripts/setup.sh" install --claude    # Claude Code only
eval "$(tmux show-env -g SCOUT_DIR)" && "$SCOUT_DIR/scripts/setup.sh" install --codex     # Codex only
eval "$(tmux show-env -g SCOUT_DIR)" && "$SCOUT_DIR/scripts/setup.sh" install --opencode  # OpenCode only
eval "$(tmux show-env -g SCOUT_DIR)" && "$SCOUT_DIR/scripts/setup.sh" install --cursor    # Cursor Agent only

eval "$(tmux show-env -g SCOUT_DIR)" && "$SCOUT_DIR/scripts/setup.sh" status   # Check installation status
eval "$(tmux show-env -g SCOUT_DIR)" && "$SCOUT_DIR/scripts/setup.sh" doctor   # Environment diagnostics
eval "$(tmux show-env -g SCOUT_DIR)" && "$SCOUT_DIR/scripts/setup.sh" uninstall # Remove all hooks
```

Re-run `install` only when the plugin directory has moved (e.g. TPM re-cloned
it to a new path) or when you add a new agent CLI.

### tmux-scout status bar

`tmux-scout` shows a `W|B|D|I` counter in `status-right` summarizing all
tracked AI agent sessions. The letters are session counts, not raw statuses:

| Letter | Meaning | Color |
|--------|---------|-------|
| `W` | waiting for your input (approval / question / plan) | `@thm_red` `#fb617e` |
| `B` | busy — agent is running a prompt or tool | `@thm_orange` `#f89860` |
| `D` | done — latest turn completed | `@thm_green` `#9ed06c` |
| `I` | idle — internal placeholder, effectively never shown | `@thm_blue` `#7aa5ff` |

Separators use `@thm_muted` `#7e8294`. Colors are defined via `set -gF` with
`#{@thm_*}` references, so they track the theme palette automatically.

The `I` (idle) counter is an internal tmux-scout placeholder for
process-only-discovered sessions and is hidden from the picker, so in practice
you will only ever see `W`, `B`, and `D`.

The segment is clickable (opens the picker) but has no underline hint; the
underline was disabled via `@scout-status-click-style off`. Open the full
picker with `prefix + O`.

## Auto-start tmux on shell login

> **Warning:** Do NOT set tmux as your login shell (e.g. `chsh -s $(which tmux)`).
> `login`/`getty` invokes the login shell before `$TERM` is configured, so tmux
> aborts with `missing or unsuitable terminal: tty1` and the terminal becomes
> unusable. Keep `/bin/bash` as your shell and auto-start via `.bashrc` instead.
> Auto-starting via `.bashrc` works fine on TTY/kmscon too, because `$TERM` is
> already set by the time the shell runs.
>
> **Recovery:** Leave the `root` account untouched (default shell, no auto-start
> script). If a user's shell/rc ever breaks, you can still log in as `root` or
> drop to single-user mode to fix it.

Add to your `~/.bashrc` or `~/.zshrc`:

- `-z "$TMUX"` — only run when not already inside tmux, preventing nested
  sessions.
- `[[ $- == *i* ]]` — only run in interactive shells, so `scp`/`rsync`/`ssh`
  remote commands don't spawn tmux.
- `command -v tmux` — skip silently when tmux isn't installed.
- `exec` — replaces the shell process so `exit` closes the terminal directly.

**Shared session (recommended)**:

```bash
if [[ -z "$TMUX" ]] && [[ $- == *i* ]] && command -v tmux >/dev/null; then
    if tmux has-session -t main 2>/dev/null; then
        exec tmux new-session -t main \; new-window
    else
        exec tmux new-session -s main
    fi
fi
```

The first terminal creates the `main` session and triggers continuum
auto-restore. Subsequent terminals create a new grouped session sharing
`main`'s windows, then open a fresh window — each terminal has independent
window/pane navigation while sharing the same session windows.

**Independent sessions**:

```bash
if [[ -z "$TMUX" ]] && [[ $- == *i* ]] && command -v tmux >/dev/null; then
    if ! tmux has-session -t main 2>/dev/null; then
        exec tmux new-session -s main
    else
        exec tmux new-session
    fi
fi
```

First terminal restores, rest get independent sessions with default
names (0, 1, 2…). Requires `@continuum-restore 'on'` in `.tmux.conf`.

For a desktop-only setup (skip TTY):

```bash
if [[ -z "$TMUX" ]] && [[ $- == *i* ]] && [[ -n "${DISPLAY}${WAYLAND_DISPLAY}" ]] && command -v tmux >/dev/null; then
    # use shared session or independent sessions logic above
fi
```

## Theme

Custom hand-written theme using the **Sonokai andromeda** palette. Colors are
defined once as `@thm_*` variables and referenced throughout the status bar
and UI styles.

```tmux
# .tmux.conf — color palette (truecolor hex, Sonokai andromeda)
set -g @thm_bg        '#2b2d3a'  # bg0 — main / pane background
set -g @thm_status_bg '#393e53'  # bg3 — status bar background (StatusLine)
set -g @thm_fg        '#e1e3e4'  # fg — foreground text
set -g @thm_muted     '#7e8294'  # grey — inactive tab
set -g @thm_gray      '#363a4e'  # bg2 — message background
set -g @thm_blue      '#7aa5ff'  # session (custom accent)
set -g @thm_cyan      '#6dcae8'  # blue — mode / active tab / hostname
set -g @thm_soft      '#e1e3e4'  # fg — light text on dark blocks
set -g @thm_coal      '#333648'  # bg1 — time + date block
set -g @thm_slate     '#3f445b'  # bg4 — battery block
set -g @thm_green     '#9ed06c'  # green — done / activity
set -g @thm_orange    '#f89860'  # orange — attention
set -g @thm_red       '#fb617e'  # red — bell / reject
set -g @thm_purple    '#bb97ee'  # purple — free
```

Status sections map to these colors:

| Section | Color |
|---------|-------|
| status bar background | `@thm_status_bg` |
| mode / active-tab / hostname | `@thm_cyan` |
| session | `@thm_blue` |
| inactive tab | `@thm_muted` |
| time + date | `@thm_coal` |
| battery | `@thm_slate` |
| free / attention | `@thm_orange` / `@thm_purple` |
| bell / reject | `@thm_red` |

The palette is truecolor hex by default; on a bare TTY
(`TERM=linux` & friends) it falls back to the fixed 16-color VGA palette via
the `%if` block in `.tmux.conf`. Block-style separators only — no powerline
glyphs, works in any terminal.

To change the theme, edit the `@thm_*` values in `.tmux.conf`.

## Keyboard shortcuts

Prefix is `Ctrl+a`. Use `Ctrl+a` `Ctrl+a` to send literal Ctrl+a to the shell.

### Session

| Key | Action |
|-----|--------|
| `prefix + C-s` | Save session |
| `prefix + C-r` | Restore session |
| `prefix + g` | Switch to session (prompt) |
| `prefix + s` | Choose session from list |
| `prefix + S` | Switch to last session |
| `prefix + (` | Previous session |
| `prefix + )` | Next session |
| `prefix + C` | Create session by name |
| `prefix + X` | Kill current session |
| `prefix + @` | Promote pane to new session |
| `prefix + C-Space` | Promote window to new session |
| `prefix + t` | Join pane into current window |
| `prefix + $` | Rename session |

### Window (tab)

| Key | Action |
|-----|--------|
| `prefix + c` | Create window |
| `prefix + w` | Choose window from list |
| `prefix + f` | Find window |
| `prefix + 1~9` | Switch to window 1-9 |
| `prefix + n` / `C-n` | Next window |
| `prefix + p` / `C-p` | Previous window |
| `prefix + a` | Last window |
| `prefix + Tab` | Last window |
| `prefix + ,` | Rename window |
| `prefix + &` | Kill window |
| `prefix + <` | Move window left |
| `prefix + >` | Move window right |

### Pane (split)

| Key | Action |
|-----|--------|
| `prefix + \|` | Split vertically |
| `prefix + \` | Split vertically (full width) |
| `prefix + -` | Split horizontally |
| `prefix + _` | Split horizontally (full height) |
| `prefix + h` / `C-h` | Left pane |
| `prefix + j` / `C-j` | Down pane |
| `prefix + k` / `C-k` | Up pane |
| `prefix + l` / `C-l` | Right pane |
| `prefix + ;` | Last pane |
| `prefix + o` | Next pane |
| `prefix + x` | Kill pane |
| `prefix + z` | Toggle zoom |
| `prefix + {` / `}` | Swap pane position |
| `prefix + E` | Toggle synchronize-panes |
| `prefix + q` | Display pane numbers |
| `prefix + H/J/K/L` | Resize pane 5 cells |
| `prefix + !` | Move pane to new window |
| `prefix + m` | Mark pane |

### Copy mode (vi-style)

Enter with `prefix + [`.

| Key | Action |
|-----|--------|
| `h/j/k/l` | Cursor movement |
| `w/b` | Next/previous word |
| `H` | Start of line |
| `L` | End of line |
| `0` | Start of line (alt) |
| `^` | Back to indentation |
| `$` | End of line (alt) |
| `gg` / `G` | Top/bottom of buffer |
| `C-f` / `C-b` | Page down/up |
| `C-d` / `C-u` | Half page down/up |
| `J` / `K` | Scroll down/up |
| `v` | Begin selection (character) |
| `V` | Select line |
| `C-v` | Rectangle selection (begin) |
| `y` | Copy to clipboard |
| `Y` | Copy to tmux buffer (put) |
| `M-y` | Yank and put (copy + paste) |
| `Esc` / `q` | Cancel/exit |
| `/` / `?` | Search forward/backward |
| `n` / `N` | Next/previous match |
| `f` / `F` | Jump forward/backward |
| `t` / `T` | Jump to forward/backward |
| `{` / `}` | Previous/next paragraph |
| `%` | Matching bracket |
| `o` | Open selection with system handler |
| `C-o` | Open selection in \$EDITOR |

### Search

| Key | Action |
|-----|--------|
| `prefix + /` | Regex search |
| `prefix + C-f` | File search |
| `prefix + C-u` | URL search |
| `prefix + M-h` | SHA-1 hash search |
| `prefix + C-g` | Git status file search |
| `prefix + C-d` | Number search |
| `prefix + M-i` | IP address search |
| `n` / `N` | Next/previous match (copy mode) |

### Logging

| Key | Action |
|-----|--------|
| `prefix + P` | Toggle logging |
| `prefix + M-p` | Save visible text |
| `prefix + M-P` | Save complete history |
| `prefix + M-c` | Clear pane history |

### TPM (plugin manager)

| Key | Action |
|-----|--------|
| `prefix + I` | Install plugins |
| `prefix + U` | Update plugins |
| `prefix + M-u` | Uninstall unused plugins |

### Other

| Key | Action |
|-----|--------|
| `prefix + F` | Fingers hint mode (copy text with hints) |
| `prefix + J` | Fingers jump mode (jump to hint) |
| `prefix + Q` | fzf menu (session/window/pane/commands/keybindings) |
| `prefix + O` | tmux-scout AI agent session picker (fzf) |
| `prefix + =` | Clipboard buffer history |
| `prefix + R` | Reload config |
| `prefix + ?` | List keybindings |
| `prefix + :` | Command mode |
| `prefix + y` | Copy command line to clipboard |
| `prefix + Y` | Copy pane CWD to clipboard |
| `prefix + d` | Detach client |
| `prefix + D` | Choose client to detach |

## Configuration

Edit `~/.tmux.conf`. After changes, reload with `prefix + R`.

### Disable auto-start

Remove or comment out `tmux-continuum` from the plugin list.
