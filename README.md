# Flyby

A tiny macOS utility: press your shortcut, a small pill appears at the bottom of
the screen, type a query, hit Return. Answer or results without leaving whatever
app you're in.

Default trigger is **double-tap Right ⌥**, and it's rebindable to anything —
see below.

First launch opens a short onboarding flow: appearance, provider, shortcut
recording, the Accessibility grant if the shortcut needs one, and a practice
step that waits for the real trigger to fire. It runs once (gated by a
`hasCompletedOnboarding` flag; installs that already recorded a shortcut skip
it) and everything it covers can be changed later in Settings.

## Trigger

Settings (⌘,) has a recorder: click it and press what you want. It accepts
three different shapes of shortcut.

- **Key combo** — press a key with modifiers, e.g. ⌥Space or ⌘⇧K. Goes through
  Carbon's `RegisterEventHotKey`, which needs **no permissions at all**.
- **Modifier chord** — hold two or more modifiers and release without pressing
  any key, e.g. Right ⌘ + Right ⌥.
- **Double-tap** — strike a single modifier twice quickly, e.g. the default
  double Right ⌥. In the recorder, tap it once and you'll be prompted to tap
  again.

The two modifier-only shapes need a `CGEventTap` and therefore Accessibility
permission — `RegisterEventHotKey` can't express "no key", and can't tell
Right ⌘ from Left ⌘ either. The tap is listen-only and subscribes to
`flagsChanged` events exclusively, never key presses; a double-tap counts only
if each strike is brief (≤0.4 s) and the second lands within 0.35 s of the
first, which is also what keeps ⌥-symbol typing and option-drags from
triggering it.

Modifier gestures are side-specific: Right ⌘ and Left ⌘ are different triggers.
A bare key with no modifiers is rejected, since it would fire while you type.
Esc cancels recording rather than becoming your shortcut.

