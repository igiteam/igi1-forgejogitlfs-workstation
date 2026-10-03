#!/bin/bash

# ===============================================
# OFP ~ IGI ~ LLM Workspace — Firefox Extension Generator v2.2
# Two-header three-panel workstation with URL persistence
# + per-service AI URL memory
# ===============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}"
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║        OFP ~ IGI ~ LLM Workspace — Extension Generator        ║"
echo "║     Two-header three-panel workstation v2.2                   ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

read -p "Extension folder name (default: ofp-igi-workspace): " EXTNAME
EXTNAME=${EXTNAME:-ofp-igi-workspace}

if [ -d "$EXTNAME" ]; then
    read -p "Folder '$EXTNAME' exists. Remove it? (y/N): " REMOVE
    REMOVE=${REMOVE:-N}
    if [[ "$REMOVE" == "y" || "$REMOVE" == "Y" ]]; then
        rm -rf "$EXTNAME"
    else
        echo "Exiting to avoid overwrite."
        exit 1
    fi
fi

mkdir -p "$EXTNAME/icons"
cd "$EXTNAME" || exit

# ---------------------------------------------------------------
# Icon
# ---------------------------------------------------------------
echo -e "${CYAN}📥 Downloading DeepSeek icon...${NC}"
curl -sL -o icons/icon.png \
    "https://registry.npmmirror.com/@lobehub/icons-static-png/1.97.1/files/dark/deepseek-color.png"

if [ ! -s icons/icon.png ]; then
    echo -e "${YELLOW}⚠ Icon download failed — using fallback SVG${NC}"
    cat > icons/icon.svg << 'SVGEOF'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">
  <rect width="64" height="64" rx="12" fill="#0f172a"/>
  <rect x="8" y="16" width="12" height="32" rx="3" fill="#38bdf8"/>
  <rect x="26" y="16" width="12" height="32" rx="3" fill="#a78bfa"/>
  <rect x="44" y="16" width="12" height="32" rx="3" fill="#fbbf24"/>
</svg>
SVGEOF
    cp icons/icon.svg icons/icon.png 2>/dev/null || true
fi

cp icons/icon.png icons/icon128.png 2>/dev/null || true

# ---------------------------------------------------------------
# manifest.json
# ---------------------------------------------------------------
cat << 'EOL' > manifest.json
{
  "manifest_version": 2,
  "name": "OFP ~ IGI ~ LLM Workspace",
  "version": "2.2.0",
  "description": "Two-header three-panel remake workstation with per-panel URL persistence and per-service AI memory.",
  "icons": {
    "48": "icons/icon.png",
    "128": "icons/icon128.png"
  },
  "permissions": [
    "webRequest",
    "webRequestBlocking",
    "webNavigation",
    "storage",
    "tabs",
    "<all_urls>"
  ],
  "browser_action": {
    "default_icon": "icons/icon.png",
    "default_title": "OFP ~ IGI ~ LLM Workspace"
  },
  "background": {
    "scripts": ["background.js"],
    "persistent": true
  },
  "web_accessible_resources": [
    "workspace.html",
    "workspace.css",
    "workspace.js"
  ],
  "browser_specific_settings": {
    "gecko": {
      "id": "@ofp-igi-llm-workspace-v2",
      "strict_min_version": "78.0"
    }
  }
}
EOL

# ---------------------------------------------------------------
# background.js
# ---------------------------------------------------------------
cat << 'EOL' > background.js
// =====================================================
// Header stripping
// =====================================================
const BLOCKED_HOSTS = [
  "github.com",
  "raw.githubusercontent.com",
  "objects.githubusercontent.com",
  "gist.githubusercontent.com",
  "camo.githubusercontent.com",
  "chat.deepseek.com",
  "deepseek.com",
  "chat.openai.com",
  "chatgpt.com",
  "openai.com",
  "claude.ai",
  "gemini.google.com",
  "mistral.ai",
  "chat.mistral.ai",
  "copilot.microsoft.com",
  "perplexity.ai"
];

const HEADERS_TO_STRIP = new Set([
  "x-frame-options",
  "content-security-policy",
  "content-security-policy-report-only"
]);

function isBlockedHost(url) {
  try {
    const host = new URL(url).hostname;
    return BLOCKED_HOSTS.some(h => host === h || host.endsWith("." + h));
  } catch {
    return false;
  }
}

