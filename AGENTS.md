# Agent instructions

## Project scope

Xana Token Monitor is a Swift macOS menu bar app with a shared Swift package and a macOS widget extension. The supported public release target is `XanaTokenMonitorMacOS` on macOS 14 or later.

The main macOS app intentionally does not use App Sandbox. It starts the locally installed Codex CLI and reads the user's local Codex state. Do not add the App Sandbox entitlement to the main target unless the architecture is deliberately redesigned.

## Requirements

- macOS 14 or later
- Xcode 16 or later
- Swift toolchain provided by Xcode
- XcodeGen only when `project.yml` has changed and the generated Xcode project needs regeneration

The main macOS target is `XanaTokenMonitorMacOS` in `XanaTokenMonitor.xcodeproj`.

## Verification before changes or release

Run the package tests first:

```sh
swift test
```

Build the macOS app without relying on a local signing identity:

```sh
xcodebuild \
  -project XanaTokenMonitor.xcodeproj \
  -scheme XanaTokenMonitorMacOS \
  -sdk macosx \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build
```

For a local Release app, use a repository-local ignored build directory:

```sh
xcodebuild \
  -project XanaTokenMonitor.xcodeproj \
  -scheme XanaTokenMonitorMacOS \
  -sdk macosx \
  -configuration Release \
  -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build
```

The resulting app is normally at:

```text
build/DerivedData/Build/Products/Release/XanaTokenMonitorMacOS.app
```

The Codex integration test is opt-in because it starts the local Codex app-server and may use the user's existing ChatGPT session:

```sh
RUN_CODEX_INTEGRATION_TEST=1 swift test --filter testCodexProviderFetchesLocalUsage
```

Run that test only when the user has asked for a live Codex integration check. It requires `codex` to be installed and signed in locally. Do not print, copy, or store Codex authentication data.

## Local deployment and launch

After a successful local Release build, install the app with:

```sh
ditto --rsrc \
  build/DerivedData/Build/Products/Release/XanaTokenMonitorMacOS.app \
  /Applications/XanaTokenMonitorMacOS.app
```

If writing to `/Applications` requires authorization, ask the user before using elevated privileges. Do not recursively delete an existing app automatically. If the app is running, ask before quitting it or replacing it.

Launch the installed app with:

```sh
open -a /Applications/XanaTokenMonitorMacOS.app
```

The app stores provider API keys in the macOS Keychain. It stores quota history locally under `~/Library/Application Support/XanaTokenMonitor/quota-history.json`. The widget uses the app group `group.com.xana.token-monitor`; widget data must not contain API keys or authentication tokens.

The Codex provider looks for the CLI at `/opt/homebrew/bin/codex`, `/usr/local/bin/codex`, or a matching executable on `PATH`. It invokes `codex app-server --stdio` and reads account, rate-limit, and usage responses.

## Credentials and privacy

Never commit or include in build artifacts:

- Real API keys, bearer tokens, passwords, or cookies
- Codex authentication files or the contents of `~/.codex`
- Apple Developer certificates, private keys, `.p12`, `.p8`, provisioning profiles, or notarization credentials
- Local Keychain values or quota history
- Environment files such as `.env`

Fixture values used by unit tests are not credentials and must never be replaced with real credentials. Keep security scans focused on actual secret-shaped values and inspect changes before committing:

```sh
git status --short
git diff --check
git grep -n -I -E 'BEGIN (RSA|EC|OPENSSH|PRIVATE) KEY|sk-[A-Za-z0-9_-]{20,}|ghp_[A-Za-z0-9]{20,}|xox[baprs]-[A-Za-z0-9-]+'
```

Do not weaken Keychain storage or add telemetry merely to make a test or build pass.

## Signing and distribution

The repository currently supports unsigned local builds. Do not invent a Team ID or signing identity. A formal public macOS binary requires an installed `Developer ID Application` certificate, Hardened Runtime, and Apple notarization. A `.pkg` installer additionally needs `Developer ID Installer`; a drag-and-drop `.app` distributed in a ZIP or DMG does not.

Before a signed release, verify the identity with:

```sh
security find-identity -v -p codesigning
```

Only use an identity whose name starts with `Developer ID Application:`. Sign and notarize all release executables, validate with `codesign` and `spctl`, and attach SHA-256 checksums to the GitHub Release. Never put signing material in the repository.

## Git and publishing

- Preserve unrelated user changes.
- Do not use destructive commands such as `git reset --hard` or broad recursive deletion.
- Do not push or create a GitHub Release unless the user has explicitly requested publication in the current workflow.
- Before publication, confirm that tests pass, the release artifact contains no secrets, and the release notes accurately describe signing status and permissions.
- The configured GitHub remote is `git@github.com:xanahopper/XanaTokenMonitor.git`.
