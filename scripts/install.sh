#!/usr/bin/env bash
# =============================================================================
# Alpax (अल्प) — Universal Installer
# =============================================================================
# USAGE (one-liner, as shown in README):
#   curl -fsSL https://raw.githubusercontent.com/SoumyaRKN/alpax/main/scripts/install.sh | bash
#
# Or with options:
#   curl -fsSL .../install.sh | bash -s -- --yes          # non-interactive (accept all defaults)
#   curl -fsSL .../install.sh | bash -s -- --prefix /opt  # custom install prefix
#
# WHAT THIS SCRIPT DOES:
#   1. Detects your OS and CPU architecture
#   2. Downloads the pre-built alpax binary (or uses local build)
#   3. Asks a few configuration questions (with sensible defaults — just press Enter)
#   4. Downloads the AI embedding model (~22 MB) and tokenizer to ~/.alpax/models/
#   5. Adds alpax to your PATH and displays MCP configuration instructions
# =============================================================================
set -euo pipefail

# ── Colours ──────────────────────────────────────────────────────────────────
if [ -t 1 ]; then
    BOLD="\033[1m"; DIM="\033[2m"; RESET="\033[0m"
    RED="\033[31m"; GREEN="\033[32m"; YELLOW="\033[33m"; CYAN="\033[36m"; BLUE="\033[34m"
else
    BOLD=""; DIM=""; RESET=""; RED=""; GREEN=""; YELLOW=""; CYAN=""; BLUE=""
fi

log_header() { echo -e "\n${BOLD}${CYAN}━━━  $*  ━━━${RESET}"; }
log_ok()     { echo -e "  ${GREEN}✓${RESET}  $*"; }
log_info()   { echo -e "  ${BLUE}→${RESET}  $*"; }
log_warn()   { echo -e "  ${YELLOW}⚠${RESET}  $*"; }
log_err()    { echo -e "  ${RED}✗${RESET}  $*" >&2; }
log_step()   { echo -e "\n${BOLD}${YELLOW}[$1/5]${RESET} $2"; }

# ── Parse flags ──────────────────────────────────────────────────────────────
NON_INTERACTIVE=false
CUSTOM_PREFIX=""
for arg in "$@"; do
    case "$arg" in
        --yes|-y)      NON_INTERACTIVE=true ;;
        --prefix=*)    CUSTOM_PREFIX="${arg#--prefix=}" ;;
        --prefix)      shift; CUSTOM_PREFIX="${1:-}" ;;
    esac
done

ask() {
    # ask <prompt> <default> <varname>
    local prompt="$1" default="$2" varname="$3"
    if $NON_INTERACTIVE; then
        printf -v "$varname" "%s" "$default"
        return
    fi
    local answer
    printf "    %s [%s]: " "$prompt" "$default"
    read -r answer </dev/tty
    printf -v "$varname" "%s" "${answer:-$default}"
}

# ── Banner ────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${CYAN}"
echo "  ╔═══════════════════════════════════════════════════════╗"
echo "  ║         Alpax (अल्प) — Installer                       ║"
echo "  ║  Ultra-lightweight local-first Code Vectorizer MCP    ║"
echo "  ╚═══════════════════════════════════════════════════════╝"
echo -e "${RESET}"

# ── Step 1: Detect platform ───────────────────────────────────────────────────
log_step 1 "Detecting your platform"

OS="$(uname -s)"
ARCH="$(uname -m)"

case "$OS" in
    Linux)  PLATFORM_OS="linux" ;;
    Darwin) PLATFORM_OS="macos" ;;
    *)
        log_err "Unsupported OS: $OS"
        log_err "For Windows, open PowerShell and run:"
        log_err "  irm https://raw.githubusercontent.com/SoumyaRKN/alpax/main/scripts/install.ps1 | iex"
        exit 1
        ;;
esac

case "$ARCH" in
    x86_64|amd64)  PLATFORM_ARCH="x86_64" ;;
    aarch64|arm64) PLATFORM_ARCH="arm64" ;;
    *)
        log_err "Unsupported CPU architecture: $ARCH"
        exit 1
        ;;
esac

PLATFORM="${PLATFORM_OS}-${PLATFORM_ARCH}"
log_ok "Detected: ${BOLD}${OS}${RESET} on ${BOLD}${ARCH}${RESET} → artifact suffix: ${DIM}${PLATFORM}${RESET}"

# ── Step 2: Download binary ───────────────────────────────────────────────────
log_step 2 "Obtaining Alpax binary"