browser.webRequest.onHeadersReceived.addListener(
  (details) => {
    if (!isBlockedHost(details.url)) return {};
    const filtered = details.responseHeaders.filter(h => {
      const name = h.name.toLowerCase();
      return !HEADERS_TO_STRIP.has(name);
    });
    return { responseHeaders: filtered };
  },
  { urls: ["<all_urls>"] },
  ["blocking", "responseHeaders"]
);

// =====================================================
// Frame ↔ panel mapping
// =====================================================
const WORKSPACE_URL = browser.runtime.getURL("workspace.html");
const frameToPanel = {};

function matchFrameToPanel(frameUrl, panels) {
  for (const panel of panels) {
    try {
      const fu = new URL(frameUrl);
      const pu = new URL(panel.url);
      if (fu.hostname === pu.hostname) {
        if (fu.pathname.startsWith(pu.pathname) ||
            pu.pathname.startsWith(fu.pathname)) {
          return panel.id;
        }
      }
    } catch {}
  }
  for (const panel of panels) {
    try {
      if (new URL(frameUrl).hostname === new URL(panel.url).hostname) {
        return panel.id;
      }
    } catch {}
  }
  return null;
}

browser.runtime.onMessage.addListener((msg, sender) => {
  if (msg && msg.type === "register-panels" && sender.tab) {
    const tabId = sender.tab.id;
    browser.webNavigation.getAllFrames({ tabId }).then(frames => {
      for (const frame of frames) {
        if (frame.frameId === 0) continue;
        const panelId = matchFrameToPanel(frame.url, msg.panels);
        if (panelId) {
          frameToPanel[tabId + ":" + frame.frameId] = panelId;
        }
      }
    }).catch(() => {});
  }
});

// =====================================================
// Relay iframe navigation → workspace tab
// =====================================================
async function relayNavigation(details) {
  if (details.frameId === 0) return;
  try {
    const tab = await browser.tabs.get(details.tabId);
    if (!tab || !tab.url || !tab.url.startsWith(WORKSPACE_URL)) return;
  } catch { return; }

  const key = details.tabId + ":" + details.frameId;
  const panelId = frameToPanel[key] || null;

  browser.tabs.sendMessage(details.tabId, {
    type: "iframe-navigated",
    frameId: details.frameId,
    panelId: panelId,
    url: details.url
  }).catch(() => {});
}

browser.webNavigation.onCommitted.addListener(relayNavigation);
browser.webNavigation.onHistoryStateUpdated.addListener(relayNavigation);
browser.webNavigation.onReferenceFragmentUpdated.addListener(relayNavigation);

// =====================================================
// Toolbar button
// =====================================================
browser.browserAction.onClicked.addListener(async () => {
  const tabs = await browser.tabs.query({ url: WORKSPACE_URL });
  if (tabs.length > 0) {
    browser.tabs.update(tabs[0].id, { active: true });
  } else {
    browser.tabs.create({ url: WORKSPACE_URL });
  }
});

browser.runtime.onInstalled.addListener(() => {
  browser.tabs.create({ url: WORKSPACE_URL });
});
EOL

# ---------------------------------------------------------------
# workspace.html
# ---------------------------------------------------------------
cat << 'EOL' > workspace.html
<!doctype html>
<html lang="en">
<head>
<meta charset="UTF-8" />
<title>OFP ~ IGI ~ LLM Workspace</title>
<link rel="icon" href="icons/icon.png" type="image/png">
<link rel="stylesheet" href="workspace.css">
</head>
<body>

