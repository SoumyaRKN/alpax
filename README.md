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

## 🚀 Quick Start Guide (For All Users)

### 1-Click Universal Installer (Recommended)

No manual path copying or environment configuration required. The installer sets up the `alpax` binary, downloads centralized models to `~/.alpax/models/`, and automatically detects and configures **Claude Desktop**, **Cursor**, and other MCP clients.

#### On macOS & Linux:
Run in your terminal:
```bash
bash scripts/install.sh
```

#### On Windows:
Open PowerShell and run:
```powershell
powershell -ExecutionPolicy Bypass -File scripts\install.ps1
```

---

### Manual Build / Developer Setup
If you prefer building from source manually:
```bash
git clone https://github.com/sourceround/alpax.git
cd alpax
bash scripts/setup.sh --yes
cargo build --release
```
The compiled, standalone binary will be located at `target/release/alpax`.

---

## 🔌 Connecting to Your AI Agent (MCP Integration)

Alpax communicates over standard input/output (`stdio`) via JSON-RPC 2.0.

### 1. Claude Desktop

Add Alpax to your `claude_desktop_config.json`:
- **macOS**: `~/Library/Application Support/Claude/claude_desktop_config.json`
- **Linux**: `~/.config/Claude/claude_desktop_config.json`
- **Windows**: `%APPDATA%\Claude\claude_desktop_config.json`

```json
{
  "mcpServers": {
    "alpax": {
      "command": "/ABSOLUTE/PATH/TO/alpax/target/release/alpax",
      "args": [],
      "env": {
        "ALPAX_MODEL_PATH": "/ABSOLUTE/PATH/TO/alpax/models/all-MiniLM-L6-v2.onnx",
        "ALPAX_TOKENIZER_PATH": "/ABSOLUTE/PATH/TO/alpax/models/tokenizer.json",
        "ALPAX_DB_PATH": "/ABSOLUTE/PATH/TO/alpax/.alpax_vector_db"
      }
    }
  }
}
```

> **Note**: Always use absolute paths in the configuration.

---

### 2. Cursor IDE

1. Open **Cursor Settings** (`Ctrl+,` or `Cmd+,`).
2. Navigate to **Features** -> **MCP Servers**.
3. Click **+ Add New MCP Server**.
4. Fill in the details:
   - **Name**: `alpax`
   - **Type**: `stdio`
   - **Command**: `/ABSOLUTE/PATH/TO/alpax/target/release/alpax`

---

### 3. Antigravity / Cline / Roo Code

Add the server to your settings file:

```json
{
  "mcpServers": {
    "alpax": {
      "command": "/ABSOLUTE/PATH/TO/alpax/target/release/alpax",
      "args": []
    }
  }
}
```

---

## 💡 How to Use with Your AI Agent

Once connected, your AI agent automatically gains access to Alpax's semantic tools:

### Zero-Friction Out-of-the-Box Operation
**You don't even have to tell Alpax to index!** When you ask your first question about any project, Alpax detects that the index is new and automatically indexes the codebase before answering.

### Natural Language Semantic Search
Ask your assistant questions about any codebase in plain English:

> *"Where is JWT authentication and token verification implemented?"*  
> *"Find where vector mean-pooling and L2 normalization occur."*  
> *"Show me how errors are mapped to JSON-RPC codes."*

### Explicit Incremental Re-Indexing (Optional)
If you made significant changes and want to trigger a manual refresh:

> *"Please re-index this workspace using Alpax."*

Alpax uses BLAKE3 cryptographic streaming digests so that unchanged files are skipped in less than 1 millisecond. Only modified files are re-embedded.

When you ask a question, the assistant calls `query_codebase`, which:
1. Vectorizes your natural language prompt.
2. Performs approximate nearest neighbor (ANN) vector search.
3. Passes the matches through the **Context Squeezer** to strip empty lines and redundant tokens.
4. Injects high-density, formatted code spans directly into the conversation:

```markdown
FILE [crates/engine/src/embed.rs]
L95-L115:
```rust
if mask_sum > 0.0 {
    for val in pooled.iter_mut().take(hidden_dim) {
        *val /= mask_sum;
    }
}

// L2 normalize
let norm: f32 = pooled.iter().map(|v| v * v).sum::<f32>().sqrt();
if norm > 1e-12 {
    for val in pooled.iter_mut().take(hidden_dim) {
        *val /= norm;
    }
}
```
```

---

## ⚙️ Configuration & Customization

Alpax is config-driven and respects parameters in the following priority order:
1. Arguments passed to MCP tool calls.
2. Environment variables.
3. `alpax.toml` in your working directory.
4. Built-in defaults.

### Configuration File (`alpax.toml`)
Created automatically when running `scripts/setup.sh`:

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