REPO="SoumyaRKN/alpax"
GITHUB_API="https://api.github.com/repos/${REPO}/releases/latest"

# Resolve latest release tag
if command -v curl >/dev/null 2>&1; then
    _dl() { curl -fsSL "$1" -o "$2"; }
    _fetch() { curl -fsSL "$1"; }
elif command -v wget >/dev/null 2>&1; then
    _dl() { wget -q "$1" -O "$2"; }
    _fetch() { wget -q -O- "$1"; }
else
    log_err "Neither curl nor wget found. Please install one and re-run."
    exit 1
fi

# Determine install prefix
if [ -n "${CUSTOM_PREFIX}" ]; then
    BIN_DIR="${CUSTOM_PREFIX}/bin"
else
    BIN_DIR="${HOME}/.local/bin"
fi
mkdir -p "${BIN_DIR}"

BINARY_INSTALLED=false

# First, check if a local release build exists in current repo
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || echo "")"
LOCAL_BUILD=""
if [ -n "${SCRIPT_DIR}" ] && [ -f "${SCRIPT_DIR}/../target/release/alpax" ]; then
    LOCAL_BUILD="${SCRIPT_DIR}/../target/release/alpax"
elif [ -f "./target/release/alpax" ]; then
    LOCAL_BUILD="./target/release/alpax"
fi

if [ -n "${LOCAL_BUILD}" ]; then
    log_info "Found locally compiled binary: ${LOCAL_BUILD}"
    cp -f "${LOCAL_BUILD}" "${BIN_DIR}/alpax"
    chmod +x "${BIN_DIR}/alpax"
    BINARY_INSTALLED=true
    log_ok "Binary installed from local build → ${BOLD}${BIN_DIR}/alpax${RESET}"
fi

if [ "${BINARY_INSTALLED}" = false ]; then
    log_info "Fetching latest release information from GitHub..."
    LATEST_TAG=$(_fetch "${GITHUB_API}" 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['tag_name'])" 2>/dev/null || true)

    if [ -z "${LATEST_TAG}" ]; then
        log_warn "Could not fetch latest release tag — defaulting to 'v1.0.0'"
        LATEST_TAG="v1.0.0"
    fi
    log_ok "Latest release: ${BOLD}${LATEST_TAG}${RESET}"

    # Construct artifact URL
    ARCHIVE_NAME="alpax-${LATEST_TAG}-${PLATFORM}.tar.gz"
    DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${LATEST_TAG}/${ARCHIVE_NAME}"

    TMPDIR_WORK="$(mktemp -d)"
    trap 'rm -rf "${TMPDIR_WORK}"' EXIT

    log_info "Downloading ${ARCHIVE_NAME}..."
    if _dl "${DOWNLOAD_URL}" "${TMPDIR_WORK}/${ARCHIVE_NAME}" 2>/dev/null; then
        log_info "Extracting binary..."
        tar xzf "${TMPDIR_WORK}/${ARCHIVE_NAME}" -C "${TMPDIR_WORK}"
        BINARY_SRC="$(find "${TMPDIR_WORK}" -name "alpax" -type f | head -1)"
        if [ -n "${BINARY_SRC}" ]; then
            cp -f "${BINARY_SRC}" "${BIN_DIR}/alpax"
            chmod +x "${BIN_DIR}/alpax"
            BINARY_INSTALLED=true
            log_ok "Binary installed → ${BOLD}${BIN_DIR}/alpax${RESET}"
        fi
    fi
fi

if [ "${BINARY_INSTALLED}" = false ]; then
    # If already installed in PATH, reuse it
    EXISTING_BIN="$(command -v alpax 2>/dev/null || true)"
    if [ -n "${EXISTING_BIN}" ] && [ -x "${EXISTING_BIN}" ]; then
        log_warn "Could not download remote binary, but found existing alpax at ${EXISTING_BIN}."
        cp -f "${EXISTING_BIN}" "${BIN_DIR}/alpax"
        BINARY_INSTALLED=true
    else
        log_err "Failed to download pre-built binary: ${DOWNLOAD_URL}"
        log_err "If you have Rust installed, you can build from source:"
        log_err "  cargo build --release"
        log_err "and re-run this script."
        exit 1
    fi
fi

export PATH="${BIN_DIR}:${PATH}"

# ── Step 3: Configuration ─────────────────────────────────────────────────────
log_step 3 "Configuration"

ALPAX_HOME="${HOME}/.alpax"
MODELS_DIR="${ALPAX_HOME}/models"
DB_DIR="${ALPAX_HOME}/db"
GLOBAL_CONFIG="${ALPAX_HOME}/alpax.toml"

