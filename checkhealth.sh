#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

PASS="[${GREEN}✓${NC}]"
FAIL="[${RED}✗${NC}]"
WARN="[${YELLOW}!${NC}]"

ALL_PASSED=true
INSTALL_MODE=false

usage() {
	cat <<EOF
Usage: $0 [OPTIONS]

Check and optionally install dependencies for monkey-tmux.

OPTIONS
  -i, --install    Install missing dependencies
  -h, --help       Show this help

Exit code: 1 if any required dependency is missing, 0 otherwise.
EOF
	exit 0
}

parse_args() {
	while [[ $# -gt 0 ]]; do
		case "$1" in
		-i | --install) INSTALL_MODE=true ;;
		-h | --help) usage ;;
		*)
			echo "Unknown option: $1"
			usage
			;;
		esac
		shift
	done
}

# ──────────────────────────── helpers ────────────────────────────

# WSL interop appends the WINDOWS PATH to ours, so tools installed on the
# Windows side (node, python, git, ...) appear as /mnt/c/... shims. They are
# NOT Linux binaries: `sudo` cannot even see them (secure_path drops /mnt/*),
# and a global `npm install -g` through the shim would land on the WINDOWS
# side, invisible to WSL tmux. Treat /mnt/* resolutions as "not installed" so
# the real Linux packages get installed instead.
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

check_bin() {
	if have_native_cmd "$1"; then
		echo -e "  ${PASS} ${2:-$1}"
		return 0
	else
		echo -e "  ${FAIL} ${2:-$1}"
		ALL_PASSED=false
		return 1
	fi
}

check_cmd() {
	local desc="$1"
	shift
	if "$@" &>/dev/null; then
		echo -e "  ${PASS} ${desc}"
		return 0
	else
		echo -e "  ${FAIL} ${desc}"
		ALL_PASSED=false
		return 1
	fi
}

check_version() {
	local bin="$1" min="$2" desc="$3"
	if ! have_native_cmd "$bin"; then
		echo -e "  ${FAIL} ${desc} (${bin} not found)"
		ALL_PASSED=false
		return 1
	fi
	local ver="" flag
	for flag in -V --version -v; do
		ver=$("$bin" "$flag" 2>/dev/null | grep -oP '\d+\.\d+' | head -1)
		[[ -n "$ver" ]] && break
	done
	if [[ -z "$ver" ]]; then
		echo -e "  ${FAIL} ${desc} (could not detect version)"
		ALL_PASSED=false
		return 1
	fi
	if printf '%s\n%s\n' "$min" "$ver" | sort -V -C; then
		echo -e "  ${PASS} ${desc} ${ver}"
		return 0
	else
		echo -e "  ${FAIL} ${desc} ${ver} (need >= ${min})"
		ALL_PASSED=false
		return 1
	fi
}

os_detect() {
	case "$(uname -s)" in
	Linux)
		if [ -f /etc/os-release ]; then
			# shellcheck disable=SC1091
			. /etc/os-release
			case "$ID" in
			ubuntu | debian | linuxmint | pop | elementary | zorin) echo "debian" ;;
			arch | manjaro | endeavouros) echo "arch" ;;
			opensuse | opensuse-leap | opensuse-tumbleweed | opensuse-microos | suse | sles) echo "opensuse" ;;
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

sudo_cmd() {
	# Lazy re-auth: Homebrew resets the sudo timestamp on EVERY invocation
	# (brew.sh runs `sudo --reset-timestamp` at startup), so a ticket that
	# was valid a minute ago can be dead here. Re-authenticate proactively
	# with an explanatory prompt instead of letting the command fail or
	# spring a context-free password prompt. `-n true` never prompts; the
	# interactive `-v` only runs when the ticket is actually gone.
	local sudo_bin
	sudo_bin=$(native_sudo) || { "$@"; return; }
	if ! "$sudo_bin" -n true 2>/dev/null; then
		"$sudo_bin" -v -p "[monkey-tmux] sudo credentials needed to continue — enter your password: " || return 1
	fi
	"$sudo_bin" "$@"
}

# System package manager install. Returns non-zero when the OS is unknown
# or the manager fails, so callers can fall back to other sources.
install_with_system_mgr() {
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

install_pkg() {
	if ! $INSTALL_MODE; then return 1; fi
	install_with_system_mgr "$@"
	# Freshly installed binaries may be shadowed by bash's per-process
	# command hash cache (a /mnt shim executed earlier in this same run);
	# re-scan PATH.
	hash -r
}

get_install_hint() {
	case "$OS" in
	debian) echo "sudo apt-get install ${*}" ;;
	arch) echo "sudo pacman -S ${*}" ;;
	opensuse) echo "sudo zypper install ${*}" ;;
	centos) echo "sudo dnf install ${*}" ;;
	macos) echo "brew install ${*}" ;;
	*) echo "install ${*} manually" ;;
	esac
}

# ──────────────────── phases ────────────────────

