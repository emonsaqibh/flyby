<p align="center">
  <img src="docs/assets/app-icon.png" width="128" height="128" alt="Flyby App Icon" />
</p>

<h1 align="center">Flyby</h1>

<p align="center">
  <strong>Instant AI answers in a floating glass bar — without breaking your flow.</strong>
</p>

<p align="center">
  <a href="https://github.com/emonsaqibh/flyby/releases/latest"><img src="https://img.shields.io/github/v/release/emonsaqibh/flyby?color=blue&label=Release" alt="Latest Release" /></a>
  <a href="#"><img src="https://img.shields.io/badge/Platform-macOS%2027%2B-black?logo=apple" alt="macOS 27+" /></a>
  <a href="#"><img src="https://img.shields.io/badge/Architecture-Apple%20Silicon-orange" alt="Apple Silicon" /></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-green" alt="License: MIT" /></a>
  <a href="https://github.com/emonsaqibh/flyby/actions/workflows/ci.yml"><img src="https://img.shields.io/github/actions/workflow/status/emonsaqibh/flyby/ci.yml?branch=main&label=CI" alt="CI Status" /></a>
</p>

<p align="center">
  <a href="#video-walkthrough">Video Demo</a> •
  <a href="#overview">Overview</a> •
  <a href="#key-features">Features</a> •
  <a href="#quick-install">Quick Install</a> •
  <a href="#supported-ai-providers">AI Providers</a> •
  <a href="#keyboard-shortcuts">Shortcuts</a> •
  <a href="#privacy--security">Privacy</a> •
  <a href="#building-from-source">Build from Source</a>
</p>

---

## Video Walkthrough

https://github.com/user-attachments/assets/531b2578-ca2c-4a6a-878a-0fcc9f19fd4e

---

## Overview

**Flyby** is a lightweight, menu-bar-only macOS utility (`LSUIElement`) designed to eliminate context switching.

