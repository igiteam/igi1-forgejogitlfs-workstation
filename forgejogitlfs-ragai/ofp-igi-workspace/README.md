# OFP ~ IGI ~ LLM Workspace — Firefox Extension v2.4

Two-header three-panel workstation with **per-panel URL history** and **knowledge base upload**.

## New in v2.4

- **🕘 history button** on every panel, next to ↗
- **History dropdown** with filter box, timestamps, and Clear button
- **Per-panel** history — panel 1, 2, 3 each track their own URLs separately
- **500-entry cap** per panel, oldest dropped
- **KB button moved to the right** in the middle panel's toolbar: `[status] [⚙️] [📋] [📚 KB]`

## New in v2.3

- KB toolbar with source/tags/paste box/upload button
- Right-click "Send to knowledge base" on any selection
- KB server configurable via ⚙️
- KB list viewer via 📋

## Upload endpoint expected on the server
POST {KB_SERVER}/v1/rag/upload
Body: { source, tags, text, metadata }
Response: { ok: true, id: "...", chunks: 12 }

GET {KB_SERVER}/v1/rag/list
Response: { documents: [...], total }

DELETE {KB_SERVER}/v1/rag/doc/:id
Response: { ok: true }

## Install

`about:debugging` → Load Temporary Add-on → pick `manifest.json`