print_header() {
	echo -e "${BOLD}monkey-tmux dependency check${NC}"
	echo ""
}

print_tmux_version() {
	echo -e "${BOLD}tmux${NC}"
	check_version tmux 3.2 "tmux"
	echo ""
}

print_platform() {
	echo -e "${BOLD}Platform${NC}"
	echo -e "  OS: ${CYAN}$(uname -s)${NC}"
	case "$OS" in
	debian) echo -e "  Package manager: ${CYAN}apt${NC}" ;;
	arch) echo -e "  Package manager: ${CYAN}pacman${NC}" ;;
	opensuse) echo -e "  Package manager: ${CYAN}zypper${NC}" ;;
	centos) echo -e "  Package manager: ${CYAN}dnf${NC}" ;;
	macos) echo -e "  Package manager: ${CYAN}homebrew${NC}" ;;
	*) echo -e "  ${WARN} Unsupported OS — install dependencies manually" ;;
	esac
	echo ""
}

check_required_tools() {
	echo -e "${BOLD}Required tools${NC}"
	check_bin git "git" || MISSING_REQUIRED+=("git")
	check_bin which "which (needed by fzf-tmux in tmux run-shell)" || MISSING_REQUIRED+=("which")
	echo ""
}

check_fzf() {
	echo -e "${BOLD}fzf${NC} (required by tmux-fzf, tmux-scout, extrakto, tmux-fzf-url)"
	if check_version fzf 0.51 "fzf (need >= 0.51 for tmux-scout)"; then
		:
	else
		MISSING_REQUIRED+=("fzf")
	fi
	echo ""
}

check_node() {
	echo -e "${BOLD}Node.js${NC} (required by tmux-scout)"
	if check_version node 16 "node (need >= 16 for tmux-scout)"; then
		:
	else
		MISSING_REQUIRED+=("node")
	fi
	echo ""
}

check_jq() {
	echo -e "${BOLD}jq${NC} (required by tmux-assistant-resurrect)"
	check_bin jq "jq" || MISSING_REQUIRED+=("jq")
	echo ""
}

check_python3() {
	echo -e "${BOLD}python3${NC} (required by extrakto)"
	check_bin python3 "python3" || MISSING_REQUIRED+=("python3")
	echo ""
}

check_clipboard() {
	echo -e "${BOLD}Clipboard${NC} (required by tmux-yank)"
	if [[ "$OS" == "macos" ]]; then
		check_bin pbcopy "pbcopy (macOS built-in)" || MISSING_REQUIRED+=("pbcopy")
	elif grep -qi microsoft /proc/version 2>/dev/null; then
		# NOTE: clip.exe is intentionally a WINDOWS binary reached through WSL
		# interop — have_native_cmd must NOT be applied here.
		if command -v clip.exe &>/dev/null; then
			echo -e "  ${PASS} clip.exe (WSL)"
			if [[ -r /proc/sys/fs/binfmt_misc/WSLInterop ]] &&
				[[ "$(head -1 /proc/sys/fs/binfmt_misc/WSLInterop 2>/dev/null)" == "enabled" ]]; then
				echo -e "  ${PASS} WSL interop (binfmt WSLInterop enabled)"
			else
				echo -e "  ${WARN} WSL interop broken — .exe calls (yank/extrakto/fzf-url) will fail"
				echo -e "         See README Troubleshooting: re-register /proc/sys/fs/binfmt_misc/WSLInterop"
			fi
		else
			echo -e "  ${FAIL} clip.exe (WSL)"
			ALL_PASSED=false
			MISSING_REQUIRED+=("clip.exe")
		fi
	else
		# X11: xclip/xsel; Wayland: wl-clipboard. tmux-yank prefers wl-copy
		# on Wayland (its helpers check wl-copy BEFORE xsel); under XWayland
		# xclip works too, so any one of the three suffices. Probes use
		# have_native_cmd so a missing first choice cannot poison
		# ALL_PASSED when a later alternative exists.
		local tool="" t
		for t in wl-copy xclip xsel; do
			if have_native_cmd "$t"; then
				tool="$t"
				break
			fi
		done
		if [[ -n "$tool" ]]; then
			echo -e "  ${PASS} ${tool} (clipboard)"
		else
			local hint="xclip"
			[[ -n "${WAYLAND_DISPLAY:-}" ]] && hint="wl-clipboard"
			echo -e "  ${FAIL} xclip / xsel / wl-copy (Wayland: install wl-clipboard)"
			MISSING_REQUIRED+=("$hint")
			ALL_PASSED=false
		fi
	fi
	echo ""
}

