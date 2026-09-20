#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────────────────────
# monkey-tmux one-shot installer
# Usage: curl -fsSL https://raw.githubusercontent.com/QMonkey/monkey-tmux/master/install.sh | bash
# ──────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

INSTALL_DIR="${INSTALL_DIR:-$HOME/Documents/monkey-tmux}"
TMUX_SRC_DIR="${TMUX_SRC_DIR:-$HOME/Documents/tmux}"
JOBS="${JOBS:-$(nproc 2>/dev/null || echo 4)}"
SUDOERS_D_DIR="${SUDOERS_D_DIR:-/etc/sudoers.d}"
SUDO_NOPASSWD=0
NOPASSWD_DROPIN="$SUDOERS_D_DIR/zz-monkey-tmux-nopasswd"

# Never let a missing HOME fail later under `set -u`.
[ -n "${HOME:-}" ] || {
	echo "[FAIL] \$HOME is not set — cannot determine install locations." >&2
	exit 1
}

info() { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok() { echo -e "${GREEN}[  OK]${NC}  $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
fail() {
	echo -e "${RED}[FAIL]${NC}  $*"
	exit 1
}

# ────────────────── OS / WSL detection ──────────────────

os_detect() {
	case "$(uname -s)" in
	Linux)
		if [ -f /etc/os-release ]; then
			# shellcheck disable=SC1091
			. /etc/os-release
			case "${ID:-}" in
			ubuntu | debian | linuxmint | pop | elementary | zorin) echo "debian" ;;
			arch | manjaro | endeavouros) echo "arch" ;;
			opensuse* | suse | sles) echo "opensuse" ;;
			centos | rhel | fedora | rocky | almalinux | ol) echo "centos" ;;
			*) echo "linux-unknown" ;;
			esac
		else
			echo "linux-unknown"
		fi
		;;
	Darwin) echo "macos" ;;
	*) echo "unknown" ;;
	esac
}

