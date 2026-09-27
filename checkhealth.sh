#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────────────────────
# monkey-tmux dependency check
#
# The check framework lives in scripts/ (a `git subtree` of
# github.com/QMonkey/monkey-scripts) — this file only declares WHAT to check.
# ──────────────────────────────────────────────────────────────

. "$(dirname "${BASH_SOURCE[0]:-$0}")/scripts/checkhealth.sh" || {
	echo "monkey-scripts not found — update this checkout (git pull / re-clone)," >&2
	echo "or run install.sh, which bootstraps monkey-scripts itself." >&2
	exit 1
}

# ──────────────────────── identity ────────────────────────
PROJECT=monkey-tmux

# ──────────────────────── version gate ────────────────────────
MAIN_VERSION="tmux|ver:3.2|tmux|pkg"
MAIN_VERSION_TITLE="tmux"

# ──────────────────────── required ────────────────────────
# Every plugin dependency gets its own bold section, as upstream always had:
#   @header|Title   section title (${NC} ends the bold span early)
#   @clipboard      tmux-yank's clipboard probe (CHECK_CLIPBOARD=required)
#   @config         the "Config files" section
REQUIRED_CHECKS=(
	"@header|Required tools"
	"git|bin|git"
	"which|bin|which (needed by fzf-tmux in tmux run-shell)"
	"@header|fzf${NC} (required by tmux-fzf, tmux-scout, extrakto, tmux-fzf-url)"
	"fzf|ver:0.51|fzf (need >= 0.51 for tmux-scout)|pkg"
	"@header|Node.js${NC} (required by tmux-scout)"
	"node|ver:16|node (need >= 16 for tmux-scout)|pkg"
	"@header|jq${NC} (required by tmux-assistant-resurrect)"
	"jq|bin|jq"
	"@header|python3${NC} (required by extrakto; TIOCSTI injection)"
	"python3|bin|python3"
	"@header|Clipboard${NC} (required by tmux-yank)"
	"@clipboard"
	"@config"
)

# ──────────────────────── optional ────────────────────────
# Reported only: nothing installs it (the distro package may not exist on
# older releases), and a missing one must not fail the check.
OPTIONAL_SECTION_TITLE="Optional tools"
OPTIONAL_TRAILING_BLANK=0 # upstream prints no spacer before Terminal capabilities
OPTIONAL_CHECKS=(
	"rg|bin|ripgrep (recommended for faster fzf search)"
)

# ──────────────────────── required install ────────────────────────
# Verbatim upstream: tmux runs this AFTER Terminal capabilities
# (INSTALL_REQUIRED_PHASE=late), installs the package-name mapping in
# one batch and re-probes via run_required_checks.

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
	if install_pkg "${pkgs[@]}"; then
		run_required_checks
		if [[ ${#MISSING_REQUIRED[@]} -gt 0 ]]; then
			echo -e "${RED}Run: $(get_install_hint "$(for b in "${MISSING_REQUIRED[@]}"; do pkg_name "$b"; done | tr '\n' ' ')")${NC}"
		fi
	else
		echo -e "${RED}Install command failed. Run: $(get_install_hint "${pkgs[*]}")${NC}"
	fi
	echo ""
}

# ──────────────────────── config ────────────────────────
CONFIG_PHASE=required
INSTALL_REQUIRED_PHASE=late
# hint reproduces upstream's verbatim missing-fail text (literal
# /path/to/monkey-tmux placeholder instead of $(pwd)).
CONFIG_LINKS=(
	"$(pwd)/.tmux.conf|$HOME/.tmux.conf|.tmux.conf||.tmux.conf|.tmux.conf not found (run: ln -sfn /path/to/monkey-tmux/.tmux.conf ~/.tmux.conf)"
)
# type|params|ok|incomplete|missing
CONFIG_HINTS=(
	"path|$HOME/.tmux/plugins/tpm/tpm|TPM (tmux plugin manager) installed|TPM dir exists but may be incomplete|TPM not installed (auto-installed on first tmux start)"
)

# ──────────────────────── advisory ────────────────────────
# tmux-fingers ships no prebuilt binary on every platform: TPM clones it and
# the first run walks the user through the build (prefix+I).
ADVISORY_PHASE=early
# title|note|type|params|ok|incomplete|missing
ADVISORY_SECTIONS=(
	"tmux-fingers${NC} (requires binary, installed via wizard on first run)||exec|$HOME/.tmux/plugins/tmux-fingers/bin/tmux-fingers $HOME/.tmux/plugins/tmux-fingers/scripts/tmux-fingers.sh $HOME/.tmux/plugins/tmux-fingers/target/release/tmux-fingers /usr/local/bin/tmux-fingers|tmux-fingers binary found|tmux-fingers plugin installed but binary not built\n         Run \033[0;36mprefix+I\033[0m in tmux and follow the wizard|tmux-fingers plugin not yet installed"
)

# ──────────────────────── terminal ────────────────────────
CHECK_TERMINAL_CAPS=1
CHECK_CLIPBOARD=required

checkhealth_main "$@"
