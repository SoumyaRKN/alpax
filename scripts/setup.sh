#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------------------------
# Alpax (अल्प) Setup & Asset Provisioning Script
# Downloads quantized ONNX model + tokenizer and configures alpax.toml
# ------------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
MODELS_DIR="${ROOT_DIR}/models"

MODEL_URL="https://huggingface.co/Xenova/all-MiniLM-L6-v2/resolve/main/onnx/model_quantized.onnx"
TOKENIZER_URL="https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2/resolve/main/tokenizer.json"

DEFAULT_MODEL_PATH="models/all-MiniLM-L6-v2.onnx"
DEFAULT_TOKENIZER_PATH="models/tokenizer.json"
DEFAULT_DB_PATH=".alpax_vector_db"
DEFAULT_CHUNK_SIZE="50"
DEFAULT_CHUNK_OVERLAP="10"

NON_INTERACTIVE=false

for arg in "$@"; do
    case "$arg" in
        -y|--yes|--non-interactive|--default)
            NON_INTERACTIVE=true
            shift
            ;;
        *)
            ;;
    esac
done

echo "=========================================================="
echo "           Alpax (अल्प) Environment Setup"
echo "=========================================================="

mkdir -p "${MODELS_DIR}"

# 0. Check and setup protoc if needed
if ! command -v protoc >/dev/null 2>&1; then
    echo "⬇ Installing protoc binary to ~/.local/bin..."
    mkdir -p ~/.local/bin ~/.local/include
    PROTOC_ZIP_URL="https://github.com/protocolbuffers/protobuf/releases/download/v25.2/protoc-25.2-linux-x86_64.zip"
    TMP_ZIP="/tmp/protoc-$$.zip"
    TMP_DIR="/tmp/protoc-$$"
    if command -v curl >/dev/null 2>&1; then
        curl -fSL "${PROTOC_ZIP_URL}" -o "${TMP_ZIP}"
    elif command -v wget >/dev/null 2>&1; then
        wget -q "${PROTOC_ZIP_URL}" -O "${TMP_ZIP}"
    fi
    if [ -f "${TMP_ZIP}" ]; then
        unzip -q "${TMP_ZIP}" -d "${TMP_DIR}"
        cp "${TMP_DIR}/bin/protoc" ~/.local/bin/
        chmod +x ~/.local/bin/protoc
        rm -rf "${TMP_DIR}" "${TMP_ZIP}"
        echo "✓ protoc installed: $(~/.local/bin/protoc --version)"
    fi
fi

# Ensure lance recursion limit in cargo registry if present
for lance_lib in ~/.cargo/registry/src/index.crates.io-*/lance-0.10.18/src/lib.rs; do
    if [ -f "${lance_lib}" ]; then
        if ! grep -q "recursion_limit" "${lance_lib}"; then
            echo "Applying recursion_limit patch to ${lance_lib}..."
            sed -i '1s/^/#![recursion_limit = "512"]\n/' "${lance_lib}"
        fi
    fi
done

# 1. Download Model
TARGET_MODEL="${ROOT_DIR}/${DEFAULT_MODEL_PATH}"
if [ -f "${TARGET_MODEL}" ]; then
    echo "✓ Model asset already exists at: ${TARGET_MODEL}"
else
    echo "⬇ Downloading quantized INT8 ONNX model from HuggingFace..."
    if command -v curl >/dev/null 2>&1; then
        curl -fL --progress-bar "${MODEL_URL}" -o "${TARGET_MODEL}"
    elif command -v wget >/dev/null 2>&1; then
        wget -q --show-progress "${MODEL_URL}" -O "${TARGET_MODEL}"
    else
        echo "Error: Neither curl nor wget is installed." >&2
        exit 1
    fi
    echo "✓ Model downloaded to ${TARGET_MODEL}"
fi

# 2. Download Tokenizer
TARGET_TOKENIZER="${ROOT_DIR}/${DEFAULT_TOKENIZER_PATH}"
if [ -f "${TARGET_TOKENIZER}" ]; then
    echo "✓ Tokenizer asset already exists at: ${TARGET_TOKENIZER}"
else
    echo "⬇ Downloading tokenizer.json..."
    if command -v curl >/dev/null 2>&1; then
        curl -fL --progress-bar "${TOKENIZER_URL}" -o "${TARGET_TOKENIZER}"
    elif command -v wget >/dev/null 2>&1; then
        wget -q --show-progress "${TOKENIZER_URL}" -O "${TARGET_TOKENIZER}"
    else
        echo "Error: Neither curl nor wget is installed." >&2
        exit 1
    fi
    echo "✓ Tokenizer downloaded to ${TARGET_TOKENIZER}"
fi

# 3. Interactive Configuration
CONFIG_FILE="${ROOT_DIR}/alpax.toml"

MODEL_PATH="${DEFAULT_MODEL_PATH}"
TOKENIZER_PATH="${DEFAULT_TOKENIZER_PATH}"
DB_PATH="${DEFAULT_DB_PATH}"
CHUNK_SIZE="${DEFAULT_CHUNK_SIZE}"
CHUNK_OVERLAP="${DEFAULT_CHUNK_OVERLAP}"

if [ "${NON_INTERACTIVE}" = false ] && [ -t 0 ]; then
    echo ""
    echo "--- Configure Alpax Parameters ---"
    
    read -r -p "Model file path [${DEFAULT_MODEL_PATH}]: " USER_MODEL
    [ -n "${USER_MODEL}" ] && MODEL_PATH="${USER_MODEL}"
    
    read -r -p "Tokenizer file path [${DEFAULT_TOKENIZER_PATH}]: " USER_TOKENIZER
    [ -n "${USER_TOKENIZER}" ] && TOKENIZER_PATH="${USER_TOKENIZER}"
    
    read -r -p "LanceDB directory path [${DEFAULT_DB_PATH}]: " USER_DB
    [ -n "${USER_DB}" ] && DB_PATH="${USER_DB}"
    
    read -r -p "Chunk size in lines [${DEFAULT_CHUNK_SIZE}]: " USER_CHUNK
    [ -n "${USER_CHUNK}" ] && CHUNK_SIZE="${USER_CHUNK}"
    
    read -r -p "Chunk overlap in lines [${DEFAULT_CHUNK_OVERLAP}]: " USER_OVERLAP
    [ -n "${USER_OVERLAP}" ] && CHUNK_OVERLAP="${USER_OVERLAP}"
fi

# 4. Write Configuration
cat > "${CONFIG_FILE}" <<EOF
# Alpax Configuration
# Generated during setup. Editable at any time.

model = "${MODEL_PATH}"
tokenizer = "${TOKENIZER_PATH}"
db = "${DB_PATH}"
chunk_size = ${CHUNK_SIZE}
chunk_overlap = ${CHUNK_OVERLAP}
EOF

echo ""
echo "✓ Configuration saved to ${CONFIG_FILE}"
echo "=========================================================="
echo "Alpax setup completed successfully."
echo "=========================================================="
