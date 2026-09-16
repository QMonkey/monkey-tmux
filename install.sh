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

# Print login profile + interactive rc file for the detected shell.
# Login files (.profile/.zprofile/.bash_profile) cover login shells (SSH,
# macOS Terminal); rc files (.bashrc/.zshrc) cover non-login interactive
# shells (Linux desktop terminals). We write to both so tools are on PATH
# everywhere.
shell_env_files() {
	local shell="${SHELL:-bash}"
	shell="${shell##*/}"
	case "$shell" in
	zsh)
		printf '%s\n' "$HOME/.zprofile"
		printf '%s\n' "$HOME/.zshrc"
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

refresh_path() {
	# In-session PATH refresh so newly installed tools are found by this script.
	if have_native_cmd go; then
		local gopath
		gopath=$(go env GOPATH 2>/dev/null || echo "$HOME/go")
		export PATH="$gopath/bin:$PATH"
	fi
	# Not `[ ... ] && . ...`: when the file is missing the function returns
	# non-zero and, under set -e, silently aborts the whole script.
	if [ -f "$HOME/.cargo/env" ]; then . "$HOME/.cargo/env"; fi
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
	# Pre-authenticate once so the password is entered at the very start
	# instead of mid-run after a long download/compile.
	"$SUDO_BIN" -v || fail "sudo authorization failed — run this script in an interactive terminal."
	# Temporary NOPASSWD for the duration of the run — the core of the
	# one-password design. Three things would otherwise kill the sudo
	# ticket mid-run and force a re-auth prompt:
	#   1. Homebrew resets the sudo timestamp on EVERY `brew` invocation
	#      (brew.sh runs `sudo --reset-timestamp` at startup) — even a
	#      never-expiring ticket dies after each brew command;
	#   2. WSL2 clock steps (host sleep/resume, TSC skew) make sudo
	#      disable tickets "from the future";
	#   3. plain expiry (default 15 minutes) on long downloads/compiles.
	# With NOPASSWD, authentication is granted by the sudoers rule itself
	# and the timestamp is never consulted — on both GNU sudo and sudo-rs
	# — so the run is immune to all three in ANY command order, and the
	# only password entry is the `sudo -v` above.
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
		sudo_cmd apt-get install -y build-essential git curl libevent-dev ncurses-dev bison pkg-config
		;;
	arch)
		sudo_cmd pacman -S --needed --noconfirm base-devel libevent ncurses bison pkgconf
		;;
	opensuse)
		sudo_cmd zypper --non-interactive install -y gcc make git libevent-devel ncurses-devel bison pkg-config
		;;
	centos)
		sudo_cmd dnf install -y gcc make git curl libevent-devel ncurses-devel bison pkgconfig
		;;
	macos)
		brew install libevent ncurses pkg-config
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

install_tmux() {
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
	local brew_prefix=""
	if have_native_cmd brew; then
		brew_prefix="$(dirname "$(dirname "$(command -v brew)")")"
		ok "Homebrew already installed at $brew_prefix."
	else
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

		local cand
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
	info "Running checkhealth.sh --install to install remaining dependencies..."
	bash "$INSTALL_DIR/checkhealth.sh" --install || {
		warn "Some dependencies could not be installed automatically."
		warn "Run 'cd $INSTALL_DIR && ./checkhealth.sh' to review remaining items."
	}
	ok "Dependency check complete."
}

# ────────────────── Step 6: Persist PATH (go/bin, cargo/bin) ──────────────────

persist_path() {
	# go install drops binaries in $(go env GOPATH)/bin (default ~/go/bin);
	# rustup installs cargo & rust-analyzer to ~/.cargo/bin; built tmux lives
	# in /usr/local/bin. None is guaranteed to be on PATH, so persist exports
	# for the detected shell (zsh→.zprofile + .zshrc, bash→.profile/.bash_profile + .bashrc).
	local block='case ":$PATH:" in *":/usr/local/bin:"*) ;; *) export PATH="/usr/local/bin:$PATH" ;; esac
case ":$PATH:" in *":$HOME/go/bin:"*) ;; *) export PATH="$HOME/go/bin:$PATH" ;; esac
case ":$PATH:" in *":$HOME/.cargo/bin:"*) ;; *) export PATH="$HOME/.cargo/bin:$PATH" ;; esac'
	append_env_block "monkey-tmux PATH" "$block"
	ok "PATH persistence added for /usr/local/bin, go/bin and cargo/bin."
}

# ────────────────── Step 7: Symlink config & install TPM + plugins ──────────────────

setup_symlinks() {
	info "Setting up configuration symlinks..."
	ln -sfn "$INSTALL_DIR/.tmux.conf" "$HOME/.tmux.conf"
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
	done < <(grep -oE "set -g @plugin [\"'][^\"']+" "$INSTALL_DIR/.tmux.conf" | sed -E "s/set -g @plugin [\"']//")
	ok "Plugins installed."
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

	refresh_path

	persist_path
	echo ""

	setup_symlinks
	echo ""

	install_tpm_and_plugins
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
	echo -e "  ${YELLOW}New PATH takes effect in NEW shells. To use it in this terminal now:${NC}"
	echo -e "    ${CYAN}source ${env_file}${NC}    ${YELLOW}# or simply: ${CYAN}exec \$SHELL${NC}"
	echo ""
}

main "$@"
