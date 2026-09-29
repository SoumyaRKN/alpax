use alpax_core::Chunk;
use ignore::WalkBuilder;
use std::fs;
use std::path::{Path, PathBuf};

const BINARY_EXTENSIONS: &[&str] = &[
    "png",
    "jpg",
    "jpeg",
    "gif",
    "bmp",
    "ico",
    "webp",
    "tiff",
    "pdf",
    "exe",
    "bin",
    "so",
    "dylib",
    "dll",
    "lock",
    "zip",
    "tar",
    "gz",
    "7z",
    "rar",
    "iso",
    "parquet",
    "lance",
    "pyc",
    "pyo",
    "pyd",
    "wasm",
    "onnx",
    "pt",
    "pth",
    "safetensors",
    "mp3",
    "mp4",
    "wav",
    "avi",
    "mov",
    "flv",
    "ttf",
    "otf",
    "woff",
    "woff2",
    "eot",
    "db",
    "sqlite",
    "sqlite3",
];

#[derive(Debug, Clone)]
pub struct Slicer {
    pub size: usize,
    pub step: usize,
}

impl Default for Slicer {
    fn default() -> Self {
        Self::new(50, 10)
    }
}

impl Slicer {
    #[must_use]
    pub fn new(size: usize, overlap: usize) -> Self {
        let actual_size = size.max(1);
        let actual_step = if actual_size > overlap {
            actual_size - overlap
        } else {
            1
        };
        Self {
            size: actual_size,
            step: actual_step,
        }
    }

    pub fn slice(&self, path: &Path) -> Option<Vec<Chunk>> {
        let content = fs::read_to_string(path).ok()?;
        let lines: Vec<&str> = content.lines().collect();

        if lines.is_empty() {
            return Some(Vec::new());
        }

        let mut chunks = Vec::new();
        let total_lines = lines.len();
        let file_str = path.to_string_lossy().to_string();

        let mut start_idx = 0;
        while start_idx < total_lines {
            let end_idx = (start_idx + self.size).min(total_lines);
            let slice_lines = &lines[start_idx..end_idx];
            let text = slice_lines.join("\n");
            let start_line = start_idx + 1;
            let end_line = end_idx;

            chunks.push(Chunk::new(file_str.clone(), text, start_line, end_line));

            if end_idx >= total_lines {
                break;
            }
            start_idx += self.step;
        }

        Some(chunks)
    }

    pub fn scan(root: &Path) -> Vec<PathBuf> {
        let mut results = Vec::new();
        let walker = WalkBuilder::new(root)
            .hidden(true)
            .git_ignore(true)
            .git_global(true)
            .git_exclude(true)
            .build();

        for entry in walker.flatten() {
            let path = entry.path();
            if !path.is_file() {
                continue;
            }

            if let Some(ext) = path.extension().and_then(|e| e.to_str()) {
                let lower_ext = ext.to_ascii_lowercase();
                if BINARY_EXTENSIONS.contains(&lower_ext.as_str()) {
                    continue;
                }
            }

            results.push(path.to_path_buf());
        }

        results
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;
    use tempfile::NamedTempFile;

    #[test]
    fn test_slicer_overlapping_windows() -> anyhow::Result<()> {
        let mut file = NamedTempFile::new()?;
        let content = (1..=25)
            .map(|i| format!("line {i}"))
            .collect::<Vec<_>>()
            .join("\n");
        file.write_all(content.as_bytes())?;
        file.flush()?;

        let slicer = Slicer::new(10, 2); // size: 10, step: 8
        let chunks = slicer.slice(file.path()).unwrap();

        assert_eq!(chunks.len(), 3);
        assert_eq!(chunks[0].start, 1);
        assert_eq!(chunks[0].end, 10);

        assert_eq!(chunks[1].start, 9);
        assert_eq!(chunks[1].end, 18);

        assert_eq!(chunks[2].start, 17);
        assert_eq!(chunks[2].end, 25);

        Ok(())
    }
}
