# Spec: Flyby on macOS 15 and 26 (Apple silicon)

## 1. Goal

Flyby requires macOS 27 today (`Package.swift`, `Resources/Info.plist`, CI).
Lower the minimum to **macOS 15 (Sequoia)**, still **Apple silicon only**.
Every Apple silicon Mac can run 15, 26 and 27, so this covers anyone on
Apple silicon who has updated at least once since late 2024.

Two features depend on a newer macOS than 15, and step down cleanly:

| | macOS 15.x | macOS 26.x | macOS 27+ |
| :--- | :--- | :--- | :--- |
| Google AI Mode, Gemini, Browser | Full | Full | Full |
| Screenshot / Screen Recording | Full | Full | Full |
| Conversation view, history (⌘Y), SQLite | Full | Full | Full |
| Hotkeys, slash commands, menu bar, updates | Full (see §5.1) | Full | Full |
| Look of the overlay and onboarding | Frosted fallback | **Liquid Glass** | Liquid Glass |
| Apple Intelligence | Off, with a note | Off, with a note | Full |

Out of scope: macOS 14, Intel, and Apple Intelligence on macOS 26 (see §2).

## 2. What the SDK actually requires

These facts come from building a copy of the package against the macOS 27 SDK
(Xcode 27.0) with lower deployment targets, not from memory:

- **Liquid Glass** (`Glass`, `.glassEffect`, `GlassEffectContainer`,
  `.glassEffectID`, `.buttonStyle(.glass/.glassProminent)`) is **macOS 26.0**,
  not 27. With the target set to 26, every glass call site compiles.
- **FoundationModels** is a macOS 26.0 framework, but Flyby's provider uses
  APIs that are **27.0**: `Transcript.Prompt(segments:contextOptions:)` and
  `ContextOptions`, `Transcript.Response(segments:)`, `LanguageModelError`, and
  `tokenCount(for:)` (26.4). With the target set to 26, only
  `AppleIntelligenceProvider.swift` fails. So Apple Intelligence is gated at 27;
  a separate macOS 26 code path is possible later but isn't part of this.
- **macOS 15 APIs** in use: `ScrollPosition` / `ScrollGeometry`
  (`UI/ConversationView.swift`) and `MeshGradient`
  (`Onboarding/OnboardingAura.swift`). They're why the minimum is 15, not 14:
  supporting 14 would mean rewriting the conversation view's scrolling.
- **Weak linking is automatic.** A probe package targeting macOS 15 that uses
  FoundationModels only inside `if #available` gets
  `LC_LOAD_WEAK_DYLIB …/FoundationModels`, with no linker flags. Don't add
  `-weak_framework` / `.unsafeFlags`; check it in CI instead (§4.1).
