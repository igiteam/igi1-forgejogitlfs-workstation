# igi1-forgejogitlfs-workstation

Tree 1 — source + intelligence + deltas
├── engine/Poseidon/AI/AICenter.cpp           ← source
├── engine/Poseidon/AI/AICenter.cpp-ai.txt    ← AI description (ragged, per-file)
├── engine/Poseidon/AI/AICenter.cpp.patch     ← diff against last release
├── engine/Poseidon/AI/AICenter.cpp.patch-ai.txt  ← description of the change
├── engine/Poseidon/Audio/Voice/VonApp.cpp
├── engine/Poseidon/Audio/Voice/VonApp.cpp-ai.txt
├── engine/Poseidon/Audio/Voice/VonApp.cpp.patch
└── ...

Tree 2 — shipped game + unpacked + manifest
├── DTA/scripts.pbo                           ← frozen original
├── DTA_Unpacked/
│   ├── _manifest.yml                         ← provenance of every entry
│   ├── ai_center.sqs
│   ├── ai_center.sqs-ai.txt                  ← AI description
│   ├── init.sqs
│   └── ...
├── Worlds/abel.wrp                           ← binary, header-only description
├── Worlds/abel.wrp-ai.txt
├── OperationFlashpoint.exe
├── OperationFlashpoint.exe-ai.txt
├── _tree.txt                                 ← flat entry list
└── ...

Tree 3 — reference / tooling
├── project-igi-research-data/...             ← same pattern
│   └── *-ai.txt alongside each file
└── ...

                    ┌──────────────────────┐
                    │  crossref phase      │
                    │  (separate script)   │
                    └──────────┬───────────┘
                               │
                               ▼
                    crossref.yml
                    AICenter.cpp → ai_center.sqs → igi/ai/graph/node_17

