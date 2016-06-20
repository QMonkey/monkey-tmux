# monkey-tmux

Read this in other languages: [简体中文](README.zh-CN.md)

## Introduction

monkey-tmux

## Screenshot

- **tmux**

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
mkdir -p ~/.tmux/plugins
cd ~/.tmux/plugins
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
```

### 2. Pane (Split)

```
prefix+|        Split current pane horizontally
prefix+-        Split current pane vertically

prefix+h/C-h    Select left pane
prefix+j/C-j    Select below pane
prefix+k/C-k    Select above pane
prefix+l/C-l    Select right pane

prefix+H        Resize current pane 5 cells to the left
prefix+J        Resize current pane 5 cells in the up direction
prefix+K        Resize current pane 5 cells in the down direction
prefix+L        Resize current pane 5 cells to the right
```

### 3. Window (Tab)

```
prefix+n/C-n    Switch to next window
prefix+p/C-p    Switch to previous window

prefix+<        Moves current window one position to the left
prefix+>        Moves current window one position to the right
```

### n. Search

```
prefix+/        Regex search
prefix+Ctrl-f   Simple file search
prefix+Ctrl-u   Url search (http, ftp and git urls)
prefix+Alt-h    Jumping over SHA-1 hashes (best used after git log command)
prefix+Ctrl-g   Jumping over git status files (best used after git status command)
prefix+Ctrl-d   Number search
prefix+Alt-i    Ip address search
```

### n. Copy mode

```
y           Copy selection to system clipboard
Y           Copy selection and paste it to the command line
n           Jumps to the next match
N           Jumps to the previous match
o           Open a highlighted selection with the system default program
Ctrl-o      Open a highlighted selection with the $EDITOR
```

### n. Plugin Manager

```
prefix+I        Installs new plugins and refreshes TMUX environment
prefix+U        Update plugins
prefix+alt+u    Uninstall plugins unused plugins
```

### n. Others

```
prefix+R    Source .tmux.conf

prefix+y    Copy text from the command line to clipboard
prefix+Y    Copy pane current working directory to clipboard
```

## FAQ

[FAQ](https://github.com/QMonkey/monkey-tmux/wiki/FAQ)

## Recommended settings

- In order to startup tmux,  add shell code below to your "~/.bashrc" file

```bash
# If not running interactively, do not do anything
[[ $- != *i* ]] && return
[[ -z "$TMUX" ]] && exec tmux -2
```

## Configuration

If you have any problem or suggestion with monkey-tmux, welcome to give me an [issue](https://github.com/QMonkey/monkey-tmux/issues)
