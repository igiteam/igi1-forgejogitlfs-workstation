// =====================================================
// 1. Config
// =====================================================
const RAG_BASE = "https://rag.songdrop.band/?url=";
const KB_SERVER_DEFAULT = "https://rag.songdrop.band";
const STORAGE_KEY_PANEL_URLS = "panelUrls";
const STORAGE_KEY_AI_URLS = "aiUrls";
const STORAGE_KEY_LAYOUT = "layout";
const STORAGE_KEY_KB_SERVER = "kbServer";

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
// 2. DOM references
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
let aiUrls = {};
let kbServer = KB_SERVER_DEFAULT;

// =====================================================
// 5. Persistence
// =====================================================
async function loadSavedUrls() {
  try {
    const r = await browser.storage.local.get(STORAGE_KEY_PANEL_URLS);
    if (r[STORAGE_KEY_PANEL_URLS] && typeof r[STORAGE_KEY_PANEL_URLS] === "object") {
      panelUrls = { ...DEFAULT_URLS, ...r[STORAGE_KEY_PANEL_URLS] };
      diag("loaded panelUrls");
    }
  } catch (e) { diag("loadSavedUrls error: " + e.message); }
}

async function loadAiUrls() {
  try {
    const r = await browser.storage.local.get(STORAGE_KEY_AI_URLS);
    if (r[STORAGE_KEY_AI_URLS] && typeof r[STORAGE_KEY_AI_URLS] === "object") {
      aiUrls = r[STORAGE_KEY_AI_URLS];
      diag("loaded aiUrls");
    }
  } catch (e) { diag("loadAiUrls error: " + e.message); }
}

async function loadKbServer() {
  try {
    const r = await browser.storage.local.get(STORAGE_KEY_KB_SERVER);
    if (r[STORAGE_KEY_KB_SERVER]) {
      kbServer = r[STORAGE_KEY_KB_SERVER];
    }
  } catch {}
}

async function saveKbServer() {
  try {
    await browser.storage.local.set({ [STORAGE_KEY_KB_SERVER]: kbServer });
  } catch {}
}

