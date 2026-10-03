# OFP ~ IGI ~ LLM Workspace — Firefox Extension v2.3

Two-header three-panel workstation with **knowledge base upload**.

## New in v2.3

- **KB toolbar** in the middle panel: source, tags, paste box, upload button
- **Right-click menu**: "Send to knowledge base" on any selected text
- **KB server config**: click ⚙️ to set the RAG server base URL
- **KB list viewer**: click 📋 to see all stored documents, delete individual ones
- **Status line**: shows how many docs are stored and which server

## Upload endpoint expected on the server
POST {KB_SERVER}/v1/rag/upload
Body: {
source: "DeepSeek",
tags: ["igi→ofp", "patrol"],
text: "the raw text...",
metadata: { from, urls, addedAt }
}
Response: { ok: true, id: "...", chunks: 12 }

GET {KB_SERVER}/v1/rag/list
Response: { documents: [ { id, source, tags, total_chunks, created_at } ], total }

DELETE {KB_SERVER}/v1/rag/doc/:id
Response: { ok: true }

The server-side patch to add these endpoints is a separate task.

## Existing features (unchanged)

- Three panels with two headers each
- Live URL navigation per panel
- Per-service AI memory
- RAG links (per panel) auto-update
- Resizable layout, persistence
- Header stripping so GitHub and AI sites load

## Install

`about:debugging` → Load Temporary Add-on → pick `manifest.json`
