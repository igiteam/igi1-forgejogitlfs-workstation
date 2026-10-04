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
// Context menu → Send selected text to KB
// =====================================================
browser.contextMenus.create({
  id: "send-to-kb",
  title: "Send to knowledge base",
  contexts: ["selection"]
});

browser.contextMenus.onClicked.addListener(async (info, tab) => {
  if (info.menuItemId !== "send-to-kb") return;
  const text = info.selectionText;
  if (!text || !text.trim()) return;

  if (tab && tab.url && tab.url.startsWith(WORKSPACE_URL)) {
    browser.tabs.sendMessage(tab.id, {
      type: "kb-fill",
      text: text
    }).catch(() => {});
    return;
  }

  await browser.storage.local.set({ kbPending: text });
  const tabs = await browser.tabs.query({ url: WORKSPACE_URL });
  if (tabs.length > 0) {
    browser.tabs.update(tabs[0].id, { active: true });
    browser.tabs.sendMessage(tabs[0].id, { type: "kb-fill", text }).catch(() => {});
  } else {
    browser.tabs.create({ url: WORKSPACE_URL });
  }
});

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