mkdir -p "${MODELS_DIR}" "${DB_DIR}"

echo ""
echo -e "  ${DIM}All settings have sensible defaults. Press ${BOLD}Enter${RESET}${DIM} to accept them.${RESET}"
echo -e "  ${DIM}You can change any setting later by editing: ${GLOBAL_CONFIG}${RESET}"
echo ""

ask "Installation directory for binary" "${BIN_DIR}"     _BIN_DIR
ask "Data directory (models, DB, config)" "${ALPAX_HOME}" _ALPAX_HOME
ask "Chunk size — lines per code snippet"  "50"           CFG_CHUNK_SIZE
ask "Chunk overlap — shared lines"         "10"           CFG_OVERLAP

# Apply user-provided overrides
BIN_DIR="${_BIN_DIR}"
ALPAX_HOME="${_ALPAX_HOME}"
MODELS_DIR="${ALPAX_HOME}/models"
DB_DIR="${ALPAX_HOME}/db"
GLOBAL_CONFIG="${ALPAX_HOME}/alpax.toml"
mkdir -p "${MODELS_DIR}" "${DB_DIR}" "${BIN_DIR}"

# Move binary if path changed
if [ ! -f "${BIN_DIR}/alpax" ] || [ "${BIN_DIR}/alpax" != "$(which alpax 2>/dev/null || true)" ]; then
    cp -f "$(which alpax 2>/dev/null || echo "${HOME}/.local/bin/alpax")" "${BIN_DIR}/alpax" 2>/dev/null || true
    chmod +x "${BIN_DIR}/alpax"
fi

# Validate numerics
[[ "${CFG_CHUNK_SIZE}" =~ ^[1-9][0-9]*$ ]] || { log_warn "Invalid chunk size, using 50"; CFG_CHUNK_SIZE=50; }
[[ "${CFG_OVERLAP}" =~ ^[0-9]+$ ]]          || { log_warn "Invalid overlap, using 10";    CFG_OVERLAP=10; }

log_ok "Configuration accepted"

# ── Step 4: Download models ───────────────────────────────────────────────────
log_step 4 "Downloading AI embedding models"

MODEL_FILE="${MODELS_DIR}/all-MiniLM-L6-v2.onnx"
TOKENIZER_FILE="${MODELS_DIR}/tokenizer.json"
MODEL_URL="https://huggingface.co/Xenova/all-MiniLM-L6-v2/resolve/main/onnx/model_quantized.onnx"
TOKENIZER_URL="https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2/resolve/main/tokenizer.json"

_download_asset() {
    local url="$1" dest="$2" label="$3"
    if [ -f "${dest}" ]; then
        log_ok "${label} already present — skipping"
        return
    fi
    log_info "Downloading ${label}..."
    if command -v curl >/dev/null 2>&1; then
        curl -fL --progress-bar "${url}" -o "${dest}" 2>&1 | sed 's/^/    /'
    else
        wget -q --show-progress "${url}" -O "${dest}" 2>&1 | sed 's/^/    /'
    fi
    log_ok "${label} downloaded"
}

_download_asset "${MODEL_URL}"     "${MODEL_FILE}"     "Embedding model (INT8 ONNX, ~22 MB)"
_download_asset "${TOKENIZER_URL}" "${TOKENIZER_FILE}" "Tokenizer (~450 KB)"

# Write global config
cat > "${GLOBAL_CONFIG}" <<TOML
# Alpax (अल्प) — Global Configuration
# Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
# Docs:      https://github.com/${REPO}#configuration
#
# This file sets your global defaults.
# Drop an alpax.toml in any project root to override per-project.

model         = "${MODEL_FILE}"
tokenizer     = "${TOKENIZER_FILE}"
db            = "${DB_DIR}"
chunk_size    = ${CFG_CHUNK_SIZE}
chunk_overlap = ${CFG_OVERLAP}
TOML
log_ok "Global config → ${BOLD}${GLOBAL_CONFIG}${RESET}"

# ── Step 5: PATH & shell RC ───────────────────────────────────────────────────
log_step 5 "Finalising PATH and environment"

ALPAX_BIN="${BIN_DIR}/alpax"

_add_to_path() {
    local rc="$1"
    local line='export PATH="'"${BIN_DIR}"':$PATH"'
    [ -f "${rc}" ] && grep -q "${BIN_DIR}" "${rc}" 2>/dev/null && return
    {   echo ""
        echo "# Added by Alpax installer (https://github.com/${REPO})"
        echo "${line}"
    } >> "${rc}"
    log_ok "PATH updated in ${DIM}${rc}${RESET}"
}

