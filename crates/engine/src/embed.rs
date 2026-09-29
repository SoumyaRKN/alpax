use anyhow::{anyhow, Result};
use ort::{inputs, GraphOptimizationLevel, Session, Value};
use std::path::Path;
use tokenizers::{PaddingParams, Tokenizer, TruncationParams};

pub const EMBEDDING_DIM: usize = 384;

pub struct Embedder {
    session: Session,
    tokenizer: Tokenizer,
}

impl Embedder {
    pub fn new(model: &Path, tokenizer_path: &Path) -> Result<Self> {
        let mut tokenizer = Tokenizer::from_file(tokenizer_path).map_err(|e| {
            anyhow!(
                "Failed to load tokenizer from {}: {e}",
                tokenizer_path.display()
            )
        })?;

        tokenizer.with_padding(Some(PaddingParams::default()));
        tokenizer
            .with_truncation(Some(TruncationParams {
                max_length: 512,
                ..Default::default()
            }))
            .map_err(|e| anyhow!("Failed to set tokenizer truncation: {e}"))?;

        let threads = num_cpus::get();
        let session = Session::builder()?
            .with_optimization_level(GraphOptimizationLevel::Level3)?
            .with_intra_threads(threads)?
            .commit_from_file(model)?;

        Ok(Self { session, tokenizer })
    }

    pub fn batch(&self, texts: &[String]) -> Result<Vec<Vec<f32>>> {
        if texts.is_empty() {
            return Ok(Vec::new());
        }

        let encodings = self
            .tokenizer
            .encode_batch(texts.to_vec(), true)
            .map_err(|e| anyhow!("Batch tokenization error: {e}"))?;

        let batch_size = encodings.len();
        if batch_size == 0 {
            return Ok(Vec::new());
        }

        let seq_len = encodings[0].get_ids().len();

        let mut flat_input_ids = Vec::with_capacity(batch_size * seq_len);
        let mut flat_attention_mask = Vec::with_capacity(batch_size * seq_len);
        let mut flat_token_type_ids = Vec::with_capacity(batch_size * seq_len);

        for enc in &encodings {
            flat_input_ids.extend(enc.get_ids().iter().map(|&id| id as i64));
            flat_attention_mask.extend(enc.get_attention_mask().iter().map(|&m| m as i64));
            flat_token_type_ids.extend(enc.get_type_ids().iter().map(|&t| t as i64));
        }

        let input_ids_val = Value::from_array(([batch_size, seq_len], flat_input_ids))?;
        let attention_mask_val = Value::from_array(([batch_size, seq_len], flat_attention_mask))?;
        let token_type_ids_val = Value::from_array(([batch_size, seq_len], flat_token_type_ids))?;

        let inps = inputs![
            "input_ids" => input_ids_val,
            "attention_mask" => attention_mask_val,
            "token_type_ids" => token_type_ids_val,
        ]?;

        let outputs = self.session.run(inps)?;
        let (shape, data) = outputs[0].try_extract_raw_tensor::<f32>()?;
        let hidden_dim = if shape.len() >= 3 {
            shape[2] as usize
        } else {
            EMBEDDING_DIM
        };

        let mut results = Vec::with_capacity(batch_size);

        for (b, enc) in encodings.iter().enumerate().take(batch_size) {
            let mut pooled = vec![0.0f32; hidden_dim];
            let mut mask_sum = 0.0f32;
            let mask = enc.get_attention_mask();

            for (s, &mask_bit) in mask.iter().enumerate().take(seq_len) {
                let mask_val = mask_bit as f32;
                if mask_val > 0.0 {
                    mask_sum += mask_val;
                    let token_offset = b * (seq_len * hidden_dim) + s * hidden_dim;
                    for h in 0..hidden_dim {
                        pooled[h] += data[token_offset + h] * mask_val;
                    }
                }
            }

            if mask_sum > 0.0 {
                for val in pooled.iter_mut().take(hidden_dim) {
                    *val /= mask_sum;
                }
            }

            // L2 normalize
            let norm: f32 = pooled.iter().map(|v| v * v).sum::<f32>().sqrt();
            if norm > 1e-12 {
                for val in pooled.iter_mut().take(hidden_dim) {
                    *val /= norm;
                }
            }

            results.push(pooled);
        }

        Ok(results)
    }

    pub fn single(&self, text: &str) -> Result<Vec<f32>> {
        let embeddings = self.batch(&[text.to_string()])?;
        embeddings
            .into_iter()
            .next()
            .ok_or_else(|| anyhow!("Failed to generate vector embedding"))
    }
}
