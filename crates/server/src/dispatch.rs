use crate::proto::{Request, Response};
use alpax_core::Config;
use alpax_engine::{Embedder, Hasher, Slicer, Store};
use alpax_squeeze::Pruner;
use serde_json::{json, Value};
use std::path::Path;
use std::sync::Arc;
use tokio::sync::Mutex;
use tracing::{error, info};

pub struct State {
    pub embedder: Embedder,
    pub store: Store,
    pub hasher: Hasher,
    pub slicer: Slicer,
    pub config: Config,
}

impl State {
    #[must_use]
    pub fn new(
        embedder: Embedder,
        store: Store,
        hasher: Hasher,
        slicer: Slicer,
        config: Config,
    ) -> Self {
        Self {
            embedder,
            store,
            hasher,
            slicer,
            config,
        }
    }
}

pub async fn handle(req: Request, state: Arc<Mutex<State>>) -> Response {
    let id = req.id.clone();
    match req.method.as_str() {
        "initialize" => Response::ok(
            id,
            json!({
                "protocolVersion": "2024-11-05",
                "capabilities": {
                    "tools": {}
                },
                "serverInfo": {
                    "name": "alpax",
                    "version": "0.1.0"
                }
            }),
        ),
        "notifications/initialized" => Response::ok(id, json!({})),
        "tools/list" => Response::ok(
            id,
            json!({
                "tools": [
                    {
                        "name": "index_workspace",
                        "description": "Scan and incrementally vector-index all code files in the given directory path.",
                        "inputSchema": {
                            "type": "object",
                            "properties": {
                                "path": {
                                    "type": "string",
                                    "description": "Absolute or relative path to the workspace root directory."
                                },
                                "force": {
                                    "type": "boolean",
                                    "description": "Force a complete re-index from scratch if true."
                                }
                            }
                        }
                    },
                    {
                        "name": "reindex_workspace",
                        "description": "Re-index workspace files. Use force: true to rebuild the entire index from scratch, or force: false to update only modified files.",
                        "inputSchema": {
                            "type": "object",
                            "properties": {
                                "path": {
                                    "type": "string",
                                    "description": "Path to workspace root (defaults to current directory)."
                                },
                                "force": {
                                    "type": "boolean",
                                    "description": "Rebuild index from scratch if true (default: true)."
                                }
                            }
                        }
                    },
                    {
                        "name": "query_codebase",
                        "description": "Perform semantic vector search against the codebase index and return squeezed context.",
                        "inputSchema": {
                            "type": "object",
                            "properties": {
                                "prompt": {
                                    "type": "string",
                                    "description": "Natural language query or code search term."
                                },
                                "limit": {
                                    "type": "integer",
                                    "description": "Maximum number of chunk matches to retrieve (default: 5)."
                                }
                            },
                            "required": ["prompt"]
                        }
                    },
                    {
                        "name": "get_config",
                        "description": "Retrieve current Alpax configuration settings.",
                        "inputSchema": {
                            "type": "object",
                            "properties": {}
                        }
                    },
                    {
                        "name": "set_config",
                        "description": "Update runtime Alpax configuration parameters.",
                        "inputSchema": {
                            "type": "object",
                            "properties": {
                                "chunk_size": {
                                    "type": "integer",
                                    "description": "Lines per chunk"
                                },
                                "chunk_overlap": {
                                    "type": "integer",
                                    "description": "Overlap line count"
                                }
                            }
                        }
                    }
                ]
            }),
        ),
        "tools/call" => {
            let params = match req.params {
                Some(p) => p,
                None => return Response::err(id, -32602, "Missing params"),
            };

            let tool_name = match params.get("name").and_then(|v| v.as_str()) {
                Some(name) => name,
                None => return Response::err(id, -32602, "Missing tool 'name' parameter"),
            };

            let args = params
                .get("arguments")
                .cloned()
                .unwrap_or_else(|| json!({}));

            match tool_name {
                "index_workspace" => handle_index(id, args, state).await,
                "reindex_workspace" => handle_reindex(id, args, state).await,
                "query_codebase" => handle_query(id, args, state).await,
                "get_config" => handle_get_config(id, state).await,
                "set_config" => handle_set_config(id, args, state).await,
                _ => Response::err(id, -32601, format!("Unknown tool: {tool_name}")),
            }
        }
        _ => Response::err(id, -32601, format!("Method '{}' not found", req.method)),
    }
}

