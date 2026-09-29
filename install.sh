#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────────────────────
# monkey-tmux one-shot installer
# Usage: curl -fsSL https://raw.githubusercontent.com/QMonkey/monkey-tmux/master/install.sh | bash
#
# The shared installer (sudo, packages, clone, checkhealth, symlinks,
# completion) lives in scripts/ — a `git subtree` of
# github.com/QMonkey/monkey-scripts. On the curl|bash path there is no
# checkout at all, so install.sh clones THIS repo and runs the copy of
# install.sh inside it — that copy carries its own scripts/, so the
# installer and the framework it loads are always the same revision.
# ──────────────────────────────────────────────────────────────

# ──────────────────────── repository identity ────────────────────────
# Declared before the framework is sourced: the bootstrap below needs both
# values, and clones into the very directory clone_monkey_project would
# have used — one clone per run, not two.
PROJECT=monkey-tmux
PROJECT_REPO=https://github.com/QMonkey/monkey-tmux.git
INSTALL_DIR="${INSTALL_DIR:-$HOME/Documents/monkey-tmux}"

# No scripts/ next to this file: either a checkout predating the subtree
# commit (pull it in and carry on) or `curl | bash`, which has no checkout
# at all. The latter clones THIS project and runs the install.sh from that
# checkout, so installer and scripts/ always come from the same revision.
_monkey_scripts="$(dirname "${BASH_SOURCE[0]:-$0}")/scripts"
if [ ! -f "$_monkey_scripts/install.sh" ]; then
	_monkey_self="${BASH_SOURCE[0]:-$0}"
	_monkey_dir="$(dirname "$_monkey_self")"
	if [ -f "$_monkey_self" ] && [ -d "$_monkey_dir/.git" ]; then
		git -C "$_monkey_dir" pull --ff-only || true
		_monkey_scripts="$_monkey_dir/scripts"
		if [ ! -f "$_monkey_scripts/install.sh" ]; then
			echo "monkey-scripts missing from $_monkey_dir (no scripts/ subtree)." >&2
			echo "  git -C $_monkey_dir pull    # outdated checkout — or the repo never added the subtree" >&2
			exit 1
		fi
	else
		# curl|bash: no checkout at all. Get one that carries scripts/ and
		# hand over to its installer, so install.sh and scripts/ can never be
		# different revisions. clone_monkey_project cannot do this job — it
		# lives in the very scripts/ being fetched. INSTALL_DIR is where the
		# framework's clone step would have put the checkout too, so that step
		# only confirms it.

		if ! command -v git >/dev/null 2>&1; then
			echo "git is required to clone $PROJECT — install it first (e.g. sudo apt-get install git), then re-run." >&2
			exit 1
		fi
		if [ -d "$INSTALL_DIR/.git" ]; then
			# An install already lives here: update it, then run that one.
			git -C "$INSTALL_DIR" pull --ff-only || true
		elif [ -d "$INSTALL_DIR" ] && [ -n "$(ls -A "$INSTALL_DIR")" ]; then
			# git clone would refuse too, so say why in our own words.
			echo "$INSTALL_DIR is not empty and is not a git clone." >&2
			echo "  move it aside, delete it, or set INSTALL_DIR elsewhere." >&2
			exit 1
		else
			# No retry() available yet — the framework loads only after this
			# clone succeeds — so inline the standard 3 attempts. A failed clone
			# leaves a partial directory behind; remove it so the next attempt
			# cannot trip over "already exists". This branch only runs on a
			# fresh install (INSTALL_DIR did not exist or was empty), so the rm
			# can never delete pre-existing data.
			_monkey_rc=1
			for _monkey_attempt in 1 2 3; do
				if git clone "$PROJECT_REPO" "$INSTALL_DIR"; then
					_monkey_rc=0
					break
				fi
				rm -rf "$INSTALL_DIR"
				if [ "$_monkey_attempt" -lt 3 ]; then
					sleep 2
				fi
			done
			[ "$_monkey_rc" -eq 0 ] || exit 1
		fi
		# </dev/null: on the curl|bash path stdin is the script pipe, and the
		# inner installer must not read what is left of the outer one.
		exec bash "$INSTALL_DIR/install.sh" "$@" </dev/null
	fi
