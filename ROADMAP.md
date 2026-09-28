# Flyby — Production Readiness

> Started 2026-09-27. This is the working list of everything that stood between
> Flyby and a product people can download and rely on: what was wrong, what was
> done about it, and what still needs a decision. It replaces
> `IMPLEMENTATION_PLAN.md` as the hand-off file between sessions.
>
> Legend: ✅ done · 🟡 partly done / needs on-device verification · ⏳ not started ·
> ❓ needs your decision

---

## 1. The fundamental problem: Google keeps asking for a CAPTCHA

### Why it happened

AI Mode was loaded into a fresh `WKWebView` that looked like a bot to Google on
almost every axis Google checks:

| Signal | What Flyby did | Why Google cared |
| --- | --- | --- |
| Identity | Never signed in; no `SID`/`__Secure-1PSID` cookies | Anonymous traffic gets the lowest trust and the most challenges |
| User agent | Hard-coded `Safari 18.3` string on whatever WebKit the OS shipped | A UA that disagrees with the engine's real feature set is a classic bot tell |
| Region | Pinned `gl=US` regardless of where the user is | Region that contradicts the IP's geolocation is another mismatch |
| Session continuity | A new `WKWebView` for every result panel | No warm page, no history, every search is a cold start |
| Link handling | `target=_blank` links silently dropped | Not a CAPTCHA cause, but the page misbehaved in other ways too |

### The fix (built in this pass)

Flyby now runs AI Mode **inside your own Google session**, in a real WebKit page
that sits invisibly behind Flyby's native answer view — the same pattern as a
cookie-backed YouTube Music client:

```
 Your browser's cookie store                        Flyby
┌──────────────────────────┐   CookieImporter   ┌────────────────────────────────┐
│ Safari  (binarycookies)  │ ─────────────────▶ │ GoogleSession                  │
│ Chrome/Arc/Brave/Edge/…  │  Google cookies    │  dedicated persistent          │
│ Firefox (cookies.sqlite) │  only              │  WKWebsiteDataStore            │
└──────────────────────────┘                    │         │                      │
        or: "Sign in within Flyby" window ────▶ │         ▼                      │
                                                │ AIModeEngine                   │
                                                │  one long-lived WKWebView      │
                                                │  real Safari UA, no gl= pin    │
                                                │  extractor script ──JSON──┐    │
                                                │                           ▼    │
                                                │ SearchController → native      │
                                                │ answer view (same renderer     │
                                                │ as Gemini)                     │
                                                └────────────────────────────────┘
```

- **Connect once** (Settings › Google, or onboarding when AI Mode is chosen):
  pick a browser, Flyby copies only `google.*` cookies into its own store.
  Safari needs Full Disk Access; Chromium browsers show one Keychain prompt;
  Firefox needs nothing. Or sign in inside Flyby.
- **Native UI**: an injected script reads the answer, headings, lists, tables
  and citations out of the page as it streams and posts them to Swift. The
  page itself is never shown unless it has to be.
- **When Google still wants something** (a CAPTCHA, an EU consent wall, a
  sign-in), the page is revealed in place with a banner explaining why. Solve it
  once; the result persists in Flyby's store like it would in a browser.
- **If the page can't be read** (Google changed its markup), Flyby falls back to
  showing the page with the reader stylesheet — never worse than before.

### Honest caveats

- **Full Disk Access is a big ask** for a search utility. It's only needed for
  Safari; Chrome-family and Firefox don't need it, and in-app sign-in needs
  nothing. The UI says this before anything is requested.
- **Google rotates session cookies.** Safari/Firefox imports refresh silently
  every 30 minutes. Chromium imports never refresh on their own (that would pop
  a Keychain prompt out of nowhere) — Flyby asks you to reconnect instead.
- **The extractor depends on Google's markup.** It keys on `data-*` hooks
  rather than obfuscated class names, and has a fallback, but it will need
  maintenance. The Gemini API provider stays the durable option.
- **Terms of service.** Google's terms don't permit automated access to Search.
  Flyby only loads the page you asked for, one per search you type, in your
  own session — but for a paid product, get a legal read before launch. ❓

---

## 2. Everything else that was half-baked

### Architecture

