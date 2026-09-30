# Alpax (अल्प)

> **Ultra-lightweight, local-first Code Vectorizer and Context-Squeezing MCP Server written in native Rust.**

[![Rust](https://img.shields.io/badge/language-Rust-orange.svg)](https://www.rust-lang.org)
[![License: Apache 2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)
[![MCP](https://img.shields.io/badge/protocol-Model%20Context%20Protocol-green.svg)](https://modelcontextprotocol.io)
[![Inference: CPU INT8](https://img.shields.io/badge/inference-Quantized%20INT8%20ONNX-purple.svg)](https://huggingface.co/Xenova/all-MiniLM-L6-v2)

Alpax provides semantic code search and context token compression for AI coding agents (**Claude Desktop**, **Cursor**, **Antigravity**, **Cline**, **Windsurf**, and any MCP-compatible client). It operates **100% locally on your CPU** with zero cloud calls, zero API keys, and zero telemetry.

---

## 🎯 Why Alpax?

Traditional search tools either rely on keyword matching (which misses semantic meaning) or heavyweight Python/CUDA vector databases (which consume gigabytes of RAM and require cloud dependencies).

Alpax solves this with a native, single-binary Rust engine:

* 🔒 **100% Private & Local**: Code embeddings and vector searches execute entirely on your machine.
* ⚡ **Ultra-Low Footprint**: Optimized to run on a single-core CPU with under 50–80 MB idle RAM.
* 📉 **Context Squeezing**: Saves expensive LLM context window tokens by stripping fluff and grouping contiguous spans into dense, high-signal code blocks.
* 🔄 **Sub-millisecond Incremental Indexing**: Uses streaming BLAKE3 hashing to automatically skip unmodified files.
* 📦 **Zero-Configuration Setup**: Single script downloads the INT8 quantized ONNX weights (~22MB) and sets up the server.

---

## 🚀 Quick Start — Install in 30 Seconds

### Linux & macOS

Paste this single command in your terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/sourceround/alpax/main/scripts/install.sh | bash
```

### Windows

Paste this in **PowerShell**:

```powershell
irm https://raw.githubusercontent.com/sourceround/alpax/main/scripts/install.ps1 | iex
```

> **That's it.** The installer will guide you through the rest interactively.

---

### What happens during installation

| Step | What the installer does |
|------|------------------------|
| **1 — Detect platform** | Identifies your OS and CPU architecture automatically |
| **2 — Download binary** | Fetches the prebuilt `alpax` binary from [GitHub Releases](https://github.com/sourceround/alpax/releases/latest) (or uses local build) |
| **3 — Configure** | Asks a few optional questions with sensible defaults (just press **Enter** to skip) |
| **4 — Download models** | Downloads the quantized AI embedding model (~22 MB) and tokenizer once |
| **5 — PATH & Instructions** | Adds the `alpax` binary to your PATH and displays MCP configuration instructions |

After installation, add Alpax to your AI agent's MCP configuration (shown below) and **restart your AI agent**.

---

### Build from Source (developers only)

```bash
git clone https://github.com/sourceround/alpax.git
cd alpax
cargo build --release
bash scripts/install.sh        # runs the installer to configure models and PATH
```

## 🔌 AI Coding Agent MCP Configuration

Alpax provides semantic code search to any MCP-compatible agent. Add the following to your agent's MCP configuration file:

### Standard MCP Configuration (JSON)

```json
{
  "mcpServers": {
    "alpax": {
      "command": "/path/to/alpax"
    }
  }
}
```

> Replace `/path/to/alpax` with the binary path (e.g. `~/.local/bin/alpax` on Linux/macOS, or `%LOCALAPPDATA%\alpax\bin\alpax.exe` on Windows).

### Config File Locations by Agent

| Agent | Config file path |
|-------|-----------------|
| **Antigravity CLI** (`agy`) | `~/.gemini/config/mcp_config.json` |
| **Claude Desktop** (macOS) | `~/Library/Application Support/Claude/claude_desktop_config.json` |
| **Claude Desktop** (Linux) | `~/.config/Claude/claude_desktop_config.json` |
| **Claude Desktop** (Windows) | `%APPDATA%\Claude\claude_desktop_config.json` |
| **Claude Code CLI** | `~/.claude.json` |
| **Cursor IDE** | `~/.cursor/mcp.json` |
| **Windsurf IDE** | `~/.codeium/windsurf/mcp_config.json` |
| **VS Code / Cline** | `~/.cline/mcp_settings.json` |
| **VS Code / Roo Code** | `~/.roo/mcp.json` |
| **VS Code / Continue** | `~/.continue/config.json` |
| **Neovim + mcphub.nvim** | `~/.config/mcphub/servers.json` |

For **Zed**, add to `~/.config/zed/settings.json` under `"context_servers"`:
```json
{
  "context_servers": {
    "alpax": {
      "command": { "path": "/path/to/alpax", "args": [] },
      "settings": {}
    }
  }
}
```

After updating the configuration, **restart your AI agent** to connect.

## ⚙️ Configuration & Customization

Alpax is config-driven and respects parameters in the following priority order:
1. Arguments passed to MCP tool calls.
2. Environment variables.
3. `alpax.toml` in your working directory.
4. Built-in defaults.

### Configuration File (`alpax.toml`)
Created automatically when running `scripts/install.sh`:

```toml
# Path to quantized INT8 ONNX model
model = "models/all-MiniLM-L6-v2.onnx"

# Path to HuggingFace tokenizer JSON
tokenizer = "models/tokenizer.json"

# Directory where local LanceDB vectors are stored
db = ".alpax_vector_db"

# Number of lines per chunk
chunk_size = 50

# Number of overlapping lines between consecutive chunks
chunk_overlap = 10
```

### Environment Variables
| Variable | Default Value | Description |
| :--- | :--- | :--- |
| `ALPAX_MODEL_PATH` | `models/all-MiniLM-L6-v2.onnx` | Path to the ONNX model |
| `ALPAX_TOKENIZER_PATH` | `models/tokenizer.json` | Path to `tokenizer.json` |
| `ALPAX_DB_PATH` | `.alpax_vector_db` | LanceDB data directory |
| `ALPAX_CHUNK_SIZE` | `50` | Lines per chunk window |
| `ALPAX_CHUNK_OVERLAP` | `10` | Overlapping line span |

---

## 🛠️ MCP Tool Reference

| Tool Name | Parameters | Purpose |
| :--- | :--- | :--- |
| `index_workspace` | `path` *(string, required)* | Recursively crawls, hashes, chunks, and vector-indexes the given directory. |
| `query_codebase` | `prompt` *(string, required)*, `limit` *(int, default: 5)* | Performs semantic ANN vector search and returns squeezed context blocks. |
| `get_config` | *none* | Returns the current operational configuration. |
| `set_config` | `chunk_size` *(int)*, `chunk_overlap` *(int)* | Dynamically adjusts chunking parameters at runtime. |

---

## 🏗️ Architecture

```
                    ┌────────────────────────────────────────┐
                    │          MCP Client (LLM Agent)         │
                    │   (Claude Desktop, Cursor, Cline, etc.) │
                    └───────────────────▲────────────────────┘
                                        │ stdio (JSON-RPC 2.0)
                                        │ stdout: clean JSON-RPC
                                        │ stderr: structured logs
                                        ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│ alpax (crates/server): Stdio MCP Daemon                                         │
│                                                                                 │
│   ├── proto: Zero-dependency JSON-RPC 2.0 framing                               │
│   └── dispatch: MCP method routing (initialize, tools/list, tools/call)         │
└───────────────────────────────────────┬─────────────────────────────────────────┘
                                        │
                         ┌──────────────┴──────────────┐
                         ▼                             ▼
┌──────────────────────────────────────────┐ ┌────────────────────────────────────┐
│ alpax-engine (crates/engine)             │ │ alpax-squeeze (crates/squeeze)     │
│                                          │ │                                    │
│ 1. Hasher: BLAKE3 streaming dirty cache  │ │ • Groups hits by file path         │
│ 2. Slicer: Git-aware sliding chunker     │ │ • Sorts line numbers sequentially  │
│ 3. Embedder: INT8 ONNX CPU mean-pooling  │ │ • Strips whitespace noise          │
│ 4. Store: LanceDB + Arrow ANN storage    │ │ • Formats compact LLM blocks       │
└──────────────────────────────────────────┘ └────────────────────────────────────┘
```

---

## ❓ Frequently Asked Questions (FAQ)

### Where is the vector database saved?
By default, in `.alpax_vector_db/` inside your working directory. You can customize this by setting `db = "/path/to/db"` in `alpax.toml` or via the `ALPAX_DB_PATH` environment variable.

### Does Alpax work completely offline?
**Yes.** Once the initial setup script downloads the model assets (`models/`), Alpax requires zero internet connectivity. All embedding generation and vector searches run locally on your CPU.

### Can I run Alpax on a low-end VPS or laptop?
**Yes.** Alpax is designed with extreme resource constraints in mind. It uses less than 80 MB of RAM while running and utilizes optimized INT8 SIMD vector instructions on single-core CPUs.

### How does incremental indexing work?
When you index a workspace, Alpax streams 64KB buffers of each file through BLAKE3 to compute a digest. On subsequent calls, files whose hashes have not changed are skipped instantly (taking < 1 millisecond).

---

## 📜 License

Licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE) for details.