# WSL interop appends the WINDOWS PATH to ours, so tools installed on the
# Windows side (node, python, sudo.exe, ...) appear as /mnt/c/... shims.
# They are not Linux binaries and root's secure_path cannot see them —
# treat /mnt/* resolutions as "not installed" so the real Linux packages
# get installed instead.
have_native_cmd() {
	command -v "$1" &>/dev/null || return 1
	case "$(command -v "$1")" in
	/mnt/*) return 1 ;; # WSL Windows-interop shim
	esac
	return 0
}

# Absolute path to a LINUX sudo, or non-zero.
native_sudo() {
	local p
	have_native_cmd sudo || return 1
	p=$(command -v sudo)
	printf '%s' "$p"
}

OS=$(os_detect)

# TIOCSTI injection right: a chaining wrapper may pre-set this to its
# own name — then THIS script must not inject. Standalone runs self-claim.
ACQUIRE_TIOCSTI="${ACQUIRE_TIOCSTI:-monkey-tmux}"

sudo_cmd() {
	# Lazy re-auth: Homebrew resets the sudo timestamp on EVERY invocation
	# (brew.sh runs `sudo --reset-timestamp` at startup), so a ticket that
	# was valid a minute ago can be dead here. Re-authenticate proactively
	# with an explanatory prompt instead of letting the command fail or
	# spring a context-free password prompt. `-n true` never prompts; the
	# interactive `-v` only runs when the ticket is actually gone.
	local sudo_bin
	sudo_bin=$(native_sudo) || {
		"$@"
		return
	}
	if ! "$sudo_bin" -n true 2>/dev/null; then
		"$sudo_bin" -v -p "[monkey-tmux] sudo credentials needed to continue — enter your password: " || return 1
	fi
	"$sudo_bin" "$@"
}

# ────────────────── TIOCSTI injection ──────────────────
# Type <cmd> + newline into the controlling terminal: the parent shell
# executes it as if the user had typed it — AFTER this script (and any
# wrapper chaining it) has fully exited, so injection can never disturb
# the run itself. Needs python3 or perl; any failure returns non-zero so
# callers can fall back to a printed hint. Never fatal.
inject_tty() {
	local cmd="$1" tiocsti
	[ -n "$cmd" ] || return 1
	# No writable controlling terminal (CI, nested pipes) — nothing to
	# inject into. access(W_OK) on /dev/tty fails with ENXIO when the
	# process has no controlling tty.
	[ -w /dev/tty ] || return 1
	# python3 first: termios.TIOCSTI carries the correct constant per
	# platform (Linux 0x5412, Darwin 0x80047412).
	if have_native_cmd python3; then
		python3 - "$cmd" <<'PYEOF' 2>/dev/null && return 0
import sys, os, fcntl, termios
cmd = sys.argv[1] + "\n"
try:
    fd = os.open("/dev/tty", os.O_WRONLY)
    ioctl = termios.TIOCSTI
except (OSError, AttributeError):
    sys.exit(1)
for ch in cmd:
    try:
        fcntl.ioctl(fd, ioctl, ord(ch))
    except OSError:
        sys.exit(1)
PYEOF
	fi
	# perl fallback: macOS ships /usr/bin/perl, Debian/Ubuntu perl-base is
	# Essential. TIOCSTI's value differs per platform.
	tiocsti=0x5412
	[ "$(uname -s)" = "Darwin" ] && tiocsti=0x80047412
	perl -e '
		my ($cmd, $tio) = @ARGV;
		open(my $tty, ">", "/dev/tty") or exit 1;
		for my $ch (split //, $cmd . "\n") {
			ioctl($tty, hex($tio), ord($ch)) or exit 1;
		}
	' "$cmd" "$tiocsti" 2>/dev/null && return 0
	return 1
}

# Print the shell startup files for the detected shell. Two cases:
#   - zsh: profile ONLY (~/.zprofile). rc files like ~/.zshrc are often
#     repo-managed dotfiles — appending to them dirties the repo; non-login
#     zsh shells get the profile via a `source ~/.zprofile` guard in the
#     rc file instead.
#   - bash: profile AND rc (~/.profile + ~/.bashrc). Non-login interactive
#     bash (WSL's wsl.exe, desktop terminal emulators, VS Code terminal)
#     only reads ~/.bashrc — .profile does not get pulled in there — so
#     both files are needed.
shell_env_files() {
	# The TARGET login shell, queried from the user database: on a
	# zsh-default machine (or after the login shell has been switched to
	# zsh) it is zsh and the env blocks belong in ~/.zprofile; on bash
	# machines they land in the bash profile files. Falls back to $SHELL,
	# then bash (macOS has no getent; its $SHELL already reflects the
	# login shell).
	local shell
	# getent does not exist on macOS — guard the call, otherwise the
	# command-not-found failure (127) would trip `set -e` and kill the
	# script before the dscl fallback below ever runs.
	if have_native_cmd getent; then
		shell=$(getent passwd "$(id -un)" 2>/dev/null | cut -d: -f7)
	fi
	if [ -z "$shell" ] && [ "$(uname -s)" = Darwin ]; then
		# No getent on macOS — query the directory service instead ($SHELL
		# is a login-time snapshot and goes stale right after a chsh in
		# the same session).
		shell=$(dscl . -read /Users/"$(id -un)" UserShell 2>/dev/null | awk '{print $2}')
	fi
	shell=${shell:-${SHELL:-bash}}
	shell=${shell##*/}
	shell="${shell##*/}"
	case "$shell" in
	zsh)
		printf '%s\n' "$HOME/.zprofile"
		;;
	bash)
		if [ -f "$HOME/.bash_profile" ]; then
			printf '%s\n' "$HOME/.bash_profile"
		else
			printf '%s\n' "$HOME/.profile"
		fi
		printf '%s\n' "$HOME/.bashrc"
		;;
	*)
		printf '%s\n' "$HOME/.profile"
		;;
	esac
}

