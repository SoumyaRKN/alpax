use alpax_core::{Chunk, Hit};
use anyhow::{anyhow, Result};
use arrow_array::{
    Array, ArrayRef, FixedSizeListArray, Float32Array, Int32Array, RecordBatch,
    RecordBatchIterator, StringArray,
};
use arrow_schema::{DataType, Field, Schema};
use futures::StreamExt;
use lancedb::connect;
use lancedb::connection::Connection;
use lancedb::query::{ExecutableQuery, QueryBase};
use lancedb::table::Table;
use std::sync::Arc;

pub const TABLE_NAME: &str = "chunks";
pub const VECTOR_DIM: i32 = 384;

pub struct Store {
    pub conn: Connection,
    pub table: Option<Table>,
}

impl Store {
    pub async fn new(path: &str) -> Result<Self> {
        let conn = connect(path).execute().await?;
        let table_names = conn.table_names().execute().await?;
        let table = if table_names.contains(&TABLE_NAME.to_string()) {
            Some(conn.open_table(TABLE_NAME).execute().await?)
        } else {
            None
        };

        Ok(Self { conn, table })
    }

    pub async fn save(&mut self, chunks: &[Chunk], vectors: &[Vec<f32>]) -> Result<()> {
        if chunks.is_empty() || vectors.is_empty() {
            return Ok(());
        }

        if chunks.len() != vectors.len() {
            return Err(anyhow!(
                "Chunks count ({}) and vectors count ({}) do not match",
                chunks.len(),
                vectors.len()
            ));
        }

        let item_field = Arc::new(Field::new("item", DataType::Float32, true));
        let schema = Arc::new(Schema::new(vec![
            Field::new(
                "vector",
                DataType::FixedSizeList(item_field.clone(), VECTOR_DIM),
                false,
            ),
            Field::new("file", DataType::Utf8, false),
            Field::new("text", DataType::Utf8, false),
            Field::new("start", DataType::Int32, false),
            Field::new("end", DataType::Int32, false),
        ]));

        let mut flat_vectors = Vec::with_capacity(vectors.len() * VECTOR_DIM as usize);
        for vec in vectors {
            if vec.len() != VECTOR_DIM as usize {
                return Err(anyhow!(
                    "Vector dimension mismatch: expected {}, got {}",
                    VECTOR_DIM,
                    vec.len()
                ));
            }
            flat_vectors.extend_from_slice(vec);
        }

        let vector_values = Arc::new(Float32Array::from(flat_vectors));
        let vector_array = Arc::new(FixedSizeListArray::try_new(
            item_field,
            VECTOR_DIM,
            vector_values as ArrayRef,
            None,
        )?);

        let files: Vec<String> = chunks.iter().map(|c| c.file.clone()).collect();
        let texts: Vec<String> = chunks.iter().map(|c| c.text.clone()).collect();
        let starts: Vec<i32> = chunks.iter().map(|c| c.start as i32).collect();
        let ends: Vec<i32> = chunks.iter().map(|c| c.end as i32).collect();

        let file_array = Arc::new(StringArray::from(files));
        let text_array = Arc::new(StringArray::from(texts));
        let start_array = Arc::new(Int32Array::from(starts));
        let end_array = Arc::new(Int32Array::from(ends));

        let batch = RecordBatch::try_new(
            schema.clone(),
            vec![
                vector_array as ArrayRef,
                file_array as ArrayRef,
                text_array as ArrayRef,
                start_array as ArrayRef,
                end_array as ArrayRef,
            ],
        )?;

        let batches = Box::new(RecordBatchIterator::new(vec![Ok(batch)], schema.clone()));

        match &self.table {
            Some(table) => {
                table.add(batches).execute().await?;
            }
            None => {
                let table = self
                    .conn
                    .create_table(TABLE_NAME, batches)
                    .execute()
                    .await?;
                self.table = Some(table);
            }
        }

        Ok(())
    }

    pub async fn remove_file(&self, file_path: &str) -> Result<()> {
        if let Some(table) = &self.table {
            let escaped = file_path.replace('\'', "''");
            let predicate = format!("file = '{escaped}'");
            let _ = table.delete(&predicate).await;
        }
        Ok(())
    }

    pub async fn clear(&mut self) -> Result<()> {
        let table_names = self.conn.table_names().execute().await?;
        if table_names.contains(&TABLE_NAME.to_string()) {
            self.conn.drop_table(TABLE_NAME).await?;
            self.table = None;
        }
        Ok(())
    }

    pub async fn find(&self, query: &[f32], limit: usize) -> Result<Vec<Hit>> {
        let table = match &self.table {
            Some(t) => t,
            None => return Ok(Vec::new()),
        };

        let mut stream = table
            .query()
            .nearest_to(query)?
            .limit(limit)
            .execute()
            .await?;

        let mut hits = Vec::new();

        while let Some(batch_res) = stream.next().await {
            let batch = batch_res?;
            let num_rows = batch.num_rows();
            if num_rows == 0 {
                continue;
            }

            let file_col = batch
                .column_by_name("file")
                .ok_or_else(|| anyhow!("Missing 'file' column in query results"))?
                .as_any()
                .downcast_ref::<StringArray>()
                .ok_or_else(|| anyhow!("Invalid type for 'file' column"))?;

            let text_col = batch
                .column_by_name("text")
                .ok_or_else(|| anyhow!("Missing 'text' column in query results"))?
                .as_any()
                .downcast_ref::<StringArray>()
                .ok_or_else(|| anyhow!("Invalid type for 'text' column"))?;

            let start_col = batch
                .column_by_name("start")
                .ok_or_else(|| anyhow!("Missing 'start' column in query results"))?
                .as_any()
                .downcast_ref::<Int32Array>()
                .ok_or_else(|| anyhow!("Invalid type for 'start' column"))?;

            let end_col = batch
                .column_by_name("end")
                .ok_or_else(|| anyhow!("Missing 'end' column in query results"))?
                .as_any()
                .downcast_ref::<Int32Array>()
                .ok_or_else(|| anyhow!("Invalid type for 'end' column"))?;

            let distance_col = batch
                .column_by_name("_distance")
                .and_then(|c| c.as_any().downcast_ref::<Float32Array>());

            for i in 0..num_rows {
                let file = file_col.value(i).to_string();
                let text = text_col.value(i).to_string();
                let start = start_col.value(i);
                let end = end_col.value(i);
                let distance = distance_col.map_or(0.0, |d| d.value(i));
                let score = 1.0 / (1.0 + distance.max(0.0));

                hits.push(Hit::new(file, text, start, end, score));
            }
        }

        Ok(hits)
    }
}
