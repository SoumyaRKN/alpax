use anyhow::Result;
use serde::{Deserialize, Serialize};
use std::env;
use std::fs;
use std::path::{Path, PathBuf};

pub const DEFAULT_MODEL: &str = "models/all-MiniLM-L6-v2.onnx";
pub const DEFAULT_TOKENIZER: &str = "models/tokenizer.json";
pub const DEFAULT_DB: &str = ".alpax_vector_db";
pub const DEFAULT_CHUNK_SIZE: usize = 50;
pub const DEFAULT_CHUNK_OVERLAP: usize = 10;

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq, Eq)]
pub struct Config {
    pub model: String,
    pub tokenizer: String,
    pub db: String,
    pub chunk_size: usize,
    pub chunk_overlap: usize,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            model: DEFAULT_MODEL.to_string(),
            tokenizer: DEFAULT_TOKENIZER.to_string(),
            db: DEFAULT_DB.to_string(),
            chunk_size: DEFAULT_CHUNK_SIZE,
            chunk_overlap: DEFAULT_CHUNK_OVERLAP,
        }
    }
}

impl Config {
    #[must_use]
    pub fn new() -> Self {
        Self::default()
    }

    pub fn load() -> Self {
        let mut cfg = Self::from_file_or_default(Path::new("alpax.toml"));
        cfg.apply_env();
        cfg
    }

    pub fn from_file<P: AsRef<Path>>(path: P) -> Result<Self> {
        let content = fs::read_to_string(path)?;
        let cfg: Self = toml::from_str(&content)?;
        Ok(cfg)
    }

    #[must_use]
    pub fn from_file_or_default<P: AsRef<Path>>(path: P) -> Self {
        Self::from_file(path).unwrap_or_default()
    }

    pub fn save<P: AsRef<Path>>(&self, path: P) -> Result<()> {
        let content = toml::to_string_pretty(self)?;
        if let Some(parent) = path.as_ref().parent() {
            if !parent.as_os_str().is_empty() {
                fs::create_dir_all(parent)?;
            }
        }
        fs::write(path, content)?;
        Ok(())
    }

    pub fn apply_env(&mut self) {
        if let Ok(val) = env::var("ALPAX_MODEL_PATH") {
            if !val.trim().is_empty() {
                self.model = val;
            }
        }
        if let Ok(val) = env::var("ALPAX_TOKENIZER_PATH") {
            if !val.trim().is_empty() {
                self.tokenizer = val;
            }
        }
        if let Ok(val) = env::var("ALPAX_DB_PATH") {
            if !val.trim().is_empty() {
                self.db = val;
            }
        }
        if let Ok(val) = env::var("ALPAX_CHUNK_SIZE") {
            if let Ok(parsed) = val.parse::<usize>() {
                if parsed > 0 {
                    self.chunk_size = parsed;
                }
            }
        }
        if let Ok(val) = env::var("ALPAX_CHUNK_OVERLAP") {
            if let Ok(parsed) = val.parse::<usize>() {
                self.chunk_overlap = parsed;
            }
        }
    }

    #[must_use]
    pub fn resolve_model(&self) -> PathBuf {
        let local = PathBuf::from(&self.model);
        if local.exists() {
            return local;
        }
        if let Some(home) = dirs_home() {
            let global = home.join(".alpax").join(&self.model);
            if global.exists() {
                return global;
            }
        }
        local
    }

    #[must_use]
    pub fn resolve_tokenizer(&self) -> PathBuf {
        let local = PathBuf::from(&self.tokenizer);
        if local.exists() {
            return local;
        }
        if let Some(home) = dirs_home() {
            let global = home.join(".alpax").join(&self.tokenizer);
            if global.exists() {
                return global;
            }
        }
        local
    }

    #[must_use]
    pub fn resolve_db(&self) -> PathBuf {
        PathBuf::from(&self.db)
    }
}

fn dirs_home() -> Option<PathBuf> {
    env::var("HOME")
        .or_else(|_| env::var("USERPROFILE"))
        .ok()
        .map(PathBuf::from)
}