fi
# shellcheck source=/dev/null
. "$_monkey_scripts/install.sh"

# ──────────────────────── layout & data ────────────────────────
TMUX_SRC_DIR="${TMUX_SRC_DIR:-$HOME/Documents/tmux}" # only for the fallback build
JOBS="${JOBS:-$(nproc 2>/dev/null || echo 4)}"
ACQUIRE_TIOCSTI="${ACQUIRE_TIOCSTI:-monkey-tmux}"
INSTALL_INFO=(
	"tmux source: ${CYAN}${TMUX_SRC_DIR}${NC} (used only for the fallback build)"
)

SYMLINKS=(
	"$INSTALL_DIR/.tmux.conf|$HOME/.tmux.conf"
)

SUMMARY_LINES=(
	"  Config:   ${CYAN}$INSTALL_DIR/.tmux.conf${NC} → ${CYAN}~/.tmux.conf${NC}"
	"  Plugins:  ${CYAN}~/.tmux/plugins/${NC} (TPM)"
	""
	"  Run ${CYAN}tmux${NC} to start."
	"  Update tmux: ${CYAN}cd $TMUX_SRC_DIR && git pull && ./configure && make && sudo make install${NC} (only if the distro build is broken/outdated)"
	"  Update monkey-tmux: ${CYAN}cd $INSTALL_DIR && git pull${NC}"
)

# ──────────────────────── project steps ────────────────────────
tmux_version() {
	# "tmux 3.7b" -> "3.7b"; also handles "tmux next-3.4".
	tmux -V 2>/dev/null | grep -oE '[0-9]+\.[0-9]+[a-z]*' | head -1
}

# tmux 3.7 — 3.7b: exiting a session crashes tmux instead of switching to the
# next one. Regression introduced in 3.7 (commit 3c3d9ce3, sorting refactor),
# fixed in 3.7c (commit c515d8ca — e.g. Arch ships 3.7c unaffected). Remove
# these entries once no distro ships 3.7 — 3.7b anymore.
# https://github.com/tmux/tmux/issues/5344
tmux_is_known_bad() {
	case "$1" in
	3.7 | 3.7a | 3.7b) return 0 ;;
	*) return 1 ;;
	esac
}

tmux_ok() {
	have_native_cmd tmux || return 1
	local ver
	ver=$(tmux_version)
	[[ -z "$ver" ]] && return 1
	tmux_is_known_bad "$ver" && return 1
	# 3.4, not 3.2: .tmux.conf uses `destroy-unattached keep-last`, which
	# older tmux rejects at config parse time ("bad value: keep-last" on
	# AlmaLinux 9's 3.2a). Keeping the requirement here — instead of
	# version-guarding the config — means every distro below 3.4 gets the
	# source build once and the config stays single-pathed.
	version_ge "$ver" "3.4"
}

build_tmux_from_source() {
	info "Building tmux from source (master)..."
	case "$OS" in
	debian | ubuntu)
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
	fedora)
		# No EPEL on Fedora — the same names ship in the base repos.
		sudo_cmd dnf install -y gcc make git curl libevent-devel ncurses-devel bison pkgconfig autoconf automake
		;;
	macos)
		brew install libevent ncurses pkg-config autoconf automake
		;;
	esac
	if [ -d "$TMUX_SRC_DIR/.git" ]; then
		info "tmux source already exists at $TMUX_SRC_DIR — pulling latest..."
		retry -s "git pull" git -C "$TMUX_SRC_DIR" pull --ff-only ||
			warn "git pull failed — building from existing source."
	else
		# A failed clone leaves a partial directory behind, which would make
		# every later attempt (and re-run) fail with "already exists" — clean
		# it up before giving up, but only when git created it (.git inside)
		# or it is empty, never when it holds pre-existing user data.
		if ! retry -s "git clone tmux" git clone https://github.com/tmux/tmux.git "$TMUX_SRC_DIR"; then
			if [ -d "$TMUX_SRC_DIR" ] && { [ -z "$(ls -A "$TMUX_SRC_DIR")" ] || [ -d "$TMUX_SRC_DIR/.git" ]; }; then
				rm -rf "$TMUX_SRC_DIR"
			fi
			fail "tmux source clone failed after 3 attempts."
		fi
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

