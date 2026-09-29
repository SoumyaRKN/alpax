# AGENTS.md: Operational Guidelines for Alpax

This document defines the strict engineering invariants, architectural rules, and operational guidelines governing development and maintenance of the **Alpax** (अल्प) codebase.

---

## 1. Core Principles & Philosophy

Alpax is an ultra-lightweight, local-first Code Vectorizer and Context-Squeezing Model Context Protocol (MCP) server written in native Rust. Its primary mission is to provide semantic code search and maximal token compression for LLM agents without cloud dependencies, heavy runtimes, or excessive memory overhead.

- **DRY (Don't Repeat Yourself)**: Zero duplicate code across crates and modules. Logic lives in a single authoritative location.
- **No Vibe Coding**: Every line of code is production-grade, idiomatic Rust. No placeholders, no `todo!()`, no `unimplemented!()`, and no mock stubs.
- **Single-Word Naming Conventions**: Crates, modules, source files, and primary structs strictly follow single-word lowercase naming:
  - Crates: `core`, `engine`, `squeeze`, `server`
  - Modules & Files: `chunk`, `hit`, `hash`, `slice`, `embed`, `store`, `prune`, `proto`, `dispatch`, `config`
  - Core Types: `Chunk`, `Hit`, `Hasher`, `Slicer`, `Embedder`, `Store`, `Pruner`, `Config`, `State`

---

## 2. Strict Engineering Invariants

### 2.1 Compiler and Linter Invariants
- Code MUST compile cleanly under the latest stable Rust toolchain.
- `cargo check --workspace` must pass with zero errors.
- `cargo clippy --workspace -- -D warnings` must pass with zero warnings.
- Explicit type annotations are required on public APIs and complex inference points.
- Errors must be propagated with typed error types (`thiserror`) or domain context (`anyhow::Result`).

### 2.2 Observability & I/O Isolation
- **MCP Framing Rule**: Standard output (`stdout`) is strictly reserved for standard MCP JSON-RPC 2.0 messages.
- Any unauthorized bytes written to `stdout` will break JSON-RPC parsers in MCP clients (e.g. Claude Desktop, Cursor, Antigravity).
- **All internal logging and diagnostics MUST be sent to `stderr`** via `tracing` with a subscriber explicitly targeting `std::io::stderr`.

### 2.3 Minimal Hardware Footprint
- Designed to run efficiently on a single-core CPU.
- Idle memory footprint must stay under **50MB RAM**.
- Quantized INT8 ONNX inference via `ort` using the native CPU execution provider.
- Prohibited dependencies: No PyTorch, no libtorch, no CUDA, no Python bridge, and no external telemetry or analytics.

### 2.4 Token Conservation
- LLM context windows are finite and costly. The squeezing engine (`squeeze::prune`) must strip redundant whitespace and empty lines, aggregate contiguous spans, group by file, and present dense contextual blocks to maximize context value per token.

### 2.5 Config-Driven Architecture
- All operational parameters (model path, tokenizer path, database path, chunk size, overlap) must have sane defaults, be configurable via interactive setup (`scripts/setup.sh`), configuration files (`alpax.toml`), environment variables, or MCP configuration endpoints.

---

## 3. Development Workflow Checklist

1. **Prior to editing**: Inspect existing modules to reuse established patterns and helpers.
2. **When modifying APIs**: Maintain backwards compatibility for JSON-RPC 2.0 endpoints.
3. **Before commit**:
   - `cargo fmt --check`
   - `cargo clippy --workspace -- -D warnings`
   - `cargo test --workspace`
   - `cargo build --release`