append_env_block() {
	# Usage: append_env_block <marker> <block>
	# Appends <block> guarded by <marker> to every shell env file, once.
	local marker="$1"
	local block="$2"
	local f
	while IFS= read -r f; do
		[ -n "$f" ] || continue
		[ -f "$f" ] || touch "$f"
		if ! grep -qF -- "$marker" "$f" 2>/dev/null; then
			printf '\n# %s\n%b\n' "$marker" "$block" >>"$f"
			ok "Added '$marker' to $f"
		fi
	done < <(shell_env_files)
}

# ────────────────── sudo setup (auth + drop-ins + keepalive) ──────────────────

SUDO_KEEPALIVE_PID=""

cleanup_sudo() {
	# Kill the keepalive (if running) and remove the temporary NOPASSWD
	# drop-in. `sudo -n rm` works while NOPASSWD is still in place — the
	# file grants it, so removal never needs a password.
	if [ -n "$SUDO_KEEPALIVE_PID" ]; then
		kill "$SUDO_KEEPALIVE_PID" 2>/dev/null
		wait "$SUDO_KEEPALIVE_PID" 2>/dev/null
	fi
	if [ "$SUDO_NOPASSWD" -eq 1 ] && [ -n "$SUDO_BIN" ]; then
		"$SUDO_BIN" -n rm -f "$NOPASSWD_DROPIN" 2>/dev/null ||
			warn "could not remove the NOPASSWD drop-in — remove it manually: sudo rm $NOPASSWD_DROPIN"
	fi
}

setup_sudo() {
	# Keep sudo credentials alive for the whole run: the gap between the first
	# sudo (build deps) and later ones (make install) can exceed the default
	# 15-min timestamp_timeout on slow downloads/compiles. A re-auth prompt
	# then aborts unattended runs (no TTY to answer it).
	# Skip when running as root or when no native sudo is available.
	SUDO_BIN=$(native_sudo) || return 0
	if [ "$(id -u)" -eq 0 ]; then
		return 0
	fi
	# Pre-authenticate so the password is entered at the very start instead
	# of mid-run after a long download/compile, then grant NOPASSWD for the
	# rest of the run:
	#
	# Probe first (`-n true`, a command): when credentials are already
	# valid — this run's own drop-in from a previous stage, or an outer
	# installer's grant — skip the authenticate step entirely; chained
	# stages never re-prompt. Failure means no valid grant exists and
	# `sudo -v` prompts for the one password of the run.
	#
	# Why the drop-in is NOPASSWD: authentication is granted by the rule
	# itself and the timestamp is never consulted, so brew's
	# --reset-timestamp, clock jumps and plain expiry are all harmless.
	# GNU sudo resolves conflicting rules last-match-wins, so this drop-in
	# (parsed after the distro's password-required rule) always wins.
	# sudo-rs would defeat this tag for VALIDATE (max_by_key picks the
	# password-required rule) — but every sudo in this script is a command
	# or the probe, where NOPASSWD wins on both implementations.
	if ! "$SUDO_BIN" -n true 2>/dev/null; then
		"$SUDO_BIN" -v || fail "sudo authorization failed — run this script in an interactive terminal."
	fi
	# Scoped to the invoking user and REMOVED on exit (incl. Ctrl-C);
	# if the script is SIGKILLed the file survives — remove manually with
	# `sudo rm $NOPASSWD_DROPIN`. If you prefer a permanent passwordless
	# sudo, add the same line to your own sudoers drop-in instead.
	if printf '%s ALL=(ALL) NOPASSWD: ALL\n' "$(id -un)" |
		"$SUDO_BIN" -n sh -c 'umask 077; cat >"$1" && chmod 0440 "$1" && visudo -c -f "$1" >/dev/null 2>&1 || { rm -f "$1"; exit 1; }' sh "$NOPASSWD_DROPIN" >/dev/null 2>&1; then
		SUDO_NOPASSWD=1
		ok "Temporary NOPASSWD drop-in installed for this run (auto-removed on exit)."
	else
		warn "could not install the temporary NOPASSWD drop-in — falling back to keepalive + lazy re-auth."
	fi
	if [ "$SUDO_NOPASSWD" -eq 0 ]; then
		# Fallback when NOPASSWD could not be installed: refresh the ticket
		# in the background so plain expiry does not prompt mid-run. It
		# cannot fully protect the run — brew resets the ticket by design
		# and WSL clock steps disable it — so when this stops, sudo_cmd()
		# re-authenticates lazily (one explanatory prompt) at the next
		# privileged call.
		(
			# 60s refresh against the 15-min default timeout leaves a 15x
			# margin; override via SUDO_KEEPALIVE_INTERVAL if needed.
			interval="${SUDO_KEEPALIVE_INTERVAL:-60}"
			# Kill the in-flight `sleep` child when TERMed, and wait() to
			# reap — WSL's init does not reap adopted zombies.
			trap 'kill $(jobs -p) 2>/dev/null; wait 2>/dev/null; exit 0' TERM
			while true; do
				sleep "$interval" &
				wait "$!" 2>/dev/null || exit 0
				if ! "$SUDO_BIN" -n true 2>/dev/null; then
					warn "sudo keepalive stopped — expected after a brew run; the next privileged command re-authenticates."
					exit 0
				fi
			done
		) &
		SUDO_KEEPALIVE_PID=$!
	fi
	# Recycle the background loop and drop the NOPASSWD grant on any exit
	# path (success, fail, Ctrl-C).
	trap cleanup_sudo EXIT
	trap 'exit 130' INT
	trap 'exit 143' TERM
}

