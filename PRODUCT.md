# Flyby — Product Source of Truth

**Status:** v0.3.0 (pre-release; dev/release builds, curl installer + in-app update checks; ad-hoc signed, not yet notarized)
**Platform:** macOS 27 and later, Apple silicon (0.3 and earlier: macOS 14 and later)
**Bundle ID:** `com.fringecore.flyby` (release build, "Flyby") · `com.fringecore.flyby.dev` (dev build, "Flyby Dev")
**Maker:** fringecore
**Name note:** "Flyby" is the working product name (was "Quick Search"; the Swift package and modules are now `Flyby` / `FlybyCore`, though a few internal identifiers still say `quickSearch`)
**Last verified against code:** 2026-09-28

> This document is the single source of truth for the product website, marketing
> copy, and the Product Hunt launch. Everything in the **Verified Facts** half is
> checked line-by-line against the shipping source. Everything in the
> **Positioning & Launch** half is proposed copy and strategy built on top of it.
>
> Rule for anyone writing marketing from this file: if a claim isn't in
> [Verified feature inventory](#4-verified-feature-inventory), don't ship it. See
> [Do-not-claim list](#16-do-not-claim-list).
>
> "Verified" means *present in the source*. v0.3.0 has not yet run on a real Mac
> — see [§9](#9-known-limitations-and-honest-caveats) before promoting anything
> about Google AI Mode.

---

## Table of contents

**Part I — What the product actually is**
1. [One-liner and elevator pitch](#1-one-liner-and-elevator-pitch)
2. [The problem](#2-the-problem)
3. [How it works — the loop](#3-how-it-works--the-loop)
4. [Verified feature inventory](#4-verified-feature-inventory)
5. [Anatomy of the interface](#5-anatomy-of-the-interface)
6. [Settings reference](#6-settings-reference)
7. [Privacy, data and permissions](#7-privacy-data-and-permissions)
8. [Technical facts](#8-technical-facts)
9. [Known limitations and honest caveats](#9-known-limitations-and-honest-caveats)

**Part II — Positioning and launch**
10. [Who it's for](#10-who-its-for)
11. [Use cases](#11-use-cases)
12. [Competitive positioning](#12-competitive-positioning)
13. [Messaging kit](#13-messaging-kit)
14. [Website plan](#14-website-plan)
15. [Product Hunt launch kit](#15-product-hunt-launch-kit)
16. [Do-not-claim list](#16-do-not-claim-list)
17. [Open decisions before launch](#17-open-decisions-before-launch)
18. [Roadmap candidates](#18-roadmap-candidates)

---
---

# Part I — What the product actually is

## 1. One-liner and elevator pitch

### One-liner
**Search the web without leaving what you're doing.**

### Standard description (2 sentences)
Flyby is a macOS menu-bar utility that puts a search bar one keystroke
away, anywhere on your Mac. Press your shortcut, a dark glass bar appears at the
bottom of the screen, you type, and you get an answer — in a card that grows up
out of the bar, or in your browser, whichever you prefer.

### Elevator pitch (paragraph)
Every search you do today costs you the same tax: leave your work, find or open a
browser window, find the right tab, click the address bar, type, read, come back,
find your place again. Flyby removes all of that. One keystroke summons a
search bar over whatever app you're in. Type your question, hit Return, and the
answer arrives in place — either as a streamed Gemini answer with live web
sources, or as Google's AI Mode answer, read out of your own Google session and
drawn natively — or in your browser if that's what the query deserves. Escape,
and you're back exactly where you were, in the app you were already in. It's
free, there's no sign-up and no server of ours, and your Gemini key lives in
your Keychain and is sent only to Google.

### Positioning statement
> For people who work in focused apps all day and search constantly, Flyby
> is a system-wide search overlay for macOS that answers questions without
> pulling you into the browser. Unlike a launcher, it doesn't try to be your
> everything-bar — it does one thing, and it stays out of the way.

---

## 2. The problem

### The core problem
**Search costs a context switch, and the context switch costs more than the
search.**

A typical search while writing, coding, or designing looks like this:

1. Stop what you're doing.
2. ⌘Tab to the browser (or Dock-click it).
3. Land on whatever tab you left open — a distraction you didn't ask for.
4. ⌘T, type, Return.
5. Read the answer.
6. ⌘Tab back.
7. Re-find your cursor, your place, your train of thought.

Steps 3 and 7 are the expensive ones. Step 3 is where "quick lookup" turns into
twenty minutes of Twitter. Step 7 is where the thought you were holding
evaporates.

### The sub-problems it addresses

| Sub-problem | How Flyby resolves it |
| --- | --- |
| **The browser is a trap.** Opening it exposes you to every other tab. | The answer appears over your current app. The browser is never opened unless you choose it. |
| **Answers get buried in results.** Ten blue links when you wanted one fact. | Gemini and Google AI Mode both put a direct answer in the card, with source cards underneath. |
| **AI chat apps are a whole separate destination.** Cmd-tab to ChatGPT is the same context switch. | The AI answer arrives on top of the app you're in and disappears when you're done. |
| **AI answers can be stale or invented.** | Gemini mode runs with Google Search grounding on, so answers reflect the live web, with clickable sources. |
| **Launchers want to own everything.** Files, apps, clipboard, snippets, window management. | Flyby is a search bar and nothing else — no files, apps, clipboard or snippets to set up. |
| **AI tools want your data and a subscription.** | No Flyby account, no telemetry, no server of ours. Your Gemini key lives in your Keychain, the request goes straight from your Mac to Google. |
| **Reaching for a shortcut interrupts the hands.** | Default trigger is a double-tap of Right ⌥ — no key press, one thumb — and a tap made while using ⌥ to type a character doesn't count. |

### The insight worth putting on the website
> The cost of a search isn't the search. It's the round trip.

---

## 3. How it works — the loop

1. **Summon.** Double-tap **Right ⌥** (default, fully rebindable). A dark
   glass bar springs out of a small blob at the bottom centre of the screen the
   mouse is on, over whatever you're doing, with a small provider dropdown
   ("Google ⌄") at its trailing end.
2. **Type.** Large type that wraps: the bar grows taller as you type, never
   wider, up to six lines. Right after the last character a grey hint says who
   will answer — "— Ask Gemini".
3. **Answer.** Hit **Return**:
   - **Gemini** → the bar becomes the answer card — the same glass growing up
     and out — your question flies up into its bubble, and a written answer
     streams in under it, with source cards underneath.
   - **Google AI Mode** → Flyby runs Google's AI Mode in a hidden page, in your
     own Google session, reads the answer out of it as it streams, and draws it
     in the same card with the same renderer as Gemini. If Google wants a
     CAPTCHA, a consent choice or a sign-in, the page is revealed in place with
     a banner saying why.
   - **Browser** → your default browser opens with the query in your chosen
     engine, and Flyby dismisses itself.
4. **Leave.** **Esc** (from the card, once to leave the input and once more to
   close), **⌘W**, the ✕ in the card's corner, or click anywhere outside.
   Flyby shrinks and fades away and focus returns to the app you were in.

Along the way:
- **⌘Return** (or **Open in Browser ⌘↩** in the card's corner) escapes to your
  real browser from any mode, at any time.
- **⌘.** (or the provider dropdown, which becomes **Stop ⌘.** while an answer
  is coming) stops an answer where it is, **⌘R** asks again, **⌘⇧C** copies
  the whole answer with its sources.
- The input keeps keyboard focus after every question — in the card it's the
  field along the bottom — so you can ask a follow-up without re-summoning it.
  **Esc** leaves it to read the answer with the keyboard; **Tab**, or just
  typing, goes back.
- Two small pills under the bar, **Recent Chats ⌘Y** and **Shortcuts ⌘/**,
  open the chat history and a card of every shortcut.
- **/** at the start of the input opens a list of commands — /settings,
  /history, /new, /google and the other providers, and more — filtered as you
  type.
- Links and source cards in an answer open in your default browser.

---

## 4. Verified feature inventory

Everything in this section is confirmed present in the source. This is the
approved claim surface. *Present in the source is not the same as proven on
hardware: this release hasn't run on a real Mac yet — see
[§9](#9-known-limitations-and-honest-caveats).*

### 4.1 Invocation
- **Global shortcut**, works from any app, including over full-screen apps and on
  every Space (`canJoinAllSpaces`, `fullScreenAuxiliary`).
- **Three shortcut shapes**, recorded by clicking a recorder in Settings (or
  onboarding) and pressing what you want:
  - **Key combo** — a key plus modifiers (⌥Space, ⌘⇧K). Implemented with
    Carbon `RegisterEventHotKey`. **Requires no permissions at all.** If another
    app already owns the combo, Flyby says so — an alert and a "Shortcut
    Unavailable — Change It…" menu item — instead of failing silently.
  - **Modifier chord** — two or more modifiers held and released with no key
    (Right ⌘ + Right ⌥). Implemented with a `CGEventTap`, which macOS gates
    behind Accessibility permission.
  - **Double-tap** — one modifier struck twice quickly (double Right ⌥). Same
    `CGEventTap` mechanism and Accessibility gate as chords. A strike counts
    only if it's brief (≤0.4 s), no other modifier is involved, and no key went
    down while it was held; the second must land within 0.35 s. That keeps
    ⌥-symbol typing, option-drags and Right ⌥ used as AltGr (typing "@" on a
    German layout) from triggering it.
- **Modifier gestures are side-specific**: Left ⌘ and Right ⌘ are different
  triggers.
- **Default trigger:** double-tap Right ⌥.
- **The recorder refuses combos that would hijack the system or every app**,
  with a one-line reason: bare keys, ⇧ plus a character, ⌘ with Q, W, C, V, X,
  Z, A, S, N, T, O, P, F, H, M or "," (matched by the character typed, so it
  holds on AZERTY), ⌘Tab, ⌘Space, ⌘`, ⌘⇧3/4/5, ⌃⌘Q and ⌃Space. Esc cancels
  recording instead of becoming the shortcut.
- Holding a chord down does not repeat-fire; it re-arms only on release.
- **First launch runs a one-time onboarding flow**: welcome (with a live demo of the bar) → provider and search engine (with the Gemini
  key field if Gemini is picked) → **Connect your Google account** (only if
  Google AI Mode is picked; skippable) → shortcut recording (pre-filled with the
  default) → Accessibility grant (only if the recorded shape needs it and it
  isn't granted; auto-advances the moment permission lands) → a practice step
  that waits for the real trigger to fire → done, with an open-at-login toggle.
  Installs that already recorded a shortcut before onboarding existed skip it;
  Settings › Advanced can run it again.
- The shortcut toggles: pressing it while Flyby is open closes it.
- **The menu-bar icon becomes a warning triangle** if the trigger can't be
  installed, so it never fails silently — with "Grant Accessibility
  Permission…" when a modifier-only shortcut lacks the grant, or "Shortcut
  Unavailable — Change It…" when a key combo is taken. For the permission case
  the app polls once a second and starts working the moment it's granted — no
  relaunch. Revoking Accessibility while the app runs is noticed too (the tap is
  health-checked every 3 s) and brings the warning back.
- Opening the app again from Finder or `open -a`, or launching a second copy of
  the same build, summons Flyby. Only one copy of each build runs.
- The menu-bar menu has **Open Flyby**, **Settings…**, **Check for Updates…**
  and **Quit**, so the app is usable with no shortcut at all.

### 4.2 The four answer providers

All four are free to use. Switchable from the provider dropdown at the input's
trailing end — "Google ⌄", "Gemini ⌄", "Apple Intelligence ⌄", "Browser ⌄" —
with **⌘1–⌘4** directly, **⌘K** to open the dropdown, or in Settings › Answers. The input names the one it'll ask: "Ask Google", "Ask
Gemini", "Ask Apple Intelligence", or "Search Google" (the browser engine's
name) for Browser.

| Provider | What it does | Setup | Where the answer lands |
| --- | --- | --- | --- |
| **Browser** | Sends the query to your default browser and dismisses | none | Your browser |
| **Google AI Mode** | Runs Google AI Mode (`udm=50`) in a hidden page in your own Google session, reads the answer out and draws it natively | none required; connecting your Google account is recommended | The answer card |
| **Gemini** | Streams a written answer with live web sources | free API key | The answer card |
| **Apple Intelligence** | Streams an answer from Apple's on-device model (FoundationModels) — private and offline, but no live web | Apple Intelligence turned on in System Settings | The answer card |

**Apple Intelligence mode specifics:**
- Runs on the Mac through the FoundationModels framework: no key, no account,
  no network request — the question and the answer never leave the Mac.
- No web access. The model is told to say so, and to point at Gemini or AI
  Mode, for anything that depends on recent or live information, and never to
  invent facts, links or sources. Answers have no source cards.
- Follow-ups carry the conversation as the session's history, trimmed to fit
  the model's context window (the last four answered turns at most).
- The model is loaded as Flyby opens with this provider selected, so the
  first question doesn't pay for it.
- Settings › Answers and onboarding show whether it's ready; when Apple
  Intelligence is off there's an **Open System Settings…** button, and when
  the model is still downloading it says so. Guardrail stops, refusals,
  unsupported languages and a too-long chat come back as readable messages.

**Gemini mode specifics:**
- Streams token-by-token over SSE (`streamGenerateContent?alt=sse`) — text
  appears as it's generated. The API key travels in the `x-goog-api-key`
  header, not the URL.
- **Google Search grounding is enabled**, so answers reflect the live web rather
  than training data.
- **Sources are extracted from the grounding metadata** and shown as clickable
  source cards under the answer, deduplicated by URL and kept in first-seen
  order, so they don't reshuffle while the answer streams.
- System instruction tunes the model to answer like a good search result: lead
  with the answer, short paragraphs or a few bullets, no preamble, no offers of
  further help.
- **Default model `gemini-3.8-flash`**, editable in Settings (a pasted
  `models/` prefix is accepted; an empty field means the default). Only a
  deliberate choice is stored, and a stored `gemini-2.5-flash` or
  `gemini-2.0-flash` — earlier defaults — is migrated to the current default.
- **Generation settings follow the model.** Any model whose name starts with
  `gemini-3` is sent a thinking config (`thinkingLevel: LOW` — a search answer
  should start quickly) and no temperature, so Google's default applies. Any
  other model is sent temperature 0.3 and no thinking config. Thought summaries,
  if one ever arrives, are never shown as the answer.
- **Rendered natively** by the same block renderer as AI Mode: headings,
  paragraphs, nested lists, fenced code (with a Copy button, and an unterminated
  fence shown as code while it streams), GitHub-style tables, quotes and rules;
  bold, italic, inline code and links inside them. `AttributedString(markdown:)`
  is used only for inline styling, because on its own it flattens lists into a
  run-on paragraph.
- **Errors are readable sentences**, not raw JSON: missing key, rejected key
  (with where to get a new one), permission denied, unknown or retired model,
  rate limit (with the server's suggested wait when it gives one), overload /
  5xx, and answers withheld for safety, recitation, blocklist or length.
  Anything else shows the HTTP status plus up to 300 characters of Google's
  message.
- **One quiet retry** on a 429 or 503 when the server's suggested wait is 5 s or
  less (1.5 s if it doesn't say).
- If Gemini stops early for a reason like safety or length after text has
  arrived, the partial answer stays, with an italic note saying why it ends
  there.

**Google AI Mode specifics:**
- **Runs in your own Google session.** Settings › Google Account (or the
  onboarding step) connects Flyby to your Google account in one of two ways:
  - **Borrow your browser's sign-in** — Safari or Firefox. Flyby copies only
    Google-domain cookies (`google.com`, its subdomains and Google's country
    domains, matched on the registrable domain so look-alikes don't qualify)
    into its own private, persistent `WKWebsiteDataStore`. Safari needs Full
    Disk Access; the pane says so before anything is requested and picks the
    grant up by itself when you come back from System Settings. Firefox usually
    needs no permission (the UI notes macOS 27 may ask for Full Disk Access);
    its default profile's `cookies.sqlite` is read from a temporary copy. A
    browser that isn't signed in to Google is refused with a button that opens
    Google's sign-in page in that browser.
  - **Sign in within Flyby** — a Flyby window on the same store. Offered as a
    fallback, labelled as such: Google refuses sign-in from embedded browsers
    for many accounts, and the window says so when it happens.
- **Chrome-family browsers are not offered.** The Chromium import code exists
  but is switched off (`chromiumImportEnabled = false`): Chrome binds Google's
  session cookies to the Mac's hardware so a copy dies within hours, and an
  ad-hoc signed app is refused Chrome's "Safe Storage" Keychain item.
- **The session keeps up with the browser.** Before an AI Mode search (and at
  launch), a Safari/Firefox copy more than 30 minutes old is silently re-read
  from the browser — a local file read that never prompts. A page that reports
  itself signed out gets one silent re-import per launch before Flyby asks you to
  reconnect. Settings shows the account the page reports ("Signed in as Name
  (email)"), with **Reconnect** and **Disconnect**; disconnecting deletes the
  Google cookies and Google/YouTube site data from Flyby's store.
- **One long-lived hidden page.** A single `WKWebView` is reused for every
  search; google.com is preloaded when Flyby opens with AI Mode selected. A
  search loads `https://www.google.com/search?q=…&udm=50&hl=…`, where `hl`
  follows your first preferred macOS language (mapped to Google's codes, e.g.
  `zh-TW`, `pt-BR`, `en-GB`). There is deliberately no `gl` region pin and no
  `pws=0`.
- **It introduces itself as Safari.** The user agent is WebKit's own plus the
  installed Safari's version — the way Safari's own UA is formed — rather than a
  hard-coded string.
- **Native answer.** An injected extractor, running in Flyby's own script
  world (Google's scripts can't see it), reads headings, paragraphs, lists,
  tables, code, quotes and cited sources out of the live page as it streams and
  posts them to Swift; Flyby draws them with the Gemini renderer. It keys on
  `data-*` hooks and page structure, never on Google's obfuscated class names or
  English text. Reads are debounced (120 ms, at most 400 ms). An answer counts
  as finished when Google's answer footer is present and nothing has changed for
  1.3 s, or after 10 s of no change if the footer never appears. The page runs
  unthrottled while hidden.
- **Follow-ups continue Google's own conversation.** While the page still holds
  the chat — its last answer finished there, and nothing since has left it —
  a follow-up is typed into AI Mode's composer on that page and sent, the way
  a user would (focus, the text through the field's value setter and an
  `input` event, then its Send button; Return if that doesn't take). Google
  keeps the thread server-side, and the extractor reads only the new turn.
  Otherwise — a chat reopened from Recent Chats, a relaunch, a page that failed,
  was stopped or is waiting on the user, a turn another provider answered, or a
  composer that won't take the question — the follow-up is a fresh AI Mode
  search whose query carries the earlier questions and the start of the last
  answer (at most 1,200 UTF-8 bytes, the new question last and whole). The
  question bubble and history always hold just what was typed. A follow-up the
  page takes but never starts answering within 20 s is asked that way too.
- **When Google wants you, the page is revealed in place.** A CAPTCHA
  (`/sorry/`, reCAPTCHA form or frame), an EU consent wall (`consent.*` or its
  form) or a sign-in (`accounts.*`) — detected from URLs and form/iframe hooks,
  not wording — switches the card to Google's page, with a banner above it
  saying what Google wants, **Connect Google…** (for a CAPTCHA when you're not
  connected, and for sign-in) and **Open in Browser**. Clicks on those pages
  stay in the card so you can work through them; landing back on a results
  page resumes the search. What Google sets while you do (a solved check, a
  consent choice) stays in Flyby's store like it would in a browser, and a
  sign-in completed on the page is adopted as your session.
- **When the answer can't be read, Flyby shows the page rather than nothing** —
  if nothing readable appears 15 s after a results page finishes loading, or a
  results page makes no progress for 45 s — with a banner saying so. With no
  page at all after 45 s the search fails with a message; an answer that stops
  growing for 45 s without Google's footer is kept as complete.
- **Show Google's Page / Show Answer** in the provider dropdown's menu flips
  between the native answer and the page at any time. The page sits inset in
  the card, between its corner buttons and its input row, with rounded corners.
- **Reader mode** (on by default) strips Google's chrome only while the page is
  on screen for its content — never on a CAPTCHA, consent or sign-in page:
  masthead, nav tabs, search box, sign-in link, left rail, footer, anything
  `position: fixed`/`sticky` and smaller than the viewport (composers, cookie
  banners), and — on a page with a single answer — the query echoed back as a
  bubble. Selectors are structural and role-based. It can be turned off if it
  ever hides too much.
- **Links:** on the revealed page, a link opens in your default browser and
  dismisses Flyby (except mid-CAPTCHA/consent/sign-in); `target=_blank` and
  `window.open` also go to your browser. Cited sources have Google's `/url?q=`
  redirect unwrapped and `#:~:text=` highlights dropped; non-http(s) links are
  rejected.
- The page is always dark, like the card it's in: its web view is darkAqua, so
  Google gets `prefers-color-scheme: dark` whatever the system is set to.
- If the page's web process dies mid-answer, what already arrived is kept;
  otherwise the card says Google's page stopped and to try again.

**Browser mode specifics:**
- Four engines: **Google, DuckDuckGo, Bing, Perplexity**.
- The engine setting applies to every browser hop, including ⌘Return from the
  other providers.
- Queries are percent-encoded to RFC 3986's unreserved set, so non-ASCII text
  and "+" arrive intact.

### 4.3 The answer card
- **The bar becomes the card.** On Return the bar's glass grows up and out into
  the card, bottom-centre where the bar was, on one spring (0.48 s response,
  0.82 damping); your question flies from where you typed it up into its bubble,
  shrinking from the bar's 22pt to the bubble's 15pt as the bubble fills in
  around it, and the input settles into a field along the card's bottom edge,
  the provider dropdown still at its trailing end. With nothing left to show — **New
  Chat**, or the history list closed with no chat behind it — the card folds
  back down into the bar.
- **Siri-sized, not window-sized:** 560pt wide on every screen, and as tall as
  700pt or whatever fits between the bar's position and 44pt below the top of
  the usable screen. The height is fixed while Flyby is open, so an answer
  streaming in scrolls rather than resizing anything; the card's content is laid
  out at that size and revealed by the growing glass.
- **Corners:** a round glass **✕** top-left (close — or back out of the history
  list, when it becomes a back arrow over a chat) and a glass capsule top-right
  with its shortcut written on it, **Open in Browser ⌘↩** (diagonal arrows;
  once there's a question). Recent Chats is the pill under the card.
- **Conversation:** each question in a dark bubble with a tail, right-aligned;
  each answer as plain white 16pt text under it, bold headings, no box. Content
  scrolls under the corner buttons and the input row and dissolves at both
  (scroll edge effect plus a fade).
- **The provider dropdown** (in the input, bottom-right) becomes **Stop ⌘.** —
  an accent-tinted capsule with a pulsing stop glyph — while an answer is
  coming. Its menu (click, or ⌘K) holds the providers with ⌘1–⌘4, the browser
  engines, and the chat's actions with their shortcuts: **Search Again** (⌘R),
  **Copy Answer** (⇧⌘C), **Show Google's Page / Show Answer** (AI Mode only)
  and **New Chat** (⌘N).
- **Keyboard focus is shown.** In the card the input has an accent rim while it
  has the keyboard. Leave it (Esc, or a click in an answer) and it says how to
  get back: "⇥ tab to ask a follow-up". Anything typed while reading goes
  straight into it.
- While waiting: placeholder lines with a slow sheen (no sheen under Reduce
  Motion). While streaming: new blocks fade in, a caret blinks after the last
  one, and the card scrolls to keep the newest text in view — until you scroll
  up to read; scrolling back to the end picks it up again.
- A follow-up lands at the end of the conversation, just above the input, and
  the answer pushes it up as it arrives. A chat reopened from history opens on
  its last question. Answer text is selectable.
- **Sources** appear as a "Sources" row of cards (favicon, site, title) that
  scrolls sideways; clicking one opens it in your browser.
- **Stop** freezes the answer as it stands ("Stopped before an answer arrived."
  if nothing had). **Copy Answer** copies the whole answer as markdown-style
  plain text with a "Sources:" list of titles and URLs appended; plain ⌘C still
  copies just the selection.
- Failures show a "No answer this time" card with the reason, **Try Again** and
  **Open in Browser**.
- **Search Again** re-answers the same turn in place: the question stays put.
- **Closing Flyby** is a separate, quicker motion: bar or card shrink to 90%
  and drop 18pt as one piece, fading a little behind the shrink (a 0.3 s smooth
  spring, no bounce).
- The input keeps keyboard focus throughout — it's one text field, in the bar
  or along the card's bottom — so you can keep typing.

### 4.4 Appearance and theming
- **Always dark, like Siri.** The bar and the card are dark whatever the
  system is set to (their window is darkAqua); there is no appearance setting.
  Settings and onboarding follow the system like any Mac window.
- **Liquid Glass**, always — it's the design, not a setting. The bar and the
  card are *smoked* glass: a dark gradient inside the glass, near-black at the
  top and clearing toward the bottom so what's behind shows through, a dark
  tint so it stays dark over a white wallpaper, and a thin lit rim, brighter
  along the bottom. The controls on the card (✕, the Recent Chats and Open in
  Browser capsules, the input field, the Google banner) are plain glass, a
  shade lighter; the provider dropdown is a quiet filled capsule inside the
  input, not glass of its own. The bar uses the *interactive* glass variant that reacts to
  the pointer; the card uses the plain one, because that motion is a
  distraction in something you're reading. Follows macOS 27's clear-to-tinted
  glass slider.
- **Settings** is a native split view: the system's floating glass sidebar and
  each pane's title in the toolbar, like System Settings.
- **Reduce Transparency** swaps every glass shape for an opaque dark fill with
  a hairline rim. Increase Contrast gets a stronger edge.
- **Reduce Motion:** the bar fades in without springing out of a blob, the bar
  and the card cross-fade instead of morphing, the question doesn't fly, the
  bar changes height without animating, and the close is a plain fade. The
  loading sheen and the pulse on the stop glyph stop.
- **The system accent colour**, not a setting of Flyby's: it tints the caret,
  links in answers, the streaming caret, quote bars, the Stop chip, the input's
  focus rim and controls.
- **VoiceOver labels** on the input, the provider dropdown and Stop, the
  card's corner buttons, question bubbles, source cards and the Google account
  rows.

### 4.5 System integration
- **Menu-bar only** (`LSUIElement`) — no Dock icon, no app switcher entry, no
  window clutter. The menu-bar icon is a magnifying glass with a sparkle; its
  tooltip names the build and version.
- **Open at login**, backed by `SMAppService`, so macOS owns the state and it
  also appears in System Settings › General › Login Items. Non-binary states
  ("waiting for approval", "registration not found") are reported honestly in
  Settings instead of pretending the toggle worked.
- **Multi-monitor aware** — the bar appears on the screen the mouse is on,
  which is the one you're looking at, and the card grows out of it there.
- Focus is handed back to whatever you were working in when Flyby closes
  (without hiding Settings or onboarding if one of those is open).
- **Gets itself installed properly.** A release build launched from a disk
  image, a translocated location or Downloads offers to copy itself into
  Applications (`/Applications`, or `~/Applications` for an account that can't
  write there), clears the quarantine flag on the copy, moves the original to
  the Trash rather than deleting it, and never replaces an app that isn't Flyby.
  Settings › General keeps a **Move to Applications** row until it's somewhere
  real, because login items and the Accessibility grant both follow the app's
  path.
- **Two builds side by side.** "Flyby Dev" and "Flyby" have different bundle IDs,
  so each has its own settings, Keychain entry, Google session, login item and
  Accessibility grant. The dev build wears an amber icon and a **DEV** badge.
- **Reset All Data** (Settings › Advanced) returns the app to a fresh-install
  state: preferences, the Gemini key, the Google connection and the login item
  all go, and onboarding starts over.

### 4.6 Interaction details that matter
All of these are handled by one key monitor in the app delegate and listed on
the ⌘/ overlay. The keyboard is in one of three places: **typing** in the input
(text editing keeps every key it uses), **reading** the card (after Esc, or a
click in an answer), or **in Google's page** (which keeps its own keys, Tab
included).

| Key / action | Behaviour |
| --- | --- |
| `Return` | Ask with the selected provider (a follow-up, once a chat is open) |
| `⌥Return` | New line in the question |
| `⌘Return` / Open in Browser ⌘↩ | Always open in your default browser, from any provider |
| `⌘K` / click the dropdown | Provider menu |
| `⌘1`–`⌘4` | Browser, Google AI Mode, Gemini, Apple Intelligence |
| `⌘.` / Stop ⌘. | Stop the answer where it is (does nothing otherwise) |
| `⌘R` | Ask the same query again, same provider |
| `⇧⌘C` | Copy the whole answer, with sources (plain `⌘C` copies the selection) |
| `⌘N` | New chat: the card folds back into the bar |
| `⌘Y` / the Recent Chats pill, or `↑` in an empty input | Recent chats: `↑`/`↓` move, `Return` opens, `⌘⌫` deletes, `Esc` backs out |
| `Esc` | One step back: the command list, the shortcuts overlay, recent chats, then (in the card) out of the input to read, then close |
| `Tab` | Back into the input, from anywhere in the card |
| Typing while reading | Goes straight into the input |
| `↑`/`↓`, `Space`/`⇧Space`, `Page Up`/`Page Down`, `⌘↑`/`⌘↓`, `Home`/`End` | Scroll the answer while reading (Page Up/Down also while typing; Home/End also from an empty input) |
| `⌘W` / ✕ | Close at once |
| `⌘/` / the Shortcuts pill | Keyboard shortcuts overlay |
| `/` at the start of the input | Command list: `↑`/`↓` pick, `Return` or `Tab` runs, `Esc` hides the list (nothing matching → Return asks the text) |
| Click outside | Close |
| Trigger again | Toggle closed |
| `⌘,` | Settings |
| Click a link or source card in an answer | Opens in your default browser |
| Click a link on Google's revealed page | Opens in your default browser and dismisses Flyby (stays put during a CAPTCHA, consent or sign-in) |

### 4.7 Install and updates
- **Install** with one command:
  `curl -fsSL https://raw.githubusercontent.com/emonsaqibh/flyby/main/install.sh | bash`
  (`… | bash -s -- --beta` includes betas; `… | bash -s -- 0.3.0` pins a
  version). It picks the newest GitHub release that carries `Flyby.zip`,
  requires macOS 14+ and refuses a download that needs a newer macOS than the
  Mac has (0.4 and later need macOS 27), verifies the code signature and the bundle ID, clears the
  quarantine flag, quits a running copy, installs into `/Applications` (or
  `~/Applications`), refuses to overwrite an app that isn't Flyby, and opens it.
- A script rather than a download link because releases aren't notarized yet,
  and files fetched with curl aren't marked as downloads.
- **Update checks** (release builds only) ask GitHub's releases API about 5 s
  after launch if a check is due, every six hours while running, and when the app
  comes back to the front after six hours or more. Only releases tagged with a
  real version and carrying the app zip count; betas only if you opt in. A newer
  release shows up as "Update Available — Flyby x.y.z…" at the top of the
  menu-bar menu and in Settings › General › Updates (with a What's New link).
  Installing is the same command: Flyby copies it and opens Terminal. **Check
  for Updates…** in the menu always answers. Automatic checks can be turned off.
  The dev build never checks.

---

## 5. Anatomy of the interface

### The bar
Modelled on macOS 27's Siri. A large rounded rectangle of smoked glass at the
bottom centre of the screen, 54pt above the Dock or screen edge — on top of
the pills — 532pt wide
(the card's width less its 14pt insets), 68pt tall for one line (26pt corner
radius), growing 26pt taller per line up to six lines and then scrolling
internally. It never gets wider. No icons inside:

- **Text** — 22pt white, wrapping. Empty, it says who will answer in grey:
  **Ask Google** (AI Mode), **Ask Gemini**, **Ask Apple Intelligence**, or
  **Search Google** (Browser — the engine's name). Once you type, the same words
  follow your last character as a grey hint — "…in nature? — Ask Gemini" — on
  whichever line that is. The hint fades in with the first character and
  cross-fades when the provider changes. The caret is the ordinary one, in the
  accent colour; macOS's inline predictions are turned off, since they'd draw
  exactly where the hint goes.
- **Provider dropdown** — at the trailing end, anchored to the bottom so it
  stays with the last line as the bar grows: the provider's short name and a
  chevron in a 28pt capsule — **Google ⌄**, **Gemini ⌄**, **Apple
  Intelligence ⌄**, **Browser ⌄**. The text wraps before it; its column is as
  wide as the wider of the name and Stop, so nothing rewraps when an answer
  starts. Click or **⌘K** opens its menu, which pops up with the current
  provider over the chip: **Answer with** (⌘1–⌘4) and **Open in browser with**,
  because the engine only ever applies to the browser hop, then the chat's
  actions with their shortcuts (**Search Again**, **Copy Answer**, **Show
  Google's Page / Show Answer**, **New Chat**), and **Connect Google
  Account…** when AI Mode is selected and no account is connected. While an
  answer is coming it's **Stop ⌘.** instead. (The dev build puts a small DEV
  badge on the bar's top edge, near the trailing end.)

In the card the same field, with the same dropdown at its end, becomes a 40pt
capsule along the bottom.

- **Slash commands** — "/" at the start of the input opens a small smoked list
  just above it, filtered as you type (names that start with what's typed
  first, then those with its letters in order: "stg" finds /settings), the
  highlighted row marked ↩. ↑↓ pick, Return or Tab runs, Esc hides the list
  (and only the list). Running one clears the "/…". The list only offers what
  would do something now: **/google**, **/gemini**, **/apple**, **/browser**
  (switch provider; the current one is ticked), **/new** (with a chat or the
  history open), **/retry** and **/copy** (with an answer), **/history**,
  **/shortcuts** and **/settings** (Flyby steps aside and Settings opens). If
  nothing matches — "/etc/hosts" — it's a question, and Return asks it. The
  "— Ask Google" hint hides while the list is up.

**The pills.** Under the bar, 10pt below it and 16pt above the Dock or screen
edge, two small smoked capsules, 28pt tall: **🕘 Recent Chats ⌘Y** and **⌨
Shortcuts ⌘/**, their keys written on them in a quieter grey. The one whose
panel is open is in the accent colour with an accent rim. They're a row of
their own, so the bar becomes the card above them without them moving; they
come out a beat after the bar's glass as Flyby opens, and go before it as it
closes.

**Engineering note worth telling:** everything lives in one fixed, oversized,
fully transparent window — the card's full width and height, the pills under it, plus a 40pt margin
for the glass's shadow. Resizing an `NSWindow` on every keystroke animates badly
and lags a fast typist, and two windows can only be animated by resizing them;
animating shapes inside a static window is a clean spring, and it's what lets the
bar and the card be one piece of glass. Clicks on the transparent parts fall
through to whatever is underneath. There is one text field for the whole time
Flyby is on screen — the bar's text and the card's input are the same field,
restyled — so focus never has to move mid-animation.

### The answer card
The bar's own glass, grown up and out: 560pt wide, up to 700pt tall, its bottom
edge where the bar's was, with a 34pt corner radius concentric with the controls
inset 14pt in its corners. Three layers: Google's page at the back (AI Mode
only, kept mounted but invisible so the extractor can read it; when showing,
inset between the corner buttons and the input with rounded corners, dark like
the card), the conversation or the recent-chats list in front of it, and the
corner controls on top — a round glass **✕** top-left, and top-right a glass
capsule with its shortcut written on it, **⤢ ⌘↩** (Open in Browser). Along the
bottom, the input is a 40pt capsule field
(15pt type, "Ask a follow-up") with the provider dropdown inside its trailing
end, and an accent rim while it has the keyboard; without it, it reads "⇥ tab
to ask a follow-up". The recent-chats list heads itself with its keys: ↑↓ move,
↩ open, ⌘⌫ delete, esc back. The conversation scrolls the card's full height,
under the buttons and the input, and dissolves at both edges. When Google needs
you, a banner sits above the page rather than over it, so it never covers the
checkbox you have to reach.

**⌘/** (or the Shortcuts pill, or /shortcuts) lays every shortcut out on a
small smoked card above the input, with the slash commands under them; Esc, ⌘/
or a click puts it away.

---

## 6. Settings reference

Always dark, in the shape of macOS 27 System Settings: a sidebar with Flyby's
icon, name and version on top and a coloured icon badge per pane — **General,
Shortcut, Answers, History, Google Account, Advanced** — and each pane opening
with a large badge, its title and one line of description, the title also in
the toolbar. Explanations sit under their sections as footers.

### General
- **About** — the app icon, name (with a DEV badge in the dev build), version
  and commit.
- **Shortcut** (its own pane) — the current shortcut drawn as key caps, a
  click-and-press recorder, and a live explanation of what the recorded trigger does ("Hold these together…", "Press this…", "Tap Right ⌥
  twice…") and a note that key combos need no permissions while chords and
  double-taps need Accessibility.
- **System** — **Move to Applications** (release build, only when it isn't in
  an Applications folder), and **Open at login** with honest status reporting.
- **Updates** (release build) — **Check for updates automatically**, **Include
  beta versions**, the version with when it was last checked and **Check Now**;
  when an update exists, its version, a What's New link and the two install
  steps (Copy Install Command, then paste into Terminal). The dev build says
  updates are off.

### Answers
- **Answer with** — Browser / Google AI Mode / Gemini / Apple Intelligence as
  selectable rows with their badges, the chosen one's setup below it; picking AI Mode with no
  account connected adds a **Connect…** row, and picking Apple Intelligence
  shows whether it's ready (with **Open System Settings…** when it's off).
- **Search engine** — Google / DuckDuckGo / Bing / Perplexity, used for every
  browser hop.
- **Google AI Mode › Reader mode** — toggle; applies when Flyby shows Google's
  page itself.
- **Gemini › API key** — secure field, stored in the Keychain.
- **Gemini › Model** — text field; empty means the default, `gemini-3.8-flash`.
- Direct link to get a free key from Google AI Studio.

### Google Account
- **Status** — "Not connected", "Connected through Safari/Firefox" or "Signed
  in within Flyby", with the account shown when the page reports it, and
  **Disconnect**.
- **Problem row** when the last attempt failed, with the fix for that failure
  (e.g. **Open Full Disk Access Settings**; **Sign in to Google in Safari** +
  **Connect Again**).
- **Use your browser's sign-in** — a row per installed Safari/Firefox (your
  default browser first), each saying up front what it needs, with **Connect**
  or **Reconnect**.
- **Sign in within Flyby instead…** — the main button when no supported browser
  is found; "Google may refuse sign-ins from embedded windows."
- A privacy note: only Google cookies are copied, into Flyby's own private store.

### Advanced
- **Show Onboarding Again** — reruns the walkthrough; nothing is erased.
- **Reset All Data…** — after a confirmation, clears every preference,
  disconnects Google, forgets the Gemini key and turns off open-at-login.

---

## 7. Privacy, data and permissions

This is a **major selling point** and every claim here is verified against the
source.

### What the app sends, and where
| Activity | Network activity |
| --- | --- |
| **Browser** search | The app makes **no network request** for the search. It hands a URL to your default browser. |
| **Google AI Mode** search | Flyby's hidden `WKWebView` loads `www.google.com/search?q=…&udm=50&hl=…` — exactly one page per search you submit — in Flyby's own persistent web store, carrying your Google session if you connected one, and the page then loads whatever Google's page loads. When Flyby opens with AI Mode selected, google.com is preloaded to warm the page. |
| **Gemini** search | One HTTPS request from your Mac directly to `generativelanguage.googleapis.com`, authenticated with your own API key. |
| **Apple Intelligence** search | **No network request.** The answer is generated on the Mac by the system's on-device model. |
| **Source cards** (Gemini and AI Mode) | Each card's icon is fetched from Google's favicon service (`www.google.com/s2/favicons?domain=<site>`). |
| **Connect** a browser (Settings › Google Account) | No network. A local read of Safari's or Firefox's cookie file. |
| **Sign in within Flyby** | Google's sign-in pages (`accounts.google.com`), in a Flyby window on the same private store. |
| **Update checks** (release builds) | `api.github.com/repos/emonsaqibh/flyby/releases` (and a release's asset list when needed): shortly after launch when due, every six hours, and on returning to the app after six hours. Can be turned off; the dev build never checks. |

### What the app does *not* do
- **No Flyby account. No sign-up.** The only identity anywhere in the product
  is the optional Google session that AI Mode runs in, and it goes only to
  Google.
- **No server of ours.** There is no backend. Nothing is proxied.
- **No telemetry, no analytics, no crash reporting.** The table above is every
  outbound request in the codebase; the only one not caused by a search is the
  update check, which asks GitHub for the public release list and adds no
  account or device identifier.
- **No search history of its own.** The query is held in memory while Flyby
  is open and cleared on close; Flyby writes no record of what you searched, and
  its logs never contain the query text (AI Mode logs only that a search started
  and how many characters it had). (See the caveat below about Google's side.)
- **No reading of your screen or clipboard.** Flyby writes to the clipboard only
  when you copy. The only other app data it reads is **Google cookies from
  Safari's or Firefox's cookie store — only after you click Connect**, then
  silently again when the copy is more than 30 minutes old (checked at launch
  and before AI Mode searches). Nothing else from the browser is kept: only
  Google-domain cookies are installed into Flyby's own `WKWebsiteDataStore`, and
  they're sent nowhere but to Google, by the AI Mode page. (It also reads
  Safari's version number, to match Safari's user agent.)

### Permissions
- **Accessibility** is required **only** for modifier-only shortcuts (chords
  and double-taps, including the default), because `RegisterEventHotKey` cannot
  express "modifiers with no key" and cannot distinguish Right ⌘ from Left ⌘.
  Record a key combo like ⌥Space instead and the shortcut needs **no
  permissions whatsoever**.
- The event tap, when used, is **listen-only** and subscribes to
  `flagsChanged` events only — modifier state changes. It does not observe key
  presses; to reject AltGr typing, a double-tap asks the window server only how
  long ago *any* key went down, never which. No Input Monitoring permission.
- **Full Disk Access** is needed **only** to connect Safari, whose cookies sit in
  a protected folder. Firefox usually needs none, and signing in within Flyby
  needs none. AI Mode also works unconnected — Google just challenges anonymous
  clients more.
- Settings live in `UserDefaults` (per build), including, if you connect, which
  browser you connected, when it was last copied, and the account name/email the
  page shows. The Gemini API key lives in the **Keychain** (per build), never in
  plain text on disk. The Google session lives in Flyby's own WebKit data store
  on disk, like a browser profile's cookies.

### The honest caveat to publish
Google sees your AI Mode queries and your Gemini queries, exactly as it would if
you searched in a browser — and when AI Mode is connected to your Google
account, those searches are made *as you*, so they can show up in your Google
account activity according to your Google settings. Flyby's AI Mode page is a
persistent web store, so like any browser it keeps Google's cookies and site
data. Flyby does not add a middleman — but it does not remove Google either. If
you want no third party at all, use Browser mode with DuckDuckGo.

---

## 8. Technical facts

| | |
| --- | --- |
| **Platform** | macOS 27.0 or later |
| **Architecture** | Apple silicon (arm64) only — macOS 27 doesn't run on Intel Macs; CI checks the binary with `lipo`. |
| **Language / stack** | Swift 6.4 toolchain (`swift-tools-version: 6.4`, Xcode 27 — the Command Line Tools lack the SwiftUI macro plugin macOS 27 needs); `FlybyCore` in Swift 6 language mode (strict concurrency), the `Flyby` app target in Swift 5 mode. SwiftUI + AppKit, FoundationModels, WebKit, Combine, Carbon HIToolbox, ServiceManagement, Security, and the system SQLite3 and CommonCrypto libraries (for reading browser cookie stores) |
| **Modules** | `FlybyCore` — Foundation-only logic, unit-tested; `Flyby` — the app; `FlybyCoreTests` |
| **Dependencies** | **Zero.** No third-party packages. |
| **App type** | `LSUIElement` menu-bar accessory — no Dock icon |
| **Version** | 0.3.0 (`Resources/Info.plist`, the dev build's fallback). Release builds take exactly the version given to `./release.sh`; dev builds derive theirs from git (`0.3.0-dev.14 · pill`). `CFBundleVersion` is a build timestamp. |
| **Bundle IDs** | `com.fringecore.flyby` ("Flyby", release) · `com.fringecore.flyby.dev` ("Flyby Dev") |
| **Build** | `./run.sh` builds and launches `build/Flyby Dev.app`; `CONF=debug ./build.sh` for lldb; `swift test` runs the FlybyCore tests |
| **Release** | `./release.sh <version>` freezes `releases/<version>/` (the app, `Flyby.zip`, `source.tar.gz`, `COMMIT`) from a clean tree, refuses to overwrite a version, and installs it (`INSTALL=0` to skip). `./publish.sh <version> notes.md` tags `v<version>`, creates the GitHub release with `Flyby.zip` (a pre-release for `-beta` versions) and confirms the zip is attached. |
| **Distribution** | GitHub Releases on `emonsaqibh/flyby`, installed with the curl script (§4.7). A drag-to-Applications DMG (`scripts/package-dmg.sh`) is made only when notarizing, or with `DMG=1`. |
| **Signing** | Ad-hoc by default. `SIGN_IDENTITY` switches to a Developer ID with the hardened runtime and a secure timestamp; with `NOTARY_PROFILE` too, `release.sh` notarizes and staples the app, then makes and notarizes the DMG. **No Developer ID yet; not notarized.** |
| **CI** | GitHub Actions on a macOS 27 / Xcode 27 runner for every non-docs push: debug build, unit tests, the dev app, and an arm64 release build; both apps uploaded as artifacts. |
| **Tests** | FlybyCore unit tests: Safari/Chromium/Firefox cookie stores, cookie conversion, Google domain matching, browser discovery, markdown parsing, the answer model, AI Mode query URLs, page classification, link cleaning, extractor messages and account labels, and version parsing |
| **App icon** | Generated placeholders: `Resources/AppIcon.icns` (glassy lens + comet on a gradient squircle) and an amber `AppIcon-Dev.icns` for the dev build, drawn by `Resources/IconGenerator/generate.swift` only when missing; swap by replacing the icns, no code change |
| **Logging** | `os.Logger`, subsystem `com.fringecore.flyby` (both builds) |
| **Liquid Glass** | Always; the classic material only under Reduce Transparency |

### Source layout
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

---

## 9. Known limitations and honest caveats

Publish these. They cost nothing and they buy enormous credibility on Product
Hunt, where "what it doesn't do" comments arrive within the hour.

### Product limitations (things it deliberately doesn't do)
- **It is not a launcher.** No app launching, no file search, no calculator, no
  clipboard history, no window management, no snippets, no extensions.
- **No search history or recents.** Every summon starts clean.
- **English UI.** Every interface string is English; there's no localization
  yet. AI Mode itself asks Google for your macOS language (`hl`) and pins no
  region (`gl`), so Google's answer may come back in your language.
- **Only Safari and Firefox can lend their Google session.** Chrome, Arc, Brave,
  Edge and other Chromium browsers are switched off, and for Firefox only the
  default profile is read.
- **Updates aren't installed in-app.** Flyby tells you about one and hands you
  the install command to paste into Terminal.
- **macOS only.** No iOS, no Windows, no Linux.

### Real caveats to state plainly
- **None of v0.3.0 has run on a real Mac yet.** It was built in a Linux sandbox
  and verified only by CI compiles (macOS 26, plus the macOS 27 SDK job), the
  FlybyCore unit tests, and an offline run of the AI Mode extractor against
  captured Google pages (a live answer from 2026-09-16 and Google's CAPTCHA and
  consent pages). **The AI Mode session import (Safari/Firefox copy, the Full
  Disk Access pick-up, the refresh) and the extractor against live Google still
  need on-device verification** — `ROADMAP.md` §4 has the checklist. There are
  no measured speeds, latencies or CAPTCHA rates; don't publish any.
- **AI Mode is inherently fragile.** It reads Google's page, so it depends on
  Google's markup; the extractor keys on `data-*` hooks rather than class names
  and falls back to showing Google's page, but it will need maintenance when
  Google changes things. Follow-ups lean on it most: they're typed into AI
  Mode's own composer, found by its `data-xid` hooks, and when that fails they
  fall back to a search that carries the conversation as text — which Google
  answers well, but not as its own thread. Google's terms don't permit
  automated access to Search; Flyby loads only the page you asked for, one per
  search, in your own session — but get a legal read before charging for it.
  **Gemini is the durable path to an inline answer; AI Mode is the zero-setup
  one.** This framing should appear on the website — it turns a weakness into
  an honest recommendation.
- **CAPTCHAs are rarer, not gone.** Running in your own Google session is meant
  to make them much rarer than for the anonymous client Flyby used to be (not yet
  confirmed on hardware). When one does appear it's shown in place, and what
  Google sets when you solve it stays in Flyby's store. Without connecting an
  account, expect them more often.
- **Full Disk Access is a big ask** for a search utility. It's only needed to
  connect Safari; Firefox usually needs nothing, and signing in within Flyby
  needs nothing — though Google refuses embedded sign-ins for many accounts.
  The UI says what each option needs before anything is requested.
- **Google rotates session cookies.** Flyby re-reads Safari/Firefox when the
  copy is over 30 minutes old, but if the browser itself signs out, AI Mode is
  signed out too until you reconnect.
- **Connected AI Mode searches are made as you**, so they may appear in your
  Google account activity, like any search in your browser.
- **Accessibility permission** is needed for the *default* double-tap shortcut.
  The mitigation (record a key combo instead — zero permissions) must be one
  line away from wherever the permission is mentioned.
- **Ad-hoc signing invalidates that permission whenever the binary changes** —
  every `./build.sh`, and each new ad-hoc-signed release an update installs.
  Users of modifier-only shortcuts should expect to remove and re-add Flyby under
  Accessibility after updating, until builds are Developer ID signed — see
  [Open decisions](#17-open-decisions-before-launch).
- **Gemini requires a free API key** the user pastes in. That's a real setup step
  and shouldn't be soft-pedalled — but it's also *why* there's no subscription
  and no account. The free tier is rate-limited, and Flyby says so when a limit
  is hit.

### Distribution blockers (must be resolved before a public launch)
- No Developer ID signature, no notarization → macOS won't open a copy
  downloaded in a browser. Today's workaround is the curl installer, which works
  because curl downloads aren't quarantined. `build.sh`/`release.sh` are wired
  for it (`SIGN_IDENTITY`, `NOTARY_PROFILE`) — this is a paid Apple Developer
  account away. It's also the precondition for re-enabling Chrome-family import.
- ~~No release artifact / no auto-update~~ → `release.sh` / `publish.sh` produce
  GitHub releases with `Flyby.zip`, `install.sh` installs them, and the app checks
  for updates. Still no one-click in-app install and no download page.
- The repository is being made public; until it is, `install.sh` and the update
  checks can't reach its releases.
- The two pre-0.3 releases (**Flyby 0.1.0 Beta**, tag `beta`; **Flyby v0.2.0**,
  delete or deprecate them and needs to be run once.
- No LICENSE file in the repository.
- ~~No app icon in the bundle~~ → placeholder icon ships in the bundle
  (generated; real artwork still wanted before launch).

---
---

# Part II — Positioning and launch

## 10. Who it's for

### Primary: the focused-app worker
People who spend the day inside one non-browser app and search constantly out of
it.
- **Developers** in an IDE or terminal — syntax, API signatures, error messages,
  "what's the flag for…".
- **Writers and editors** in a text editor — facts, dates, spellings,
  definitions.
- **Designers** in Figma or Sketch — references, conventions, hex values,
  "what's the standard size for…".
- **Analysts** in a spreadsheet — formula syntax, unit conversions, definitions.

**What they feel:** the browser is where focus goes to die, and every lookup is a
gamble on whether they come back.

### Secondary: the keyboard-first Mac user
People who already use Raycast/Alfred/Spotlight fluently, live on shortcuts, and
will adopt anything that removes a step. They will evaluate this in ninety
seconds and either keep it forever or delete it.

**What they want:** something small, fast, native, keyboard-complete, with no
onboarding.

### Tertiary: the privacy-minded AI user
People who want AI answers but not another account, another subscription,
another company holding their query history.

**What they want:** bring-your-own-key, local, no server, verifiable.

### Explicitly not for
- People who want a full AI assistant with memory and conversation.
- People who want a launcher (they already have one).
- People who want cross-platform.
- People who won't paste an API key *and* don't want to use Google.

---

## 11. Use cases

Each of these is a candidate for a website section, a screenshot, or a Product
Hunt gallery card.

### 1. The mid-sentence fact check
*Writing a paragraph, need a date.* Chord, "when was the swift language
released", Return, read, Esc. The document never lost focus.

### 2. The API signature you almost remember
*In your editor.* Chord, "swift urlsession bytes for request", Return. Gemini
answers with the signature and links the docs. Copy the line, Esc, keep typing.

### 3. The error message
*Terminal spits a cryptic error.* Select it, chord, paste, Return. Gemini
answers grounded in the live web — so it knows about the version you're
actually on, not the one it was trained on.

### 4. The "is this still true?" check
*Reading a two-year-old blog post.* Chord, ask, Return. Grounding means the
answer reflects today's web, and the source cards let you verify in one click.

### 5. The deliberate browser hop
*A query that genuinely deserves the full web.* Chord, type, **⌘Return** — your
browser opens with your engine of choice. The pill got out of the way instead of
insisting on answering.

### 6. The comparison shop
*Perplexity as your engine.* Chord, "best portable ssd 2026", ⌘Return, straight
into Perplexity. Flyby is the on-ramp, not the destination.

### 7. Searching over a full-screen app
*Presenting, or in full-screen Xcode.* The pill appears over full-screen apps and
on every Space. Nothing gets minimised, nothing gets rearranged.

### 8. The definition, without the round trip
*Reading a paper.* Chord, term, Return, read the streamed definition, Esc.

---

## 12. Competitive positioning

### The honest comparison table

| | Flyby | Spotlight | Raycast / Alfred | ChatGPT / Claude desktop | Arc Max / browser AI |
| --- | --- | --- | --- | --- | --- |
| Summon anywhere | ✅ | ✅ | ✅ | ✅ | ❌ browser only |
| Answers **in place**, no browser | ✅ | ❌ hands to browser | ⚠️ extensions, varies | ✅ own window | ❌ |
| Live-web-grounded AI answer | ✅ | ❌ | ⚠️ paid / plugin | ⚠️ varies | ✅ |
| Clickable sources | ✅ | ❌ | ⚠️ | ⚠️ | ✅ |
| Free | ✅ | ✅ | ⚠️ freemium | ⚠️ freemium | ⚠️ |
| No account | ✅ no sign-up (Google sign-in optional, for AI Mode) | ✅ | ❌ | ❌ | ❌ |
| Bring your own key | ✅ | — | ⚠️ | ❌ | ❌ |
| No telemetry | ✅ | ⚠️ | ❌ | ❌ | ❌ |
| Scope | search only | files/apps | everything | conversation | browsing |
| Learning curve | none | none | real | none | none |

### The three sentences that position it
1. **Against launchers:** Raycast wants to be your command centre. Flyby
   wants to be a search bar and then go away.
2. **Against AI desktop apps:** ChatGPT's app is a destination you switch to.
   Flyby appears over what you're already doing and vanishes.
3. **Against the browser:** the browser is where a ten-second lookup becomes
   twenty minutes. This never opens it unless you tell it to.

### Where a competitor genuinely wins
Say this out loud somewhere; it makes everything else believable.
- **Raycast/Alfred** are better if you want one bar for apps, files, clipboard,
  window management and snippets.
- **ChatGPT/Claude apps** are better for a real conversation with follow-ups.
- **A browser** is better when you actually want to browse — which is why
  ⌘Return exists.

---

## 13. Messaging kit

### Taglines (pick one, use everywhere)
1. **Search without leaving.** ← *recommended: shortest, states the whole product*
2. Answers where you already are.
3. The search bar that comes to you.
4. One keystroke. Answer. Gone.
5. Search anything, from anywhere, without opening a browser.

### Website headline options
- **H1:** Search without leaving what you're doing.
  **Sub:** A search pill one keystroke away, anywhere on your Mac. Answers arrive
  in place — no browser, no tab, no context switch.
- **H1:** The browser is where focus goes to die.
  **Sub:** Flyby answers your question over whatever app you're in, then
  gets out of the way.
- **H1:** One keystroke. Your answer. Back to work.
  **Sub:** A tiny macOS search overlay with live-web AI answers, sources, and no
  sign-up.

### Feature copy blocks (reusable)

**Anywhere, instantly**
> Double-tap Right ⌥ — or record any shortcut you want — and a search pill
> appears over whatever you're doing. Full-screen apps, any Space, any monitor.
> Esc and you're back exactly where you were.

**Three ways to get an answer**
> Stream a written answer inline with live web sources. Get Google's AI Mode
> answer, drawn natively from your own Google session. Or fire the query at your
> browser with Google, DuckDuckGo, Bing or Perplexity. Switch with one click on
> the pill.

**Grounded, with receipts**
> Gemini answers run with Google Search grounding on, so they reflect the live
> web rather than training data — and answers carry clickable source cards, so
> you can check.

**⌘Return always escapes**
> Some queries deserve the whole web. ⌘Return sends the query straight to your
> browser from any mode, so you're never trapped in the wrong tool.

**Your key, your Keychain, no sign-up**
> No sign-up, no subscription, no server of ours, no telemetry. Your Gemini key
> lives in your macOS Keychain and the request goes straight from your Mac to
> Google.

**Native, down to the details**
> Liquid Glass throughout, and the smoked, always-dark look of macOS 27's Siri.
> No themes to fiddle with: it takes your Mac's accent colour, and Settings and
> onboarding follow your Mac's light or dark appearance like any native app.

**Doesn't want to be your everything-bar**
> No file search, no clipboard history, no window management, no extensions.
> It's a search bar. There's nothing to learn and nothing to maintain.

**Zero dependencies, zero Dock icon**
> Swift, SwiftUI and AppKit, no third-party packages, no Dock icon, no windows
> in your way. Just a magnifying glass in the menu bar.

### Microcopy
- Empty bar placeholder: *Ask Gemini* / *Ask Google* / *Ask Apple Intelligence*
  / *Search Google*, by provider; *Ask a follow-up* in a chat (already in the
  product)
- Download button: **Download for macOS** / sub: *Free · macOS 27+ · no sign-up*
  (until releases are notarized, this has to hand over the curl one-liner — see
  [§14](#14-website-plan))
- Setup line: *Paste a free Gemini key, or use it with no setup at all.*

---

## 14. Website plan

### Recommended structure — a single long landing page

**1. Hero**
- H1 + sub from [Messaging kit](#13-messaging-kit).
- **Primary asset: a looping GIF/video, ~6 seconds**, showing the real loop:
  someone typing in an editor → chord → pill fades in over the code → question
  typed → answer streams in with sources → Esc → cursor still blinking in the
  same place. *This one asset does more selling than the rest of the page
  combined.*
- Buttons: **Download for macOS** · *View on GitHub*. Until releases are
  notarized, "Download" must show the curl install command rather than link a
  file — a browser-downloaded build won't open.
- Trust line: *Free · macOS 27+ · No sign-up · No telemetry* (add *Open source*
  only once the repo has a LICENSE)

**2. The problem** — three-step visual of the round trip (leave → get distracted
→ come back lost), with the line **"The cost of a search isn't the search. It's
the round trip."**

**3. How it works** — four steps with a small looping clip each: Summon → Type →
Answer → Leave.

**4. Four providers** — four cards (Browser / AI Mode / Gemini / Apple
Intelligence) with the what-it-does and setup columns from the table above. Be
explicit that all four are free, and that Apple Intelligence never leaves the Mac.

**5. Grounded answers with sources** — screenshot of the answer panel with source
cards visible. Explain grounding in one sentence.

**6. Made to disappear** — the design/engineering section. The transparent
oversized window, the spring-animated width, the panel unfolding out of the pill,
Liquid Glass. *Craft is the differentiator
against a hundred AI-wrapper launches; show the numbers.*

**7. Privacy** — the "what it does not do" list, verbatim from
[§7](#7-privacy-data-and-permissions), including the honest Google caveat. A
plain, unstyled list reads as more truthful here than a designed one.

**8. Your shortcut, your way** — the recorder, chords vs key combos, and the
permission story stated plainly with the mitigation on the same line.

**9. Comparison** — the table from [§12](#12-competitive-positioning), including
the row where competitors win.

**10. FAQ** — see below.

**11. Download / footer** — requirements, version, GitHub, license, contact.

### FAQ (site + Product Hunt)

**Is it free?**
Yes, all of it. Browser and AI Mode need no setup (AI Mode works better once you
connect your Google account). Gemini needs a free API key from Google AI Studio;
the free tier is rate-limited but covers everyday use.

**Do I need an account?**
No Flyby account — there's no sign-up anywhere in the product. Google AI Mode
can optionally run in your own Google account, borrowed from Safari or Firefox or
signed in within Flyby, which makes Google far less likely to ask if you're
human.

**Does it need permissions?**
Only if you use a modifier-only shortcut like the default double-tap of
Right ⌥ — macOS only delivers those through an Accessibility-gated event tap.
Record a shortcut with a regular key (⌥Space, ⌘⇧K) and the shortcut needs no
permissions at all. Separately, connecting AI Mode to Safari's Google sign-in
needs Full Disk Access, because Safari keeps its cookies in a protected folder;
Firefox usually needs nothing.

**Where does my data go?**
Nowhere we control — there is no server. In Gemini mode the request goes straight
from your Mac to Google's API with your own key. In AI Mode a hidden web view
loads Google in your own session, exactly as your browser would, and Flyby reads
the answer out of it on your Mac. In Browser mode the app makes no network
request for the search. Source-card icons come from Google's favicon service, and
release builds check GitHub for updates. No telemetry, no analytics, no history
stored by Flyby.

**Is my API key safe?**
It's stored in your macOS Keychain, never written to disk in plain text, and only
ever sent to Google's API endpoint.

**Does it replace Raycast/Alfred/Spotlight?**
No, and it doesn't try. Those are launchers. This is a search bar that gives you
answers without opening a browser. They coexist fine.

**Why Gemini and not OpenAI/Claude?**
Gemini's free tier plus built-in Google Search grounding is what makes a
zero-cost, live-web answer possible without a backend. Other providers are on the
roadmap.

**Does it work over full-screen apps?**
Yes, and on every Space, on whichever monitor your mouse is on.

**Why does AI Mode sometimes show me Google's page?**
When Google wants something only you can give — a CAPTCHA, an EU consent choice,
a sign-in — Flyby shows Google's page right in the panel with a note saying why;
deal with it once and carry on. Connecting your Google account makes the
"are you human?" checks much rarer. And if Google changes its page so Flyby
can't read the answer, it shows you the page rather than nothing. Gemini mode is
the durable path to an inline answer; AI Mode is the zero-setup one.

**Does it store my searches?**
Flyby doesn't. The query lives in memory while the pill is open and is cleared
when it closes. If AI Mode is connected to your Google account, Google records
those searches the way it would in your browser, per your Google activity
settings.

**Is it open source?**
→ *decide before launch, see [§17](#17-open-decisions-before-launch)*

### Assets needed
| Asset | Notes | Priority |
| --- | --- | --- |
| Hero loop (6s, silent, looping) | The whole product in one shot. **Highest-leverage asset on the site.** | P0 |
| Screenshot: the bar over an editor, mid-question with the "— Ask Gemini" hint | Show it small and unobtrusive | P0 |
| Screenshot: answer card with sources | The payoff shot | P0 |
| Screenshot: the dark bar over a light app | Proves it holds up on anything (it's always dark) | P1 |
| Screenshot: provider dropdown menu open | Shows the four modes exist | P1 |
| Screenshot: Settings panes | Shows depth | P1 |
| Clip: shortcut recorder in use | Shows the chord idea, which is unusual | P2 |
| Clip: Liquid Glass refracting over a colourful window | Craft signal | P2 |
| App icon | **Only a generated placeholder exists** — real artwork wanted for the bundle, the site and PH | P0 |
| OG/social card | 1200×630 | P1 |

---

## 15. Product Hunt launch kit

### Listing fields

**Name:** Flyby
*(working name — see [§17](#17-open-decisions-before-launch) before the launch
cements it.)*

**Tagline (60 char max):**
- `Search the web without leaving what you're doing` (47) ← recommended
- `AI answers over any Mac app. One keystroke. No sign-up.` (55)
- `A search bar that comes to you, anywhere on your Mac` (51)

**Description (~260 chars):**
> Press a shortcut and a search pill appears over whatever app you're in. Get a
> streamed AI answer with live web sources, Google's AI Mode answer drawn
> natively, or hand it to your browser. No sign-up, no telemetry, no Dock icon.
> Free, native macOS.

**Topics:** Mac, Productivity, Artificial Intelligence, Search, Developer Tools,
Menu Bar Apps

**Gallery order** (first image is ~80% of the decision):
1. Hero GIF — the full loop over a real editor.
2. Answer card with source cards.
3. The bar, small and quiet, over a real app.
4. Provider button menu — the ways to answer.
5. Privacy card — "no sign-up · no server · no telemetry · key in Keychain".
6. Settings — the glass sidebar and pane headers, proving the craft.
7. Comparison card vs launchers/AI apps.

### Maker's first comment (draft)

> Hey Product Hunt 👋
>
> I built Flyby because of one specific, stupid loop I kept repeating:
> I'd be deep in an editor, need a small fact, ⌘Tab to the browser — and land on
> whatever tab I'd left open. Twenty minutes later I'd remember what I actually
> went there for.
>
> The search took four seconds. The round trip cost twenty minutes.
>
> So Flyby never opens a browser unless you ask it to. You double-tap Right ⌥
> (or any shortcut you record), a small pill appears over whatever you're
> doing, you type, and the answer comes to you:
>
> • **Gemini** — a written answer streamed inline, grounded in Google Search, with
>   clickable sources. Bring your own free API key.
> • **Google AI Mode** — Google's AI answer, read out of Google's page in your own
>   Google session and drawn natively in the panel. Works with zero setup; better
>   once you connect Safari or Firefox's Google sign-in.
> • **Browser** — hand it to Google, DuckDuckGo, Bing or Perplexity and get out of
>   the way. ⌘Return does this from any mode.
>
> Esc, and you're back exactly where you were.
>
> Things I care about that you might too:
> • **No sign-up, no server, no telemetry.** There's no backend at all. Your
>   Gemini key lives in your Keychain and talks straight to Google.
> • **No permissions needed** for the shortcut if you record a key combo. The
>   default double-tap needs Accessibility, because macOS won't deliver
>   modifiers-with-no-key any other way.
> • **Native, zero dependencies.** Swift + SwiftUI + AppKit. Liquid Glass
>   throughout, and Apple Intelligence on-device.
>
> Two honest caveats: AI Mode reads Google's page, so it depends on Google's
> markup — when Google wants a check, you'll see its page right there, and
> connecting Safari needs Full Disk Access. Gemini is the durable path. And this
> is deliberately **not** a launcher: no file search, no clipboard history, no
> window management. It's a search bar that knows how to leave.
>
> I'd love to know what your first query is, and what would make this a daily
> driver for you. I'm here all day.

### Anticipated PH comments and answers
| Comment | Answer |
| --- | --- |
| "Raycast already does this" | Raycast is a launcher with AI as a feature; this is a search bar with nothing else in it, free, no sign-up. They coexist. |
| "Why not OpenAI/Claude?" | Gemini's free tier + built-in Search grounding is what makes a zero-cost live-web answer possible with no backend. More providers are on the list. |
| "Another ChatGPT wrapper" | There's no wrapper — no server, no proxy, no sign-up, your key goes straight to Google. And only Gemini mode calls an LLM API at all; the other two are Google's own AI Mode page and your browser. |
| "Is scraping Google AI Mode allowed?" | Flyby loads exactly one Google page per search you type, in your own Google session, and reads the answer out of that page on your Mac to draw it natively — nothing is stored or re-served. It's also the mode we tell people is fragile; the Gemini API is the durable one. *(Get the legal read in §17 before answering this for a paid product.)* |
| "Accessibility permission = keylogger?" | The tap is listen-only and subscribes exclusively to modifier-flag changes, not key presses. Use a key-combo shortcut and there's no tap at all. |
| "Full Disk Access to read my cookies?!" | Only to connect Safari, whose cookie file sits in a protected folder. Flyby copies only Google's cookies, into its own private store, and only after you click Connect. Firefox usually needs nothing, you can sign in within Flyby instead, and AI Mode works without any of it. |
| "Windows/Linux?" | Not planned. This leans hard on AppKit. |
| "Where's the download?" | Today it's a one-line curl install from the GitHub README (releases aren't notarized yet, so a browser download won't open). → **a proper download link needs the Developer ID, see §17** |

### Launch checklist
- [ ] Developer ID signature + notarization (Gatekeeper blocks a browser
      download otherwise; `SIGN_IDENTITY` / `NOTARY_PROFILE` are already wired
      into `build.sh` and `release.sh`)
- [ ] Verify v0.3.0 on a real Mac — AI Mode session import and the extractor
      especially (`ROADMAP.md` §4)
- [x] App icon (placeholder ships; consider real artwork before launch)
- [x] Release pipeline — `release.sh` / `publish.sh` / `install.sh` and in-app
      update checks; a notarized DMG and a download page still needed
- [ ] Repository public (the installer and update checks read its releases)
- [ ] Retire the pre-0.3 `beta` / `Golden` releases
- [ ] Website live
- [ ] LICENSE file for the public repo
- [ ] Hero GIF and all P0 screenshots
- [ ] Repo README aligned with website copy
- [ ] A way for people to reach you (email, X, GitHub issues)
- [ ] Decide the name (see below)
- [ ] Cut 1.0.0 with `./release.sh 1.0.0` and `./publish.sh`

---

## 16. Do-not-claim list

Do **not** write any of these. They are false today.

- ❌ "Works on Windows / Linux / iOS"
- ❌ "Offline" or "works without internet" — every mode needs the network
- ❌ "Private AI" / "your queries never leave your Mac" — Google receives Gemini
  and AI Mode queries, and connected AI Mode searches are made as your Google
  account
- ❌ "End-to-end encrypted"
- ❌ "Search your files / apps / clipboard" — it does none of these
- ❌ "Search history" / "recents" — deliberately absent
- ❌ "Supports OpenAI / Claude / local models" — Gemini only
- ❌ "No permissions required" **without** the "if you use a key-combo shortcut"
  qualifier — and connecting Safari needs Full Disk Access
- ❌ "Never touches your browser data" — connecting reads Google cookies from
  Safari or Firefox
- ❌ "Works with Chrome / Arc / Brave / Edge" — Chromium import is switched off
- ❌ "No CAPTCHAs" / "never asks if you're human" — they're expected to be much
  rarer in your own session (not yet measured), and are shown in place when
  they happen
- ❌ "Notarized" / "Mac App Store" / "identified developer" — not yet true
- ❌ "Auto-updates" / "updates itself" — it checks for updates and hands you a
  Terminal command; nothing installs automatically
- ❌ "Open source" — no LICENSE file yet
- ❌ Any speed, latency or CAPTCHA-rate figure — nothing has been measured on
  real hardware
- ❌ Any user count, download count, rating, or testimonial that hasn't happened
- ❌ Any claim that AI Mode is stable or officially supported by Google

**Claims that need their qualifier attached every single time:**
- "No permissions needed" → *…if you record a key-combo shortcut.*
- "Free" → *…Gemini mode needs your own free API key.*
- "No account" → *…no Flyby account; AI Mode can optionally use your Google
  account.*

---

## 17. Open decisions before launch

These need your call; nothing in the product depends on them, but the website
and the PH listing do.

1. **The name.** "Flyby" is the working name (chosen 2026-07-24, replacing the
   generic "Quick Search"); confirm it's final before launch cements it. The
   bundle IDs and Keychain service are already `com.fringecore.flyby` (and
   `.dev`) — renaming after launch costs the permission grant, stored settings,
   the Google session and the login item registration.
2. **Open source or not.** The repo is being made public (the installer and
   updater need it to be), which settles "View on GitHub" as a hero button — but
   public isn't open source until there's a licence. Pick one (MIT, Apache-2.0,
   or "all rights reserved"); the repo has no LICENSE file today.
3. **Price.** Free forever, free with a paid tier later, or donation/pay-what-you
   -want? Current architecture (no account, no server) makes anything but free or
   one-time-paid awkward.
4. **Distribution.** Today: GitHub Releases, the curl installer, and in-app
   update checks. A Developer ID ($99/yr) removes the curl workaround, makes a
   notarized DMG and a normal download link possible, and is the precondition for
   re-enabling Chrome-family import. Mac App Store would require sandboxing, which
   likely conflicts with the event tap, the login item and reading another
   browser's cookie store. **Recommendation: direct download, Developer ID signed
   and notarized.**
5. **Domain and where the site is hosted.**
6. **Support channel** — GitHub issues, email, or X.
7. **Whether to lead with "AI" or with "no context switch."** The AI angle gets
   more PH traffic and more competition; the focus angle is more defensible and
   more true to the product. **Recommendation: lead with focus, let AI be the
   biggest feature under it.**
8. **Google's terms.** Google's terms don't permit automated access to Search.
   Get a legal read on running AI Mode in the user's session before charging for
   the product or answering the "is this allowed?" comment with confidence.
9. **In-app Google sign-in.** Google discourages sign-in inside embedded web
   views; Flyby offers it only as a labelled fallback. Keep it, or ship browser
   import only?
10. **Query history** — whether to build it (it's the most-requested kind of
    feature), on or off by default, and where it's stored.

---

## 18. Roadmap candidates

Not built. Do not put on the website as promises; useful for the "what's next"
paragraph of the PH comment and for replying to feature requests.

**High value, small effort**
- Query history with ↑/↓ recall (needs an explicit privacy decision)
- Seed the pill from the current text selection

**High value, larger effort**
- More AI providers: OpenAI, Claude, local models via Ollama
- Custom search engine with a `%s` template
- Bang-style prefixes to switch provider inline (`!g`, `!ai`)
- Per-query provider override without changing the default
- Localization (a String Catalog; every string is an English literal today)

**Infrastructure**
- Developer ID signing + notarization *(launch blocker)*
- One-click in-app update install (Sparkle or equivalent) — today the app only
  checks and hands over the install command
- Re-enable Chrome-family Google session import once builds are Developer ID
  signed and re-tested
- Homebrew cask
- Real app icon artwork *(placeholder ships today; drop-in `.icns` swap)*