async fn index_internal(st: &mut State, root_path: &Path, force: bool) -> Result<String, String> {
    if force {
        info!("Force re-indexing: clearing hash cache and resetting vector table...");
        st.hasher.clear();
        let _ = st.store.clear().await;
    }

    info!("Starting workspace scan at: {}", root_path.display());
    let current_files = Slicer::scan(root_path);
    info!("Discovered {} candidate files", current_files.len());

    let current_set: std::collections::HashSet<std::path::PathBuf> = current_files
        .iter()
        .map(|p| p.canonicalize().unwrap_or_else(|_| p.clone()))
        .collect();

    // 1. Remove deleted files from LanceDB
    let cached = st.hasher.cached_paths();
    let mut files_deleted = 0usize;
    for cached_path in cached {
        if !current_set.contains(&cached_path) {
            let _ = st.store.remove_file(&cached_path.to_string_lossy()).await;
            st.hasher.remove(&cached_path);
            files_deleted += 1;
        }
    }

    // 2. Scan and slice dirty files
    let mut files_indexed = 0usize;
    let mut files_skipped = 0usize;
    let mut all_chunks = Vec::new();

    for file_path in &current_files {
        if st.hasher.dirty(file_path) {
            // Remove previous chunks for this file if updating to avoid duplication
            let _ = st.store.remove_file(&file_path.to_string_lossy()).await;

            if let Some(chunks) = st.slicer.slice(file_path) {
                if !chunks.is_empty() {
                    files_indexed += 1;
                    all_chunks.extend(chunks);
                } else {
                    files_skipped += 1;
                }
            } else {
                files_skipped += 1;
            }
        } else {
            files_skipped += 1;
        }
    }

    let total_chunks = all_chunks.len();
    if total_chunks > 0 {
        info!(
            "Embedding and saving {} chunks from {} changed files",
            total_chunks, files_indexed
        );

        // Process in small batches (64) to keep memory footprint minimal
        const BATCH_SIZE: usize = 64;
        for chunk_slice in all_chunks.chunks(BATCH_SIZE) {
            let texts: Vec<String> = chunk_slice.iter().map(|c| c.text.clone()).collect();
            let vectors = st
                .embedder
                .batch(&texts)
                .map_err(|e| format!("Embedding error: {e}"))?;

            st.store
                .save(chunk_slice, &vectors)
                .await
                .map_err(|e| format!("Vector store error: {e}"))?;
        }
    }

    let mut parts = Vec::new();
    if files_indexed > 0 {
        parts.push(format!(
            "indexed {files_indexed} changed files ({total_chunks} chunks)"
        ));
    }
    if files_deleted > 0 {
        parts.push(format!("pruned {files_deleted} deleted files"));
    }
    if files_skipped > 0 {
        parts.push(format!("skipped {files_skipped} unchanged files"));
    }

    let summary = if parts.is_empty() {
        "Index is up to date (0 files changed).".to_string()
    } else {
        format!("Indexing complete. {}.", parts.join(", "))
    };

    info!("{summary}");
    Ok(summary)
}

