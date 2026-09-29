#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# Alpax (अल्प) Universal 1-Click Installer for Linux & macOS
# Designed for non-technical users to set up Alpax with zero manual steps.
# -----------------------------------------------------------------------------

echo "=========================================================="
echo "          Alpax (अल्प) Universal 1-Click Installer"
echo "=========================================================="

HOME_DIR="${HOME:-~}"
ALPAX_HOME="${HOME_DIR}/.alpax"
MODELS_DIR="${ALPAX_HOME}/models"
BIN_DIR="${HOME_DIR}/.local/bin"

mkdir -p "${MODELS_DIR}"
mkdir -p "${BIN_DIR}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || echo "")"
LOCAL_BINARY=""
if [ -n "${SCRIPT_DIR}" ] && [ -f "${SCRIPT_DIR}/../target/release/alpax" ]; then
    LOCAL_BINARY="${SCRIPT_DIR}/../target/release/alpax"
fi

# 1. Install Binary
TARGET_BIN="${BIN_DIR}/alpax"
if [ -n "${LOCAL_BINARY}" ] && [ -f "${LOCAL_BINARY}" ]; then
    echo "📦 Installing alpax binary to ${TARGET_BIN}..."
    cp -f "${LOCAL_BINARY}" "${TARGET_BIN}"
    chmod +x "${TARGET_BIN}"
else
    echo "⬇ Checking local alpax build..."
    if command -v cargo >/dev/null 2>&1; then
        echo "Building optimized alpax binary via cargo..."
        cargo install --path "${SCRIPT_DIR}/../crates/server" --root "${HOME_DIR}/.local"
    else
        echo "Error: Neither prebuilt binary nor cargo was found." >&2
        exit 1
    fi
fi
echo "✓ Binary installed at: ${TARGET_BIN}"

# Ensure ~/.local/bin is in PATH for current session
export PATH="${BIN_DIR}:${PATH}"

# 2. Download Centralized Models to ~/.alpax/models
MODEL_FILE="${MODELS_DIR}/all-MiniLM-L6-v2.onnx"
TOKENIZER_FILE="${MODELS_DIR}/tokenizer.json"

MODEL_URL="https://huggingface.co/Xenova/all-MiniLM-L6-v2/resolve/main/onnx/model_quantized.onnx"
TOKENIZER_URL="https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2/resolve/main/tokenizer.json"

if [ -f "${MODEL_FILE}" ]; then
    echo "✓ Model asset already exists at: ${MODEL_FILE}"
else
    echo "⬇ Downloading lightweight AI embedding model (~22MB)..."
    if command -v curl >/dev/null 2>&1; then
        curl -fL --progress-bar "${MODEL_URL}" -o "${MODEL_FILE}"
    elif command -v wget >/dev/null 2>&1; then
        wget -q --show-progress "${MODEL_URL}" -O "${MODEL_FILE}"
    fi
    echo "✓ Model downloaded."
fi

if [ -f "${TOKENIZER_FILE}" ]; then
    echo "✓ Tokenizer asset already exists at: ${TOKENIZER_FILE}"
else
    echo "⬇ Downloading tokenizer file (~450KB)..."
    if command -v curl >/dev/null 2>&1; then
        curl -fL --progress-bar "${TOKENIZER_URL}" -o "${TOKENIZER_FILE}"
    elif command -v wget >/dev/null 2>&1; then
        wget -q --show-progress "${TOKENIZER_URL}" -O "${TOKENIZER_FILE}"
    fi
    echo "✓ Tokenizer downloaded."
fi

# 3. Auto-configure Claude Desktop if installed
CLAUDE_CONFIG=""
if [ "$(uname)" = "Darwin" ]; then
    CLAUDE_CONFIG="${HOME_DIR}/Library/Application Support/Claude/claude_desktop_config.json"
else
    CLAUDE_CONFIG="${HOME_DIR}/.config/Claude/claude_desktop_config.json"
fi

if [ -d "$(dirname "${CLAUDE_CONFIG}")" ]; then
    echo ""
    echo "🔍 Detected Claude Desktop installation!"
    
    python3 -c "
import json, os, sys

config_path = '${CLAUDE_CONFIG}'
alpax_bin = '${TARGET_BIN}'

try:
    if os.path.exists(config_path):
        with open(config_path, 'r') as f:
            data = json.load(f)
    else:
        data = {}
        
    servers = data.setdefault('mcpServers', {})
    servers['alpax'] = {
        'command': alpax_bin,
        'args': []
    }
    
    with open(config_path, 'w') as f:
        json.dump(data, f, indent=2)
    print('✓ Automatically added Alpax to Claude Desktop configuration at ' + config_path)
except Exception as e:
    print('Notice: Could not automatically update Claude Desktop config: ' + str(e))
" 2>/dev/null || true
fi

echo ""
echo "=========================================================="
echo "🎉 Alpax installation completed successfully!"
echo "=========================================================="
echo ""
echo "You can now use Alpax in your favorite AI editors:"
echo ""
echo "▶ For Cursor IDE:"
echo "  1. Open Cursor Settings -> Features -> MCP Servers"
echo "  2. Click '+ Add New MCP Server'"
echo "  3. Name: alpax | Type: stdio | Command: ${TARGET_BIN}"
echo ""
echo "▶ For Claude Desktop / Cline / Windsurf / Antigravity:"
echo "  Add this to your MCP configuration:"
echo ""
echo "  \"mcpServers\": {"
echo "    \"alpax\": {"
echo "      \"command\": \"${TARGET_BIN}\""
echo "    }"
echo "  }"
echo ""
echo "▶ How to use in any project:"
echo "  Just ask your assistant: 'Where is the auth logic in this codebase?'"
echo "  Alpax indexes your files automatically and returns squeezed context!"
echo "=========================================================="