# ────────────────── Step 1: Install tmux ──────────────────

# ────────────────── package index refresh ──────────────────
# Refresh the package index before installing: a stale or missing index is
# the usual cause of "Unable to locate package" on freshly provisioned
# machines. Retried once for transient network failures; a failed refresh
# is never fatal — the install step still runs. Guarded to at most one
# refresh per run — call freely before every install.
PKG_DB_REFRESHED=0
refresh_pkg() {
	[ "$PKG_DB_REFRESHED" -eq 1 ] && return 0
	PKG_DB_REFRESHED=1
	local attempt
	for attempt in 1 2; do
		case "$OS" in
		debian) sudo_cmd apt-get update ;;
		arch) sudo_cmd pacman -Sy ;;
		opensuse) sudo_cmd zypper --non-interactive refresh ;;
		centos) sudo_cmd dnf makecache -q ;;
		macos | *) return 0 ;;
		esac && return 0
		[ "$attempt" -lt 2 ] && sleep 2
	done
	return 0
}

# System package manager install. Returns non-zero when the OS is unknown
# or the manager fails, so callers can fall back to other sources.
install_with_system_mgr() {
	refresh_pkg
	case "$OS" in
	debian) sudo_cmd apt-get install -y "$@" ;;
	arch) sudo_cmd pacman -S --noconfirm "$@" ;;
	opensuse) sudo_cmd zypper --non-interactive install -y "$@" ;;
	centos)
		sudo_cmd dnf install -y epel-release || true
		sudo_cmd dnf install -y "$@"
		;;
	macos) brew install "$@" ;;
	*) return 1 ;;
	esac
}

tmux_version() {
	# "tmux 3.7b" -> "3.7b"; also handles "tmux next-3.4".
	tmux -V 2>/dev/null | grep -oE '[0-9]+\.[0-9]+[a-z]*' | head -1
}

# tmux 3.7b: exiting a session crashes tmux instead of switching to the next
# one (fixed in 3.7c — e.g. Arch ships 3.7c unaffected). Remove this entry
# once no distro ships 3.7b anymore.
tmux_is_known_bad() {
	[[ "$1" == "3.7b" ]]
}

tmux_ok() {
	have_native_cmd tmux || return 1
	local ver
	ver=$(tmux_version)
	[[ -z "$ver" ]] && return 1
	tmux_is_known_bad "$ver" && return 1
	printf '%s\n%s\n' "3.2" "$ver" | sort -V -C
}