<div class="app-container">

  <!-- ============ PANEL 1: OFP / CWR ============ -->
  <div class="panel" id="panel-1" data-source="https://github.com/BohemiaInteractive/CWR">
    <div class="panel-header top-header">
      <span class="panel-title">OFP · CWR</span>
      <input type="text" class="url-input" id="nav-1"
             spellcheck="false" placeholder="Enter URL and press Enter...">
      <a class="open-btn" id="open-1" target="_blank" rel="noopener" title="Open in new tab">↗</a>
    </div>
    <div class="panel-header bottom-header">
      <span class="rag-label">rag:</span>
      <input type="text" class="rag-input" id="rag-1" readonly title="RAG link (auto-updates)">
      <button class="mini-btn" data-copy="1" title="Copy RAG link">📋</button>
    </div>
    <div class="iframe-container">
      <iframe id="iframe-1" loading="lazy"></iframe>
    </div>
  </div>

  <div class="resizer" data-target="0"></div>

  <!-- ============ PANEL 2: AI chat ============ -->
  <div class="panel" id="panel-2" data-source="https://chat.deepseek.com">
    <div class="panel-header top-header">
      <select class="ai-select" id="ai-2" title="Change AI service">
        <option value="https://chat.deepseek.com">DeepSeek</option>
        <option value="https://chatgpt.com">ChatGPT</option>
        <option value="https://claude.ai">Claude</option>
        <option value="https://gemini.google.com">Gemini</option>
        <option value="https://chat.mistral.ai">Mistral</option>
        <option value="https://copilot.microsoft.com">Copilot</option>
        <option value="https://www.perplexity.ai">Perplexity</option>
      </select>
      <input type="text" class="url-input" id="nav-2"
             spellcheck="false" placeholder="Enter URL and press Enter...">
      <a class="open-btn" id="open-2" target="_blank" rel="noopener" title="Open in new tab">↗</a>
    </div>
    <div class="panel-header bottom-header empty">
      <span class="no-rag">— no RAG —</span>
    </div>
    <div class="iframe-container">
      <iframe id="iframe-2" referrerpolicy="no-referrer" loading="lazy"></iframe>
    </div>
  </div>

  <div class="resizer" data-target="1"></div>

  <!-- ============ PANEL 3: IGI research ============ -->
  <div class="panel" id="panel-3" data-source="https://github.com/heaven-hm/project-igi-research-data/tree/main">
    <div class="panel-header top-header">
      <span class="panel-title">IGI · research</span>
      <input type="text" class="url-input" id="nav-3"
             spellcheck="false" placeholder="Enter URL and press Enter...">
      <a class="open-btn" id="open-3" target="_blank" rel="noopener" title="Open in new tab">↗</a>
    </div>
    <div class="panel-header bottom-header">
      <span class="rag-label">rag:</span>
      <input type="text" class="rag-input" id="rag-3" readonly title="RAG link (auto-updates)">
      <button class="mini-btn" data-copy="3" title="Copy RAG link">📋</button>
    </div>
    <div class="iframe-container">
      <iframe id="iframe-3" loading="lazy"></iframe>
    </div>
  </div>

</div>

<script src="workspace.js"></script>
</body>
</html>
EOL

# ---------------------------------------------------------------
# workspace.css
# ---------------------------------------------------------------
cat << 'EOL' > workspace.css
* { margin: 0; padding: 0; box-sizing: border-box; }
html, body { height: 100%; overflow: hidden; }

body {
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", system-ui, sans-serif;
  background: #0f172a;
  color: #e2e8f0;
  font-size: 13px;
  display: flex;
  flex-direction: column;
}

.app-container {
  display: flex;
  flex: 1;
  min-height: 0;
  overflow: hidden;
}

.panel {
  height: 100%;
  position: relative;
  overflow: hidden;
  background: #0f172a;
  display: flex;
  flex-direction: column;
  min-width: 0;
  flex: 0 0 auto;
}

