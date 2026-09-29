# Flyby

A tiny macOS utility: press your shortcut, a dark glass bar appears at the
bottom of the screen — Siri's, more or less — type a query, hit Return. Answer or
results without leaving whatever app you're in.

Default trigger is **double-tap Right ⌥**, and it's rebindable to anything —
see below.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/emonsaqibh/flyby/main/install.sh | bash
```

Needs **macOS 27 on Apple silicon**. That downloads the newest release, puts it
in Applications and opens it. It's a menu-bar-only app (`LSUIElement`) — no
Dock icon, nothing in the app switcher; look for the sparkle magnifying glass
in the menu bar.

- **Why a script:** releases are ad-hoc signed and not notarized yet, and macOS
  won't open an un-notarized app downloaded in a browser. Files fetched with
  curl aren't marked as downloads, so it opens normally.
- **Updating:** Flyby checks for updates by itself; Settings › General ›
  Updates (**Check Now**) or menu bar › **Check for Updates…** asks right away.
  When there's one, it hands you the same command.
- **Betas and pinned versions:** add `-s -- --beta` to include betas, or
  `-s -- 0.3.0-beta.1` for a specific version. Flyby 0.3 and earlier run from
  macOS 14; `install.sh` refuses a version your Mac can't open.

**Applications is not optional.** `SMAppService` registers a path for
open-at-login, and Accessibility permission is bound to the exact bundle it was
granted to. Run Flyby from a disk image or Downloads and macOS may run it from a
randomised read-only mount (App Translocation), so both silently break on the
next launch. Flyby notices and offers to move itself; Settings › General keeps a
**Move to Applications** button around until it's somewhere real.

## What's new in 0.5

- **Ask about your screen:** ⌥⇧Space (or **Screenshot** under the bar, or
  `/screenshot`) takes a picture of the window you're in — a wave of light
  crosses the screen from the bar as it does — and opens Flyby with it over the
  input. Ask Google AI Mode or Gemini about it; follow-ups can bring a new one.
  Nothing's sent until you press Return, and chats keep a thumbnail. Updating
  shows what's new once, to keep, change or turn off the shortcut; new installs
  meet it in the walkthrough.
- **Double-tap and chord shortcuts work on macOS 27,** which gates them behind
  Input Monitoring as well as Accessibility; Flyby now asks for both.

Full notes: [docs/releases/0.5.0.md](docs/releases/0.5.0.md).

## What's new in 0.4

- **Looks like macOS 27's Siri:** an always-dark glass bar at the bottom of the
  screen that grows up into an answer card.
- **Follow-ups and Recent Chats:** keep asking in the same conversation. Chats
  stay on your Mac, and ⌘Y reopens one.
- **Apple Intelligence:** a fourth provider on Apple's on-device model — no
  key, no account, and your question never leaves your Mac.
- **Keyboard map and "/" commands:** ⌘/ shows every shortcut; "/" at the start
  of the bar lists commands.
- **New onboarding and Settings,** in the shape of macOS 27's System Settings.

**0.4.1** fixes Google AI Mode follow-ups, which now stay in the same Google
conversation ([notes](docs/releases/0.4.1.md)).

Full notes: [docs/releases/0.4.0.md](docs/releases/0.4.0.md).

## First launch

First launch opens a short, animated onboarding (always dark, Dia-style: a
drifting glow, headlines that reveal letter by letter, a live demo of the bar):
provider, shortcut, the Accessibility and Input Monitoring grants if the
shortcut needs them, and a
practice step that waits for the real trigger to fire. It runs once (gated by a
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
and Input Monitoring — `RegisterEventHotKey` can't express "no key", and can't
tell Right ⌘ from Left ⌘ either. (On macOS 27 a listen-only tap without Input
Monitoring is created and then quietly switched off, even though it only hears
modifier changes.) The tap is listen-only and subscribes to
`flagsChanged` events exclusively, never key presses; a double-tap counts only
if each strike is brief (≤0.4 s) and the second lands within 0.35 s of the
first, which is also what keeps ⌥-symbol typing and option-drags from
triggering it.

Modifier gestures are side-specific: Right ⌘ and Left ⌘ are different triggers.
A bare key with no modifiers is rejected, since it would fire while you type.
Esc cancels recording rather than becoming your shortcut.

**If the shortcut ever stops working**, the menu bar icon turns into a warning
triangle and grows an "Allow Your Shortcut…" item, which opens whichever of
the two panes still needs Flyby. That only ever applies to modifier-only
gestures — if you'd rather not deal with the permissions, record a key combo
instead.

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

Building needs **Xcode 27** — macOS 27's SwiftUI implements `@State` and friends
as macros whose plugin ships with Xcode, not the Command Line Tools. `build.sh`
picks Xcode by itself when `xcode-select` points at the Command Line Tools;
for a bare `swift build` or `swift test`, prefix
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

Every push runs CI on a macOS 27 runner with Xcode 27 — unit tests, the dev
build, and an Apple silicon release build — and attaches both apps to the run.

**Accessibility and Input Monitoring are only needed for modifier-only
shortcuts** (see Trigger above). If you use one, onboarding walks you through
both; approve Flyby in System Settings › Privacy & Security › Accessibility
and › Input Monitoring. The app polls, so Accessibility takes effect within a
second; after Input Monitoring macOS may ask to reopen it. Screenshots need
**Screen Recording**, which macOS asks for the first time you take one.

macOS keys those grants to the app's signature. An ad-hoc signature changes on
every build, so run `./scripts/dev-signing.sh` once: it makes a local signing
certificate (one password prompt, to trust it for code signing) that
`build.sh` then signs Flyby Dev with, and the grants survive rebuilds. Without
it, remove **Flyby Dev** from each list with the − button after a rebuild and
add it back. Key-combo shortcuts need none of this.

To see what the app is doing:

```bash
/usr/bin/log show --last 5m --info --predicate 'subsystem == "com.fringecore.flyby"' --style compact
```

Art is generated, not drawn by hand: `Resources/AppIcon.icns` (and the dev
build's `AppIcon-Dev.icns`) from `Resources/IconGenerator/generate.swift`, and
the DMG background from `Resources/DMGGenerator/generate.swift`. Each is only
regenerated when missing, so dropping in real artwork replaces it.

## Providers

Pick one from the dropdown at the trailing end of the bar — "Google ⌄",
"Gemini ⌄" — with ⌘1–⌘4, or in Settings. Its menu (click it, or ⌘K) is split
into **Answer with** and **Open in browser with**, because the engine only ever
applies to the browser hop — including ⌘Return from any provider. The bar says which one will answer: "Ask
Gemini" while it's empty, and "— Ask Gemini" right after your last character
as you type.

| Provider | What it does | Setup |
| --- | --- | --- |
| **Browser** | Fires the query at your default browser and dismisses | none |
| **Google AI Mode** | Google's AI answer, drawn natively in the answer card | connect your Google account (recommended) |
| **Gemini** | Streams a written answer with live web sources | paste a free API key |
| **Apple Intelligence** | Streams an answer from the on-device model — private and offline, but no live web | Apple Intelligence turned on in System Settings |

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
provider dropdown's menu flips to it at any time.

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

### Apple Intelligence

Answers come from Apple's on-device model through the FoundationModels
framework: no key, no account, and neither the question nor the answer leaves
the Mac. It has no web access, so it's told to say so — and to point at Gemini
or AI Mode — for anything that depends on recent or live information. Follow-ups
carry the conversation, trimmed to fit the model's context window. The model is
loaded as Flyby opens, so the first answer doesn't wait for it. Settings ›
Search and onboarding say whether it's ready, with a button to System Settings
when Apple Intelligence is turned off.

## Appearance

Flyby looks like macOS 27's Siri, and like Siri it's **always dark** — there's no
light/dark setting. Settings and onboarding follow your Mac's appearance like any
other window. Flyby uses your Mac's accent colour for the caret, links in
answers, the Stop chip and the input's focus rim.

### Liquid Glass

Flyby is Liquid Glass by design — there's no switch for it. The bar and the
answer card are *smoked* glass: near-black at the top, clearing toward the
bottom so what's behind shows through, with a thin lit rim, and dark over any
wallpaper. The card's corner buttons and its input field are plain glass on
top of it. Both follow macOS 27's glass slider (clear to tinted) in System
Settings.
The bar uses interactive glass that reacts to the pointer; the card doesn't,
since pointer motion is a distraction in something you're reading.

The bar and the card are one piece of glass in one window, which is what lets
them move like the Dynamic Island: the bar springs out of a small blob when it
opens, grows taller line by line as you type, and on Return grows up and out
into the answer card while your question flies up into its bubble and the input
settles along the card's bottom edge. New Chat folds the card back into the bar.
Closing is a different, quicker motion: everything shrinks and fades down
together, as it stands, the way a window leaves.

Settings is a native split view: the system's floating glass sidebar, with each
pane's title in the toolbar, like System Settings.

Reduce Transparency swaps the glass for opaque dark fills. Reduce Motion
cross-fades the bar and the card instead of morphing one into the other, and
turns the other springs into short fades.

## Chats and history

Once an answer is on screen, the input along the bottom of the card is the chat
box: the cursor stays in it, it says "Ask a follow-up", and whatever you ask
next is added to the conversation above rather than replacing it. Every
provider answers a follow-up in the context of the conversation so far. Gemini
and Apple Intelligence are sent the earlier turns; Google AI Mode is asked the
follow-up in its own conversation, typed into the page Flyby already has open.
Where that page can't carry on — a chat reopened from Recent Chats, or one
another provider answered part of — the earlier questions and the start of the
last answer go into the search with it. **New Chat** (⌘N, or in the provider
button's menu) starts over.

Every chat is saved on your Mac — one small file per chat in
`~/Library/Application Support/<bundle id>/History/`, never uploaded. Press ↑ in
an empty input (or ⌘Y, or the **Recent Chats** pill under the bar) to see
recent chats; ↑↓
and Return pick one, and you carry on where you left off. The newest 200 are
kept. Clear them in Settings › History.

### The AI Mode page

The embedded AI Mode page is dark too: the injected reader stylesheet sets
`color-scheme: light dark` and the web view's `appearance` is pinned to dark,
which is what WebKit derives `prefers-color-scheme` from. Google honours it.

## Open at login

Settings › General has an **Open at login** toggle, backed by `SMAppService`
rather than a login-item helper bundle. macOS owns the state, so it also appears
in System Settings › General › Login Items and can be turned off there.

Registration is tied to the app's location, so re-toggle it after moving the
app. If macOS reports a state that isn't a plain on/off — waiting for approval,
or a registration it can't find — Settings says so instead of pretending the
toggle worked.

## Layout at runtime

The bar sits at the bottom centre of the screen: 532pt wide, 22pt type, 68pt
tall for one line and 26pt taller for each line after, up to six, then it
scrolls internally. It never gets wider. The provider dropdown sits inside its
trailing end, anchored to the bottom so it stays with the last line.

Hitting Return grows the bar into the answer card — 560pt wide on every screen,
up to 700pt tall (less where the screen is shorter), its bottom edge where the
bar's was. A ✕ top-left closes (or backs out of the history list); top-right,
**Open in Browser ⌘↩** shows its shortcut on it; and the input runs along the
bottom as a capsule, the same dropdown at its end.

Under the bar sit two small smoked pills, **Recent Chats ⌘Y** and **Shortcuts
⌘/**. They're a row of their own: the bar becomes the card above them without
moving them, and the bar sits 54pt above the Dock to make room for them.

Type **/** at the start of the input for commands — /google, /gemini, /apple,
/browser, /new, /retry, /copy, /history, /shortcuts, /settings — in a small
list above it, filtered as you type. ↑↓ pick, Return or Tab runs, Esc hides the
list. If nothing matches ("/etc/hosts"), Return just asks it.
The input keeps the keyboard after every question, with an accent rim to say
so, so you can keep asking without re-summoning Flyby.

Everything is drawn in one fixed, oversized, transparent window — the card's
size plus a margin for the glass's shadow. Resizing an NSWindow on every
keystroke animates badly and lags a fast typist, and two windows can only be
animated by resizing them; animating shapes inside a static window is a clean
spring. Clicks on the transparent parts fall through to whatever is underneath.

## Keys

**⌘/** (or the Shortcuts pill) shows all of these on a small card, with the
slash commands. The keyboard is either typing in
the input, reading the card (after Esc, or a click in an answer), or in Google's
page, which keeps its own keys.

| Key | Action |
| --- | --- |
| `Return` | Ask with the selected provider (a follow-up, once a chat is open) |
| `⌥Return` | New line |
| `⌘Return` | Always open in your default browser (Open in Browser ⌘↩) |
| `⌘K` | Provider menu |
| `⌘1`–`⌘4` | Browser, Google AI Mode, Gemini, Apple Intelligence |
| `⌘.` | Stop the answer where it is (the dropdown is Stop ⌘. while answering) |
| `⌘R` | Ask again |
| `⇧⌘C` | Copy the whole answer, with sources (plain `⌘C` copies the selection) |
| `⌘N` | New chat |
| `⌘Y`, or `↑` in an empty input | Recent chats: `↑`/`↓` move, `Return` opens, `⌘⌫` deletes |
| `Esc` | One step back: the command list, the shortcuts, recent chats, out of the input to read (in the card), then close |
| `/` at the start of the input | Commands: `↑`/`↓` pick, `Return` or `Tab` runs |
| `Tab` | Back into the input from anywhere in the card; typing while reading does too |
| `↑`/`↓`, `Space`, `Page Up`/`Page Down`, `⌘↑`/`⌘↓`, `Home`/`End` | Scroll the answer while reading |
| `⌘W` | Close at once |
| `⌘/` | Keyboard shortcuts |

The dropdown's menu shows the provider (⌘1–⌘4) and chat shortcuts. Clicking anywhere outside
Flyby also closes it. Links in answers open in your default browser.

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
  main.swift, AppDelegate.swift   wiring: hotkey → overlay, menu bar, windows
  SearchController.swift  one phase + one AnswerSnapshot for every provider
  GeminiProvider.swift    SSE streaming, grounding sources, readable errors
  Google/                 GoogleSession (cookie store, connect/refresh),
                          AIModeEngine (hidden page + extractor), sign-in window
  UI/                     answer renderer, attention banner, Google connect view
  FlybyPanel, FlybyRootView   the window, the stage and its springs: bar ↔ card
  InputBar                the input with its inline hint, the provider chip
  ProviderMenu            the chip's menu (AppKit, so ⌘K can open it)
  KeyboardShortcuts       the keyboard map as shown on the ⌘/ overlay
  SlashCommands           "/" commands and their list
  AnswerCard              the card's content: corner buttons, web layer
  SettingsView, OnboardingView
  HotKeyMonitor, Shortcut, ShortcutRecorder   Carbon hot keys + event tap
  Installer, SingleInstance                   where the app lives; one copy
  Updates/                GitHub release checks
  Support/BuildFlavor     dev vs release
  Settings, Surface
```
