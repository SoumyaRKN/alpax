use serde::{Deserialize, Serialize};

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
pub struct Hit {
    pub file: String,
    pub text: String,
    pub start: i32,
    pub end: i32,
    pub score: f32,
}

impl Hit {
    #[must_use]
    pub fn new(file: String, text: String, start: i32, end: i32, score: f32) -> Self {
        Self {
            file,
            text,
            start,
            end,
            score,
        }
    }
}