**If the shortcut ever stops working**, the menu bar icon turns into a warning
triangle and grows a "Grant Accessibility Permission…" item. That only ever
applies to modifier-only gestures — if you'd rather not deal with the
permission, record a key combo instead.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/emonsaqibh/flyby/main/install.sh | bash
```

That downloads the newest release, puts it in Applications and opens it; add
`-s -- --beta` for betas, or `-s -- 0.3.0` for a specific version. Flyby then
tells you when there's an update (menu bar › **Check for Updates…**, or
Settings › General › Updates) and hands you the same command.

Why a script and not a download link: releases aren't notarized yet, and macOS
won't open an un-notarized app downloaded in a browser. Files fetched with curl
aren't marked as downloads, so it opens normally.

It's a menu-bar-only app (`LSUIElement`) — no Dock icon, nothing in the app
switcher; look for the sparkle magnifying glass in the menu bar. Needs macOS 14
or later; runs natively on Apple silicon and Intel.

**Applications is not optional.** `SMAppService` registers a path for
open-at-login, and Accessibility permission is bound to the exact bundle it was
granted to. Run Flyby from a disk image or Downloads and macOS may run it from a
randomised read-only mount (App Translocation), so both silently break on the
next launch. Flyby notices and offers to move itself; Settings › General keeps a
**Move to Applications** button around until it's somewhere real.

## Build and run

There are two builds — **Flyby Dev**, where all work happens, and **Flyby**,
the frozen release people install. They have different bundle IDs, so they run
side by side with separate settings, Keychain entries, Google session and
permissions.

```bash
./run.sh                 # build Flyby Dev (build/Flyby Dev.app) and launch it
CONF=debug ./build.sh    # unoptimized dev build, for lldb
swift test               # FlybyCore unit tests
./release.sh 0.3.0       # freeze a release into releases/0.3.0/ and install it
./publish.sh 0.3.0 notes.md   # tag v0.3.0 and publish the GitHub release
```

The dev build takes its version from git (`0.3.0-dev.14 · pill`), wears an
amber icon and a DEV badge, and never checks for updates. **[RELEASING.md](RELEASING.md)**
has the whole workflow: versions, betas, signing and notarization, and retiring
the pre-0.3 releases.

Every push runs CI on GitHub's macOS 26 runner — unit tests, the dev build, and a
universal release build — and attaches both apps to the run.

**Accessibility permission is only needed for modifier-only shortcuts** (see
Trigger above). If you use one, onboarding walks you through the grant; approve
it in System Settings › Privacy & Security › Accessibility and it starts working
within a second — the app polls, so no relaunch needed.

Because local builds are ad-hoc signed, the signature changes on every rebuild,
so macOS drops that permission after each `./build.sh`. Remove **Flyby Dev**
with the − button and add it back. Key-combo shortcuts are immune to all of this.

To see what the app is doing:

```bash
log show --last 5m --info --predicate 'subsystem == "com.fringecore.flyby"' --style compact
```

Art is generated, not drawn by hand: `Resources/AppIcon.icns` (and the dev
build's `AppIcon-Dev.icns`) from `Resources/IconGenerator/generate.swift`, and
the DMG background from `Resources/DMGGenerator/generate.swift`. Each is only
regenerated when missing, so dropping in real artwork replaces it.

## Providers

Pick one from the bubble on the trailing edge of the pill, or in Settings. Its
menu is split into **Answer with** and **Open in browser with**, because the
engine only ever applies to the browser hop — including ⌘Return from any
provider.

| Provider | What it does | Setup |
| --- | --- | --- |
| **Browser** | Fires the query at your default browser and dismisses | none |
| **Google AI Mode** | Google's AI answer, drawn natively in the panel | connect your Google account (recommended) |
| **Gemini** | Streams a written answer with live web sources | paste a free API key |

### Google AI Mode, and why it no longer asks for CAPTCHAs

Google challenges anonymous, cookie-less clients constantly. So AI Mode runs in
**your own Google session**: Settings › Google Account copies your Google
sign-in from **Safari** or **Firefox** into Flyby's own private web store
(only `google.*` cookies; nothing leaves your Mac), or you can sign in inside
Flyby. Safari needs Full Disk Access — the Settings pane explains, and picks
the grant up as soon as you come back. The copy refreshes itself from the
browser every 30 minutes.

The answer comes from a real Google page that runs invisibly behind Flyby's own
answer view: an injected script reads the headings, lists, tables and cited
sources as they stream and Flyby draws them natively — the same renderer as
Gemini. If Google still wants something (a CAPTCHA, an EU consent choice, a
sign-in), the page is revealed in place with a banner saying why; deal with it
once and it sticks. If Google changes its markup and the answer can't be read,
Flyby shows the page itself rather than nothing. **Show Google's Page** in the
panel header flips to it at any time.

Source cards under an answer show each site's icon, fetched from Google's
favicon service (`www.google.com/s2/favicons`) — the one request answers make
beyond the provider itself.

Chrome-family browsers aren't offered: Chrome ties its Google session to the
Mac's Secure Enclave, so a copied session lasts hours, and an ad-hoc signed app
can't read Chrome's Keychain key anyway.

### Gemini

Get a key at [aistudio.google.com/apikey](https://aistudio.google.com/apikey);
it's stored in the Keychain. Google Search grounding is on, so answers reflect
the live web. The default model is `gemini-3.8-flash` (changeable in Settings).
Rate limits, bad keys and blocked answers come back as readable messages, and a
rate-limited or overloaded request is retried once.

## Appearance

Settings › Appearance has two controls:

- **Appearance** — System, Light or Dark. Set once on `NSApp`, so the pill, the
  result panel and the settings window all inherit it. System follows macOS
  live.
- **Accent** — System or one of seven colors. Tints the ↩ badge, the caret,
  links and source chips. System derives from your macOS accent colour.

### Liquid Glass

Flyby is Liquid Glass by design — there's no switch for it. On macOS 26 and
later the pill and the answer panel are glass, and builds made with the macOS 27
SDK follow macOS 27's glass slider (clear to tinted) in System Settings. The
pill is laid out like Spotlight: a glass bar with the ↩ and provider controls as
separate glass bubbles that morph out of it as you type. The panel uses regular
(non-interactive) glass, since pointer motion is a distraction in something
you're reading, with a floating glass header whose buttons merge and split as
they come and go.

The pill and the panel share one window and one glass container, which is what
lets them move like the Dynamic Island: the pill springs out of a small blob
when it opens, the panel grows up out of the pill's capsule when there's an
answer, and closing folds it all back down.

macOS 14–15 and Reduce Transparency get the classic blurred material instead.
Reduce Motion swaps the springs for short fades.

## Chats and history

Once an answer is on screen, the pill becomes the chat box: the cursor stays in
it, it says "Ask a follow-up…", and whatever you ask next is added to the
conversation above rather than replacing it. Gemini answers follow-ups in the
context of the conversation so far; Google AI Mode answers each question on its
own. **New Chat** (⌘N) starts over.

Every chat is saved on your Mac — one small file per chat in
`~/Library/Application Support/<bundle id>/History/`, never uploaded. Press ↑ in
an empty pill (or ⌘Y, or the clock button in the panel) to see recent chats; ↑↓
and Return pick one, and you carry on where you left off. The newest 200 are
kept. Clear them in Settings › Search.

### Accent derivation

An accent is stored as a **hue**, not a colour. The colour itself is derived per
appearance by solving for the shade that hits a target WCAG relative luminance,
so every theme lands at the same contrast against the surface it's drawn on —
deep and saturated on light, soft and pale on dark.

This matters because fixed colours can't be legible in both modes, and because
hues aren't interchangeable: green at a given HSB brightness is far lighter than
blue at the same brightness. Solving against luminance rather than brightness is
what makes the swatches consistent.

The solver works on two axes, and needs to. Dimming alone can't reach the
light-on-dark target for blue or purple — saturated blue is intrinsically dark,
so it tops out well short even at full brightness. When that happens the solver
desaturates toward white instead.

Measured against the pill surfaces, all seven themes plus System land at
**4.15:1 in light** and **4.00:1 in dark**. For comparison, the previous fixed
system colours ranged from 1.75:1 to 2.88:1 — green and orange on light were the
worst offenders.

The embedded AI Mode page follows the app's appearance too: the injected reader
stylesheet sets `color-scheme: light dark` and the web view's `appearance` is
pinned to the chosen mode, which is what WebKit derives `prefers-color-scheme`
from. Google honours it, so AI Mode renders dark when the app is dark.

## Open at login

Settings › General has an **Open at login** toggle, backed by `SMAppService`
rather than a login-item helper bundle. macOS owns the state, so it also appears
in System Settings › General › Login Items and can be turned off there.

Registration is tied to the app's location, so re-toggle it after moving the
app. If macOS reports a state that isn't a plain on/off — waiting for approval,
or a registration it can't find — Settings says so instead of pretending the
toggle worked.

## Layout at runtime

The pill is a small capsule at the bottom centre of the screen that grows
sideways as you type, up to 860pt, then scrolls internally.

Hitting Return unfolds a result panel upward out of the pill, centred on the
same axis so the two read as one object. The pill keeps focus throughout, so you
can retype and search again without re-summoning it. Esc closes both.

The pill's window is a fixed oversized transparent frame with only the capsule
drawn inside it — resizing an NSWindow on every keystroke animates badly and
lags a fast typist, whereas animating the capsule's width inside a static window
is a clean spring. Clicks on the transparent margin fall through to whatever is
underneath.

## Keys

| Key | Action |
| --- | --- |
| `Return` | Search with the selected provider |
| `⌘Return` | Always open in your default browser |
| `⌘.` | Stop the answer where it is |
| `⌘R` | Ask again |
| `⌘⇧C` | Copy the whole answer, with sources (plain `⌘C` copies the selection) |
| `Esc` | Close |

Clicking anywhere outside the pill also closes it. Links in answers open in your
default browser.

The shortcut recorder refuses combos that would hijack the system or every app —
⌘Q, ⌘W, ⌘C, ⌘V, ⌘Tab, ⌘Space, screenshot keys and the like — and bare or
shift-only keys. If another app has already taken your combo, the menu bar says
**Shortcut Unavailable — Change It…** instead of failing silently.

## Layout

```
Sources/FlybyCore/        Foundation-only logic, unit-tested (Tests/FlybyCoreTests)
  Answer/                 AnswerBlock, WebSource, AnswerSnapshot, MarkdownParser
  Cookies/                Safari / Chromium / Firefox cookie stores, Google domains
  AIMode/                 query URLs, page classification, link cleaning, messages
  Support/                SemanticVersion
Sources/Flyby/            the app
  main.swift, AppDelegate.swift   wiring: hotkey → pill, menu bar, windows
  SearchController.swift  one phase + one AnswerSnapshot for every provider
  GeminiProvider.swift    SSE streaming, grounding sources, readable errors
  Google/                 GoogleSession (cookie store, connect/refresh),
                          AIModeEngine (hidden page + extractor), sign-in window
  UI/                     answer renderer, attention banner, Google connect view
  PillView/PillPanel      the capsule and its window
  ResultPanel(View)       the panel, header, web layer
  SettingsView, OnboardingView
  HotKeyMonitor, Shortcut, ShortcutRecorder   Carbon hot keys + event tap
  Installer, SingleInstance                   where the app lives; one copy
  Updates/                GitHub release checks
  Support/BuildFlavor     dev vs release
  Settings, Surface, Theme
```
