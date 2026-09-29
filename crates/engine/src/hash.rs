use anyhow::Result;
use std::collections::HashMap;
use std::fs::File;
use std::io::Read;
use std::path::{Path, PathBuf};

const BUFFER_SIZE: usize = 64 * 1024; // 64KB streaming buffer

#[derive(Default, Debug, Clone)]
pub struct Hasher {
    cache: HashMap<PathBuf, String>,
}

impl Hasher {
    #[must_use]
    pub fn new() -> Self {
        Self {
            cache: HashMap::new(),
        }
    }

    pub fn digest(path: &Path) -> Result<String> {
        let mut file = File::open(path)?;
        let mut hasher = blake3::Hasher::new();
        let mut buffer = [0u8; BUFFER_SIZE];

        loop {
            let bytes_read = file.read(&mut buffer)?;
            if bytes_read == 0 {
                break;
            }
            hasher.update(&buffer[..bytes_read]);
        }

        Ok(hasher.finalize().to_hex().to_string())
    }

    pub fn dirty(&mut self, path: &Path) -> bool {
        let canonical = path.canonicalize().unwrap_or_else(|_| path.to_path_buf());
        match Self::digest(&canonical) {
            Ok(current_hash) => {
                if let Some(cached_hash) = self.cache.get(&canonical) {
                    if *cached_hash == current_hash {
                        return false;
                    }
                }
                self.cache.insert(canonical, current_hash);
                true
            }
            Err(_) => false,
        }
    }

    pub fn clear(&mut self) {
        self.cache.clear();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;
    use tempfile::NamedTempFile;

    #[test]
    fn test_hasher_dirty_tracking() -> Result<()> {
        let mut file = NamedTempFile::new()?;
        file.write_all(b"hello world")?;
        file.flush()?;

        let mut hasher = Hasher::new();
        let path = file.path().to_path_buf();

        // First check should be dirty
        assert!(hasher.dirty(&path));

        // Immediate second check should not be dirty
        assert!(!hasher.dirty(&path));

        // Modify file
        file.write_all(b" new content")?;
        file.flush()?;

        // Third check should be dirty again
        assert!(hasher.dirty(&path));

        Ok(())
    }
}