Tree 1 (source)     Tree 2 (game)         Tree 3 (reference)
    │                   │                     │
    │ source files      │ unpacked .pbo      │ IGI research
    │ + .patch files    │ + _manifest.yml    │
    │                   │ + _tree.txt        │
    │                   │ + Worlds/*.wrp     │
    │                   │ + .exe, .cfg       │
    │                   │                   │
    └───────────────────┴───────────────────┘
                        │
                        ▼
                  AI cross-reference
                        │
                        ▼
              "this .cpp change → this .sqs
               → repack scripts.pbo → rebuild"

ok but also the tree 1 will have the ai_dump data for example what each file does, and that could be ragged to

Yes — that's the missing piece. Tree 1 isn't just source; it's source + *-ai.txt descriptions + .patch files, all three interleaved. That's what makes the cross-reference possible, because the AI reads Tree 1's description of what a file is supposed to do and then reads Tree 2's description of what actually shipped, and matches them.

Let me redraw the whole thing with that baked in.
The full picture
text

Tree 1 — source + intelligence + deltas
├── engine/Poseidon/AI/AICenter.cpp           ← source
├── engine/Poseidon/AI/AICenter.cpp-ai.txt    ← AI description (ragged, per-file)
├── engine/Poseidon/AI/AICenter.cpp.patch     ← diff against last release
├── engine/Poseidon/AI/AICenter.cpp.patch-ai.txt  ← description of the change
├── engine/Poseidon/Audio/Voice/VonApp.cpp
├── engine/Poseidon/Audio/Voice/VonApp.cpp-ai.txt
├── engine/Poseidon/Audio/Voice/VonApp.cpp.patch
└── ...

Tree 2 — shipped game + unpacked + manifest
├── DTA/scripts.pbo                           ← frozen original
├── DTA_Unpacked/
│   ├── _manifest.yml                         ← provenance of every entry
│   ├── ai_center.sqs
│   ├── ai_center.sqs-ai.txt                  ← AI description
│   ├── init.sqs
│   └── ...
├── Worlds/abel.wrp                           ← binary, header-only description
├── Worlds/abel.wrp-ai.txt
├── OperationFlashpoint.exe
├── OperationFlashpoint.exe-ai.txt
├── _tree.txt                                 ← flat entry list
└── ...

Tree 3 — reference / tooling
├── project-igi-research-data/...             ← same pattern
│   └── *-ai.txt alongside each file
└── ...

                    ┌──────────────────────┐
                    │  crossref phase      │
                    │  (separate script)   │
                    └──────────┬───────────┘
                               │
                               ▼
                    crossref.yml
                    AICenter.cpp → ai_center.sqs → igi/ai/graph/node_17

The "ragged" part you flagged

Yes — *-ai.txt files will be uneven. A 40-line BSearch.hpp gets a 3-line description. A 1,200-line AIUnitImpl.cpp gets a full function-by-function breakdown. That's fine and intentional. The crossref phase doesn't need them to be the same size; it needs them to be indexed by the same key.

Two rules make ragged output usable:

Rule 1 — every *-ai.txt starts with a fixed header block. Everything after is free-form.
markdown

---
source: engine/Poseidon/AI/AICenter.cpp
tree: 1
sha256: a1b2c3d4...
lines: 842
described_at: 2026-10-04T14:23:00Z
model: llama3.1:8b
tags: [ai, group, radio, arcade]
related: [DTA_Unpacked/ai_center.sqs]
---

# AICenter.cpp

Purpose: Manages AI group coordination, arcade template lookup, radio dispatch.
...

(rest of the description, however long it needs to be)

The YAML frontmatter is machine-readable and identical across all three trees. The AI cross-reference phase parses only the frontmatter first, builds the map, then dives into bodies only where it needs detail.

Rule 2 — the tags are drawn from a shared vocabulary. Not free-form. If Tree 1 tags AICenter.cpp with [ai, group, radio], and Tree 2 tags ai_center.sqs with [ai, group, radio], the crossref matches them by tag overlap, not by semantic guessing. You build the vocabulary once (it's the set of subsystem names — ai, audio, network, ui, render, io, script, terrain, vehicle, weapon, mission, campaign), and every description picks from that set.

That's how ragged becomes comparable.
Revised pipeline — three scripts

Script 1: tree-to-ai.py (already scoped)
Walks any tree. For each source file, produces a sibling *-ai.txt with the frontmatter header. Skips binary formats it can't describe (.exe, .dll, .ogg, .paa — treated as opaque) but produces header-only descriptions for formats it can (.p3d, .wrp, .lip, .pbo).

Script 2: patch-to-ai.py (new, trivial)
Walks Tree 1 for *.patch files. For each, produces *.patch-ai.txt describing what changed and which Tree 2 entries are affected. Cheap — patches are small text.

Script 3: crossref.py (the actual value)
Reads all three trees' *-ai.txt files. Parses only the frontmatter of each. Builds a tag-keyed index. Emits crossref.yml:
yaml

AICenter.cpp:
  tree1: engine/Poseidon/AI/AICenter.cpp
  tree2: DTA_Unpacked/ai_center.sqs        # matched by tag: [ai, group]
  tree3: project-igi-research-data/ai/graph/node_17
  confidence: 0.87
  last_matched: 2026-10-04T14:30:00Z

VonApp.cpp:
  tree1: engine/Poseidon/Audio/Voice/VonApp.cpp
  tree2: DTA_Unpacked/scripts/von_app.sqs
  tree3: null                              # IGI has no von equivalent
  confidence: 0.92

Then every future .patch gets routed through this map automatically.
The order of operations
text

Step 1 — unpack Tree 2
    OperationFlashpoint/DTA/*.pbo → DTA_Unpacked/
    (you already said you can do this)
    Also emit _manifest.yml for each

Step 2 — run tree-to-ai.py on all three trees
    Tree 1 → *-ai.txt next to each source file
    Tree 2 → *-ai.txt next to each unpacked file
    Tree 3 → *-ai.txt next to each reference file

Step 3 — run crossref.py once
    Reads all three *-ai.txt files
    Emits crossref.yml

Step 4 — from then on, when you edit Tree 1:
    diffs appear as *.patch
    patch-to-ai.py describes them
    AI uses crossref.yml to say:
      "these 3 patches affect these 2 .pbo"
      "repack scripts.pbo and Data.pbo with these changes"

Two decisions left

Decision A — where does -ai.txt live?

Option 1 — next to the source file. AICenter.cpp and AICenter.cpp-ai.txt sit side by side. Pro: everything travels together, one tree. Con: it pollutes the source tree, and if you ever git add . you'll commit 6,000 AI files.

Option 2 — parallel tree. ___openofpcwr-ai/engine/Poseidon/AI/AICenter.cpp-ai.txt. Source stays clean. The AI tree is a mirror. Con: two trees to keep in sync, and when the AI wants to read both the source and the description it has to jump between paths.

Option 3 — same file, appended. Source file gets a // == AI-DESCRIPTION == block at the end. Single file. Con: pollutes the source, breaks diffs, breaks the compiler if you're not careful.

I'd pick Option 2 for Tree 1 (source stays committable) and Option 1 for Tree 2 (_Unpacked/ is a shadow anyway, not version-controlled; keeping description next to the file is friendlier). Slight inconsistency, but each is right for its context.

If you want consistency instead, Option 2 everywhere.

Decision B — model target.

Ollama / LM Studio / Anthropic / OpenAI — still need this. My default recommendation: Ollama with llama3.1:8b if you want free and local, or Claude Haiku if you want fast and cheap ($0.25/M input tokens, 6,000 files at ~500 tokens each ≈ $0.75 for the whole run). Either works with the same script; the flag changes.
What I'll write next

Once you answer A and B, I'll ship:

    tree-to-ai.py — the walker

    patch-to-ai.py — the diff describer (short)

    crossref.py — the matcher (reads only frontmatter)

    A shared _vocabulary.yml — the tag list all three trees draw from

Four files, ~600 lines total. Runs on any of the three trees. Produces the *-ai.txt files and the crossref.yml. Then the extension you already have can query it, and the IGI↔OFP mapping becomes a real, queryable artifact instead of something you hold in your head.

Which answers?
i told u no ai, we have the 7 free ai website in the center, if they can and they can read the rag.domain,.com?url=*ai.txt&url2=*engine.cpp
there u are!

Oh — I see it now. I completely missed it. You're not building an AI pipeline. You're building the plumbing so the AI websites in panel 2 can do the work themselves.

Let me re-read what you actually said at the start of this whole conversation, because it lines up exactly:

    "what is going on that during the project Opencwc will get diff files and ai files which describes each file, so engine.cpp engine-cpp-ai.txt"

And then:

    "the tree 1 will have the ai_dump data for example what each file does, and that could be ragged too"

I read "ai_dump" as "output of an AI" and assumed you meant a batch pipeline that generates them. But you meant it the other way: the ai_dump is the input to the AI. You're pre-staging the descriptions so the free AI websites can consume them via the RAG endpoint.

And the RAG endpoint is the thing we built. rag.songdrop.band/?url=...&url=... already fetches, chunks, embeds, and serves. The whole point of that service is to be the middleman that turns arbitrary URLs into RAG-ready data. So the extension's job is:

Panel 2 (any of the 7 AI sites) → chat box → you paste a rag.songdrop.band/?url=... link → the AI fetches it → you ask your question.

That's the entire architecture. No tree-to-ai.py. No Ollama. No API keys. No scripts. The AI does the cross-referencing in its own context window, reading whatever you point it at.
So the pipeline is
text

You're in panel 2, chatting with DeepSeek

You type:
  "Compare these two:
   https://rag.songdrop.band/?url=https://raw.githubusercontent.com/.../AICenter.cpp-ai.txt
   https://rag.songdrop.band/?url=https://raw.githubusercontent.com/.../ai_center.sqs-ai.txt"

DeepSeek fetches both via the RAG service
RAG fetches the raw URL, chunks, embeds, returns structured JSON
DeepSeek reads the descriptions and answers

And for a changed file, you'd feed it three URLs at once:
text

https://rag.songdrop.band/?url=.../AICenter.cpp-ai.txt
                   &url=.../AICenter.cpp.patch
                   &url=.../ai_center.sqs-ai.txt

The -ai.txt is the "what it was supposed to be," the .patch is the "what changed," and the second -ai.txt is "what shipped." The AI has everything to say "here's what needs to happen to Tree 2."
That means the deliverables are different from what I offered

Not tree-to-ai.py. Not crossref.py. Instead:

1. tree-to-urls.py (or even just a shell script)
Walks a tree, prints one RAG URL per file. So you can paste them into panel 2 without hand-typing paths. Something like:
text

https://rag.songdrop.band/?url=https://raw.githubusercontent.com/.../AICenter.cpp-ai.txt
https://rag.songdrop.band/?url=https://raw.githubusercontent.com/.../AIGroup.cpp-ai.txt
https://rag.songdrop.band/?url=https://raw.githubusercontent.com/.../AIUnit.cpp-ai.txt
...

Actually — even better — a multi-URL variant that respects the RAG server's existing &url= chain:
text

https://rag.songdrop.band/?url=.../AICenter.cpp-ai.txt&url=.../AIGroup.cpp-ai.txt&url=.../AIUnit.cpp-ai.txt&deep=1

Since our RAG server already supports deep=1 for similarities/duplicates/patterns across multiple URLs, you can hand the AI a single link that does the comparison server-side, and the AI just reads the analysis.

2. The -ai.txt generation is a separate question.

Where do they come from? Three possibilities:

    Hand-written by you as you work through the tree. Slow but human-vetted.

    Generated by the same AI websites in panel 2, then pasted back as files. You feed the AI rag.songdrop.band/?url=.../AICenter.cpp (the raw source), ask "describe this," copy the reply, save as AICenter.cpp-ai.txt. Ugly, manual, but works with zero additional infra.

    Generated by a separate batch script that uses a free AI API. This is what I kept offering, and you kept saying no to because you don't want an API — you want the free web UIs.

If it's the second one, then we need a small helper: a "save this AI reply as a file" button in the extension. Because otherwise the loop is: ask AI → copy reply → switch to file manager → paste into a new file → repeat 6,000 times. That's the actual pain point, not the pipeline.

3. The extension work.

Given everything, the useful additions to your v2.3 extension are:

    Multi-URL RAG builder. A small UI in panel 1 and panel 3: select files from a list, hit "build RAG link", get a single rag.songdrop.band/?url=...&url=...&deep=1 link, auto-paste into panel 2's chat. That replaces hand-typing URLs.

    "Save to ai_dump" button. Right-click in any panel → "Save as -ai.txt" → saves the selected text (or the whole page content) into a shadow _ai_dump/ tree next to the source. So when you ask DeepSeek "describe AICenter.cpp", you click the button, it writes AICenter.cpp-ai.txt in the right place, and the file is now available at a raw URL for the next round.

    A tree browser in panel 1 and panel 3 that shows the local files (via file:// or a local HTTP server) so you can click into a file, see its -ai.txt sibling, and copy either one.

The three questions now

I need to know which shape you actually want before writing anything, because I've offered the wrong thing twice:

Q1 — Where do -ai.txt files come from?
Hand, AI-website reply + manual save, or a batch script you run once? If it's the second, we need the "Save as -ai.txt" button. If it's the first, we skip that entirely.

Q2 — Are the trees served over HTTP, or opened locally?
rag.songdrop.band needs to fetch the source files. So AICenter.cpp has to be reachable at some URL. Options:

    GitHub raw (if the trees are pushed to a public repo — raw.githubusercontent.com/...)

    A local HTTP server (python -m http.server 8000 in the tree root — reachable as http://localhost:8000/...)

    The RAG server itself, configured to serve local files by path

Which one? This is the piece I don't have visibility into.

Q3 — does the RAG server need to change at all?
The current rag.songdrop.band/?url=... fetches remote URLs. If your trees are local, the RAG server needs a new mode: ?local=/path/to/AICenter.cpp or a separate /file/ endpoint that reads from disk. Otherwise you're stuck pushing everything to GitHub first.

Answer Q2 first, because it determines whether we touch the RAG server or not. Then Q1. Then I'll write the right script — probably a 30-line extension tweak, not the 600-line pipeline I kept offering.
or for example im reading shit, and i found 5 files, connected to the problem adding anaglyphic3d to operation flashpoint - than its a new txt can be created to talk about that shit

Yes. That's the actual unit of knowledge. Not the per-file -ai.txt. The "topic" file.

Let me reframe everything around that, because it changes what the system is.
The unit is a topic, not a file

You're reading through the code. You notice something: "adding anaglyphic 3D to OFP requires changes in EngineGL33Anaglyph3D.cpp, EngineGL33Stereo3D.cpp, Camera.cpp, Renderer.cpp, and settings/GraphicsConfig.cpp."

You write it down. Not as five separate per-file notes. As one file — topics/anaglyph-3d.txt — that says:
text

topic: anaglyph-3d
title: Adding anaglyphic 3D to Operation Flashpoint
status: research

related source files:
  engine/Poseidon/PoseidonGL33/EngineGL33Anaglyph3D.cpp
  engine/Poseidon/PoseidonGL33/EngineGL33Stereo3D.cpp
  engine/Poseidon/World/Scene/Camera/Camera.cpp
  engine/Poseidon/Graphics/Core/EngineDrawing.cpp
  engine/Poseidon/UI/Settings/GraphicsConfig.cpp

related shipped files:
  DTA_Unpacked/config.bin       (graphics flags)
  Data3D.pbo (unpacked)          (stereo pair textures)

related IGI research:
  project-igi-research-data/rendering/...

notes:
  - Anaglyph needs per-eye render target
  - Existing EngineGL33_Stereo3D.cpp already splits eyes; maybe reuse
  - Open question: does .wrp terrain need a second pass?
  - See also: red/cyan offsets in Camera.cpp line 402

open questions:
  - What happens when reflection is enabled?
  - Does this affect the editor viewport?

ai prompt used:
  https://rag.songdrop.band/?url=.../EngineGL33Anaglyph3D.cpp&url=.../Camera.cpp&url=.../GraphicsConfig.cpp&deep=1

That's the artifact. It's a cross-cutting topic — a thread you pulled. The per-file -ai.txt files are just raw material the topic file points at.
So the system has two layers

Layer 1 — per-file descriptions (*-ai.txt)
Generated once per source file. Rarely change. They're the "what does this do" record. These are what the RAG server serves when you ask "tell me about Camera.cpp."

Layer 2 — topic files (topics/*.txt)
Created whenever you (or the AI) discover a thread connecting multiple files. They're short, dense, human-written (or AI-assisted-and-vetted), and they carry:

    a title

    a status (research, planned, in-progress, shipped)

    a list of related files across all three trees

    notes

    open questions

    the RAG prompt that generated or confirmed the finding

Topic files are the actual knowledge. Per-file files are the reference library.
Why this is the right shape

Because the questions you actually ask aren't "what does Camera.cpp do." They're:

    "What do I need to touch to add anaglyph 3D?" → open topics/anaglyph-3d.txt

    "Has anyone looked at why the HUD breaks in stereo mode?" → search topics/ for stereo, hud

    "Which topics are still open?" → filter by status: research

    "If I change Camera.cpp, what topics does it affect?" → grep topics/ for Camera.cpp

That last one is the killer feature. Every source change can be traced to the topics it belongs to, which tells you what else might break.
The workflow becomes
text

You read code.
You spot a pattern.
You open a new topic file.
You list the files involved across all three trees.
You hit "Build RAG link" in the extension (which takes
  the file list from the topic and produces a single
  rag.songdrop.band/?url=...&url=...&deep=1 URL).
You paste it into panel 2.
DeepSeek analyzes the whole cluster.
You copy the reply into the topic file as `ai analysis`.
You refine the notes.
Topic file lives forever, searchable.

Later, when you actually implement the change:
text

You edit the source files.
Patches appear.
You open the same topic file.
Status: research → in-progress.
You add: "changed EngineGL33_2D.cpp line 42 to fork per-eye render".
You build a new RAG link with the patch files + the changed files.
You paste, ask "does this break anything?", copy reply.
When done: status → shipped.

And the shipped game gets a matching topics/anaglyph-3d.shipped.txt describing what actually landed in Tree 2 — which entries in which .pbo changed, what the user-visible behavior is.
What this changes about the extension

The v2.3 extension is fine as-is for the three panels. What it needs is a fourth mode — a topic editor side panel:

    Left edge of the whole window: a thin bar, collapsible, showing topics/ list

    Click a topic → it opens a small editor pane (over the top of panel 2, or as a modal) with:

        title, status, tags

        the list of related files (clickable → jumps panel 1 or 3 to that file)

        the free-form notes area

        a "Build RAG link" button that takes all the file paths listed and produces one rag.songdrop.band/?url=...&url=...&deep=1 link

        a "Copy link to clipboard" button

        a "Paste AI reply into this topic" button

So the loop is: open topic → build link → paste into DeepSeek → copy reply → paste back into topic → save. All without leaving the extension.
Where the topics live

Either:

    topics/ at the root of Tree 1 — sits alongside engine/, version-controlled with the source, travels with the repo

    topics/ in a separate repo — cleaner separation, harder to keep in sync

I'd pick the first. It's just text files in a directory. They belong next to the code they describe.
What I'd actually write, given this

Nothing big. Three small things:

1. topic-template.txt — a starter file with the right headings. You copy it, rename it, fill it in. 15 lines.

2. Extension patch — "Build RAG link from file list" — a small text box in the topic editor where you paste a list of file paths, one per line, and it produces the RAG URL with all &url= params. This is the piece that removes the tedium. ~40 lines of JS.

3. Extension patch — "Save reply to topic" — a button that takes the selected text (or the contents of the last message in panel 2, if the AI site exposes it) and appends it to the currently-open topic file. This one's harder because cross-origin iframes don't let you read their content — you'd have to right-click-select-copy manually, then hit "paste into topic" in the extension, which reads the clipboard. ~30 lines of JS.

That's it. The rest is you doing the reading and the writing.
One question

Where do topics live, and how does the extension know the tree paths?

The extension is a browser tab. It can't read your local filesystem. So either:

    The trees are served over HTTP (local python -m http.server or a remote server), and the extension fetches topics/ over that HTTP endpoint — then topic files are read/written via the same server. Writing means you'd need a small write endpoint on the server, not just a static file server.

    The topics live in browser.storage.local — no filesystem at all. They're just extension state, backed up via export/import buttons. Simpler, but then they're not in the repo.

    You open a directory picker once, and the extension uses the File System Access API (Chrome-only, not Firefox) to read/write topic files directly. Firefox doesn't support this.

Since it's a Firefox extension: the topics almost have to live on a server you can POST to, or in extension storage. Which one do you want?

If the trees are already going to be served over HTTP for the RAG server to fetch them (which they must be, since RAG fetches URLs), then adding a /topics/ write endpoint to that same server is trivial — 20 lines of code. That's probably the answer.

Confirm: are the trees served over HTTP, and is that server yours to modify?
Tree 1 — source + intelligence + deltas
├── engine/Poseidon/AI/AICenter.cpp           ← source
├── engine/Poseidon/AI/AICenter.cpp-ai.txt    ← AI description (ragged, per-file)
├── engine/Poseidon/AI/AICenter.cpp.patch     ← diff against last release
├── engine/Poseidon/AI/AICenter.cpp.patch-ai.txt  ← description of the change
├── engine/Poseidon/Audio/Voice/VonApp.cpp
├── engine/Poseidon/Audio/Voice/VonApp.cpp-ai.txt
├── engine/Poseidon/Audio/Voice/VonApp.cpp.patch
└── ...

Tree 2 — shipped game + unpacked + manifest
├── DTA/scripts.pbo                           ← frozen original
├── DTA_Unpacked/
│   ├── _manifest.yml                         ← provenance of every entry
│   ├── ai_center.sqs
│   ├── ai_center.sqs-ai.txt                  ← AI description
│   ├── init.sqs
│   └── ...
├── Worlds/abel.wrp                           ← binary, header-only description
├── Worlds/abel.wrp-ai.txt
├── OperationFlashpoint.exe
├── OperationFlashpoint.exe-ai.txt
├── _tree.txt                                 ← flat entry list
└── ...

Tree 3 — reference / tooling
├── project-igi-research-data/...             ← same pattern
│   └── *-ai.txt alongside each file
└── ...

                    ┌──────────────────────┐
                    │  crossref phase      │
                    │  (separate script)   │
                    └──────────┬───────────┘
                               │
                               ▼
                    crossref.yml
                    AICenter.cpp → ai_center.sqs → igi/ai/graph/node_17

this is good but stay with me lemme explain

I'm here. Go ahead.

Just so I'm tracking the current state before you continue:

    The three-tree layout is locked

    -ai.txt files sit alongside each source file (your choice of Option 1, both trees)

    .patch files sit alongside in Tree 1, with -ai.txt companions

    _manifest.yml per _Unpacked/ directory

    _tree.txt flat index at each tree root

    Topics are a layer on top, not per-file

    The RAG server (rag.songdrop.band/?url=...) is the fetch mechanism for the AI sites

    No batch AI pipeline — the free web UIs do the work

I'm not going to ask another question or offer another format. Explain what's on your mind and I'll stay with it.

The 80/20 principle applied to the tree

80% of Tree 1 is the base engine — ___openofpcwr's existing source. That doesn't change. It's the substrate your mod sits on. Its -ai.txt files describe what's already there, so when you or the AI reads a file during the mod work, you don't have to re-derive what Camera.cpp does from scratch. The description is pre-baked, sitting next to it, and it's just reference material.

20% is the mod — the .patch files, which represent deltas against that base. Each patch has a companion -ai.txt describing what changed and why. Because patches are the actual intellectual work of the mod, their descriptions matter more. They're the ones you write by hand or with AI assistance.

So the tree has two kinds of "AI knowledge" files:
text

AICenter.cpp                    ← base source (80%, never changes)
AICenter.cpp-ai.txt             ← description of base (written once, reference)
AICenter.cpp.patch              ← your delta (20%, the mod)
AICenter.cpp.patch-ai.txt       ← description of delta (written per change)

The base descriptions are library cards. The patch descriptions are changelog entries. Same format, different purpose, both live side by side with their source.
What "easy to understand" means here

You said it: the question is whether these -ai.txt files create easy-to-understand stuff.

That's the only design constraint that matters. Not "comprehensive." Not "technical." Easy to understand — for you, on a Tuesday evening, six months from now, when you've forgotten what AICenter.cpp does and you need to know in 30 seconds whether it's involved in the anaglyph-3D problem.

So the -ai.txt format has to be:

    Short. If it doesn't fit on one screen, it's too long. Two paragraphs and a short list, max.

    Plain English. No "instantiates an FSM with deferred transition callbacks." Just: "This is where the AI decides what to do next."

    Front-loaded. The first line answers "what is this?" The rest is supporting detail.

    Greppable. Terms you'll actually search for are in there. Not synonyms. Real words.

    Consistent. Every file's description follows the same shape, so your eye knows where to look.

A concrete format

Let me propose one and see if it lands. Not "the format" — a first draft you can push back on.

For a base source file (AICenter.cpp-ai.txt):
text

# AICenter.cpp

One-line: Coordinates AI groups — receives commands, dispatches them to units, tracks group state.

What it does:
  - Owns the master AI group list
  - Routes orders from scripts and arcade templates down to individual units
  - Handles radio messages between groups
  - Decides when a group is "done" with an order

Who calls it:
  Scripts (via SQF/SQS), the arcade template loader, radio dispatch

What it calls:
  AIGroup, AIUnit, AIRadio, ArcadeTemplate

Notes:
  - The group state machine lives in AISubgroupFSM.cpp, not here
  - Radio messages are async — delivery order is not guaranteed
  - Look here when AI gets "stuck" and doesn't respond to new orders

Last reviewed: 2026-10-04

That's roughly 15 lines. Fits on one screen. Answers: what, who, when, where.

For a patch (AICenter.cpp.patch-ai.txt):
text

# AICenter.cpp.patch

Change: Added hook for stereo-per-eye rendering of AI vision indicators.

Why: Anaglyph 3D mode needs the AI "detection cone" debug overlay
     to render once per eye. Currently it renders once, causing a
     double-image ghost in anaglyph mode.

What changed:
  - New method: AICenter::RenderForEye(eye) — called from Camera
  - Existing RenderDebug() now delegates to RenderForEye(left)
  - No behavior change in non-anaglyph modes

Touches: Camera.cpp, SceneDraw.cpp, GraphicsConfig.cpp

Related topic: topics/anaglyph-3d.txt

Status: applied to base, awaiting Tree 2 repack

Same shape. ~15 lines. Answers: what, why, blast radius, where the thread lives.
The workflow this enables

    Once — you describe the base engine. Either by hand (slow, careful) or with AI help reading the source (fast, you review). 6,000 files becomes 6,000 little reference cards. They sit in the tree forever.

    Every time you do mod work — you edit source, diff produces a .patch, you write (or AI drafts, you edit) the .patch-ai.txt. Two files land side by side: the delta and its description.

    When you hit a problem — you grep -ai.txt files for stereo, anaglyph, hud, whatever. You get a short list of files. You read their cards. In two minutes you know which three files matter. Then you open a topic file to track the thread.

    When you ask the AI — you hand it the RAG URL pointing at Camera.cpp-ai.txt + Camera.cpp.patch-ai.txt + SceneDraw.cpp-ai.txt. It reads four short cards instead of four 1,200-line source files. Its answer comes back faster and more focused, because you pre-digested the input.

Where the "AI writes them" part fits

Two honest options for generating the base descriptions:

Option A — manual. You read each file, write the card yourself. Reliable. Tiring. Works for the 200–500 files you actually care about (the ones in your mod's blast radius). The other 5,500 can have a stub card that just says "unreviewed" until you need it.

Option B — AI-assisted, one file at a time. You're in panel 2 chatting with DeepSeek. You click a button "Describe this file" next to any file in panel 1. The extension sends the source content (via the RAG URL) to the chat. DeepSeek writes the card. You read it, fix the two things it got wrong, click "Save as -ai.txt", and it lands next to the source. ~30 seconds per file.

Neither is a 6,000-file batch job. Both are incremental — you describe files as you encounter them. The library grows organically. After a month of mod work, you've described the 300 files that actually matter, and the rest stay stubs.

That's the 80/20 again: 80% of the value comes from 20% of the files. You don't need to describe all 6,000. You need to describe the ones you touch.
What I'd actually build

Given all that, the right deliverables are:

1. ai-stub.sh — for every source file in a tree that doesn't yet have a -ai.txt, create a stub:
text

# AICenter.cpp

(not yet described)

Review this file when you encounter it in mod work.
When done, replace this stub with a real description.

Template: _templates/ai-card-template.txt

Cheap. Gives you a visual "have I looked at this?" marker across the tree. Zero AI involved.

2. _templates/ai-card-template.txt and _templates/patch-card-template.txt — the two starter files. Copy, fill, save.

3. Extension additions:

    A "Describe this file" button that appears when you're viewing a source file in panel 1 (or when you right-click one). It builds the RAG URL for that file, pastes it into panel 2's chat, and pre-fills the prompt "Write an easy-to-understand card for this file using the template."

    A "Save reply as -ai.txt" button that takes the AI's reply and saves it next to the currently-open file. Since Firefox can't write to the local filesystem directly, this has to go through a server. Same server as the RAG one — just a POST /v1/card/save endpoint.

4. One server endpoint — POST /v1/card/save that takes {path, content} and writes the file. ~15 lines of Python added to the RAG server. Nothing else changes.

That's it. No tree-to-ai.py. No batch pipeline. No API keys. Just: you read code, you ask an AI to help write the card, you save it, you move on. The tree slowly accumulates knowledge.
What I need to confirm before writing

Q1 — the card format. Is the 15-line shape above right, or do you want different headings? What you'd change matters more than what you'd keep. If it's close, say so and we run with it. If it's wrong, say what you'd want instead.

Q2 — the RAG server. Is rag.songdrop.band a server you control and can add endpoints to? If yes, adding POST /v1/card/save is trivial. If no, we need a different way to write files back to the tree, and that changes the extension design.

Q3 — -ai.txt for binary files. What do you want for .p3d, .paa, .wrp, .exe, .dll? Skip entirely, or a "this is an opaque binary, don't try to read it" stub? I'd lean on skip-for-now, add-if-needed — because you'll know when you need to know what a .p3d contains.

Answer those three and I'll write ai-stub.sh, the two templates, and the extension patch. Small, focused, runs today.

Read all four files. Here's what I actually see in front of me right now, and how the pieces fit.
What you have working

1. The RAG server (setup-rag.sh) — deployed, live at rag.songdrop.band. Handles ?url=...&url=...&deep=1&analyze=...&recache=1. Redis cache, Bull queue, dual concurrency (5 RAG / 2 analysis), 24h cache for analysis. This is the plumbing the AI websites will call.

2. The Firefox extension (v2.3) — three panels. Panel 1 = OFP/CWR GitHub. Panel 2 = 7 AI sites (DeepSeek default). Panel 3 = IGI research GitHub. Two headers per panel: top has URL nav, bottom has the RAG link. Middle panel has a KB toolbar. Header stripping so GitHub/AI sites render inside iframes.

3. The tree generator (tree_create.sh) — produces tree.txt, tree-plain.txt, tree-files.tsv per tree. Works on macOS.

4. The diff applier (BashDiffApplier) — takes a unified diff the AI produced, applies it to the current script, previews changes, uploads. This is for the in-browser editing of scripts from panel 1.
The picture that's forming

Reading these four side by side, the loop is:
text

1. You're in the extension, three panels open.
2. Panel 1 shows a source file on GitHub (e.g. AICenter.cpp).
3. Panel 3 shows the IGI research counterpart.
4. You look at panel 1's bottom header — it shows the RAG link:
     rag.songdrop.band/?url=https://raw.githubusercontent.com/.../AICenter.cpp
5. You copy that link, paste into panel 2 (DeepSeek).
6. DeepSeek fetches the RAG URL, sees the chunked + embedded source.
7. You ask it something.
8. DeepSeek replies with an analysis OR a diff.
9. If it's a diff, BashDiffApplier applies it to the panel-1 script.
10. If it's an analysis, you right-click → "Send to knowledge base" → it lands in the KB panel.

And the -ai.txt files are what make step 5 cheap. Instead of pointing the RAG URL at the 1,200-line AICenter.cpp, you point it at AICenter.cpp-ai.txt — the 15-line card. The RAG server chunks and embeds 15 lines instead of 1,200. DeepSeek reads it 20x faster. The AI's answer comes back focused because you pre-digested the input.

Same for .patch files: point at AICenter.cpp.patch-ai.txt, not the raw diff.
What's actually missing (concrete)

Looking at the extension's workspace.js in v2.3, I see:

    Panel 1 and 3 already have the RAG link in the bottom header. Good.

    The RAG link is for the whole current URL, not for a specific file you've selected.

    There's no way to point the RAG link at a -ai.txt sibling of the currently-open file.

    There's no "Build multi-URL RAG link" UI — you can't chain five -ai.txt files into one link for the topic workflow you described.

    There's no topic editor at all — the KB panel is a flat list of uploaded documents, not the topic files with status, related-files, and open questions.

    There's no "Save as -ai.txt" button — when DeepSeek writes a card, you can't save it back to the tree from the extension.

And the tree generator (tree_create.sh) produces tree.txt, tree-plain.txt, tree-files.tsv — but none of those are consumed by the extension. The extension has no concept of a tree. It just has three iframes pointed at GitHub.

That's the actual gap. Everything in between — the trees, the -ai.txt files, the topic files — has no browser presence yet. You're still doing it by hand in the terminal.
The minimum thing that makes this work

If I were to build the one piece that unlocks the whole loop, it would be this:

A "RAG link builder" in the extension's bottom header, on every panel.

Instead of the bottom header showing one fixed RAG link, it shows a small editor:
text

rag: [ ] url1.txt
     [ ] url2.txt
     [x] current file
     [ ] current file's -ai.txt sibling
     [ ] current file's .patch
     [ ] current file's .patch-ai.txt
     [Build link]

You tick the boxes, hit Build, and it produces:
text

rag.songdrop.band/?url=.../AICenter.cpp-ai.txt&url=.../AICenter.cpp.patch-ai.txt&url=.../ai_center.sqs-ai.txt&deep=1

That single string goes into the clipboard. You paste it into DeepSeek's chat. That's the entire workflow.

And once that link exists, the "Save reply as -ai.txt" button becomes possible — because the extension knows which file the link was built from, so it knows where to save the reply. POST /v1/card/save with {path: "AICenter.cpp-ai.txt", content: "<DeepSeek's reply>"}.

Two additions to the RAG server:

    GET /v1/tree/:treeName/*path — serves raw file content (so the extension can list files in a tree, and so the RAG server itself can fetch local files instead of only remote URLs)

    POST /v1/card/save — writes a file back to the tree

That's about 40 lines of Python on top of the existing RAG server, plus ~120 lines of JS in the extension. Everything else you've built already sits under it.
The question I actually have

Reading the four files again, I notice the extension's RAG_BASE is https://rag.songdrop.band/?url= and it builds a link from the panel's current URL. That means when you're on github.com/BohemiaInteractive/CWR/blob/main/engine/Poseidon/AI/AICenter.cpp, the RAG link is:
text

rag.songdrop.band/?url=https://github.com/BohemiaInteractive/CWR/blob/main/engine/Poseidon/AI/AICenter.cpp

But the RAG server fetches that URL, gets an HTML page with GitHub's UI wrapped around the file, chunks the HTML, embeds the HTML. Not the file.

Does processSingleUrl in setup-rag.sh handle github.com → raw.githubusercontent.com rewriting? Looking at the code... no, it doesn't. It fetches the URL as-given. So for GitHub pages, the AI gets a wall of HTML noise, not the source code.

That's the single biggest bug in the current stack. Everything downstream — the -ai.txt cards, the topics, the crossref — is built on the assumption that RAG returns clean source. Right now it returns HTML mush for any GitHub URL.

Fixing it is three lines in processSingleUrl:
js

// GitHub HTML → raw
url = url.replace(/^https?:\/\/github\.com\/([^/]+)\/([^/]+)\/blob\/(.+)$/, 
                  'https://raw.githubusercontent.com/$1/$2/$3');
// GitHub tree → raw directory listing via API (optional)

Or a generic "is this HTML?" detection after fetch — if Content-Type is text/html and the body contains <html, then either bail with a warning or ask the sender for the raw URL.

Is that already patched on the live server, or is it the next thing to fix? Because if it's not fixed, none of the -ai.txt workflow will work through the extension — you'd be feeding the AI GitHub's HTML chrome instead of your cards.

Confirm that, and I'll write the three pieces: the RAG-link builder patch, the card-save endpoint, and the GitHub-raw rewrite. Small, focused, in the order that unblocks the loop.

The 7 AI sites aren't alternatives — they're a panel of experts

I was reading the AI dropdown as "pick one." But if you've got 7 and you want all of them, the workflow is:

    DeepSeek reads the source and drafts a change

    ChatGPT reads the same source and drafts a different change

    Claude reads the same source and drafts a third

    Gemini/Mistral/Copilot/Perplexity do the same

    You compare all 7

That's a council, not a switcher. And for a mod on a 20-year-old engine where you're not sure how to do X, getting 7 independent opinions is exactly the right call — because the "correct" answer isn't in any training set. It's in the intersection of what all 7 say.

So the middle panel isn't "DeepSeek." It's "the room." The dropdown becomes a tabs strip with 7 tabs. Each tab is its own iframe with its own conversation state. All 7 stay loaded. You ask the same question in all 7, then read across.

Or — better — one shared prompt box, submitted to all 7 at once, each returns into its own tab. But cross-origin iframes make that hard. You can't programmatically type into chat.deepseek.com from your extension unless they expose a public API or you use the browser's accessibility layer (fragile). So the realistic version is: 7 tabs, you paste the same question in each manually, then read.

Which brings us to the second requirement.
Extracting the whole conversation

You want to keep what the AIs said. Not just "the winning answer" — the whole thing. Every reply from every site, timestamped, with which model said what.

That's the input to the -ai.txt cards and the topic files. The conversation is the research. When you ask 7 AIs "how would you add anaglyph 3D to this engine?", the 7 replies together are the topic file's ai analysis section.

So the flow becomes:
text

1. You open a topic in the side panel.
2. You build a RAG link for the files involved.
3. You paste the link + your question into DeepSeek, ChatGPT, Claude, Gemini,
   Mistral, Copilot, Perplexity — all 7 tabs.
4. Each answers.
5. You click "Extract conversation" in the extension.
6. The extension grabs the visible text from each open tab and appends it to
   the topic file as:
       ## DeepSeek
       [reply]
       ## ChatGPT
       [reply]
       ## Claude
       [reply]
       ...
7. Status: research → in-progress.
8. Later, you edit the source, patches appear, you repeat for the "does it work" round.

The extraction is the missing piece. Two honest ways to build it:

Option A — clipboard-based, one tab at a time. You select the AI's reply, right-click → "Send to topic → [topic name]". The extension reads the selection from the context menu (info.selectionText, which Firefox provides) and appends it to the currently-open topic. Zero cross-origin issues. Manual per reply but reliable.

Option B — content-script scraping. Inject a content script into each AI host that knows how to read that site's message list. When you hit "Extract", it walks the DOM of each open tab, pulls the messages, returns them. Faster, does all 7 at once. But fragile — every site redesign breaks the scraper. You'd write 7 small scrapers, one per site.

The pragmatic hybrid: start with Option A (works today, no site-specific code, survives redesigns), and if the manual selection gets tiring, add Option B scrapers for the 2–3 sites you use most.

Option A actually has a nice property: you only save the replies you decide matter. DeepSeek's wrong answer stays out of the topic. You're the filter. That's not a bug — for this workflow, it's the right default.
What this means for the extension

The v2.3 structure holds. What changes:

Panel 2 becomes a tabbed council. 7 AI sites, each in its own iframe, kept alive, switched via a tab strip at the top instead of a dropdown. Existing per-service URL memory already supports this — you just need to render 7 iframes and toggle visibility.

The KB panel becomes a topic editor. Currently it's "paste text → upload to RAG server." That's wrong for the topic workflow. It should be:

    A list of topics (from a topics/ directory served by the RAG server, or from extension storage)

    Click a topic → it opens with its fields: title, status, related files, notes, open questions

    A "Build RAG link" button that takes the related-files list and produces the multi-URL link

    A "Copy link" button

    A "Paste last reply" button that takes the clipboard and appends it under a ## <site> heading, using the currently-active AI tab's hostname as the heading

    A "Save topic" button that writes it back

The RAG server gets a /v1/topics/ endpoint. List, read, write. Text files only. Same pattern as the /v1/card/save idea, just a different directory. ~40 lines of Python.

A global right-click item: "Send to topic → [currently open topic]". Fire on any selection, anywhere in the workspace (including inside the AI iframes, because the selection originates in the iframe but the context menu is registered on the whole tab). Appends the selection under a heading for whichever panel it came from.
What I'd actually build, in order

    GitHub-raw rewrite in processSingleUrl — 3 lines, unblocks everything. Without it the RAG URL for github.com/... returns HTML mush. This is the first fix because nothing else works if the RAG output is garbage.

    Topic files — templates, a topics/ directory in Tree 1, a couple of stubs to see the shape. No code yet, just the format.

    /v1/topics/ endpoints on the RAG server (list, get, put). ~40 lines of Python appended to gateway.js's route section.

    Topic editor in the extension's KB panel — replaces the current flat upload list with a topic browser + editor. ~150 lines of JS + a bit of CSS.

    "Build RAG link" button in the topic editor — takes the related source files: list from the open topic, converts paths to raw GitHub URLs, chains them into one RAG URL with &url= params. ~40 lines.

    "Paste reply to topic" button — reads clipboard, appends under the active AI tab's heading. ~20 lines.

    Right-click: "Send to topic" — already have the context-menu plumbing in background.js from the KB feature. Redirect it at topics instead of the KB upload. ~15 lines.

    Panel 2 → tabs instead of dropdown — 7 iframes, tab strip, memory of which site is active. ~80 lines. This is the biggest single change and can come last, because the workflow works fine with the dropdown until you want to compare answers side by side.

Items 1–4 give you a working topic system end to end. Items 5–8 are the ergonomics that make it pleasant.
One thing to decide before I write

Where do the topic files live?

Two honest options:

    topics/ in Tree 1, served over HTTP by the RAG server. Version-controlled with the source. git log topics/ becomes the research history. But: needs the RAG server to expose topics/ as a read/write directory.

    browser.storage.local in the extension. No filesystem, no server changes. Export/import buttons for backup. But: not in the repo, harder to grep from the terminal, and if you clear the extension you lose everything.

I'd pick topics/ in Tree 1 because the whole point of this project is that the research lives next to the code. But it does mean the RAG server needs a filesystem-write endpoint, which is the one place where "the RAG server only reads URLs" becomes "the RAG server also reads/writes local files." That's a real change in its security posture, so it should be a deliberate one — token-protected, path-restricted to the tree directory.

Confirm that, and I'll write items 1 through 4 as the first drop. Then we look at how it feels, then do 5–8.

One more thing to flag: the extension currently has a kbPending storage key for the KB upload from context menu. If topics replace the KB, that key needs a new name (topicPending) or the two features will fight. Small, but worth doing right now instead of retrofitting later.