install_tmux() {
	# openSUSE splits the terminfo database: terminfo-base is minimal and
	# terminfo-screen carries only screen.* aliases — NO tmux entries in
	# either (verified against the Leap 16 / Tumbleweed RPM contents).
	# Without the full terminfo package, every shell inside tmux hits
	# "tset: unknown terminal type tmux-256color".
	if [ "$OS" = opensuse ]; then
		install_pkg terminfo ||
			warn "could not install terminfo — tmux may report an unknown terminal type (tmux-256color)."
	fi
	if tmux_ok; then
		ok "tmux $(tmux_version) already installed and meets requirement (>= 3.4, no known-bad release)."
		return 0
	fi
	# Modern distros ship tmux >= 3.4 — the system package is preferred
	# (security updates, no compiler toolchain needed). The source build
	# only kicks in for old distros (e.g. AlmaLinux 9's 3.2a, CentOS 7's
	# 1.8) or known-bad releases (e.g. openSUSE Tumbleweed's 3.7b), and
	# builds tmux MASTER.
	info "Installing tmux via the system package manager..."
	install_pkg tmux || warn "system package manager failed — will try building from source."
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

# tmux-scout needs fzf >= 0.51; distro packages lag far behind (Ubuntu noble
# ships 0.44). Homebrew's fzf is current — install it BEFORE checkhealth.sh
# --install runs, so fzf never counts as "missing" there.
install_fzf() {
	have_native_cmd fzf && return 0
	if ! have_native_cmd brew; then
		warn "Homebrew not found — fzf will come from the distro (may be < 0.51, tmux-scout needs >= 0.51)."
		return 0
	fi
	info "Installing fzf via Homebrew (distro versions lag behind)..."
	brew install fzf || warn "brew install fzf failed — checkhealth.sh will try the system package manager."
	hash -r
}

# Clone the plugins listed in .tmux.conf — what TPM's prefix+I does, without
# needing a running tmux server. tmux-fingers' binary is built by its own
# wizard on first use inside tmux.
install_tpm_and_plugins() {
	local tpm_dir="${HOME}/.tmux/plugins/tpm"
	if [ -x "$tpm_dir/tpm" ]; then
		ok "TPM already installed."
	else
		mkdir -p "${HOME}/.tmux/plugins"
		info "Cloning TPM (tmux plugin manager)..."
		retry -s "git clone tpm" git clone https://github.com/tmux-plugins/tpm "$tpm_dir"
		ok "TPM → $tpm_dir"
	fi

	local plugin repo
	while IFS= read -r plugin; do
		[ -n "$plugin" ] || continue
		repo="${HOME}/.tmux/plugins/$(basename "$plugin")"
		if [ -d "$repo" ]; then
			info "plugin already present: $plugin"
			continue
		fi
		if retry -s "git clone $plugin" git clone "https://github.com/$plugin" "$repo"; then
			ok "plugin → $repo"
		else
			warn "failed to clone plugin: $plugin"
		fi
		# `set [-a-z]+` also matches `set -as`/`set -gq` plugin declarations.
	done < <(grep -oE "set -[a-z]+ @plugin [\"'][^\"']+" "$INSTALL_DIR/.tmux.conf" | sed -E "s/set -[a-z]+ @plugin [\"']//")
	ok "Plugins installed."
}

# Every interactive, non-tmux shell execs into the main session (self-guarded:
# no-op when $TMUX is set or the shell is non-interactive). Written via
# append_env_block so it lands in the profile files with dedup.
install_autostart() {
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

# A hook prints its own trailing blank line when it produced output.
install_step_prepare() {
	ensure_git
	echo ""
}
install_step_tool() {
	install_tmux
	echo ""
}
install_step_post_tool() {
	install_linuxbrew
	echo ""
	install_fzf
	echo ""
}
install_step_after() {
	install_tpm_and_plugins
	echo ""
	install_autostart
	echo ""
}

install_main "$@"
