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