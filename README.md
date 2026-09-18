# monkey-tmux

A tmux configuration focused on functional completeness, performance, Vim-like keybindings, and TTY compatibility.

## Screenshot

![tmux](pictures/tmux.png "tmux")

## Features

- **Session persistence**: auto-save/restore via `tmux-resurrect` + `tmux-continuum`
- **Vim-style copy mode**: `v/V/C-v` for selection, `H/L` for line nav, `h/j/k/l` for movement
- **Fuzz copy**: `tmux-fingers` provides vimium-style hint-based copy/paste
- **Fuzzy completion**: `extrakto` grabs text from pane scrollback into an fzf popup (insert/copy/open/edit/filter)
- **URL picker**: `prefix + u` fzf-picks URLs in the pane and opens them (`tmux-fzf-url`)
- **Pane/window management**: standard keybindings + `tmux-pain-control` + `tmux-sessionist`
- **fzf integration**: prefix+Q for fuzzy session/window/pane/command/keybinding search
- **Clipboard**: `tmux-yank` for system clipboard, `tmux-open` for opening files/urls
- **Logging**: `tmux-logging` for saving pane output
- **Status bar**: custom Sonokai andromeda theme with session, hostname, time, battery
- **Automatic window naming**: tabs show `index.name`, where `name` is `process:directory` (basename), `process:~` in home, or `ssh` for remote sessions
- **AI agent monitoring**: `tmux-scout` status widget + fzf picker for tracking AI coding agent sessions
- **AI session persistence**: `tmux-assistant-resurrect` restores AI coding assistant sessions (Claude Code, OpenCode, etc.) across tmux restarts
- **Mouse support**: native tmux mouse (`set -g mouse on`)
- **Modal indicator**: mode indicator (prefix/copy/normal) in status bar
- **TTY-safe**: no powerline glyphs, pure block separators, works in any terminal

## Requirements

