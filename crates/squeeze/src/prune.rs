use alpax_core::Hit;
use std::collections::BTreeMap;

#[derive(Default, Clone, Debug, Copy)]
pub struct Pruner;

impl Pruner {
    #[must_use]
    pub fn new() -> Self {
        Self
    }

    #[must_use]
    pub fn squeeze(hits: Vec<Hit>) -> String {
        if hits.is_empty() {
            return "No matching context found.".to_string();
        }

        let mut grouped: BTreeMap<String, Vec<Hit>> = BTreeMap::new();
        for hit in hits {
            grouped.entry(hit.file.clone()).or_default().push(hit);
        }

        let mut blocks: Vec<String> = Vec::new();

        for (file, mut file_hits) in grouped {
            file_hits.sort_by_key(|h| h.start);

            for hit in file_hits {
                let cleaned_lines: Vec<&str> = hit
                    .text
                    .lines()
                    .filter(|line| !line.trim().is_empty())
                    .collect();
                let cleaned_text = cleaned_lines.join("\n");

                let block = format!(
                    "FILE [{}]\nL{}-{}:\n```\n{}\n```",
                    file, hit.start, hit.end, cleaned_text
                );
                blocks.push(block);
            }
        }

        blocks.join("\n\n")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_squeeze_empty() {
        assert_eq!(Pruner::squeeze(vec![]), "No matching context found.");
    }

    #[test]
    fn test_squeeze_prunes_whitespace_and_sorts() {
        let hits = vec![
            Hit::new(
                "src/main.rs".to_string(),
                "    \nlet b = 2;\n\n    let c = 3;\n".to_string(),
                10,
                15,
                0.9,
            ),
            Hit::new(
                "src/main.rs".to_string(),
                "let a = 1;\n\n".to_string(),
                1,
                5,
                0.95,
            ),
        ];

        let squeezed = Pruner::squeeze(hits);
        let expected = "FILE [src/main.rs]\nL1-5:\n```\nlet a = 1;\n```\n\nFILE [src/main.rs]\nL10-15:\n```\nlet b = 2;\n    let c = 3;\n```";
        assert_eq!(squeezed, expected);
    }
}
