# Alpax MCP API Specification

Alpax implements the Model Context Protocol (MCP) over standard input/output (`stdio`) using JSON-RPC 2.0 framing.

---

## 1. Protocol Methods

### 1.1 `initialize`
Initial handshake between the MCP client and the Alpax server.

#### Request
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "initialize",
  "params": {
    "protocolVersion": "2024-11-05",
    "capabilities": {},
    "clientInfo": {
      "name": "mcp-client",
      "version": "1.0.0"
    }
  }
}
```

#### Response
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "protocolVersion": "2024-11-05",
    "capabilities": {
      "tools": {}
    },
    "serverInfo": {
      "name": "alpax",
      "version": "0.1.0"
    }
  }
}
```

---

### 1.2 `tools/list`
Lists the semantic search and vectorization tools provided by Alpax.

#### Request
```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "method": "tools/list",
  "params": {}
}
```

#### Response
```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "result": {
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
            }
          },
          "required": ["path"]
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
      }
    ]
  }
}
```

---

### 1.3 `tools/call`

#### 1.3.1 `index_workspace`
Scans the specified directory, checks file modification hashes via BLAKE3, extracts overlapping line slices, computes ONNX embeddings, and stores them in LanceDB.

##### Request
```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "method": "tools/call",
  "params": {
    "name": "index_workspace",
    "arguments": {
      "path": "./crates"
    }
  }
}
```

##### Response
```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "result": {
    "content": [
      {
        "type": "text",
        "text": "Indexing complete. Indexed 18 files (142 chunks), skipped 4 unchanged files."
      }
    ]
  }
}
```

---

#### 1.3.2 `query_codebase`
Performs semantic vector search across indexed chunks, filters and ranks by cosine similarity, prunes redundant whitespace, and formats the output into compact blocks.

##### Request
```json
{
  "jsonrpc": "2.0",
  "id": 4,
  "method": "tools/call",
  "params": {
    "name": "query_codebase",
    "arguments": {
      "prompt": "How does vector mean pooling and normalization work?",
      "limit": 3
    }
  }
}
```

##### Response
```json
{
  "jsonrpc": "2.0",
  "id": 4,
  "result": {
    "content": [
      {
        "type": "text",
        "text": "FILE [crates/engine/src/embed.rs]\nL72-L105:\n```\nlet mask_expanded = attention_mask.insert_axis(Axis(2));\nlet sum_embeddings = (&token_embeddings * &mask_expanded).sum_axis(Axis(1));\nlet sum_mask = mask_expanded.sum_axis(Axis(1));\nlet mean_pooled = &sum_embeddings / &sum_mask;\nlet norm = mean_pooled.mapv(|x| x * x).sum().sqrt();\n```"
      }
    ]
  }
}
```

---

## 2. Error Responses
Standard JSON-RPC 2.0 error payloads:
- `-32700`: Parse error (invalid JSON).
- `-32600`: Invalid Request.
- `-32601`: Method not found (unknown method or unknown tool).
- `-32602`: Invalid params.
- `-32603`: Internal error with detailed message written to `stderr`.