async fn handle_index(id: Option<Value>, args: Value, state: Arc<Mutex<State>>) -> Response {
    let path_str = args.get("path").and_then(|v| v.as_str()).unwrap_or(".");
    let force = args.get("force").and_then(|v| v.as_bool()).unwrap_or(false);

    let root_path = Path::new(path_str);
    if !root_path.exists() {
        return Response::err(
            id,
            -32602,
            format!("Path '{}' does not exist", root_path.display()),
        );
    }

    let mut st = state.lock().await;
    match index_internal(&mut st, root_path, force).await {
        Ok(msg) => Response::ok(
            id,
            json!({
                "content": [
                    {
                        "type": "text",
                        "text": msg
                    }
                ]
            }),
        ),
        Err(e) => {
            error!("Indexing failed: {e}");
            Response::err(id, -32603, e)
        }
    }
}

async fn handle_reindex(id: Option<Value>, args: Value, state: Arc<Mutex<State>>) -> Response {
    let path_str = args.get("path").and_then(|v| v.as_str()).unwrap_or(".");
    let force = args.get("force").and_then(|v| v.as_bool()).unwrap_or(true); // Default to full rebuild for explicit reindex

    let root_path = Path::new(path_str);
    if !root_path.exists() {
        return Response::err(
            id,
            -32602,
            format!("Path '{}' does not exist", root_path.display()),
        );
    }

    let mut st = state.lock().await;
    match index_internal(&mut st, root_path, force).await {
        Ok(msg) => Response::ok(
            id,
            json!({
                "content": [
                    {
                        "type": "text",
                        "text": msg
                    }
                ]
            }),
        ),
        Err(e) => {
            error!("Re-indexing failed: {e}");
            Response::err(id, -32603, e)
        }
    }
}

async fn handle_query(id: Option<Value>, args: Value, state: Arc<Mutex<State>>) -> Response {
    let prompt = match args.get("prompt").and_then(|v| v.as_str()) {
        Some(p) => p,
        None => return Response::err(id, -32602, "Missing 'prompt' argument in query_codebase"),
    };

    let limit = args
        .get("limit")
        .and_then(|v| v.as_u64())
        .map_or(5usize, |v| v as usize);

    info!("Executing semantic search for query: '{prompt}' with limit: {limit}");
    let mut st = state.lock().await;

    // Automatic Just-in-Time Incremental Sync before answering query:
    // Takes <1ms when no files changed; auto-indexes modified files on the fly
    let _ = index_internal(&mut st, Path::new("."), false).await;

    let query_vector = match st.embedder.single(prompt) {
        Ok(v) => v,
        Err(e) => {
            error!("Prompt embedding failed: {e}");
            return Response::err(id, -32603, format!("Embedding error: {e}"));
        }
    };

    let hits = match st.store.find(&query_vector, limit).await {
        Ok(h) => h,
        Err(e) => {
            error!("Vector search failed: {e}");
            return Response::err(id, -32603, format!("Search error: {e}"));
        }
    };

    let result_text = Pruner::squeeze(hits);

    Response::ok(
        id,
        json!({
            "content": [
                {
                    "type": "text",
                    "text": result_text
                }
            ]
        }),
    )
}

async fn handle_get_config(id: Option<Value>, state: Arc<Mutex<State>>) -> Response {
    let st = state.lock().await;
    Response::ok(id, json!(st.config))
}

async fn handle_set_config(id: Option<Value>, args: Value, state: Arc<Mutex<State>>) -> Response {
    let mut st = state.lock().await;
    let mut modified = false;

    if let Some(size) = args.get("chunk_size").and_then(|v| v.as_u64()) {
        st.config.chunk_size = size as usize;
        modified = true;
    }
    if let Some(overlap) = args.get("chunk_overlap").and_then(|v| v.as_u64()) {
        st.config.chunk_overlap = overlap as usize;
        modified = true;
    }

    if modified {
        st.slicer = Slicer::new(st.config.chunk_size, st.config.chunk_overlap);
        let _ = st.config.save("alpax.toml");
    }

    Response::ok(
        id,
        json!({
            "content": [
                {
                    "type": "text",
                    "text": format!("Configuration updated: chunk_size={}, chunk_overlap={}", st.config.chunk_size, st.config.chunk_overlap)
                }
            ],
            "config": st.config
        }),
    )
}
