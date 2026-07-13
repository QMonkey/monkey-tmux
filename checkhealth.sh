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

# ──────────────────────────── helpers ────────────────────────────

check_bin() {
	if command -v "$1" &>/dev/null; then
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
	if ! command -v "$bin" &>/dev/null; then
		echo -e "  ${FAIL} ${desc} (${bin} not found)"
		ALL_PASSED=false
		return 1
	fi
	local ver
	ver=$("$bin" -V 2>/dev/null | grep -oP '\d+\.\d+' | head -1 || echo "0")
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
			. /etc/os-release
			case "$ID" in
			ubuntu | debian | linuxmint | pop | elementary | zorin) echo "debian" ;;
			arch | manjaro | endeavouros) echo "arch" ;;
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

OS=$(os_detect)

sudo_cmd() {
	if command -v sudo &>/dev/null; then
		sudo "$@"
	else
		"$@"
	fi
}

install_pkg() {
	if ! $INSTALL_MODE; then return 1; fi
	case "$OS" in
	debian) sudo_cmd apt-get install -y "$@" ;;
	arch) sudo_cmd pacman -S --noconfirm "$@" ;;
	macos) brew install "$@" ;;
	*) return 1 ;;
	esac
}

get_install_hint() {
	case "$OS" in
	debian) echo "sudo apt-get install ${*}" ;;
	arch) echo "sudo pacman -S ${*}" ;;
	macos) echo "brew install ${*}" ;;
	*) echo "install ${*} manually" ;;
	esac
}

# ──────────────────── main ────────────────────

echo -e "${BOLD}monkey-tmux dependency check${NC}"
echo ""

# ──── tmux version ────
echo -e "${BOLD}tmux${NC}"
check_version tmux 3.2 "tmux"
echo ""

# ──── platform ────
echo -e "${BOLD}Platform${NC}"
echo -e "  OS: ${CYAN}$(uname -s)${NC}"
case "$OS" in
debian) echo -e "  Package manager: ${CYAN}apt${NC}" ;;
arch) echo -e "  Package manager: ${CYAN}pacman${NC}" ;;
macos) echo -e "  Package manager: ${CYAN}homebrew${NC}" ;;
*) echo -e "  ${WARN} Unsupported OS — install dependencies manually" ;;
esac
echo ""

# ──── required tools ────
echo -e "${BOLD}Required tools${NC}"
MISSING_REQUIRED=()

check_bin git "git" || MISSING_REQUIRED+=("git")

echo ""

# ──── fzf ────
echo -e "${BOLD}fzf${NC} (required by tmux-fzf)"
if check_bin fzf "fzf"; then
	:
else
	MISSING_REQUIRED+=("fzf")
fi
echo ""

# ──── gitmux ────
echo -e "${BOLD}gitmux${NC} (required for git status in status bar)"
if check_bin gitmux "gitmux"; then
	:
else
	MISSING_REQUIRED+=("gitmux")
fi
echo ""

# ──── clipboard ────
echo -e "${BOLD}Clipboard${NC} (required by tmux-yank)"
if [[ "$OS" == "macos" ]]; then
	check_bin pbcopy "pbcopy (macOS built-in)" || MISSING_REQUIRED+=("pbcopy")
else
	if check_bin xclip "xclip" 2>/dev/null; then
		:
	elif check_bin xsel "xsel" 2>/dev/null; then
		:
	else
		echo -e "  ${FAIL} xclip or xsel"
		MISSING_REQUIRED+=("xclip")
		ALL_PASSED=false
	fi
fi
echo ""

# ──── tmux-fingers binary ────
echo -e "${BOLD}tmux-fingers${NC} (requires binary, installed via wizard on first run)"
FINGERS_DIR="${HOME}/.tmux/plugins/tmux-fingers"
FINGERS_BIN=""
for candidate in \
	"$FINGERS_DIR/bin/tmux-fingers" \
	"$FINGERS_DIR/scripts/tmux-fingers.sh" \
	"$FINGERS_DIR/target/release/tmux-fingers" \
	/usr/local/bin/tmux-fingers; do
	if [[ -x "$candidate" ]]; then
		FINGERS_BIN="$candidate"
		break
	fi
done
if [[ -n "$FINGERS_BIN" ]]; then
	echo -e "  ${PASS} tmux-fingers binary found"
else
	if [[ -d "$FINGERS_DIR" ]]; then
		echo -e "  ${WARN} tmux-fingers plugin installed but binary not built"
		echo -e "         Run ${CYAN}prefix+I${NC} in tmux and follow the wizard"
	else
		echo -e "  ${WARN} tmux-fingers plugin not yet installed"
	fi
fi
echo ""

# ──── optional ────
echo -e "${BOLD}Optional tools${NC}"
if check_bin rg "ripgrep (recommended for faster fzf search)" 2>/dev/null; then :; fi

