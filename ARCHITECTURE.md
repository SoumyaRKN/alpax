# ARCHITECTURE.md: Alpax System Architecture

Alpax (अल्प) is an ultra-low-footprint, local-first Code Vectorizer and Context-Squeezing Model Context Protocol (MCP) server written in native Rust.

```
                    ┌────────────────────────────────────────┐
                    │          MCP Client (LLM Agent)         │
                    │   (Cursor, Claude Desktop, Antigravity)│
                    └───────────────────▲────────────────────┘
                                        │ stdio (JSON-RPC 2.0)
                                        │ stdout: responses
                                        │ stdin: requests
                                        ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│ crates/server: MCP Server                                                       │
│                                                                                 │
│  - proto: JSON-RPC 2.0 Parser & Serializer                                      │
│  - dispatch: Request Router                                                     │
│      ├── initialize                                                             │
│      ├── tools/list: [index_workspace, query_codebase]                          │
│      └── tools/call                                                             │
│             │                                                                   │
│             ├───────────────┐                                                   │
│             ▼               ▼                                                   │
│      [index_workspace]  [query_codebase]                                        │
└─────────────┼───────────────┼───────────────────────────────────────────────────┘
              │               │
              ▼               ▼
┌─────────────────────────────┼───────────────────────────────────────────────────┐
│ crates/engine: Core Engine  │                                                   │
│                             │                                                   │
│  1. hash: Hasher            │                                                   │
│     - BLAKE3 64KB Streaming │                                                   │
│     - Dirty Cache Check     │                                                   │
│                             │                                                   │
│  2. slice: Slicer           │                                                   │
│     - ignore::WalkBuilder   │                                                   │
│     - Sliding Window Slices │                                                   │
│                             │                                                   │
│  3. embed: Embedder         │                                                   │
│     - Quantized INT8 ONNX   │ 3. embed: Embedder                                │
│     - Tokenizer (HF onig)   │    - Vectorize search prompt (dim 384)            │
│     - Mean Pooling + L2     │                                                   │
│                             │                                                   │
│  4. store: Store (LanceDB)  │ 4. store: Store (LanceDB)                         │
│     - Arrow RecordBatch     │    - ANN Vector Search (cosine / L2)              │
│     - FixedSizeList<f32,384>│    - Returns Vec<Hit>                             │
└─────────────────────────────┼───────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│ crates/squeeze: Context Pruning & Squeezing                                      │
│                                                                                 │
│  - prune: Pruner                                                                │
│      - Groups hits by file path                                                 │
│      - Sorts lines monotonically                                                │
│      - Strips empty / whitespace-only lines                                     │
│      - Formats compact Markdown blocks: FILE [<path>] L<start>-<end>            │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## 1. Subsystem Breakdown

### 1.1 `crates/core` (`alpax-core`)
Fundamental data transfer objects (DTOs) and shared types with zero heavy dependencies:
- **`Chunk`**: A contiguous block of code extracted from a source file, with 1-based start and end line numbers.
- **`Hit`**: A semantic search match returned by the vector index, containing chunk content, line span, and cosine similarity score.
- **`Config`**: Dynamic system configuration supporting default constants, environment variables (`ALPAX_*`), and persistent configuration files (`alpax.toml`).

### 1.2 `crates/engine` (`alpax-engine`)
Local vector search and indexing infrastructure:
- **`hash` (`Hasher`)**: Computes BLAKE3 cryptographic digests using 64KB chunk buffers. Maintains an in-memory hash cache to skip unchanged files during incremental indexing.
- **`slice` (`Slicer`)**: Traverses workspaces respecting `.gitignore`, filters out binary and lock files, and slices text into configurable sliding windows (default 50 lines, 10 overlap).
- **`embed` (`Embedder`)**: Runs quantized INT8 `all-MiniLM-L6-v2` ONNX models using the CPU execution provider. Features attention-mask-weighted mean pooling and vector L2 normalization to produce 384-dimensional unit embeddings.
- **`store` (`Store`)**: Wraps LanceDB for serverless, low-latency disk-backed vector storage. Converts chunks and embeddings into Apache Arrow record batches (`FixedSizeListArray<Float32, 384>`) and executes approximate nearest neighbor (ANN) searches.

### 1.3 `crates/squeeze` (`alpax-squeeze`)
Context optimization and compression:
- **`prune` (`Pruner`)**: Eliminates whitespace fluff, groups multiple hits belonging to the same source file, orders line numbers, and builds condensed code representations to conserve LLM token budgets.

### 1.4 `crates/server` (`alpax`)
The stdio MCP daemon:
- **`proto`**: Implements JSON-RPC 2.0 framing without bloated server frameworks.
- **`dispatch`**: Routes MCP lifecycle methods (`initialize`, `tools/list`, `tools/call`).
- **`main`**: Sets up `tracing` to output strictly to `std::io::stderr`, reads line-delimited JSON-RPC requests from `stdin`, executes operations through shared thread-safe state (`Arc<Mutex<State>>`), and writes responses to `stdout`.

---

## 2. End-to-End Data Flows

### 2.1 Indexing Pipeline (`index_workspace`)
1. Client issues `tools/call` with tool name `index_workspace` and workspace `path`.
2. `Slicer::scan` walks the path, pruning ignored files, hidden directories, and binaries.
3. For each file candidate, `Hasher::dirty` computes its BLAKE3 hash and checks against previous indexing state.
4. Dirty files are parsed into overlapping chunks via `Slicer::slice`.
5. Text chunks are batched into `Embedder::batch`, producing `[N, 384]` normalized float vectors.
6. Chunks and vectors are serialized into Arrow record batches and committed to LanceDB table `"chunks"` via `Store::save`.
7. Summary response containing indexed and skipped counts is returned via JSON-RPC.

### 2.2 Query Pipeline (`query_codebase`)
1. Client issues `tools/call` with tool name `query_codebase`, a query `prompt`, and an optional `limit`.
2. Query text is converted to a 384-d vector via `Embedder::single`.
3. LanceDB executes an ANN vector search via `Store::find`, returning the top-k matches as `Vec<Hit>`.
4. `Pruner::squeeze` groups matches by file, strips empty lines, orders line numbers, and formats an LLM-optimized context block.
5. The squeezed context block is returned to the client in the MCP tool response.

---

## 3. Configuration & Observability

- **Configuration Priority**:
  1. Explicit parameters passed to MCP tools.
  2. Environment variables (`ALPAX_MODEL_PATH`, `ALPAX_TOKENIZER_PATH`, `ALPAX_DB_PATH`, `ALPAX_CHUNK_SIZE`, `ALPAX_CHUNK_OVERLAP`).
  3. `alpax.toml` in project or working directory.
  4. Built-in defaults.
- **Observability**:
  - `stdout`: Reserved exclusively for newline-delimited JSON-RPC 2.0.
  - `stderr`: Structured diagnostic logs via `tracing_subscriber::fmt().with_writer(std::io::stderr)`.
