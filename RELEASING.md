# Building and releasing Flyby

Flyby has two builds. All work happens in **Flyby Dev**; **Flyby** is what
people install, and each version of it is built once and frozen.

| | Dev | Release |
| --- | --- | --- |
| Made by | `./build.sh` · `./run.sh` | `./release.sh <version>` |
| App | `build/Flyby Dev.app`, and every build kept in `dev-builds/<version>/` | `releases/<version>/Flyby.app` → `/Applications/Flyby.app` |
| Bundle ID | `com.fringecore.flyby.dev` | `com.fringecore.flyby` |
| Version | from git: `0.3.0-dev.14 · pill` | exactly what you pass: `0.3.0`, `0.4.0-beta.1` |
| Architectures | arm64 | arm64 — macOS 27 doesn't run on Intel Macs |
| Icon / badge | amber icon, **DEV** badge | blue icon, no badge |
| Updates | off — rebuild instead | checks GitHub, offers the install command |

Different bundle IDs mean separate settings, Keychain entries (the Gemini key),
Google session, open-at-login registration and Screen Recording grant. The two run
side by side, and nothing you do in Flyby Dev can touch the installed release.

## Day to day

```sh
./run.sh                 # build Flyby Dev and launch it
CONF=debug ./build.sh    # unoptimized, for lldb
swift test               # FlybyCore unit tests
./scripts/dev-signing.sh # once per Mac: a local certificate for dev builds
```

With the certificate, Flyby Dev keeps its Screen Recording (and Full Disk
Access) grants across rebuilds; ad-hoc signed, it loses them every
time. Only dev builds on that Mac use it — CI and releases are unaffected.

Building needs Xcode 27 (`build.sh` uses it even when `xcode-select` points at
the Command Line Tools, which can't build macOS 27 SwiftUI). For a bare
`swift test`, prefix `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

Every push runs CI on a macOS 27 runner with Xcode 27: unit tests, the dev
build, and an Apple silicon release-flavor build. Both apps are attached to the
run as artifacts (`Flyby-Dev`, `Flyby-release-ci`) if you want to try a build
without compiling.

**Branches:** `main` only ever holds released or releasable code. Work happens
on `dev` (or `feature/<name>` branches merged into `dev`); when `dev` is ready,
merge it into `main` and release from `main`.

## Cutting a release

1. **Pick the version.** `x.y.z` for a public release, `x.y.z-beta.n` for a
   beta. Versions are never reused.
2. **Freeze it** from a clean checkout of `main`:

   ```sh
   ./release.sh 0.3.0
   ```

   This builds the release flavor into `releases/0.3.0/` — the app,
   `Flyby.zip`, `source.tar.gz` (exactly what was built) and `COMMIT` — and
   installs it into `/Applications` (`INSTALL=0` to skip). It refuses to run
   with uncommitted changes or to overwrite an existing version.
3. **Try the installed build.** It's what everyone will get.
4. **Publish it:**

   ```sh
   ./publish.sh 0.3.0 notes.md
   ```

   This checks the release was built from `HEAD`, tags `v0.3.0`, pushes the
   tag, and creates the GitHub release with `Flyby.zip` attached — a
   pre-release for `-beta` versions, the repo's **Latest** for plain ones. It
   then confirms the zip is really attached, because `install.sh` and the
   in-app updater both depend on it. Needs the GitHub CLI (`brew install gh`,
   `gh auth login`).

### Not on GitHub

Releases are made on the Mac that has the release certificate (see Signing,
below). `.github/workflows/release.yml` still runs on every `v*` tag, but only
to check: on the tag `publish.sh` pushes it finds the release already there and
stops, successfully; anywhere else — another tag, or Actions › Release › Run
workflow — it refuses, because a build there would be ad-hoc and everyone would
grant Flyby's permissions again. Its old build-and-publish steps are kept for
if the certificate is ever given to it as a secret.

People install or update with the one-liner from the README:

```sh
curl -fsSL https://raw.githubusercontent.com/emonsaqibh/flyby/main/install.sh | bash
```

It picks the newest stable release (`… | bash -s -- --beta` includes betas;
`… | bash -s -- 0.3.0` pins a version), installs it without the quarantine flag
and opens it. Installed releases check for updates every six hours and hand the
user the same command.

## Signing and notarization

macOS keys Flyby's privacy grants — Screen Recording, and Full Disk Access
for Safari import — to its code signature. An ad-hoc signature is different on every
build, so up to 0.5.1 every update was a new app to macOS and people granted
everything again. From 0.5.2, releases are signed with a self-signed
**"Flyby Release Signing"** certificate: each release's signature names that
certificate, the next one signed with it matches, and the grants stay. Nobody
has to trust the certificate for that, and the installer's `codesign --verify`
accepts it.

- **Once, on the Mac releases are made on:** `./scripts/release-signing.sh`
  (one password prompt, to trust it for code signing there). `build.sh` signs
  release builds with it from then on, and `release.sh` refuses to release
  without it — `ALLOW_ADHOC=1` for a throwaway local build.
- **Back it up**: Keychain Access › login › My Certificates ›
  "Flyby Release Signing" › File › Export Items… as a password-protected
  `.p12`. Releasing from another Mac means importing that. Lose it and the
  next release is a new app to macOS again: everyone grants once more.

It's still not notarized. That's why the installer is a curl script: a zip
downloaded in a browser is quarantined, and macOS 15+ won't open an
un-notarized quarantined app without a trip to System Settings.

Once you have a Developer ID certificate:

```sh
export SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
export NOTARY_PROFILE=flyby   # xcrun notarytool store-credentials flyby …
./release.sh 1.0.0
```

`build.sh` then signs with the hardened runtime and a secure timestamp, and
`release.sh` notarizes and staples the app, then makes a drag-to-Applications
DMG (`scripts/package-dmg.sh`) and notarizes that too. `publish.sh` attaches
the DMG alongside the zip. At that point a normal download link works as well.