build_tmux_from_source() {
	info "Building tmux from source (master)..."
	case "$OS" in
	debian)
		# autoconf/automake: the master branch has no generated ./configure —
		# autogen.sh (which needs them) must run before configure.
		sudo_cmd apt-get install -y build-essential git curl libevent-dev ncurses-dev bison pkg-config autoconf automake
		;;
	arch)
		sudo_cmd pacman -S --needed --noconfirm base-devel libevent ncurses bison pkgconf
		;;
	opensuse)
		sudo_cmd zypper --non-interactive install -y gcc make git libevent-devel ncurses-devel bison pkg-config autoconf automake
		;;
	centos)
		sudo_cmd dnf install -y gcc make git curl libevent-devel ncurses-devel bison pkgconfig autoconf automake
		;;
	macos)
		brew install libevent ncurses pkg-config autoconf automake
		;;
	esac
	if [ -d "$TMUX_SRC_DIR/.git" ]; then
		info "tmux source already exists at $TMUX_SRC_DIR — pulling latest..."
		git -C "$TMUX_SRC_DIR" pull --ff-only || warn "git pull failed — building from existing source."
	else
		git clone https://github.com/tmux/tmux.git "$TMUX_SRC_DIR"
	fi

	pushd "$TMUX_SRC_DIR" >/dev/null
	info "Compiling tmux (master) with ${JOBS} jobs..."
	# The master branch does not ship a generated ./configure — autogen.sh
	# produces it (needs autoconf + automake, installed above).
	if [ ! -f ./configure ]; then
		sh ./autogen.sh 2>&1 | tee /tmp/tmux-autogen.log || {
			fail "tmux autogen.sh failed. Check /tmp/tmux-autogen.log"
		}
	fi
	./configure 2>&1 | tee /tmp/tmux-configure.log || {
		fail "tmux configure failed. Check /tmp/tmux-configure.log"
	}
	make -j"$JOBS" 2>&1 | tee /tmp/tmux-build.log || {
		fail "tmux build failed. Check /tmp/tmux-build.log"
	}
	info "Installing tmux..."
	sudo_cmd make install 2>&1 | tee /tmp/tmux-install.log || {
		fail "tmux install failed. Check /tmp/tmux-install.log"
	}
	popd >/dev/null

	export PATH="/usr/local/bin:$PATH"
	hash -r
}

# ────────────────── Step 0: Ensure git ──────────────────

ensure_git() {
	# git is needed BEFORE checkhealth.sh --install gets a chance to install
	# it: the Homebrew installer clones the brew repository, and this script
	# clones monkey-tmux, the tmux source and the TPM plugins — all of it
	# happens earlier in the chain.
	if ! have_native_cmd git; then
		info "Installing git..."
		install_with_system_mgr git
		hash -r
	fi
	have_native_cmd git || fail "git installation failed — install it manually (e.g. sudo apt-get install git)."
}

# ────────────────── Step 1: Install tmux ──────────────────

install_tmux() {
	# openSUSE splits the terminfo database: terminfo-base is minimal and
	# terminfo-screen carries only screen.* aliases — NO tmux entries in
	# either (verified against the Leap 16 / Tumbleweed RPM contents).
	# Without the full terminfo package, every shell inside tmux hits
	# "tset: unknown terminal type tmux-256color".
	if [ "$OS" = opensuse ]; then
		install_with_system_mgr terminfo ||
			warn "could not install terminfo — tmux may report an unknown terminal type (tmux-256color)."
	fi
	if tmux_ok; then
		ok "tmux $(tmux_version) already installed and meets requirement (>= 3.2, no known-bad release)."
		return 0
	fi
	# Modern distros ship tmux >= 3.2 — the system package is preferred
	# (security updates, no compiler toolchain needed). The source build
	# only kicks in for old distros (e.g. CentOS 7 ships 1.8) or known-bad
	# releases (e.g. openSUSE Tumbleweed's 3.7b), and builds tmux MASTER.
	info "Installing tmux via the system package manager..."
	install_with_system_mgr tmux || warn "system package manager failed — will try building from source."
	hash -r
	if tmux_ok; then
		ok "tmux $(tmux_version) installed."
		return 0
	fi
	build_tmux_from_source
	if tmux_ok; then
		ok "tmux $(tmux_version) built and installed successfully."
	else
		fail "tmux installation completed but tmux is still missing or below requirement."
	fi
}

