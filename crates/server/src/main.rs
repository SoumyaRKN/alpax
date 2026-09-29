mod dispatch;
mod proto;

use alpax_core::Config;
use alpax_engine::{Embedder, Hasher, Slicer, Store};
use anyhow::Result;
use dispatch::{handle, State};
use proto::{Request, Response};
use std::sync::Arc;
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::sync::Mutex;
use tracing::{error, info};

#[tokio::main]
async fn main() -> Result<()> {
    // Observability constraint: Strictly write all diagnostics to stderr
    tracing_subscriber::fmt()
        .with_writer(std::io::stderr)
        .with_env_filter(
            tracing_subscriber::EnvFilter::from_default_env()
                .add_directive(tracing::Level::INFO.into()),
        )
        .init();

    info!("Starting Alpax (अल्प) MCP Server v0.1.0");

    let config = Config::load();
    let model_path = config.resolve_model();
    let tokenizer_path = config.resolve_tokenizer();
    let db_path = config.resolve_db();

    info!("Configuration loaded: {:?}", config);

    if !model_path.exists() {
        error!(
            "Model file not found at: {}. Please run 'bash scripts/setup.sh' to download required weights.",
            model_path.display()
        );
        std::process::exit(1);
    }

    if !tokenizer_path.exists() {
        error!(
            "Tokenizer file not found at: {}. Please run 'bash scripts/setup.sh' to download tokenizer configuration.",
            tokenizer_path.display()
        );
        std::process::exit(1);
    }

    let embedder = Embedder::new(&model_path, &tokenizer_path)?;
    let db_path_str = db_path
        .to_str()
        .ok_or_else(|| anyhow::anyhow!("Invalid database path encoding"))?;
    let store = Store::new(db_path_str).await?;
    let hasher = Hasher::new();
    let slicer = Slicer::new(config.chunk_size, config.chunk_overlap);

    let state = Arc::new(Mutex::new(State::new(
        embedder, store, hasher, slicer, config,
    )));

    info!("Alpax engine initialized successfully. Ready for MCP stdio connections.");

    let stdin = tokio::io::stdin();
    let mut reader = BufReader::new(stdin).lines();
    let mut stdout = tokio::io::stdout();

    while let Ok(Some(line)) = reader.next_line().await {
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }

        let resp = match serde_json::from_str::<Request>(trimmed) {
            Ok(req) => handle(req, state.clone()).await,
            Err(e) => {
                error!("Invalid JSON-RPC request received: {e}");
                Response::err(None, -32700, format!("Parse error: {e}"))
            }
        };

        if let Ok(serialized) = serde_json::to_string(&resp) {
            stdout.write_all(serialized.as_bytes()).await?;
            stdout.write_all(b"\n").await?;
            stdout.flush().await?;
        }
    }

    info!("Alpax stdio connection closed. Exiting.");
    Ok(())
}