check_tmux_fingers() {
	echo -e "${BOLD}tmux-fingers${NC} (requires binary, installed via wizard on first run)"
	local fingers_dir="${HOME}/.tmux/plugins/tmux-fingers" candidate fingers_bin=""
	for candidate in \
		"$fingers_dir/bin/tmux-fingers" \
		"$fingers_dir/scripts/tmux-fingers.sh" \
		"$fingers_dir/target/release/tmux-fingers" \
		/usr/local/bin/tmux-fingers; do
		if [[ -x "$candidate" ]]; then
			fingers_bin="$candidate"
			break
		fi
	done
	if [[ -n "$fingers_bin" ]]; then
		echo -e "  ${PASS} tmux-fingers binary found"
	else
		if [[ -d "$fingers_dir" ]]; then
			echo -e "  ${WARN} tmux-fingers plugin installed but binary not built"
			echo -e "         Run ${CYAN}prefix+I${NC} in tmux and follow the wizard"
		else
			echo -e "  ${WARN} tmux-fingers plugin not yet installed"
		fi
	fi
	echo ""
}

check_optional_tools() {
	echo -e "${BOLD}Optional tools${NC}"
	if check_bin rg "ripgrep (recommended for faster fzf search)" 2>/dev/null; then :; fi
}

check_terminal_caps() {
	echo -e "${BOLD}Terminal capabilities${NC}"
	if [[ -n "${COLORTERM:-}" ]] || [[ "$TERM" =~ (256color|tmux|screen|alacritty|kitty|wezterm|xterm-kitty) ]]; then
		echo -e "  ${PASS} TERM=${TERM} (true color capable)"
	else
		echo -e "  ${WARN} TERM=${TERM} — true color may not work"
	fi
	echo ""
}

check_config_files() {
	echo -e "${BOLD}Config files${NC}"
	local tmuxconf="${HOME}/.tmux.conf"
	if [[ -L "$tmuxconf" ]]; then
		local target
		target=$(readlink -f "$tmuxconf" 2>/dev/null || readlink "$tmuxconf")
		if [[ -f "$target" ]]; then
			echo -e "  ${PASS} .tmux.conf → ${target}"
		else
			echo -e "  ${FAIL} .tmux.conf symlink broken → ${target}"
			ALL_PASSED=false
		fi
	elif [[ -f "$tmuxconf" ]]; then
		echo -e "  ${WARN} .tmux.conf exists but is not a symlink"
	else
		echo -e "  ${FAIL} .tmux.conf not found (run: ln -s /path/to/monkey-tmux/.tmux.conf ~/.tmux.conf)"
		ALL_PASSED=false
	fi

	local tpm_dir="${HOME}/.tmux/plugins/tpm"
	if [[ -x "$tpm_dir/tpm" || -f "$tpm_dir/tpm" ]]; then
		echo -e "  ${PASS} TPM (tmux plugin manager) installed"
	elif [[ -d "$tpm_dir" ]]; then
		echo -e "  ${WARN} TPM dir exists but may be incomplete"
	else
		echo -e "  ${WARN} TPM not installed (auto-installed on first tmux start)"
	fi

	echo ""
}

install_missing_required() {
	if ! $INSTALL_MODE || [[ ${#MISSING_REQUIRED[@]} -eq 0 ]]; then
		return 0
	fi
	echo -e "${YELLOW}Installing missing packages: ${MISSING_REQUIRED[*]}${NC}"
	echo ""
	# Package names that differ from the binary name, per package manager.
	# A case function instead of `declare -A`: macOS still ships bash 3.2,
	# which has no associative arrays.
	pkg_name() {
		local bin="$1"
		case "$OS:$bin" in
		debian:node) echo "nodejs" ;;
		debian:which) echo "debianutils" ;;
		arch:node) echo "nodejs" ;;
		arch:python3) echo "python" ;;
		opensuse:node) echo "nodejs" ;;
		centos:node) echo "nodejs" ;;
		*) echo "$bin" ;;
		esac
	}
	local pkgs=() b
	for b in "${MISSING_REQUIRED[@]}"; do
		pkgs+=("$(pkg_name "$b")")
	done
	if [[ ${#pkgs[@]} -gt 0 ]]; then
		if install_pkg "${pkgs[@]}"; then
			echo -e "${GREEN}Done.${NC}"
		else
			echo -e "${RED}Failed. Run: $(get_install_hint "${pkgs[*]}")${NC}"
		fi
	fi
	echo ""
}

print_summary() {
	if $ALL_PASSED; then
		echo -e "${GREEN}${BOLD}All required dependencies satisfied.${NC}"
		exit 0
	else
		echo -e "${RED}${BOLD}Some required dependencies are missing.${NC}"
		if ! $INSTALL_MODE; then
			echo -e "Run ${CYAN}$0 --install${NC} to install them automatically."
		fi
		exit 1
	fi
}

# ──────────────────── main ────────────────────

main() {
	parse_args "$@"
	OS=$(os_detect)
	MISSING_REQUIRED=()
	print_header
	print_tmux_version
	print_platform
	check_required_tools
	check_fzf
	check_node
	check_jq
	check_python3
	check_clipboard
	check_tmux_fingers
	check_optional_tools
	check_terminal_caps
	check_config_files
	install_missing_required
	print_summary
}

main "$@"