# ────────────────── Step 2: Install Homebrew / Linuxbrew ──────────────────

install_linuxbrew() {
	local brew_prefix="" cand
	if have_native_cmd brew; then
		brew_prefix="$(dirname "$(dirname "$(command -v brew)")")"
		ok "Homebrew already installed at $brew_prefix."
	else
		# brew may exist at a standard prefix without being on PATH — an
		# earlier monkey-* component installed it and this process did not
		# inherit the profile. Adopt it instead of re-downloading.
		for cand in /home/linuxbrew/.linuxbrew /opt/homebrew /usr/local; do
			if [ -x "$cand/bin/brew" ]; then
				brew_prefix="$cand"
				ok "Homebrew found at $brew_prefix (not on PATH — adopting)."
				break
			fi
		done
	fi
	if [ -z "$brew_prefix" ]; then
		info "Installing Homebrew/Linuxbrew..."
		# NOTE: the installer's exit trap runs `sudo -k` (and the `brew`
		# commands it spawns reset the timestamp too) — that used to require
		# sed-patching the installer, but the temporary NOPASSWD drop-in
		# makes the timestamp irrelevant, so the official installer runs
		# unmodified. If the NOPASSWD drop-in failed to install, the next
		# privileged command simply re-authenticates once (sudo_cmd).
		# Download fully before executing: `curl | bash` would run a
		# truncated script if the connection drops mid-stream.
		local installer="/tmp/homebrew_install.$$.sh"
		local fetched=0 attempt
		# `curl -fsSL -o` is silent: on a slow network the download (and its
		# retries) would look like a hang without this line.
		info "Downloading the Homebrew installer..."
		for attempt in 1 2 3; do
			if curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh -o "$installer"; then
				fetched=1
				break
			fi
			sleep 2
		done
		if [ "$fetched" != 1 ]; then
			warn "Homebrew installer download failed — continuing without Homebrew."
			return 0
		fi
		NONINTERACTIVE=1 /bin/bash "$installer" ||
			warn "Homebrew installer failed — continuing without Homebrew."
		rm -f "$installer"

		for cand in /home/linuxbrew/.linuxbrew /opt/homebrew /usr/local; do
			if [ -x "$cand/bin/brew" ]; then
				brew_prefix="$cand"
				break
			fi
		done
	fi

	if [ -n "$brew_prefix" ]; then
		eval "$("$brew_prefix/bin/brew" shellenv)"
		ok "Homebrew/Linuxbrew ready at $brew_prefix."
		# Persist shellenv for future shells (login + interactive rc).
		# Runs even when brew pre-dates this run: without it, brew-installed
		# tools (node/npm/...) vanish from PATH in new shells. Idempotent —
		# append_env_block skips if the marker is already present.
		# The case guard makes re-sourcing (e.g. a login .profile sourcing
		# .bashrc, both carrying this block) a no-op instead of prepending
		# brew's bin/sbin to PATH twice.
		local line
		line="case \":\$PATH:\" in *\":${brew_prefix}/bin:\"*) ;; *) eval \"\$(${brew_prefix}/bin/brew shellenv)\" ;; esac"
		append_env_block "Homebrew shellenv" "$line"
	else
		warn "brew not found — continuing without Homebrew."
	fi
}

# ────────────────── Step 3: Install fzf via Homebrew ──────────────────

