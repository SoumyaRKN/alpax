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
| `index_workspace` | `path` *(string)*, `force` *(boolean, optional)* | Recursively crawls, hashes, chunks, and vector-indexes the given directory. |
| `reindex_workspace` | `path` *(string, optional)*, `force` *(boolean, default: true)* | Re-indexes workspace files (incremental update or full rebuild). |
| `query_codebase` | `prompt` *(string, required)*, `limit` *(int, default: 5)* | Performs semantic ANN vector search and returns squeezed context blocks. |
| `get_config` | *none* | Returns the current operational configuration. |
| `set_config` | `chunk_size` *(int)*, `chunk_overlap` *(int)* | Dynamically adjusts chunking parameters at runtime. |

---

## 💡 User Guide: Maximizing Context & Saving Tokens with Prompts

Alpax is designed to eliminate context window exhaustion. Large language models quickly degrade in reasoning quality and become slow or expensive when full source files (containing hundreds of lines of imports, boilerplate, and blank lines) are repeatedly dumped into context.

By pairing Alpax with well-crafted agent instructions and prompts, you can achieve **up to 70–90% token reduction** with **zero quality loss**.

### 1. Configure Your Agent System Instructions
To make your AI agent proactively utilize Alpax instead of reading whole files into context, add the following directive to your project's agent rules file (e.g. `AGENTS.md`, `.cursorrules`, `CLAUDE.md`, or your agent's system prompt):

```markdown
### Codebase Exploration & Token Conservation
- When searching for functionality, references, or bug origins, ALWAYS use the Alpax `query_codebase` tool before reading raw files.
- Never dump entire source files into context unless full file modification is explicitly required.
- Rely on Alpax squeezed context blocks (`FILE [<path>] L<start>-<end>`) to pinpoint exact line spans.
- Run `reindex_workspace(force: false)` after significant code refactoring to keep the semantic index fresh.
```

### 2. Prompting Strategies for Maximal Quality & Efficiency

#### A. Use Semantic Descriptions Instead of Single Keywords
Alpax uses a deep 384-dimensional dense embedding model (`all-MiniLM-L6-v2`). Natural language descriptions match semantics far better than simple substring keywords:
* ❌ **Poor (Keyword)**: `"auth"`
* ✅ **Optimal (Semantic)**: `"middleware verifying JWT tokens and validating expiration timestamps"`

#### B. Scope the Context Limit
Control the number of matches retrieved using the `limit` parameter:
* **Pinpointed lookups (`limit: 2-3`)**: When finding a specific error code, constant, or utility function signature.
* **Feature implementations (`limit: 5`, default)**: Ideal balance of context density and token consumption for general tasks.
* **Architectural surveys (`limit: 8-10`)**: When mapping cross-module dependencies or tracing end-to-end data flows.

#### C. Zero Quality Loss: How Context Squeezing Works
When `query_codebase` runs, Alpax's internal squeezing engine:
1. **Groups contiguous and overlapping line slices** by file to prevent duplicate token reading.
2. **Sorts line spans sequentially** so your LLM reads coherent logic flows.
3. **Strips fluff & blank padding** while preserving code structure and line numbers (`L<start>-<end>`).
4. **Enables targeted file reads**: If an agent needs deeper context, it already has the exact file path and line numbers to inspect a targeted slice rather than the entire file.

### 3. Comparison: Raw File Reads vs. Alpax Context Squeezing

| Metric | Raw File Reading (`cat` / read tool) | Alpax Semantic Squeeze (`query_codebase`) |
| :--- | :--- | :--- |
| **Token Consumption** | ~3,000 – 12,000+ tokens per search | ~200 – 800 tokens per search |
| **Context Window Pollution** | High (imports, comments, blank lines) | Minimal (dense, high-signal logic spans) |
| **Search Accuracy** | Exact keyword only | Conceptual / semantic understanding |
| **Model Attention Retention** | Diluted across large context | Focused on relevant code snippets |
| **Speed** | Slow sequential crawling | Sub-millisecond ANN vector retrieval |

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