# ──── terminal capabilities ────
echo -e "${BOLD}Terminal capabilities${NC}"
if [[ -n "${COLORTERM:-}" ]] || [[ "$TERM" =~ (256color|tmux|screen|alacritty|kitty|wezterm|xterm-kitty) ]]; then
	echo -e "  ${PASS} TERM=${TERM} (true color capable)"
else
	echo -e "  ${WARN} TERM=${TERM} — true color may not work"
fi
if [[ -n "${DISPLAY:-}" || -n "${WAYLAND_DISPLAY:-}" || "$OS" == "macos" ]]; then
	echo -e "  ${PASS} GUI session (powerline glyphs supported)"
else
	echo -e "  ${PASS} TTY session (block separators will be used)"
fi
if command -v fc-list &>/dev/null; then
	if fc-list 2>/dev/null | grep -qi "nerd\|powerline"; then
		echo -e "  ${PASS} Nerd Font / Powerline font detected"
	else
		echo -e "  ${WARN} No Nerd Font detected (block separators will be used in TTY)"
	fi
fi
echo ""

# ──── config files ────
echo -e "${BOLD}Config files${NC}"
TMUXCONF="${HOME}/.tmux.conf"
if [[ -L "$TMUXCONF" ]]; then
	TARGET=$(readlink -f "$TMUXCONF" 2>/dev/null || readlink "$TMUXCONF")
	if [[ -f "$TARGET" ]]; then
		echo -e "  ${PASS} .tmux.conf → ${TARGET}"
	else
		echo -e "  ${FAIL} .tmux.conf symlink broken → ${TARGET}"
		ALL_PASSED=false
	fi
elif [[ -f "$TMUXCONF" ]]; then
	echo -e "  ${WARN} .tmux.conf exists but is not a symlink"
else
	echo -e "  ${FAIL} .tmux.conf not found (run: ln -s /path/to/monkey-tmux/.tmux.conf ~/.tmux.conf)"
	ALL_PASSED=false
fi

GITMUX_CONF="${HOME}/.gitmux.yml"
if [[ -L "$GITMUX_CONF" ]]; then
	TARGET=$(readlink -f "$GITMUX_CONF" 2>/dev/null || readlink "$GITMUX_CONF")
	if [[ -f "$TARGET" ]]; then
		echo -e "  ${PASS} .gitmux.yml → ${TARGET}"
	else
		echo -e "  ${FAIL} .gitmux.yml symlink broken → ${TARGET}"
		ALL_PASSED=false
	fi
elif [[ -f "$GITMUX_CONF" ]]; then
	echo -e "  ${PASS} .gitmux.yml exists"
else
	echo -e "  ${WARN} .gitmux.yml not found (auto-linked on first tmux start)"
fi

# ──── TPM ────
TPM_DIR="${HOME}/.tmux/plugins/tpm"
if [[ -x "$TPM_DIR/tpm" || -f "$TPM_DIR/tpm" ]]; then
	echo -e "  ${PASS} TPM (tmux plugin manager) installed"
elif [[ -d "$TPM_DIR" ]]; then
	echo -e "  ${WARN} TPM dir exists but may be incomplete"
else
	echo -e "  ${WARN} TPM not installed (auto-installed on first tmux start)"
fi

echo ""

# ──── install missing ────
if $INSTALL_MODE && [[ ${#MISSING_REQUIRED[@]} -gt 0 ]]; then
	echo -e "${YELLOW}Installing missing packages: ${MISSING_REQUIRED[*]}${NC}"
	echo ""

	declare -A APT_NAMES=(
		["fzf"]="fzf"
		["xclip"]="xclip"
	)
	declare -A PACMAN_NAMES=(
		["fzf"]="fzf"
		["xclip"]="xclip"
	)
	declare -A BREW_NAMES=()

	pkg_name() {
		local bin="$1"
		case "$OS" in
		debian) echo "${APT_NAMES[$bin]:-$bin}" ;;
		arch) echo "${PACMAN_NAMES[$bin]:-$bin}" ;;
		macos) echo "${BREW_NAMES[$bin]:-$bin}" ;;
		*) echo "$bin" ;;
		esac
	}

	pkgs=()
	for b in "${MISSING_REQUIRED[@]}"; do
		case "$b" in
		gitmux)
			if command -v go &>/dev/null; then
				echo -e "  Installing gitmux via ${CYAN}go install${NC}..."
				if go install github.com/arl/gitmux@latest; then
					echo -e "  ${PASS} gitmux installed"
				else
					echo -e "  ${FAIL} gitmux installation failed"
				fi
			else
				echo -e "  ${FAIL} gitmux: need Go 1.16+ installed first ($(get_install_hint golang))"
			fi
			continue
			;;
		esac
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
fi

# ──── summary ────
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