let saveUrlTimer = null;
function saveUrlSoon() {
  if (saveUrlTimer) return;
  saveUrlTimer = setTimeout(async () => {
    saveUrlTimer = null;
    try {
      await browser.storage.local.set({ [STORAGE_KEY_PANEL_URLS]: panelUrls });
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
// 7. URL input wiring
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
// 8. AI select
// =====================================================
if (aiSelect) {
  aiSelect.addEventListener("change", () => {
    const opt = aiSelect.options[aiSelect.selectedIndex];
    if (!opt) return;

    const prevHost = hostOf(panelUrls[2]);
    if (prevHost) {
      aiUrls[prevHost] = panelUrls[2];
      saveAiUrlsSoon();
    }

    const targetUrl = urlForOption(opt);
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
  if (!msg) return;

  if (msg.type === "iframe-navigated") {
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
    return;
  }

  if (msg.type === "kb-fill") {
    const textarea = document.getElementById("kb-text");
    if (textarea) {
      textarea.value = msg.text;
      textarea.focus();
      // Open the KB panel so the user sees it
      const panel = document.getElementById("kb-panel");
      const toggle = document.getElementById("kb-toggle");
      if (panel && panel.style.display === "none") {
        panel.style.display = "flex";
        if (toggle) toggle.classList.add("active");
      }
      const result = document.getElementById("kb-result");
      if (result) {
        result.textContent = "Text loaded. Add tags and click Upload.";
        result.className = "kb-result";
      }
    }
  }
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
// 12. Register panels with background
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
// 13. Knowledge Base UI
// =====================================================
const kbToggle = document.getElementById("kb-toggle");
const kbPanel = document.getElementById("kb-panel");
const kbUploadBtn = document.getElementById("kb-upload");
const kbClearBtn = document.getElementById("kb-clear");
const kbSourceSel = document.getElementById("kb-source");
const kbTagsInput = document.getElementById("kb-tags");
const kbTextArea = document.getElementById("kb-text");
const kbResult = document.getElementById("kb-result");
const kbStatus = document.getElementById("kb-status");
const kbListDiv = document.getElementById("kb-list");
const kbServerBtn = document.getElementById("kb-server-btn");
const kbListBtn = document.getElementById("kb-list-btn");

if (kbToggle) {
  kbToggle.addEventListener("click", () => {
    const hidden = kbPanel.style.display === "none";
    kbPanel.style.display = hidden ? "flex" : "none";
    kbToggle.classList.toggle("active", hidden);
  });
}

if (kbServerBtn) {
  kbServerBtn.addEventListener("click", () => {
    const current = kbServer;
    const next = prompt("RAG server base URL:", current);
    if (next && next.trim()) {
      kbServer = next.trim().replace(/\/+$/, "");
      saveKbServer();
      toast("KB server set to " + kbServer);
    }
  });
}

if (kbClearBtn) {
  kbClearBtn.addEventListener("click", () => {
    kbTextArea.value = "";
    kbTagsInput.value = "";
    if (kbResult) { kbResult.textContent = ""; kbResult.className = "kb-result"; }
  });
}

if (kbUploadBtn) {
  kbUploadBtn.addEventListener("click", async () => {
    const text = (kbTextArea.value || "").trim();
    if (!text) {
      kbResult.textContent = "Nothing to upload — paste or right-click some text first.";
      kbResult.className = "kb-result err";
      return;
    }

    const source = kbSourceSel.value || "user";
    const tags = (kbTagsInput.value || "")
      .split(",")
      .map(t => t.trim())
      .filter(Boolean);

    // Auto-tag with the source panel URLs, if any
    if (panelUrls[1]) tags.push("CWR");
    if (panelUrls[3]) tags.push("IGI");

    const payload = {
      source,
      tags,
      text,
      metadata: {
        from: hostOf(panelUrls[2]) || "workspace",
        urls: {
          p1: panelUrls[1],
          p3: panelUrls[3]
        },
        addedAt: Date.now()
      }
    };

    kbUploadBtn.disabled = true;
    kbResult.textContent = "Uploading to " + kbServer + " ...";
    kbResult.className = "kb-result";

    try {
      const res = await fetch(kbServer + "/v1/rag/upload", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload)
      });
      const data = await res.json().catch(() => ({}));

      if (!res.ok) {
        throw new Error(data.error || ("HTTP " + res.status));
      }

      kbResult.textContent = "Stored " + (data.chunks ?? "?") + " chunks — id " + (data.id || "unknown");
      kbResult.className = "kb-result ok";
      kbTextArea.value = "";
      kbTagsInput.value = "";
      toast("KB: stored " + (data.chunks ?? 0) + " chunks");
      refreshKbStatus();
    } catch (e) {
      kbResult.textContent = "Upload failed: " + e.message;
      kbResult.className = "kb-result err";
    } finally {
      kbUploadBtn.disabled = false;
    }
  });
}

async function refreshKbStatus() {
  if (!kbStatus) return;
  try {
    const res = await fetch(kbServer + "/v1/rag/list", { method: "GET" });
    if (!res.ok) throw new Error("HTTP " + res.status);
    const data = await res.json();
    const total = data.total ?? (data.documents ? data.documents.length : 0);
    kbStatus.textContent = total + " doc" + (total === 1 ? "" : "s") + " · " + hostOf(kbServer);
  } catch (e) {
    kbStatus.textContent = "KB offline · " + hostOf(kbServer);
  }
}

if (kbListBtn) {
  kbListBtn.addEventListener("click", async () => {
    kbListDiv.innerHTML = "Loading...";
    try {
      const res = await fetch(kbServer + "/v1/rag/list");
      if (!res.ok) throw new Error("HTTP " + res.status);
      const data = await res.json();
      const docs = data.documents || [];
      if (docs.length === 0) {
        kbListDiv.textContent = "(empty)";
        return;
      }
      kbListDiv.innerHTML = "";
      for (const d of docs.slice(0, 50)) {
        const el = document.createElement("div");
        el.className = "kb-list-item";
        el.innerHTML =
          '<span class="kb-li-meta">' +
          (d.source || "?") + " · " +
          (d.tags || []).join(",") + " · " +
          (d.total_chunks || "?") + " chunks" +
          '</span><button class="kb-li-del" data-id="' + d.id + '" title="Delete">🗑️</button>';
        kbListDiv.appendChild(el);
      }
      kbListDiv.querySelectorAll(".kb-li-del").forEach(btn => {
        btn.addEventListener("click", async () => {
          const id = btn.dataset.id;
          if (!confirm("Delete this document?")) return;
          try {
            await fetch(kbServer + "/v1/rag/doc/" + id, { method: "DELETE" });
            btn.parentElement.remove();
            refreshKbStatus();
          } catch (e) {
            toast("Delete failed: " + e.message);
          }
        });
      });
    } catch (e) {
      kbListDiv.textContent = "Failed: " + e.message;
    }
  });
}

// Handle pending KB text from context menu (stored before workspace loaded)
(async () => {
  try {
    const r = await browser.storage.local.get("kbPending");
    if (r.kbPending) {
      await browser.storage.local.remove("kbPending");
      const textarea = document.getElementById("kb-text");
      if (textarea) {
        textarea.value = r.kbPending;
        const panel = document.getElementById("kb-panel");
        if (panel) panel.style.display = "flex";
        if (kbToggle) kbToggle.classList.add("active");
      }
    }
  } catch {}
})();

// =====================================================
// 14. Resize
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
// 15. Toast
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
// 16. Init
// =====================================================
document.addEventListener("DOMContentLoaded", async () => {
  await loadLayout();
  await loadSavedUrls();
  await loadAiUrls();
  await loadKbServer();

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
  refreshKbStatus();

  let t;
  window.addEventListener("resize", () => {
    clearTimeout(t);
    t = setTimeout(applyLayout, 100);
  });
});
