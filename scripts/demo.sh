#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
BINARY="${ROOT_DIR}/target/release/alpax"

if [ ! -f "${BINARY}" ]; then
    echo "Release binary not found. Building with cargo build --release..."
    cargo build --release --manifest-path "${ROOT_DIR}/Cargo.toml"
fi

echo "=========================================================="
echo "          Alpax (अल्प) Live MCP Demo"
echo "=========================================================="
echo ""
echo "1. Initializing MCP Handshake & Listing Available Tools..."
printf '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05"}}\n{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}\n' | "${BINARY}"
echo ""

echo "2. Indexing workspace (crates/core)..."
printf '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"index_workspace","arguments":{"path":"crates/core"}}}\n' | "${BINARY}"
echo ""

echo "3. Querying codebase: 'Chunk struct start and end lines'..."
printf '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"query_codebase","arguments":{"prompt":"Chunk struct start and end lines","limit":2}}}\n' | "${BINARY}"
echo ""

echo "=========================================================="
echo "✓ Demo completed successfully!"
echo "=========================================================="