.resizer {
  width: 6px;
  background: #1e293b;
  cursor: col-resize;
  flex: 0 0 auto;
  user-select: none;
  position: relative;
  z-index: 10;
  transition: background 0.1s;
}
.resizer:hover { background: #3b82f6; }
.resizer::after {
  content: "";
  position: absolute;
  top: 50%; left: 50%;
  transform: translate(-50%, -50%);
  width: 2px; height: 30px;
  background: #475569;
  border-radius: 1px;
}
body.resizing iframe { pointer-events: none !important; }
body.resizing { cursor: col-resize; }

.top-header {
  background: #f9f9fb;
  color: #15141a;
  padding: 0 8px 0 10px;
  border-bottom: 1px solid #e0e0e6;
  display: flex;
  align-items: center;
  gap: 8px;
  height: 40px;
  flex-shrink: 0;
  font-size: 12px;
}

.panel-title {
  font-weight: 600;
  color: #15141a;
  background: #ffffff;
  padding: 3px 9px;
  border-radius: 4px;
  border: 1px solid #e0e0e6;
  font-size: 12px;
  white-space: nowrap;
  display: inline-flex;
  align-items: center;
  gap: 5px;
  flex-shrink: 0;
}
.panel-title::before {
  content: "";
  width: 7px;
  height: 7px;
  border-radius: 50%;
  background: #0060df;
  display: inline-block;
}

.ai-select {
  background: #ffffff;
  border: 1px solid #d7d7db;
  color: #15141a;
  padding: 4px 6px;
  border-radius: 4px;
  font-size: 12px;
  height: 28px;
  cursor: pointer;
  font-weight: 600;
  flex-shrink: 0;
  min-width: 100px;
}
.ai-select:hover { background: #f0f0f4; }
.ai-select:focus { outline: none; border-color: #0060df; box-shadow: 0 0 0 2px rgba(0,96,223,0.2); }

.url-input {
  flex: 1;
  min-width: 0;
  background: #ffffff;
  border: 1px solid #d7d7db;
  color: #15141a;
  padding: 4px 8px;
  border-radius: 4px;
  font-size: 12px;
  font-family: ui-monospace, Consolas, monospace;
  height: 28px;
  transition: border-color 0.15s, box-shadow 0.15s;
}
.url-input:hover { background: #f7f7fa; }
.url-input:focus {
  outline: none;
  border-color: #0060df;
  box-shadow: 0 0 0 2px rgba(0,96,223,0.2);
  background: #ffffff;
}

.open-btn {
  color: #0060df;
  text-decoration: none;
  font-size: 14px;
  line-height: 1;
  padding: 4px 8px;
  border-radius: 4px;
  border: 1px solid transparent;
  white-space: nowrap;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  min-width: 30px;
  height: 28px;
  flex-shrink: 0;
  background: #ffffff;
}
.open-btn:hover {
  background: #eaeaf0;
  border-color: #e0e0e6;
}

.bottom-header {
  background: #f0f0f4;
  color: #15141a;
  padding: 0 8px 0 10px;
  border-bottom: 1px solid #d7d7db;
  display: flex;
  align-items: center;
  gap: 6px;
  height: 34px;
  flex-shrink: 0;
  font-size: 11px;
}

.bottom-header.empty {
  justify-content: center;
  color: #8b8b94;
}

.no-rag {
  font-style: italic;
  font-size: 11px;
  color: #9a9aa3;
}

.rag-label {
  font-weight: 600;
  color: #15141a;
  font-size: 11px;
  font-family: ui-monospace, Consolas, monospace;
  flex-shrink: 0;
  letter-spacing: 0.02em;
}

.rag-input {
  flex: 1;
  min-width: 0;
  background: #ffffff;
  border: 1px solid #d7d7db;
  color: #15141a;
  padding: 4px 7px;
  border-radius: 4px;
  font-size: 11px;
  font-family: ui-monospace, Consolas, monospace;
  height: 24px;
  cursor: pointer;
}
.rag-input:hover { background: #f7f7fa; }
.rag-input:focus { outline: none; border-color: #0060df; }

.mini-btn {
  background: #ffffff;
  border: 1px solid #d7d7db;
  color: #15141a;
  padding: 4px 7px;
  border-radius: 4px;
  cursor: pointer;
  font-size: 11px;
  white-space: nowrap;
  height: 24px;
  min-width: 30px;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
}
.mini-btn:hover { background: #eaeaf0; border-color: #c0c0c8; }
.mini-btn:active { background: #d7d7db; }

.iframe-container {
  flex: 1;
  position: relative;
  background: #0f172a;
  overflow: hidden;
}

iframe {
  width: 100%;
  height: 100%;
  border: none;
  background: white;
}

::-webkit-scrollbar { width: 10px; height: 10px; }
::-webkit-scrollbar-track { background: #1e293b; }
::-webkit-scrollbar-thumb { background: #475569; border-radius: 4px; }
::-webkit-scrollbar-thumb:hover { background: #64748b; }
EOL

# ---------------------------------------------------------------
# workspace.js
# ================================================================
# NOTE ON ORDERING:
# Everything that is referenced by top-level code must be declared
# BEFORE that code runs. This script is structured as:
#   1. Config constants
#   2. DOM element references (aiSelect, etc.)
#   3. Helper functions (diag, hostOf, etc.)
#   4. State (panelUrls, aiUrls)
#   5. Persistence functions
#   6. Event wiring
#   7. Init (runs on DOMContentLoaded)
# ---------------------------------------------------------------
cat << 'EOL' > workspace.js
// =====================================================
// 1. Config
// =====================================================
const RAG_BASE = "https://rag.songdrop.band/?url=";
const STORAGE_KEY_PANEL_URLS = "panelUrls";
const STORAGE_KEY_AI_URLS = "aiUrls";
const STORAGE_KEY_LAYOUT = "layout";

const DEFAULT_URLS = {
  1: "https://github.com/BohemiaInteractive/CWR",
  2: "https://chat.deepseek.com",
  3: "https://github.com/heaven-hm/project-igi-research-data/tree/main",
};

const PANELS = [
  { id: 1, iframeId: "iframe-1", navId: "nav-1", openId: "open-1", ragId: "rag-1" },
  { id: 2, iframeId: "iframe-2", navId: "nav-2", openId: "open-2", ragId: null      },
  { id: 3, iframeId: "iframe-3", navId: "nav-3", openId: "open-3", ragId: "rag-3" },
];

const AI_HOSTS = [
  "deepseek.com", "openai.com", "chatgpt.com", "claude.ai",
  "gemini.google.com", "mistral.ai", "chat.mistral.ai",
  "copilot.microsoft.com", "perplexity.ai"
];

// =====================================================
// 2. DOM references (resolved once at script load)
// =====================================================
const aiSelect = document.getElementById("ai-2");
const diagEl = document.getElementById("diag");

// =====================================================
// 3. Helpers
// =====================================================
function diag(msg) {
  console.log("[workspace]", msg);
  if (diagEl) {
    const t = new Date().toTimeString().slice(0, 8);
    diagEl.textContent = "[" + t + "] " + msg;
  }
}

function hostOf(url) {
  try { return new URL(url).hostname; } catch { return null; }
}

function optionForUrl(url) {
  if (!aiSelect) return null;
  const h = hostOf(url);
  if (!h) return null;
  return Array.from(aiSelect.options).find(o => hostOf(o.value) === h) || null;
}

function urlForOption(option) {
  const h = hostOf(option.value);
  if (h && aiUrls[h]) return aiUrls[h];
  return option.value;
}

function matchUrlToPanel(url) {
  const host = hostOf(url);
  if (!host) return null;

  if (AI_HOSTS.some(h => host === h || host.endsWith("." + h))) return 2;

  if (host === "github.com" || host.endsWith(".github.com")) {
    const lower = url.toLowerCase();
    if (lower.includes("bohemiainteractive/cwr")) return 1;
    if (lower.includes("heaven-hm/project-igi-research-data")) return 3;
    for (const id of [1, 3]) {
      try {
        if (hostOf(panelUrls[id]) === host) return id;
      } catch {}
    }
    return 3;
  }
  return null;
}

// =====================================================
// 4. State
// =====================================================
let panelUrls = { ...DEFAULT_URLS };
let aiUrls = {};  // hostname -> last URL for that service

// =====================================================
// 5. Persistence
// =====================================================
async function loadSavedUrls() {
  try {
    const r = await browser.storage.local.get(STORAGE_KEY_PANEL_URLS);
    if (r[STORAGE_KEY_PANEL_URLS] && typeof r[STORAGE_KEY_PANEL_URLS] === "object") {
      panelUrls = { ...DEFAULT_URLS, ...r[STORAGE_KEY_PANEL_URLS] };
      diag("loaded panelUrls: " + JSON.stringify(panelUrls));
    }
  } catch (e) { diag("loadSavedUrls error: " + e.message); }
}

async function loadAiUrls() {
  try {
    const r = await browser.storage.local.get(STORAGE_KEY_AI_URLS);
    if (r[STORAGE_KEY_AI_URLS] && typeof r[STORAGE_KEY_AI_URLS] === "object") {
      aiUrls = r[STORAGE_KEY_AI_URLS];
      diag("loaded aiUrls: " + JSON.stringify(aiUrls));
    }
  } catch (e) { diag("loadAiUrls error: " + e.message); }
}

let saveUrlTimer = null;
function saveUrlSoon() {
  if (saveUrlTimer) return;
  saveUrlTimer = setTimeout(async () => {
    saveUrlTimer = null;
    try {
      await browser.storage.local.set({ [STORAGE_KEY_PANEL_URLS]: panelUrls });
      diag("saved panelUrls: " + JSON.stringify(panelUrls));
    } catch (e) { diag("save error: " + e.message); }
  }, 800);
}

async function saveAiUrlsSoon() {
  try { await browser.storage.local.set({ [STORAGE_KEY_AI_URLS]: aiUrls }); } catch {}
}

// =====================================================
// 6. Update helpers
// =====================================================
function updateUrlInput(panelId, url) {
  const p = PANELS.find(x => x.id === panelId);
  if (!p) return;
  const navEl = document.getElementById(p.navId);
  const openEl = document.getElementById(p.openId);
  if (navEl && document.activeElement !== navEl) navEl.value = url;
  if (openEl) openEl.href = url;
}

function updateRagInput(panelId, url) {
  const p = PANELS.find(x => x.id === panelId);
  if (!p || !p.ragId) return;
  const ragEl = document.getElementById(p.ragId);
  if (ragEl) ragEl.value = RAG_BASE + encodeURIComponent(url);
}

function setPanelUrl(panelId, url, opts = {}) {
  panelUrls[panelId] = url;

  const p = PANELS.find(x => x.id === panelId);
  if (!p) return;

  if (opts.load) {
    const iframe = document.getElementById(p.iframeId);
    if (iframe) iframe.src = url;
  }

  updateUrlInput(panelId, url);
  updateRagInput(panelId, url);

  const panel = document.getElementById("panel-" + panelId);
  if (panel) panel.dataset.source = url;

  // If panel 2 navigated, record under its hostname too
  if (panelId === 2) {
    const h = hostOf(url);
    if (h) {
      aiUrls[h] = url;
      saveAiUrlsSoon();
    }
  }

  saveUrlSoon();
}

// =====================================================
// 7. URL input wiring — type + Enter to load
// =====================================================
for (const p of PANELS) {
  const input = document.getElementById(p.navId);
  if (!input) continue;
  input.addEventListener("keydown", (e) => {
    if (e.key === "Enter") {
      const url = input.value.trim();
      if (!url) return;
      const finalUrl = /^https?:\/\//i.test(url) ? url : "https://" + url;
      setPanelUrl(p.id, finalUrl, { load: true });
    }
  });
  input.addEventListener("focus", () => input.select());
}

// =====================================================
// 8. AI select — with per-service URL memory
// =====================================================
if (aiSelect) {
  aiSelect.addEventListener("change", () => {
    const opt = aiSelect.options[aiSelect.selectedIndex];
    if (!opt) return;

    // Remember the URL of the *previous* service before we leave it
    const prevHost = hostOf(panelUrls[2]);
    if (prevHost) {
      aiUrls[prevHost] = panelUrls[2];
      saveAiUrlsSoon();
      diag("remembered " + prevHost + " -> " + panelUrls[2]);
    }

    // Load either the remembered URL for the new service, or its root
    const targetUrl = urlForOption(opt);
    diag("AI select -> " + opt.value + " (loading " + targetUrl + ")");
    setPanelUrl(2, targetUrl, { load: true });
  });
}

// =====================================================
// 9. Copy RAG link
// =====================================================
document.addEventListener("click", (e) => {
  const btn = e.target.closest("[data-copy]");
  if (!btn) return;
  const n = btn.dataset.copy;
  const el = document.getElementById("rag-" + n);
  if (!el || !el.value) return;
  navigator.clipboard.writeText(el.value);
  toast("RAG link copied from panel " + n);
});

// =====================================================
// 10. Iframe navigation relay from background
// =====================================================
browser.runtime.onMessage.addListener((msg) => {
  if (!msg || msg.type !== "iframe-navigated") return;

  let panelId = msg.panelId;
  if (!panelId) panelId = matchUrlToPanel(msg.url);
  if (!panelId) return;

  if (panelUrls[panelId] === msg.url) return;

  panelUrls[panelId] = msg.url;
  updateUrlInput(panelId, msg.url);
  updateRagInput(panelId, msg.url);

  const panel = document.getElementById("panel-" + panelId);
  if (panel) panel.dataset.source = msg.url;

  if (panelId === 2) {
    const h = hostOf(msg.url);
    if (h) {
      aiUrls[h] = msg.url;
      saveAiUrlsSoon();
    }
    if (aiSelect) {
      const match = optionForUrl(msg.url);
      if (match) aiSelect.value = match.value;
    }
  }

  saveUrlSoon();
});

// =====================================================
// 11. Save on unload
// =====================================================
window.addEventListener("beforeunload", () => {
  try { browser.storage.local.set({ [STORAGE_KEY_PANEL_URLS]: panelUrls }); } catch {}
});
window.addEventListener("pagehide", () => {
  try { browser.storage.local.set({ [STORAGE_KEY_PANEL_URLS]: panelUrls }); } catch {}
});

// =====================================================
// 12. Register panels with background (for frame mapping)
// =====================================================
function registerPanels() {
  try {
    browser.runtime.sendMessage({
      type: "register-panels",
      panels: [
        { id: 1, url: panelUrls[1] },
        { id: 2, url: panelUrls[2] },
        { id: 3, url: panelUrls[3] },
      ],
    });
  } catch {}
}

// =====================================================
// 13. Resize
// =====================================================
const panels = [
  document.getElementById("panel-1"),
  document.getElementById("panel-2"),
  document.getElementById("panel-3"),
].filter(Boolean);

const minWidths = [260, 260, 260];
let layout = { w1: 33.33, w2: 33.33, w3: 33.34 };
let isResizing = false;
let activeDivider = null;
let startX = 0;
let startWidths = [0, 0, 0];

function applyLayout() {
  if (panels.length < 3) return;
  const cw = document.querySelector(".app-container").clientWidth;
  panels[0].style.width = (cw * layout.w1 / 100) + "px";
  panels[1].style.width = (cw * layout.w2 / 100) + "px";
  panels[2].style.width = (cw * layout.w3 / 100) + "px";
}

async function loadLayout() {
  try {
    const r = await browser.storage.local.get(STORAGE_KEY_LAYOUT);
    if (r[STORAGE_KEY_LAYOUT]) layout = r[STORAGE_KEY_LAYOUT];
  } catch {}
  applyLayout();
}

async function saveLayout() {
  try {
    await browser.storage.local.set({ [STORAGE_KEY_LAYOUT]: layout });
  } catch {}
}

document.querySelectorAll(".resizer").forEach((r, idx) => {
  r.addEventListener("mousedown", (e) => {
    e.preventDefault();
    isResizing = true;
    activeDivider = idx;
    startX = e.clientX;
    startWidths = panels.map(p => p.clientWidth);
    document.body.classList.add("resizing");
  });
});

document.addEventListener("mousemove", (e) => {
  if (!isResizing || panels.length < 3) return;
  const dx = e.clientX - startX;

  if (activeDivider === 0) {
    const pair = startWidths[0] + startWidths[1];
    let w1 = startWidths[0] + dx;
    w1 = Math.max(minWidths[0], Math.min(pair - minWidths[1], w1));
    panels[0].style.width = w1 + "px";
    panels[1].style.width = (pair - w1) + "px";
    panels[2].style.width = startWidths[2] + "px";
  } else {
    const pair = startWidths[1] + startWidths[2];
    let w2 = startWidths[1] + dx;
    w2 = Math.max(minWidths[1], Math.min(pair - minWidths[2], w2));
    panels[0].style.width = startWidths[0] + "px";
    panels[1].style.width = w2 + "px";
    panels[2].style.width = (pair - w2) + "px";
  }
});

document.addEventListener("mouseup", () => {
  if (!isResizing) return;
  isResizing = false;
  activeDivider = null;
  document.body.classList.remove("resizing");
  if (panels.length < 3) return;
  const cw = document.querySelector(".app-container").clientWidth;
  layout = {
    w1: panels[0].clientWidth / cw * 100,
    w2: panels[1].clientWidth / cw * 100,
    w3: panels[2].clientWidth / cw * 100,
  };
  saveLayout();
});

// =====================================================
// 14. Toast
// =====================================================
function toast(msg) {
  const t = document.createElement("div");
  t.style.cssText = `
    position: fixed; bottom: 20px; left: 50%; transform: translateX(-50%);
    background: #f9f9fb; color: #15141a; padding: 8px 16px;
    border-radius: 4px; z-index: 1000; border: 1px solid #e0e0e6;
    font-size: 12px; box-shadow: 0 4px 12px rgba(0,0,0,0.25);
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", system-ui, sans-serif;
  `;
  t.textContent = msg;
  document.body.appendChild(t);
  setTimeout(() => t.remove(), 1800);
}

// =====================================================
// 15. Init
// =====================================================
document.addEventListener("DOMContentLoaded", async () => {
  await loadLayout();
  await loadSavedUrls();
  await loadAiUrls();

  for (const p of PANELS) {
    const url = panelUrls[p.id] || DEFAULT_URLS[p.id];

    const iframe = document.getElementById(p.iframeId);
    if (iframe) iframe.src = url;

    updateUrlInput(p.id, url);
    updateRagInput(p.id, url);

    if (p.id === 2 && aiSelect) {
      const h = hostOf(url);
      if (h) {
        const match = Array.from(aiSelect.options).find(o => hostOf(o.value) === h);
        if (match) aiSelect.value = match.value;
      }
    }
  }

  registerPanels();

  let t;
  window.addEventListener("resize", () => {
    clearTimeout(t);
    t = setTimeout(applyLayout, 100);
  });
});
EOL

# ---------------------------------------------------------------
# README + LICENSE
# ---------------------------------------------------------------
cat << 'EOL' > README.md
# OFP ~ IGI ~ LLM Workspace — Firefox Extension v2.2

Two-header three-panel remake workstation.

## Fixed in v2.2
- **`aiSelect` is now declared before use** — the previous build threw
  `ReferenceError: aiSelect is not defined` at script parse time, which
  killed the rest of the file (no RAG links, no resize, no persistence).
- **`diag()` is now defined** — the previous build called it from the
  AI-select handler without ever declaring it, causing a second
  ReferenceError.
- **Function-scope ordering fixed** — helpers, DOM refs, and state are
  all declared before any code that references them.

## Per-service AI memory (new)
The middle panel remembers the last URL you were on **for each AI**.
Switching DeepSeek → ChatGPT → DeepSeek lands you back in the exact
DeepSeek conversation you were in, not the root.

- `aiUrls["chat.deepseek.com"]` = last DeepSeek URL
- `aiUrls["chatgpt.com"]` = last ChatGPT URL
- etc.

Persisted to `browser.storage.local` under the key `aiUrls`.

## Panel layout
Two headers per panel:
- Top: name (or AI select) + URL input + ↗
- Bottom: `rag:` label + RAG input + 📋 (panels 1 and 3);
  empty placeholder on panel 2

## Install
`about:debugging` → Load Temporary Add-on → pick `manifest.json`
EOL

cat << EOL > LICENSE.md
MIT License

Copyright (c) $(date +%Y)

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
EOL

# ---------------------------------------------------------------
# Package
# ---------------------------------------------------------------
echo -e "${CYAN}📦 Packaging as .xpi...${NC}"

XPI_FILE="${EXTNAME}.xpi"
rm -f "$XPI_FILE" 2>/dev/null

if command -v 7z &> /dev/null; then
    7z a "$XPI_FILE" * -r -x!*.xpi > /dev/null
elif command -v zip &> /dev/null; then
    zip -r "$XPI_FILE" * -x "*.xpi" > /dev/null
else
    echo -e "${RED}Error: need zip or 7z to create XPI${NC}"
    exit 1
fi

if [ -f "$XPI_FILE" ]; then
    echo -e "${GREEN}✅ Created: $XPI_FILE ($(du -h "$XPI_FILE" | cut -f1))${NC}"
    mv "$XPI_FILE" "$HOME/Downloads/${EXTNAME}.xpi"
    echo -e "${GREEN}✅ XPI moved to: $HOME/Downloads/${EXTNAME}.xpi${NC}"
    cd ..
    echo ""
    echo -e "${GREEN}✨ FILES:${NC}"
    echo -e " • ${EXTNAME}/ — source folder"
    echo -e " • ~/Downloads/${EXTNAME}.xpi — packaged addon"
    echo ""
    echo -e "${CYAN}🚀 INSTALL:${NC}"
    echo -e " • about:debugging → Load Temporary Add-on → ${EXTNAME}/manifest.json"
else
    echo -e "${RED}❌ Failed to create XPI${NC}"
fi