Press your shortcut (default: **⌥/**), and a dark, Siri-style floating glass bar appears at the bottom of your screen over whatever application you are working in. Type your question, hit `Return`, and the bar fluidly morphs into an answer card with streamed answers and cited sources.

- **Zero Window Jitter:** Operates seamlessly across full-screen spaces, IDEs, and browsers without stealing focus away from your active work.
- **Multimodal Screen Querying:** Capture and ask about your active window with a single hotkey.
- **Local & Private:** Native on-device history, direct browser cookie syncing, and zero middleman servers.

---

## Key Features

- **⚡ Liquid Glass Interface**  
  Built with native Apple-style spring animations. The input bar seamlessly morphs into an answer card without window-resize jitter, adapting organically over any wallpaper or workspace.

- **📸 Screen Intelligence ("Ask About Your Screen")**  
  Hit `⌥⇧Space` or type `/screenshot` to capture your active window with an elegant radiating light wave. Ask Google AI Mode or Gemini about the window you're in — code errors, UI designs, charts, or articles.

- **🧠 Quad-Engine AI Support**  
  Seamlessly toggle between four distinct intelligence providers:
  - **Google AI Mode**: Live AI overviews rendered natively from your existing Google session (Safari/Firefox cookie sync) with citations and zero CAPTCHAs.
  - **Gemini**: Fast streaming with live Google Search grounding via your free API key (`gemini-3.8-flash`).
  - **Apple Intelligence**: 100% on-device, offline, private reasoning through macOS 27's FoundationModels framework.
  - **Browser**: Instant query pass-through to your default browser.

- **💬 Persistent Multi-Turn Conversations**  
  Continue asking follow-up questions within the same card. Re-open any of your last 200 conversations at any time with `⌘Y`.

- **🔒 Privacy by Architecture**  
  Conversations are stored locally on your Mac (`~/Library/Application Support/`). Zero telemetry, zero external trackers, and no middleman servers.

- **⌨️ Deep Keyboard Flow**  
  Full keyboard navigation, slash commands (`/google`, `/gemini`, `/apple`, `/screenshot`, `/copy`), and a shortcut recorder for any key combo — no permissions needed.

---

## Quick Install

Open Terminal and run:

```bash
curl -fsSL https://raw.githubusercontent.com/emonsaqibh/flyby/main/install.sh | bash
```

> **Requirements:** macOS 27 or later on Apple silicon.
> 
> *Flyby runs exclusively as a menu-bar companion (`LSUIElement`) — look for the sparkle magnifying glass in your menu bar.*

### Updating
Flyby automatically checks for updates in the background. You can also trigger an immediate check via **Menu Bar › Check for Updates…** or in **Settings › General › Check Now**.

Pre-built binaries are also available on the **[Releases](https://github.com/emonsaqibh/flyby/releases/latest)** page.

---

## Supported AI Providers

| Provider | Engine Type | Live Web | Vision / Screenshots | Setup Required | Privacy Level |
| :--- | :--- | :---: | :---: | :--- | :--- |
| **Google AI Mode** | Native DOM Streaming | Yes | Yes | Safari or Firefox sign-in sync | Standard Google Account session |
| **Gemini** | Direct REST / SSE API | Yes | Yes | Free Gemini API key | Google API (Search Grounded) |
| **Apple Intelligence** | On-Device Foundation Model | No | No | Enable in macOS System Settings | **100% Offline & Private** |
| **Browser** | Web Redirect | Yes | No | None | Handed to default browser |

### Google AI Mode (Zero CAPTCHAs & Native Extraction)
AI Mode runs inside your own Google session: Settings › Google Account securely mirrors your sign-in cookies from **Safari** or **Firefox** into Flyby's sandboxed cookie store. The answer is streamed invisibly from Google's `/search?udm=50` UI: an injected reader script parses headings, lists, tables, and cited sources in real time, rendering them natively inside Flyby's glass card.

### Gemini
Provide a free API key from [Google AI Studio](https://aistudio.google.com/apikey). Flyby stores it securely in your macOS Keychain. Google Search grounding is enabled by default so answers always reflect real-time web facts.

### Apple Intelligence
Uses macOS 27's native `FoundationModels` framework. No accounts, no API keys, and zero network requests. Your queries and answers never leave your Mac.

---

## Keyboard Shortcuts

### Global Triggers
| Shortcut | Action |
| :--- | :--- |
| **⌥/** *(Default)* | Open / Dismiss Flyby bar |
| **⌥⇧Space** *(Default)* | Capture active window and open Flyby with screenshot attached |

*(Both are customizable in Settings › Shortcut. Shortcuts are key combos — a key with modifiers — which macOS delivers with no permissions at all. Double-taps and held-modifier chords were removed in 0.6: they needed Accessibility and Input Monitoring.)*

### In-App Navigation
| Key | Action |
| :--- | :--- |
| `Return` | Submit query (or follow-up if conversation is open) |
| `⌥Return` | Insert a new line in the query |
| `⌘Return` | Open query immediately in your default browser |
| `⌘K` | Open AI Provider switcher menu |
| `⌘1` – `⌘4` | Quick-switch provider: Browser, Google AI Mode, Gemini, Apple Intelligence |
| `⌘.` | Stop generation mid-stream |
| `⌘R` | Retry / Re-ask query |
| `⇧⌘C` | Copy full formatted answer with sources (`⌘C` copies current selection) |
| `⌘N` | Start a new chat (folds card back into input bar) |
| `⌘Y` or `↑` | Open Recent Chats history |
| `Esc` | Step backward: dismiss menus / unfocus input / dismiss Flyby |
| `Tab` | Refocus input field from answer card |
| `⌘,` | Open Settings |
| `⌘/` | Open in-app keyboard shortcut cheatsheet |

### Slash Commands
Type `/` at the beginning of the input field to trigger quick actions:
* `/screenshot` — Capture the active window and attach to query
* `/google` — Switch to Google AI Mode
* `/gemini` — Switch to Gemini
* `/apple` — Switch to Apple Intelligence
* `/browser` — Switch to Browser redirect
* `/new` — Start a fresh conversation
* `/retry` — Re-run the last question
* `/copy` — Copy the last answer to clipboard
* `/history` — Browse recent conversations
* `/shortcuts` — Display keyboard shortcuts overlay
* `/settings` — Open Flyby Settings

---

## Privacy & Security

* **Local-First Storage:** All conversation history is saved exclusively on your local Mac in `~/Library/Application Support/com.fringecore.flyby/History/`. Flyby does not operate cloud sync servers or telemetry endpoints.
* **On-Device Cookie Syncing:** Google session sync reads only `google.*` session cookies from local browser databases on your Mac. These tokens never leave your machine.
* **Permissions Transparency:**
  * **No keyboard permissions:** Shortcuts are key combos, which need no Accessibility or Input Monitoring at all — Flyby never asks for either.
  * **Screen Recording:** Only requested when you explicitly invoke the screenshot feature (`⌥⇧Space` or `/screenshot`). Flyby captures only the active window, never your background screen.

---

## Building from Source

### Prerequisites
* **macOS 27** running on Apple silicon.
* **Xcode 27.0** or later.

### Build Commands

```bash
# Clone the repository
git clone https://github.com/emonsaqibh/flyby.git
cd flyby

# Build and launch Flyby Dev locally
./run.sh

# Build unoptimized debug build for LLDB
CONF=debug ./build.sh

# Run unit tests
swift test
```

> **Note on Build Flavors:**  
> Flyby uses a dual-target architecture:
> * **Flyby Dev** (`com.fringecore.flyby.dev`): Used for local development and testing. Wears an amber icon with a DEV badge and is signed with a local signing certificate so permissions survive rebuilds.
> * **Flyby (Release)** (`com.fringecore.flyby`): The frozen distribution build. Wears the standard blue icon.

---

## Architecture Overview

```
Sources/
├── FlybyCore/               # Headless Foundation logic (100% unit-tested)
│   ├── Answer/              # Markdown parsing, snapshots, and source models
│   ├── Cookies/             # Safari, Firefox, and Chromium cookie extraction
│   └── AIMode/              # Google AI Mode DOM querying & classification
└── Flyby/                   # macOS Application Layer (SwiftUI + AppKit)
    ├── Google/              # Hidden WKWebView session & DOM script extractor
    ├── GeminiProvider.swift # SSE streaming provider with search grounding
    ├── AppleIntelligence/  # FoundationModels on-device provider
    ├── Capture/             # Window capture & light wave animations
    ├── FlybyPanel.swift     # Smoked liquid glass window & spring physics
    ├── InputBar.swift       # Siri-style floating input pill & provider chip
    ├── AnswerCard.swift     # Expanding card, source chips, and action buttons
    ├── HotKeyMonitor.swift  # Carbon hot keys (key combos, no permissions)
    └── SettingsUI/          # Native macOS split-view settings interface
```

---

## License

This project is licensed under the **MIT License** — see the [LICENSE](LICENSE) file for details.
