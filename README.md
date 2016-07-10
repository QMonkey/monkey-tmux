# monkey-tmux

Read this in other languages: [简体中文](README.zh-CN.md)

## Introduction

monkey-tmux

## Screenshot

![tmux](https://raw.githubusercontent.com/QMonkey/monkey-tmux/master/pictures/tmux.png "tmux")

## How to install

### 1. Git clone

```bash
git clone https://github.com/QMonkey/monkey-tmux.git
```

### 2. Install dependences

#### 2.1 Ubuntu

```bash
sudo apt-get install tmux
sudo apt-get install xclip or sudo apt-get install xsel
sudo pip install powerline-status
```

#### 2.2 OpenSUSE

```bash
sudo zypper install tmux
sudo zypper install xclip or sudo zypper install xsel
sudo pip install powerline-status
```

#### 2.3 CentOS

```bash
sudo yum install tmux
sudo yum install xclip or sudo yum install xsel
sudo pip install powerline-status
```

#### 2.4 Mac

```bash
brew install tmux
sudo pip install powerline-status

# Less than Mac OS X 10.10
brew install reattach-to-user-namespace or sudo port install tmux-pasteboard
```

#### 2.5 Fonts

- [powerline-font](https://github.com/powerline/fonts)

### 3. Install monkey-tmux

```bash
cd monkey-tmux
cp .tmux.conf ~/.tmux.conf
mkdir -p ~/.tmux
cd ~/.tmux
# Change '/usr/lib/python3.4/site-packages/powerline/' to your own powerline path
ln -s /usr/lib/python3.4/site-packages/powerline/ powerline
tmux
# Finally, press prefix+I to install plugins
```

## Keyboard shortcut

```
The "prefix" key below means "Ctrl+a".
```

### 1. Session

```
prefix+C-s      Save session
prefix+C-r      Restore session

prefix+g        Prompt for session name and switch to it
prefix+s        Choose a session from a list
prefix+S        Switches to the last session
prefix+(        Switch to previous session
prefix )        Switch to next session

prefix+C        Prompt for creating a new session by name
prefix+X        Kill current session without detaching tmux
prefix+@        Promote current pane into a new session
prefix+!        Move the current pane into a new separate window

prefix+$        Rename current session
```

### 2. Pane (Split)

```
prefix+|        Split current pane horizontally
prefix+-        Split current pane vertically

prefix+h/C-h    Go to the left pane
prefix+j/C-j    Go to the below pane
prefix+k/C-k    Go to the above pane
prefix+l/C-l    Go to the right pane
prefix+;        Go to the ‘last’ (previously used) pane

prefix+x        Kill current pane
prefix+z        Toggle pane zoom

prefix+{        Move the current pane to the previous position (depends on pane numbers)
prefix+}        Move the current pane to the next position (depends on pane numbers)
prefix+q        Display pane numbers

prefix+H        Resize current pane 5 cells to the left
prefix+J        Resize current pane 5 cells in the up direction
prefix+K        Resize current pane 5 cells in the down direction
prefix+L        Resize current pane 5 cells to the right
```

### 3. Window (Tab)

```
prefix+c        Create window
prefix+w        Choose a window from a list
prefix+f        Find window

prefix+1~9      Switch to window 1~9
prefix+n/C-n    Switch to next window
prefix+p/C-p    Switch to previous window

prefix+,        Rename current window
prefix+&        Kill current window

prefix+<        Moves current window one position to the left
prefix+>        Moves current window one position to the right
```

### 4. Search

```
prefix+/        Regex search
prefix+Ctrl-f   Simple file search
prefix+Ctrl-u   Url search (http, ftp and git urls)
prefix+Alt-h    Jumping over SHA-1 hashes (best used after git log command)
prefix+Ctrl-g   Jumping over git status files (best used after git status command)
prefix+Ctrl-d   Number search
prefix+Alt-i    Ip address search
```

### 5. Copy mode

```
prefix+[    Enter copy mode

y           Copy selection to system clipboard
Y           Copy selection and paste it to the command line
n           Jumps to the next match
N           Jumps to the previous match
o           Open a highlighted selection with the system default program
Ctrl-o      Open a highlighted selection with the $EDITOR

v/Space     Start selection
C-[/ESC     Clear selection
Enter       Copy selection

H           Cursor to top screen
M           Cursor to middle screen
L           Cursor to bottom screen

gg          Cursor to top line
G           Cursor to bottom line

0           Start of line
^           Back to indentation
$           End of line
:           Goto line

C-d         Half page down
C-u         Half page up
C-f         Next page
C-b         Previous page

j           Cursor down
k           Cursor up
h           Cursor left
l           Cursor right
J/C-Down    Scroll down
K/C-Up      Scroll up

w           Next word
b           Previous word

?           Search backward
/           Search forward
q           Quit mode
```

### 6. Plugin Manager

```
prefix+I        Installs new plugins and refreshes TMUX environment
prefix+U        Update plugins
prefix+alt+u    Uninstall plugins unused plugins
```

### 7. Others

```
prefix+R    Source .tmux.conf

prefix+y    Copy text from the command line to clipboard
prefix+Y    Copy pane current working directory to clipboard

prefix+?    Display a list of keyboard shortcuts in copy mode
prefix+:    Enter command mode
```

## FAQ

[FAQ](https://github.com/QMonkey/monkey-tmux/wiki/FAQ)

## Recommended settings

- In order to startup tmux,  add shell code below to your "~/.bashrc" file

```bash
# If not running interactively, do not do anything
[[ $- != *i* ]] && return

if [[ -z "$TMUX" ]]; then
    tmux has-session -t main 2>/dev/null
    if [[ "$?" -eq 0 ]]; then
        exec tmux -2 new-session
    else
        exec tmux -2 new-session -s main
    fi
fi
```

- Remap Caps Lock key to Ctrl

```bash
# Windows
# Please install keytweak

# Linux
# Please put this in the 10-caps2ctrl.conf file under /etc/X11/xorg.conf.d/
Section "InputClass"
        Identifier             "keyboard-layout"
        MatchIsKeyboard        "on"
        Option "XkbOptions"    "ctrl:nocaps"
EndSection

# Mac
# Go to System Preferences -> Keyboard -> Keyboard Tab -> Modifier Keys and select Control for Caps Lock
```

## Configuration

If you have any problem or suggestion with monkey-tmux, welcome to give me an [issue](https://github.com/QMonkey/monkey-tmux/issues)
