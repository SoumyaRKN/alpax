# Alpax Developer Guide & Verification Checklist

This document details the development environment setup, build instructions, testing procedures, and verification checklist for the **Alpax** workspace.

---

## 1. Prerequisites

- **Rust**: Version 1.75+ (Edition 2021). Tested with Rust 1.98.1.
- **Tools**: `cargo`, `rustc`, `clippy`, `rustfmt`.
- **System**: Linux x86_64 / aarch64, macOS, or Windows with standard C runtime.
- **Disk Space**: ~150MB for ONNX model weights and tokenizer files.

---

## 2. Setup & Asset Provisioning

Run the installer to download the binary, quantized `all-MiniLM-L6-v2` ONNX model, and tokenizer configuration:

```bash
bash scripts/install.sh
```

Non-interactive setup using all defaults:
```bash
bash scripts/install.sh --yes
```

The script provisions:
- `models/all-MiniLM-L6-v2.onnx` (quantized INT8 model, ~23MB)
- `models/tokenizer.json` (~700KB)
- `alpax.toml` (system configuration file)

---

## 3. Configuration System

Configuration is loaded in the following order of precedence:
1. Direct runtime arguments in MCP tool calls.
2. Environment variables:
   - `ALPAX_MODEL_PATH`: Path to ONNX model (default: `./models/all-MiniLM-L6-v2.onnx`)
   - `ALPAX_TOKENIZER_PATH`: Path to HuggingFace tokenizer JSON (default: `./models/tokenizer.json`)
   - `ALPAX_DB_PATH`: LanceDB database directory (default: `./.alpax_vector_db`)
   - `ALPAX_CHUNK_SIZE`: Number of lines per chunk (default: `50`)
   - `ALPAX_CHUNK_OVERLAP`: Overlap line count between consecutive chunks (default: `10`)
3. `alpax.toml` configuration file in project root or current working directory:
   ```toml
   model = "models/all-MiniLM-L6-v2.onnx"
   tokenizer = "models/tokenizer.json"
   db = ".alpax_vector_db"
   chunk_size = 50
   chunk_overlap = 10
   ```
4. Built-in system defaults.

---

## 4. Verification Checklist

Execute these commands in sequence to guarantee zero regressions:

### 4.1 Automated Assets Check
```bash
test -f models/all-MiniLM-L6-v2.onnx && test -f models/tokenizer.json
```

### 4.2 Workspace Type Check
```bash
cargo check --workspace
```

### 4.3 Test Suite Execution
```bash
cargo test --workspace
```

### 4.4 Linter & Idiom Check
```bash
cargo clippy --workspace -- -D warnings
```

### 4.5 Release Optimization Build
```bash
cargo build --release
```

Binary output will be located at `target/release/alpax`.

---

## 5. Integrating with MCP Clients

### Claude Desktop / Cursor / Antigravity (`mcp_config.json`)

Add the Alpax server under your MCP client configuration:

```json
{
  "mcpServers": {
    "alpax": {
      "command": "/absolute/path/to/alpax/target/release/alpax",
      "args": [],
      "env": {
        "ALPAX_MODEL_PATH": "/absolute/path/to/alpax/models/all-MiniLM-L6-v2.onnx",
        "ALPAX_TOKENIZER_PATH": "/absolute/path/to/alpax/models/tokenizer.json",
        "ALPAX_DB_PATH": "/absolute/path/to/alpax/.alpax_vector_db"
      }
    }
  }
}
```