case "${SHELL:-/bin/sh}" in
    */zsh)  _add_to_path "${HOME}/.zshrc" ;;
    */bash)
        _add_to_path "${HOME}/.bashrc"
        [ -f "${HOME}/.bash_profile" ] && _add_to_path "${HOME}/.bash_profile"
        ;;
    */fish)
        FISH_CONF="${HOME}/.config/fish/config.fish"
        mkdir -p "$(dirname "${FISH_CONF}")"
        if [ -f "${FISH_CONF}" ] && ! grep -q "${BIN_DIR}" "${FISH_CONF}" 2>/dev/null; then
            echo "" >> "${FISH_CONF}"
            echo "# Added by Alpax installer" >> "${FISH_CONF}"
            echo "fish_add_path ${BIN_DIR}" >> "${FISH_CONF}"
            log_ok "PATH updated in ${DIM}${FISH_CONF}${RESET}"
        fi
        ;;
    *)
        _add_to_path "${HOME}/.profile"
        ;;
esac

# ── Final summary ─────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${GREEN}"
echo "  ╔═══════════════════════════════════════════════════════╗"
echo "  ║          🎉  Alpax is installed and ready!           ║"
echo "  ╚═══════════════════════════════════════════════════════╝"
echo -e "${RESET}"

echo -e "  ${DIM}Binary:${RESET}    ${BOLD}${ALPAX_BIN}${RESET}"
echo -e "  ${DIM}Models:${RESET}    ${MODELS_DIR}"
echo -e "  ${DIM}Config:${RESET}    ${GLOBAL_CONFIG}"
echo -e "  ${DIM}Vector DB:${RESET} ${DB_DIR}  (auto-created per project)"
echo ""

echo -e "${BOLD}${CYAN}━━━  AI Coding Agent Configuration  ━━━${RESET}"
echo "  Alpax is designed to work with any Model Context Protocol (MCP) compatible agent."
echo "  To use Alpax, please add it to your coding agent's MCP configuration."
echo ""
echo -e "  ${BOLD}Standard MCP Configuration (JSON):${RESET}"
cat <<SNIPPET
  {
    "mcpServers": {
      "alpax": {
        "command": "${ALPAX_BIN}"
      }
    }
  }
SNIPPET
echo ""
echo -e "  ${BOLD}For Zed Editor (~/.config/zed/settings.json):${RESET}"
cat <<SNIPPET
  {
    "context_servers": {
      "alpax": {
        "command": { "path": "${ALPAX_BIN}", "args": [] },
        "settings": {}
      }
    }
  }
SNIPPET
echo ""
echo -e "  ${BOLD}Common Agent MCP Configuration File Paths:${RESET}"
echo -e "    • ${CYAN}Antigravity CLI (agy)${RESET}     ~/.gemini/config/mcp_config.json"
echo -e "    • ${CYAN}Claude Desktop (Linux)${RESET}    ~/.config/Claude/claude_desktop_config.json"
echo -e "    • ${CYAN}Claude Desktop (macOS)${RESET}    ~/Library/Application Support/Claude/claude_desktop_config.json"
echo -e "    • ${CYAN}Claude Code CLI${RESET}           ~/.claude.json"
echo -e "    • ${CYAN}Cursor IDE${RESET}                ~/.cursor/mcp.json"
echo -e "    • ${CYAN}Windsurf IDE${RESET}              ~/.codeium/windsurf/mcp_config.json"
echo -e "    • ${CYAN}VS Code (Cline)${RESET}           ~/.cline/mcp_settings.json"
echo -e "    • ${CYAN}VS Code (Roo Code)${RESET}        ~/.roo/mcp.json"
echo -e "    • ${CYAN}VS Code (Continue)${RESET}        ~/.continue/config.json"
echo -e "    • ${CYAN}Zed Editor${RESET}                ~/.config/zed/settings.json"
echo -e "    • ${CYAN}Neovim (mcphub.nvim)${RESET}      ~/.config/mcphub/servers.json"
echo ""
echo -e "  ${YELLOW}After updating your agent's config, restart the agent to connect.${RESET}"
echo ""
echo "  Restart your terminal or run one of:"
echo -e "    ${DIM}source ~/.zshrc${RESET}   ${DIM}source ~/.bashrc${RESET}   ${DIM}source ~/.profile${RESET}"
echo ""