- tmux >= 3.2
- [fzf](https://github.com/junegunn/fzf) >= 0.51 (required for `tmux-fzf`, `tmux-scout`, `extrakto`, `tmux-fzf-url`)
- [python3](https://www.python.org/) (required for `extrakto`)
- [Node.js](https://nodejs.org/) >= 16 (required for `tmux-scout`)
- [jq](https://jqlang.github.io/jq/) (required for `tmux-assistant-resurrect`)
- xclip, xsel (X11) or [wl-clipboard](https://github.com/bugaevc/wl-clipboard) (Wayland, for clipboard)

`tmux-fzf-url` self-installs its bundled `xre` binary on first use (needs `curl`).

### Install dependencies

```bash
# Ubuntu/Debian
sudo apt-get install fzf python3 debianutils

# OpenSUSE
sudo zypper install fzf python3 which

# CentOS (enable EPEL first)
sudo dnf install epel-release
sudo dnf install fzf python3 which

# Arch Linux
sudo pacman -S fzf python3 which

# macOS
brew install fzf python3 which
```

## Installation

Pick one of the two ways below: a one-click script, or manual setup.

### Option 1: One-click install

Install tmux (system package when possible, built from source only if the distro version is too old or known-broken), all dependencies, and the plugin set automatically:

```bash
curl -fsSL https://raw.githubusercontent.com/QMonkey/monkey-tmux/master/install.sh | bash
```

What the script does, step by step:

1. Install tmux — the system package is preferred (tmux >= 3.2 is all the config needs); if the distro version is too old or a known-bad release (3.7b crashes on session exit), tmux master is built from source into `/usr/local`
2. Pre-authorize `sudo` once — the only password entry of the whole run — and install a **temporary** NOPASSWD sudoers drop-in for the invoking user, removed automatically on exit. Homebrew resets the sudo timestamp on every `brew` invocation and WSL2 clock jumps invalidate tickets; NOPASSWD makes the run immune to both in any command order. If the drop-in cannot be installed, the script falls back to a background keepalive plus lazy re-authentication
3. Install Homebrew (Linuxbrew) as the fallback package manager — its shellenv is persisted to your shell rc files (with PATH dedup guards) even when Homebrew already existed
4. Install `fzf` via Homebrew (tmux-scout needs >= 0.51; distro packages lag far behind)
5. Clone monkey-tmux to `~/Documents/monkey-tmux` (or update it if already cloned)
6. Install the remaining dependencies (git, which, node, jq, python3, xclip) via `checkhealth.sh --install`; WSL Windows-PATH shims (`/mnt/...`) are detected and the real Linux packages get installed instead
7. Symlink `~/.tmux.conf` to the repo, clone TPM, and clone every plugin listed in `.tmux.conf` — no need to press `prefix + I`
8. Add the auto-start block to your shell profiles — every interactive non-tmux shell execs into the `main` session (see [Disable auto-start](#disable-auto-start))

> The script keeps the tmux source tree at `~/Documents/tmux` only when the fallback build was used. Once your distro ships a fixed/current tmux, remove `/usr/local/bin/tmux` to fall back to the system package.
>
> WSL note: the config yanks through Windows' `clip.exe` on purpose — it is the one "Windows shim" the scripts treat as a first-class tool.

### Option 2: Manual installation

```bash
git clone https://github.com/QMonkey/monkey-tmux.git ~/monkey-tmux
ln -sfn $(pwd)/.tmux.conf ~/.tmux.conf
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

`tmux-scout` shows a `W|B|D` counter in `status-right` summarizing all
tracked AI agent sessions. The letters are session counts, not raw statuses:

| Letter | Meaning                                             | Color                   |
| ------ | --------------------------------------------------- | ----------------------- |
| `W`    | waiting for your input (approval / question / plan) | `@thm_red` `#fb617e`    |
| `B`    | busy — agent is running a prompt or tool            | `@thm_orange` `#f89860` |
| `D`    | done — latest turn completed                        | `@thm_green` `#9ed06c`  |

Separators use `@thm_muted` `#7e8294`. Colors are defined via `set -gF` with
`#{@thm_*}` references, so they track the theme palette automatically.

The `I` (idle) placeholder is intentionally omitted: it is an internal
tmux-scout placeholder for process-only-discovered sessions that never reaches
the picker, so only `W`, `B`, and `D` are shown.

The segment is clickable (opens the picker) but has no underline hint; the
underline was disabled via `@scout-status-click-style off`. Open the full
picker with `prefix + O`.

### Window naming

Tabs are named automatically (`automatic-rename on` + custom
`automatic-rename-format`) and displayed as `index.name`:

- normal: `process:directory` (directory is the basename of the active pane's
  working directory, e.g. `zsh:monkey-tmux`)
- in `$HOME`: `process:~` (e.g. `zsh:~`)
- over SSH: `ssh` (the local working directory would be misleading)

Names refresh when the foreground process changes — after `cd`, the tab
updates when you run the next command. `set-titles-string` uses the same
format, so the terminal window title matches the tab.

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

| Section                      | Color                         |
| ---------------------------- | ----------------------------- |
| status bar background        | `@thm_status_bg`              |
| mode / active-tab / hostname | `@thm_cyan`                   |
| session                      | `@thm_blue`                   |
| inactive tab                 | `@thm_muted`                  |
| time + date                  | `@thm_coal`                   |
| battery                      | `@thm_slate`                  |
| free / attention             | `@thm_orange` / `@thm_purple` |

The battery block is shown only when a real battery is present. On Linux it
checks `/sys/class/power_supply/*/type` for a `Battery` entry (a bare dir check
isn't enough — desktops have `Mains`/`USB` supplies); on macOS it requires
`pmset -g batt` to report `present: true` (so desktop Macs never show a bogus
`BAT:0%`). Other platforms let the plugin try. The gate is the `@battery_enabled`
option set via `if-shell` in `.tmux.conf`.
| bell / reject | `@thm_red` |

The palette is truecolor hex by default; on a bare Linux TTY
(`TERM=linux`) it falls back to the fixed 16-color VGA palette via the `%if`
block in `.tmux.conf`. Block-style separators only — no powerline glyphs,
works in any terminal.

To change the theme, edit the `@thm_*` values in `.tmux.conf`.

## Keyboard shortcuts

Prefix is `Ctrl+a`. Use `Ctrl+a` `Ctrl+a` to send literal Ctrl+a to the shell.

### Session

| Key                | Action                        |
| ------------------ | ----------------------------- |
| `prefix + C-s`     | Save session                  |
| `prefix + C-r`     | Restore session               |
| `prefix + g`       | Switch to session (prompt)    |
| `prefix + s`       | Choose session from list      |
| `prefix + S`       | Switch to last session        |
| `prefix + (`       | Previous session              |
| `prefix + )`       | Next session                  |
| `prefix + C`       | Create session by name        |
| `prefix + X`       | Kill current session          |
| `prefix + @`       | Promote pane to new session   |
| `prefix + C-Space` | Promote window to new session |
| `prefix + t`       | Join pane into current window |
| `prefix + $`       | Rename session                |

### Window (tab)

| Key                  | Action                  |
| -------------------- | ----------------------- |
| `prefix + c`         | Create window           |
| `prefix + w`         | Choose window from list |
| `prefix + f`         | Find window             |
| `prefix + 1~9`       | Switch to window 1-9    |
| `prefix + n` / `C-n` | Next window             |
| `prefix + p` / `C-p` | Previous window         |
| `prefix + a`         | Last window             |
| `prefix + Tab`       | Last window             |
| `prefix + ,`         | Rename window           |
| `prefix + &`         | Kill window             |
| `prefix + <`         | Move window left        |
| `prefix + >`         | Move window right       |

### Pane (split)

| Key                  | Action                           |
| -------------------- | -------------------------------- |
| `prefix + \|`        | Split vertically                 |
| `prefix + \`         | Split vertically (full width)    |
| `prefix + -`         | Split horizontally               |
| `prefix + _`         | Split horizontally (full height) |
| `prefix + h` / `C-h` | Left pane                        |
| `prefix + j` / `C-j` | Down pane                        |
| `prefix + k` / `C-k` | Up pane                          |
| `prefix + l` / `C-l` | Right pane                       |
| `prefix + ;`         | Last pane                        |
| `prefix + o`         | Next pane                        |
| `prefix + x`         | Kill pane                        |
| `prefix + z`         | Toggle zoom                      |
| `prefix + {` / `}`   | Swap pane position               |
| `prefix + E`         | Toggle synchronize-panes         |
| `prefix + q`         | Display pane numbers             |
| `prefix + H/J/K/L`   | Resize pane 5 cells              |
| `prefix + !`         | Move pane to new window          |
| `prefix + m`         | Mark pane                        |

### Copy mode (vi-style)

Enter with `prefix + [`.

| Key           | Action                                        |
| ------------- | --------------------------------------------- |
| `h/j/k/l`     | Cursor movement                               |
| `w/b`         | Next/previous word                            |
| `H`           | Start of line                                 |
| `L`           | End of line                                   |
| `0`           | Start of line (alt)                           |
| `^`           | Back to indentation                           |
| `$`           | End of line (alt)                             |
| `gg` / `G`    | Top/bottom of buffer                          |
| `C-f` / `C-b` | Page down/up                                  |
| `C-d` / `C-u` | Half page down/up                             |
| `J` / `K`     | Scroll down/up                                |
| `v`           | Begin selection (character)                   |
| `V`           | Select line                                   |
| `C-v`         | Rectangle selection (begin)                   |
| `y`           | Copy to clipboard                             |
| `Y`           | Copy to tmux buffer (put)                     |
| `M-y`         | Yank and put (copy + paste)                   |
| `Esc` / `q`   | Cancel/exit                                   |
| `/` / `?`     | Search forward/backward (regex)               |
| `n` / `N`     | Next/previous match                           |
| `*` / `#`     | Search forward/backward for word under cursor |
| `f` / `F`     | Jump forward/backward                         |
| `t` / `T`     | Jump to forward/backward                      |
| `{` / `}`     | Previous/next paragraph                       |
| `%`           | Matching bracket                              |
| `o`           | Open selection with system handler            |
| `C-o`         | Open selection in \$EDITOR                    |

### Search (native regex)

tmux >= 3.1 has built-in regex search — `tmux-copycat` is no longer needed.

| Key          | Action                                             |
| ------------ | -------------------------------------------------- |
| `prefix + /` | Enter copy mode and start a regex search (forward) |
| `/` / `?`    | Search forward/backward (inside copy mode)         |
| `n` / `N`    | Next/previous match                                |
| `*` / `#`    | Search for word under cursor                       |

`prefix + /` is bound to `copy-mode` + `search-forward` in `.tmux.conf`,
replacing `tmux-copycat`'s `prefix + /`.

### Logging

| Key            | Action                |
| -------------- | --------------------- |
| `prefix + P`   | Toggle logging        |
| `prefix + M-p` | Save visible text     |
| `prefix + M-P` | Save complete history |
| `prefix + M-c` | Clear pane history    |

### TPM (plugin manager)

| Key            | Action                   |
| -------------- | ------------------------ |
| `prefix + I`   | Install plugins          |
| `prefix + U`   | Update plugins           |
| `prefix + M-u` | Uninstall unused plugins |

### Fingers (hint-based copy / jump)

`tmux-fingers` highlights matches (words, paths, hashes, etc.) with letter
hints; press the hint letters to act on a match.

| Key                 | Action                                                |
| ------------------- | ----------------------------------------------------- |
| `prefix + F`        | Hint mode: select a match to copy it to the clipboard |
| `prefix + T`        | Jump mode: select a match to move the cursor to it    |
| `TAB`               | Toggle multi mode (select multiple matches)           |
| `q` / `Esc` / `C-c` | Exit fingers mode                                     |

`prefix + T` (jump mode) is bound to `T` — not the upstream default `J` — to
keep `prefix + J` free for pain-control's resize-down and `prefix + t` for
sessionist's join-pane.

### Extrakto (fuzzy completion from scrollback)

`prefix + G` opens an fzf popup with text grabbed from the current pane. Pick
a completion to insert it into the command line, or use the popup keys shown
in the fzf header (`i` insert, `c` copy, `o` open, `e` edit, `f` filter,
`g` re-grab, `h` help) to act on the grabbed text.

| Key          | Action                                      |
| ------------ | ------------------------------------------- |
| `prefix + G` | Grab pane text (screen or history) into fzf |

Bound to `G` instead of upstream's default `Tab`, which would clash with
`prefix + Tab` (last-window).

### URL picker (tmux-fzf-url)

| Key          | Action                                            |
| ------------ | ------------------------------------------------- |
| `prefix + u` | fzf over URLs in the pane; Enter opens them       |
| `ctrl-y`     | In the picker, copy the selected URL to clipboard |

On first use the plugin installs its `xre` binary automatically (`curl` is
required once).

### Other

| Key          | Action                                              |
| ------------ | --------------------------------------------------- |
| `prefix + Q` | fzf menu (session/window/pane/commands/keybindings) |
| `prefix + O` | tmux-scout AI agent session picker (fzf)            |
| `prefix + =` | Clipboard buffer history                            |
| `prefix + R` | Reload config                                       |
| `prefix + ?` | List keybindings                                    |
| `prefix + :` | Command prompt (tmux commands)                      |
| `prefix + y` | Copy command line to clipboard                      |
| `prefix + Y` | Copy pane CWD to clipboard                          |
| `prefix + d` | Detach client                                       |
| `prefix + D` | Choose client to detach                             |

### Command prompt key bindings

The `prefix + :` prompt (a single-line command editor) uses **emacs** keys
(`status-keys emacs`); copy mode uses **vi** keys (`mode-keys vi`).

| Key           | Action                               |
| ------------- | ------------------------------------ |
| `Up` / `Down` | Previous / next command from history |
| `C-a` / `C-e` | Start / end of line                  |
| `C-k`         | Delete to end of line                |
| `C-u`         | Delete entire line                   |
| `M-f` / `M-b` | Forward / backward one word          |
| `Tab`         | Completion                           |
| `C-y`         | Insert top paste buffer              |
| `Esc`         | Cancel                               |

## Configuration

Edit `~/.tmux.conf`. After changes, reload with `prefix + R`.

### Disable auto-start

Remove or comment out `tmux-continuum` from the plugin list.

## Troubleshooting

### WSL: `'... clip.exe' returned 2` / `run-detectors` errors

On WSL2 several plugins shell out to Windows binaries: `tmux-yank` pipes yanks
to `clip.exe`, `extrakto` copies via `tmux show-buffer|clip.exe`, and
`tmux-fzf-url` opens URLs via `explorer.exe`. All of these rely on WSL
interop: the kernel's `binfmt_misc` `WSLInterop` entry matches PE executables
(magic `MZ`) and delegates them to `/init`, which forwards execution to the
Windows host.

When that entry goes stale (typically after a WSL kernel or `/init` update),
every `.exe` fails with `run-detectors: unable to find an interpreter` and
exit code 2, surfacing in tmux as e.g. `'tmux show-buffer|clip.exe' returned 2`.

Fix (no WSL restart needed) — re-register the binfmt entry against the
current kernel:

```sh
sudo sh -c 'echo -1 > /proc/sys/fs/binfmt_misc/WSLInterop && echo ":WSLInterop:M::MZ::/init:PF" > /proc/sys/fs/binfmt_misc/register'
cmd.exe /c "echo ok"   # verify
```

WSL re-registers the entry on every VM boot, so this does not need to be
redone after `wsl --shutdown` or a reboot. If the error reappears on every
boot, the kernel and `/init` are persistently out of sync — run `wsl --update`
on the Windows side.

### WSL: `tmux-fzf-url` reports `'... returned 1'` but the URL opens

This is harmless noise: with interop fixed, `explorer.exe` actually runs and
opens the URL, but it notoriously exits with code 1 even on success (it
delegates to the running instance). The plugin passes that exit code through.
No action needed; to silence it, wrap the opener so exit codes `0`/`1` are
treated as success and point `@fzf-url-open` at the wrapper.