install_fzf() {
	# tmux-scout needs fzf >= 0.51; distro packages lag far behind (Ubuntu
	# noble ships 0.44). Homebrew's fzf is current — install it BEFORE
	# checkhealth.sh --install runs, so fzf never counts as "missing" there.
	have_native_cmd fzf && return 0
	if ! have_native_cmd brew; then
		warn "Homebrew not found — fzf will come from the distro (may be < 0.51, tmux-scout needs >= 0.51)."
		return 0
	fi
	info "Installing fzf via Homebrew (distro versions lag behind)..."
	brew install fzf || warn "brew install fzf failed — checkhealth.sh will try the system package manager."
	hash -r
}

# ────────────────── Step 4: Clone monkey-tmux ──────────────────

clone_monkey_tmux() {
	if [ -d "$INSTALL_DIR/.git" ]; then
		info "monkey-tmux already exists at $INSTALL_DIR — pulling latest..."
		git -C "$INSTALL_DIR" pull --ff-only || warn "git pull failed — keeping existing version."
	else
		info "Cloning monkey-tmux to $INSTALL_DIR..."
		git clone https://github.com/QMonkey/monkey-tmux.git "$INSTALL_DIR"
	fi
	ok "monkey-tmux ready at $INSTALL_DIR."
}

# ────────────────── Step 5: Run checkhealth.sh --install ──────────────────

run_checkhealth() {
	# PATH preseed before detection: checkhealth runs as a subprocess and
	# only inherits the current shell's env. persist_path writes the
	# go/bin & cargo/bin blocks to the profile LATER in main, so on a
	# first run freshly go/cargo-installed binaries would be reported
	# missing and re-installed by the retry loop. Export only — nothing
	# is written to any profile here.
	case ":$PATH:" in *":$HOME/go/bin:"*) ;; *) export PATH="$HOME/go/bin:$PATH" ;; esac
	case ":$PATH:" in *":$HOME/.cargo/bin:"*) ;; *) export PATH="$HOME/.cargo/bin:$PATH" ;; esac
	info "Running checkhealth.sh --install to install remaining dependencies..."
	# --install checks first and installs after; transient failures
	# (network blips, apt locks, aborted downloads) heal on retry. After
	# the first pass everything installed is skipped, so retries are
	# cheap verifications. Three attempts, exit code 0 wins.
	local attempt ok=0
	for attempt in 1 2 3; do
		if bash "$INSTALL_DIR/checkhealth.sh" --install --skip-check-config; then
			ok=1
			break
		fi
		if [ "$attempt" -lt 3 ]; then
			warn "checkhealth attempt $attempt/3 failed — retrying..."
			sleep 2
		fi
	done
	if [ "$ok" = 1 ]; then
		ok "Dependency check complete."
	else
		warn "Some dependencies could not be installed automatically."
		warn "Run 'cd $INSTALL_DIR && ./checkhealth.sh' to review remaining items."
	fi
}

# ────────────────── Step 6: Symlink config & install TPM + plugins ──────────────────

setup_symlinks() {
	info "Setting up configuration symlinks..."
	ln -sf "$INSTALL_DIR/.tmux.conf" "$HOME/.tmux.conf"
	ok ".tmux.conf → $INSTALL_DIR/.tmux.conf"
}

install_tpm_and_plugins() {
	local tpm_dir="${HOME}/.tmux/plugins/tpm"
	if [ -x "$tpm_dir/tpm" ]; then
		ok "TPM already installed."
	else
		mkdir -p "${HOME}/.tmux/plugins"
		info "Cloning TPM (tmux plugin manager)..."
		git clone https://github.com/tmux-plugins/tpm "$tpm_dir"
		ok "TPM → $tpm_dir"
	fi

	# Clone the plugins listed in .tmux.conf — what TPM's prefix+I does,
	# without needing a running tmux server. tmux-fingers' binary is built
	# by its own wizard on first use inside tmux.
	local plugin repo
	while IFS= read -r plugin; do
		[ -n "$plugin" ] || continue
		repo="${HOME}/.tmux/plugins/$(basename "$plugin")"
		if [ -d "$repo" ]; then
			info "plugin already present: $plugin"
			continue
		fi
		if git clone "https://github.com/$plugin" "$repo"; then
			ok "plugin → $repo"
		else
			warn "failed to clone plugin: $plugin"
		fi
		# `set [-a-z]+` also matches `set -as`/`set -gq` plugin declarations.
	done < <(grep -oE "set -[a-z]+ @plugin [\"'][^\"']+" "$INSTALL_DIR/.tmux.conf" | sed -E "s/set -[a-z]+ @plugin [\"']//")
	ok "Plugins installed."
}

