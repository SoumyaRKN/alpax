use serde::{Deserialize, Serialize};

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq, Eq)]
pub struct Chunk {
    pub file: String,
    pub text: String,
    pub start: usize,
    pub end: usize,
}

impl Chunk {
    #[must_use]
    pub fn new(file: String, text: String, start: usize, end: usize) -> Self {
        Self {
            file,
            text,
            start,
            end,
        }
    }
}