| | Item | Status |
| --- | --- | --- |
| A1 | One flat module; nothing testable without a window | ✅ Split into `FlybyCore` (Foundation-only, Swift 6 strict concurrency, unit-tested) and the `Flyby` app |
| A2 | Every provider had its own state shape (`mode`, `answer`, `sources`, `errorMessage`, …) | ✅ `SearchController` is one `phase` + one `AnswerSnapshot`; every provider renders through the same native view |
| A3 | AI Mode was a raw web page with CSS hacks; Gemini a separate markdown view | ✅ Both produce `AnswerBlock`s; one renderer (headings, nested lists, code, quotes, tables, sources, follow-ups) |
| A4 | Module still named `QuickSearch` | ✅ Renamed to `Flyby` |
| A5 | No tests, no CI | ✅ Unit tests for the cookie stores, markdown, AI Mode messages and versions; CI on a macOS 27 / Xcode 27 runner |

### Search, providers and answers

| | Item | Status |
| --- | --- | --- |
| S1 | AI Mode CAPTCHAs (see §1) | ✅ Built; 🟡 needs a signed-in run on a real Mac |
| S2 | New `WKWebView` per result panel; `target=_blank` links silently dropped | ✅ One long-lived page; new-window links open in the default browser |
| S3 | Reader-mode script ran `getComputedStyle` on every element on every DOM mutation, stopped after 20 s | ✅ Debounced extractor that only reads the answer container; reader CSS only when the page is shown |
| S4 | Same query twice did nothing (mode unchanged) | ✅ Every submit restarts; ⌘R retries |
| S5 | Gemini source chips reshuffled on every streamed chunk (dictionary order) | ✅ Stable, first-seen order |
| S6 | Gemini errors were raw JSON; no retry | ✅ Readable messages for bad key / quota / rate limit / safety; one retry on 429/503 |
| S7 | Gemini default model `gemini-2.5-flash` (shuts down 16 Oct 2026) | ✅ `gemini-3.8-flash`, verified against Google's own gemini-cli; old stored values migrate |
| S8 | Markdown: no code blocks, tables, quotes, nesting; broke mid-stream | ✅ All of those, including unterminated fences while streaming |
| S9 | No stop, retry or copy | ✅ Header buttons + ⌘. / ⌘R / ⌘⇧C |
| S10 | Result panel could open on a different display than the pill | ✅ Opens on the pill's screen |
| S11 | Query history / recents | ⏳ Needs a privacy decision ❓ |
| S12 | Follow-up conversation in AI Mode (typing into Google's composer) | ⏳ Follow-up chips exist; a true thread is next |
| S13 | A private, offline provider | ✅ Apple Intelligence (FoundationModels, on-device): streams, carries follow-ups, prewarms as the pill opens; 🟡 run in the app on a real Mac |

### Hotkeys and input

| | Item | Status |
| --- | --- | --- |
| H1 | Hot key could stay paused forever after recording ended abnormally (closing Settings, switching tabs, onboarding Back/Continue) | ✅ Fixed at the recorder and at window close |
| H2 | Recorder swallowed keystrokes in every Flyby window while armed | ✅ Only handles its own window's events |
| H3 | A combo already taken by another app was reported as "needs Accessibility" and polled forever | ✅ Distinct state, menu item "Shortcut Unavailable — Change It…" |
| H4 | Recorder accepted ⌘Q, ⌘W, ⌘C, ⌘V, ⌘Tab, shift+letter… | ✅ Refused with a hint |
| H5 | Double-tap Right ⌥ fired while typing "@" on German / Polish layouts | ✅ Rejects taps with a key press during the hold |
| H6 | Revoking Accessibility while running went unnoticed | ✅ Detected; warning + poll resume |
| H7 | Dead keys and F13–F20 displayed as "Key 24" or blank | ✅ Fixed key naming |

### Install, launch and lifecycle

| | Item | Status |
| --- | --- | --- |
| L1 | Installer kept the quarantine flag → translocated again → "Move?" prompt every launch | ✅ Strips quarantine after copying |
| L2 | Installer permanently deleted originals; replaced any `Flyby.app` without checking it | ✅ Trash, not delete; bundle-id check |
| L3 | Two copies could run at once (DMG + Applications) | ✅ Single-instance guard, per bundle id |
| L4 | Dismissing the pill hid Settings and onboarding too (the practice step said "press Esc") | ✅ Only hides when nothing else of Flyby's is open |
| L5 | Swift 6 concurrency warnings; deprecated `activate(ignoringOtherApps:)` | ✅ Main-actor isolation throughout; macOS 14 `activate()` |

### Design (macOS 26/27 Liquid Glass)

| | Item | Status |
| --- | --- | --- |
| D1 | Glass only as a background swap | ✅ Spotlight-style glass pill with morphing bubbles; regular glass panel; glass header buttons; soft scroll edge |
| D2 | macOS 27 "Golden Gate" | ✅ Targets macOS 27 on Apple silicon (0.4); the 26 glass APIs are still the current ones in the 27 SDK and pick up its refinements; menu icons kept visible under 27's new default; pre-glass fallbacks removed except for Reduce Transparency |
| D3 | Settings: three flat tabs, no Google account, no updates | ✅ Native split view with the glass sidebar: General (+ Updates), Appearance, Search, Google Account, Advanced |
| D4 | Onboarding progress dots counted steps you'd never see; wrong slide direction on first Back | ✅ Fixed; Google step for AI Mode |
| D5 | VoiceOver labels, Reduce Motion, Reduce Transparency | ✅ Labels and selected traits; fade instead of unfold; classic material under Reduce Transparency |
| D6 | Real icon artwork (placeholder is generated) | ⏳ ❓ |
| D7 | Localization (all strings are English literals) | ⏳ Needs a String Catalog; not started |

### Build, signing and distribution

| | Item | Status |
| --- | --- | --- |
| B1 | One build for everything; no way to develop without touching the installed app | ✅ Flyby Dev vs Flyby, separate bundle ids — see [RELEASING.md](RELEASING.md) |
| B2 | Host-architecture only | ✅ Superseded: from 0.4, Apple silicon only (macOS 27 has no Intel support); CI checks it |
| B3 | DMG signed without a timestamp; only the DMG stapled | ✅ `release.sh` notarizes + staples the app, then the DMG |
| B4 | No release process, no updater | ✅ `release.sh` / `publish.sh` / `install.sh`, in-app update checks |
| B5 | Old `Golden` / `beta` releases with non-version tags | ✅ Deleted |
| B6 | Repo is private, so the installer and updater can't reach it | ❓ You chose to make it public — flip the switch in GitHub settings |
| B7 | Developer ID signing + notarization | ⏳ Needs a paid Apple Developer account; everything is wired for it |
| B8 | LICENSE file | ⏳ ❓ |

---

## 3. Decisions only you can make ❓

1. **Make the repo public** (chosen) — GitHub › Settings › Danger Zone.
2. **Retire the old releases** — `--delete` (recommended) or deprecate.
3. **Developer ID** ($99/yr) — removes the curl-installer workaround, enables
   notarization, and is the precondition for re-enabling Chrome-family import.
4. **License** for a public repo (MIT, Apache-2.0, or "all rights reserved").
5. **Terms of service** read on automating Google's AI Mode for a paid product.
6. **In-app Google sign-in** — Google's policy discourages sign-in inside
   embedded web views. Flyby offers it only as a fallback, labelled as such;
   keep it, or ship browser import only?
7. **Query history** — on or off by default, and where it's stored.

---

## 4. How to verify on a Mac

Nothing here has run on real hardware yet: this pass was built in a Linux
sandbox and verified by CI compiles, unit tests, and an offline run of the AI
Mode extractor against captured Google pages. On a Mac:

1. `./run.sh` — Flyby Dev starts in the menu bar; onboarding appears.
2. Pick **Google AI Mode**, connect **Safari** — expect the Full Disk Access
   explanation; grant it; come back; it should connect by itself.
3. Search a few things. Answers should appear natively, with sources; no
   CAPTCHA. If one appears, it's shown in place — solve it, and it continues.
4. **Show Google's Page** flips to Google's page; links open in your browser.
5. Gemini: paste a key; ask; ⌘. mid-answer; ⌘R; ⌘⇧C.
6. Record a double-tap shortcut; type "@" on a German layout; nothing fires.
7. Glass: the ↩ and provider bubbles morph out of the bar as you type; the
   panel unfolds with a spring (a fade with Reduce Motion).
8. `INSTALL=0 ./release.sh 0.3.0` in a clean clone — check the release
   and dev builds run side by side.