# ────────────────── Step 7: Auto-start tmux on shell login ──────────────────

install_autostart() {
	# Every interactive, non-tmux shell execs into the main session
	# (self-guarded: no-op when $TMUX is set or the shell is
	# non-interactive). Write it via append_env_block so it lands in the
	# profile files with dedup.
	local block='if [[ -z "${TMUX:-}" ]] && [[ $- == *i* ]] && command -v tmux >/dev/null; then
    if tmux has-session -t main 2>/dev/null; then
        exec tmux new-session -t main \; new-window
    else
        exec tmux new-session -s main
    fi
fi'
	append_env_block "monkey-tmux auto-start" "$block"
	ok "tmux auto-start added to shell profiles."
}

# ────────────────── Main ──────────────────

main() {
	echo ""
	echo -e "${BOLD}╔══════════════════════════════════════════╗${NC}"
	echo -e "${BOLD}║       monkey-tmux installer              ║${NC}"
	echo -e "${BOLD}╚══════════════════════════════════════════╝${NC}"
	echo ""

	info "Detected OS: ${CYAN}${OS}${NC}"
	info "monkey-tmux: ${CYAN}${INSTALL_DIR}${NC}"
	info "tmux source: ${CYAN}${TMUX_SRC_DIR}${NC} (used only for the fallback build)"
	echo ""

	setup_sudo

	ensure_git
	echo ""

	install_tmux
	echo ""

	install_linuxbrew
	echo ""

	install_fzf
	echo ""

	clone_monkey_tmux
	echo ""

	run_checkhealth
	echo ""

	setup_symlinks
	echo ""

	install_tpm_and_plugins
	echo ""

	install_autostart
	echo ""

	echo -e "${GREEN}${BOLD}monkey-tmux installation complete!${NC}"
	echo ""
	echo -e "  Config:   ${CYAN}$INSTALL_DIR/.tmux.conf${NC} → ${CYAN}~/.tmux.conf${NC}"
	echo -e "  Plugins:  ${CYAN}~/.tmux/plugins/${NC} (TPM)"
	echo ""
	echo -e "  Run ${CYAN}tmux${NC} to start."
	echo -e "  Update tmux: ${CYAN}cd $TMUX_SRC_DIR && git pull && ./configure && make && sudo make install${NC} (only if the distro build is broken/outdated)"
	echo -e "  Update monkey-tmux: ${CYAN}cd $INSTALL_DIR && git pull${NC}"
	echo ""
	# PATH exports were written to shell rc files, but they only apply to
	# shells started AFTER this point. A child process can never change the
	# parent shell's environment, so spell out how to pick it up now.
	local env_file
	env_file="$(shell_env_files | head -1)"
	# ACQUIRE_TIOCSTI protocol: only the script that claimed the injection
	# right acts. When chained, the wrapper holds the right and injects once
	# at its own end — per-component hints would be redundant there.
	if [ "$ACQUIRE_TIOCSTI" != "monkey-tmux" ]; then
		: # wrapper holds the injection right
	elif inject_tty "source ${env_file}"; then
		echo -e "  ${GREEN}Injected 'source ${env_file}' into the current terminal.${NC}"
	else
		echo -e "  ${YELLOW}New PATH takes effect in NEW shells. To use it in this terminal now:${NC}"
		echo -e "    ${CYAN}source ${env_file}${NC}    ${YELLOW}# or simply: ${CYAN}exec \$SHELL${NC}"
	fi
	echo ""
}

main "$@"
