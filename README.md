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
- **Status bar**: tmux-power block theme with session, hostname, git branch, time, battery
- **Mouse support**: `tmux-better-mouse-mode` for responsive mouse
- **Modal indicator**: mode indicator (prefix/copy/normal) in status bar
- **TTY-safe**: no powerline glyphs, pure block separators, works in any terminal

## Requirements

- tmux >= 3.2
- [fzf](https://github.com/junegunn/fzf) (required for `tmux-fzf`)
- [gitmux](https://github.com/arl/gitmux) (required for git status in status bar)
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

### Install gitmux

```bash
# Requires Go 1.16+
go install github.com/arl/gitmux@latest
```

## Installation

```bash
git clone https://github.com/QMonkey/monkey-tmux.git ~/monkey-tmux
ln -sf $(pwd)/.tmux.conf ~/.tmux.conf
```

Config files are in `configs/` and are auto-linked on first tmux start:
- `configs/.gitmux.yml` → `~/.gitmux.yml` (git status in status bar)

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

## Auto-start tmux on shell login

Add to your `~/.bashrc` or `~/.zshrc`:

**First terminal restores, rest are independent**:

```bash
if [[ -z "$TMUX" ]] && command -v tmux >/dev/null; then
    if ! tmux has-session -t main 2>/dev/null; then
        exec tmux new-session -s main
    else
        exec tmux new-session
    fi
fi
```

The first terminal triggers continuum auto-restore; subsequent terminals
get independent sessions with default names (0, 1, 2…). Requires
`@continuum-restore 'on'` in `.tmux.conf`.

**Shared session** (recommended):

```bash
if [[ -z "$TMUX" ]] && command -v tmux >/dev/null; then
    if tmux has-session -t main 2>/dev/null; then
        exec tmux attach -t main
    else
        exec tmux new-session -s main
    fi
fi
```

All terminals attach to the same `main` session — windows and panes are
mirrored across terminals.

For a desktop-only setup (skip TTY):

```bash
if [[ -z "$TMUX" ]] && [[ -n "$DISPLAY" ]] && command -v tmux >/dev/null; then
    # use the shared session or continuum logic above
fi
```

`exec` replaces the shell process so `exit` closes the terminal directly.

## Theme

`tmux-power` with `snow` theme. Block-style separators (TTY-safe).

To change theme, modify `@tmux_power_theme` in `.tmux.conf`:
```tmux
set -g @tmux_power_theme 'everforest'  # also: moon, coral, gold, forest, violet, redwine, sky, snow
```

## Git status in status bar

gitmux config is bundled as `configs/.gitmux.yml` in the repo and auto-linked to `~/.gitmux.yml`.
Only visible when the current pane is inside a git repository.
Edit `~/.gitmux.yml` to customize.

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