- **SF Symbols:** all 66 symbol names in `Sources/` exist on macOS 15.0
  (checked against the system's `name_availability.plist`), including
  `apple.intelligence`.

### Everything the compiler rejects at a macOS 15 target

A release (whole-module) build lists every error, 61 in 12 files:

| File | Lines | What |
| :--- | :--- | :--- |
| `AppleIntelligenceProvider.swift` | 42–206 | FoundationModels (26.0; some 26.4 and 27.0) |
| `Surface.swift` | 63, 69–71 | `.glassEffect`, `Glass` |
| `Surface.swift` | 129, 131 | `.buttonStyle(.glassProminent / .glass)` |
| `Surface.swift` | 146–153 | `.safeAreaBar`, `.scrollEdgeEffectStyle`, `.scrollEdgeEffectHidden` |
| `Surface.swift` | 258 | `GlassEffectContainer` |
| `FlybyRootView.swift` | 135, 143, 240 | `GlassEffectContainer`, `.glassEffectID` |
| `InputBar.swift` | 288 | `GlassEffectContainer` |
| `Onboarding/OnboardingComponents.swift` | 96, 100–101 | `.glassEffect`, `Glass` |
| `Onboarding/SetupSteps.swift` | 82 | `GlassEffectContainer` |
| `Onboarding/ScreenshotStep.swift` | 149, 151, 160 | `.buttonStyle(.glassProminent / .glass)` |
| `Onboarding/ShortcutSteps.swift` | 62 | `.transition(.symbolEffect(.drawOn))` |
| `OnboardingView.swift` | 200, 212 | `.buttonStyle(.glass / .glassProminent)` |
| `UI/AttachmentTray.swift` | 81 | `.buttonStyle(.glass)` |

`FlybyCore` builds at 15 unchanged. That list is the whole compile-time job.
Runtime differences the compiler can't see are in §5.

## 3. Changes

The rule throughout: **each glass primitive gets its fallback in one place**
(`Surface`, `PaneGlass`, `GlassGroup`, `flybyGlassButton`, `cardScrollEdges`),
and call sites go through those rather than growing `#available` checks.

### 3.1 Apple Intelligence, gated at macOS 27

`AppleIntelligenceProvider.swift`:

- Keep `AppleIntelligenceProvider` as the facade the rest of the app calls,
  with no availability annotation. Move everything that touches FoundationModels
  (sessions, transcript building, prewarm, streaming, the `warmSession` cache)
  into a private `@available(macOS 27.0, *)` enum in the same file. The cache
  has to move: a stored property can't be marked `@available`, and its type
  (`LanguageModelSession`) is 26+.
- Add a readiness case for this Mac's macOS being too old:

  ```swift
  /// macOS is older than 27, which Flyby's use of the model needs.
  case needsNewerMacOS
  ```

  Wording for `problem`: *"Apple Intelligence in Flyby needs macOS 27 or
  later. Gemini and Google AI Mode work on this Mac."*
- Facade methods check `#available(macOS 27.0, *)` first: `readiness` returns
  `.needsNewerMacOS`, `prewarm()` does nothing, `context(from:)` returns `[]`,
  and `stream` finishes with `AppleIntelligenceError(.needsNewerMacOS problem)`.
- `AppleIntelligenceError.explanation(for:)` (line 186): wrap the
  `LanguageModelError` and `SystemLanguageModel.Error` casts in
  `if #available(macOS 27.0, *)`.

`UI/AppleIntelligenceStatus.swift`: add `.needsNewerMacOS` to `tint` and
`symbol` (same as `.unsupported`: secondary, `xmark.circle.fill`). The
System Settings button already shows only for `.turnedOff`, so no change there.

**Keep Apple Intelligence in the provider list, disabled**, rather than
removing it on older macOS. Provider shortcuts are numbered by position in
`ProviderKind.allCases` (`InputBar.swift:178`), so removing a case would
renumber ⌘1–⌘4 between Macs. Add `ProviderKind.isAvailable` (false for
`.appleIntelligence` below 27) and use it at each place a provider is chosen:

- `ProviderMenu.swift:46`: item disabled, subtitle or tooltip "Needs macOS 27".
- `AppDelegate.swift:289` (⌘-digit switching): ignore the digit for an
  unavailable provider.
- `SettingsUI/AnswersPane.swift:18`: picker row disabled; the status line
  below already explains why.
- `Onboarding/SetupSteps.swift:90`: the tile shows the note and can't be
  picked.
- `Settings.swift:227`: a stored `appleIntelligence` on macOS below 27 (for
  example, settings migrated from another Mac) loads as `.browser`, the
  existing default.

### 3.2 Overlay glass: `Surface` (Surface.swift:26)

The Reduce Transparency branch is unchanged. The glass branch becomes
`if #available(macOS 26.0, *) { …today's code… } else { …fallback… }`, with
`glass` moved into a 26-only helper.

The fallback keeps the smoke gradient and rim, and puts a real blur of the
desktop behind them. **Use an `NSVisualEffectView`, not SwiftUI's
`.ultraThinMaterial`.** The overlay is a clear, borderless,
`.nonactivatingPanel` (`FlybyPanel.swift:27–36`). A SwiftUI material there
isn't guaranteed to blur what's behind the window or to stay in its active
look while Flyby isn't the active app. Add a small representable:

```swift
/// The desktop behind the panel, blurred — the frosted stand-in for Liquid
/// Glass before macOS 26.
struct BehindWindowBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
```

Place it as `.background { BehindWindowBlur().clipShape(shape).opacity(isVisible ? 1 : 0) }`
under the smoke fill. `interactive` has no equivalent below 26; ignore it.

**The bar → card morph should still animate.** It comes from the animated
`geometry.outline` shape and clip in `FlybyRootView.swift` (`surface`, around
line 221), not from `.glassEffectID`. There's only one glass element, so the
ID keeps its identity rather than morphing between two. Verify it on 15
(§5.2), especially the blob appearing and disappearing.

### 3.3 Glass containers and IDs

- `GlassGroup` (Surface.swift:248): below 26, return `content` unchanged.
  Don't wrap it in an `HStack`: `GlassEffectContainer`'s `spacing` is how
  close shapes must be to merge, not layout spacing, and callers already lay
  out their own content (e.g. `UI/AttentionBanner.swift:37`).
- Replace the raw `GlassEffectContainer`s with `GlassGroup`:
  `FlybyRootView.swift:135, 143`, `InputBar.swift:288` (`spacing: 2`),
  `Onboarding/SetupSteps.swift:82` (`spacing: 12`). Don't add a second wrapper
  type; `GlassGroup` is the wrapper.
- `.glassEffectID` (FlybyRootView.swift:240): an `extension View` helper,
  `flybyGlassEffectID(_:in:)`, that applies it on 26+ and is a no-op below.

### 3.4 Buttons

`flybyGlassButton(prominent:)` (Surface.swift:127) already exists. Below 26
it uses `.borderedProminent` / `.bordered`. Route the raw styles through it:

- `OnboardingView.swift:200` (`.glass`), `:212` (`.glassProminent`)
- `Onboarding/ScreenshotStep.swift:149, 160` (`.glassProminent`), `:151` (`.glass`)
- `UI/AttachmentTray.swift:81` (`.glass`)

### 3.5 Card scroll edges (Surface.swift:144)

`cardScrollEdges(reachesInput:)`: below 26, use
`.safeAreaInset(edge:spacing:)` with the same clear spacers in place of
`.safeAreaBar`, and skip `.scrollEdgeEffectStyle` / `.scrollEdgeEffectHidden`.
Keep the `CardEdgeFade` mask. It already fades content under the corner
buttons and the input, which is most of what the soft edge effect adds.

### 3.6 Onboarding

- `PaneGlass` (Onboarding/OnboardingComponents.swift:67): below 26,
  `.background { shape.fill(.regularMaterial); if let tint { shape.fill(tint) } }`
  plus a `.separator` hairline. The walkthrough is an ordinary window over
  its own aura, so a SwiftUI material is fine here.
- `ShortcutSteps.swift:62`: below 26, `.transition(.scale.combined(with: .opacity))`
  in place of `.symbolEffect(.drawOn)`.

## 4. Build, CI and docs

### 4.1 Configuration

- `Package.swift`: `platforms: [.macOS(.v15)]`. Rewrite the header comment,
  which says 27 is required because glass and FoundationModels "are the
  product".
- `Resources/Info.plist`: `LSMinimumSystemVersion` → `15.0`.
- `build.sh`: keep the SDK ≥ 27 check (building still needs Xcode 27 and its
  SDK; only the deployment target drops). Update the comments and error text
  that say Flyby targets macOS 27. The SDK re-stamping step (lines 128–139)
  still applies and needs no change.
- `.github/workflows/ci.yml:70–73`: check `minos 15.0` instead of `minos 27`,
  and add a weak-link assertion:

  ```bash
  otool -l build/Flyby.app/Contents/MacOS/Flyby \
    | grep -B2 'FoundationModels' | grep -q LC_LOAD_WEAK_DYLIB
  ```

  Tests can keep running on the macOS 27 runner.
- `.github/workflows/release.yml`: add the same `minos` / weak-link checks
  next to the existing `lipo` check (line 107).
- `README.md` (lines 13, 62, 84, 111, 172): requirement becomes macOS 15 on
  Apple silicon; Apple Intelligence and Liquid Glass are noted as macOS 27
  and macOS 26 respectively.

### 4.2 Updates

Existing 0.6.x users are all on 27, so an update can't strand anyone. Check
that whatever serves updates (`Sources/Flyby/Updates`) doesn't carry its own
minimum-macOS gate that would need the same change.

## 5. Runtime risks: verify on real macOS 15

The compiler can't catch these.

### 5.1 Option-only hot keys

All three defaults are Option-only combos: `⌥Space`, the `⌥/` fallback, and
`⌥⇧Space` for screenshots (`Shortcut.swift:24–30`). macOS 15 changed which
Option-only combos `RegisterEventHotKey` accepts. Test registration on 15.0
and on the latest 15.x. If it's refused, the user already sees the reason
(`HotKeyMonitor.swift:142` → `ShortcutProblemNote`), but the out-of-box
experience would be broken. We'd then need macOS-15 defaults that include
⌃ or ⌘, which is a product decision.

### 5.2 How the overlay looks and moves

- The frosted fallback blurs the desktop, stays in its active look while
  another app is frontmost, and reads as dark over a white wallpaper.
- The bar → card morph, the blob's appear/disappear, and Reduce Motion's
  crossfade all animate.
- Reduce Transparency and Increase Contrast still take their existing paths.

### 5.3 Liquid Glass on macOS 26

Flyby's glass has only been seen on 27. Built with the 27 SDK, it should
render on 26 with 26's version of the material. Look over the bar, card,
pills and onboarding for anything that relied on 27 behavior.

### 5.4 Permissions and deep links

- The Screen Recording onboarding step: first-time prompt, the
  `ScreenCapture.openSettings()` deep link, and relaunch after granting.
  macOS 15 also re-confirms screen recording periodically, so check how the
  screenshot shortcut behaves when that prompt appears.
- The System Settings URLs Flyby opens resolve to the right panes on 15.

### 5.5 Web features

AI Mode streaming and sign-in in WebKit on macOS 15, whose WebKit is older than 27's, and
cookie import from Safari, Chrome and Firefox.

## 6. How to test

Test in macOS virtual machines on an Apple silicon Mac (UTM or Tart; both run
macOS 15 and 26 guests from Apple's restore images). Use the latest 15.x and
26.x, plus 15.0 for the hot-key check in §5.1. Install a Flyby Dev build from a
feature branch; CI's ad-hoc build is fine too.

## 7. Acceptance criteria

1. `./build.sh` succeeds with Xcode 27; `swift test` passes on macOS 27.
2. The binary's `LC_BUILD_VERSION` has `minos 15.0`, `lipo -archs` is
   `arm64`, and FoundationModels is `LC_LOAD_WEAK_DYLIB` (enforced in CI and
   release).
3. **macOS 27:** nothing changes, including glass, Apple Intelligence, and
   provider numbering.
4. **macOS 26:** Liquid Glass everywhere. Apple Intelligence is listed but
   disabled, with the "needs macOS 27" note, and can't be chosen from the
   menu, ⌘-digits, Settings or onboarding.
5. **macOS 15:** launches without crashing; onboarding completes; the overlay
   and onboarding use the frosted fallback; Browser, AI Mode, Gemini,
   screenshots, history and follow-ups work; Apple Intelligence is as on 26.
6. Every item in §5 checked off on a real macOS 15 system, with any failures
   fixed or filed.
