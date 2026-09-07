# Xana Token Monitor

Xana Token Monitor is a macOS menu bar app for viewing usage and quota information from several AI providers in one place. It keeps a local history of quota snapshots and can expose the latest snapshot through the macOS widget.

## Current status

The first public release targets macOS 14 or later. The project also contains shared Swift package code and platform targets, but the supported release workflow currently focuses on the macOS menu bar app.

Supported integrations currently exposed by the UI:

- OpenAI API organization usage (requires an OpenAI Admin API key).
- OpenAI Codex local ChatGPT usage (requires the Codex CLI to be installed and signed in with ChatGPT on this Mac).
- Kimi for Coding quota.
- ZhipuAI quota.
- Anthropic and Xiaomi MiMo quota monitoring is temporarily disabled until real quota integrations are implemented.

This app is a usage viewer. It does not send prompts or provide a model client.

## Privacy and credential handling

- API keys are stored in the macOS Keychain, not in the saved provider configuration.
- The app sends authenticated usage requests only when refreshing the provider selected by the user. The destination is the provider endpoint configured in the app.
- The Codex integration starts the local `codex app-server` process. Codex manages its own ChatGPT authentication and network requests; this app reads the returned account, rate-limit, and usage data and does not store Codex tokens.
- Quota history is stored locally at `~/Library/Application Support/XanaTokenMonitor/quota-history.json`.
- The widget receives provider display names and quota snapshots through the app group. API keys and authentication tokens are not included in the widget data.
- There is currently no analytics, advertising, or telemetry service in this project.

For the full data-handling description, see [PRIVACY.md](PRIVACY.md).

## Install a release

Download the macOS `.zip` from the repository's [Releases](https://github.com/xanahopper/XanaTokenMonitor/releases) page, unzip it, and move `XanaTokenMonitorMacOS.app` to `/Applications`.

The Codex provider is optional. To use it, install the Codex CLI and sign in with ChatGPT before adding the provider in the app. Other providers require their own API key or account access.

## Build from source

Requirements:

- macOS 14 or later.
- Xcode 16 or later.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen), if the Xcode project needs to be regenerated from `project.yml`.

```sh
swift test
xcodebuild -project XanaTokenMonitor.xcodeproj \
  -scheme XanaTokenMonitorMacOS \
  -sdk macosx \
  -configuration Debug \
  build
```

For a distributable build, use a Developer ID signed and notarized archive. Development builds may be unsigned and can trigger a macOS security warning.

## Uninstall

1. Remove `XanaTokenMonitorMacOS.app` from `/Applications`.
2. Remove providers from the app before uninstalling when possible; this deletes their API keys from the Keychain.
3. To remove local quota history, delete `~/Library/Application Support/XanaTokenMonitor`.
4. If necessary, use Keychain Access to remove generic-password items for the service `com.xana.XanaTokenMonitor.api-keys`.
5. Remove the widget from Notification Center and optionally delete the app-group data at `~/Library/Group Containers/group.com.xana.token-monitor`.

## License and trademarks

The original source code is released under the [MIT License](LICENSE). Provider names, logos, and other third-party marks remain the property of their respective owners. The MIT License does not grant rights to third-party trademarks or assets.

## Security

Please see [SECURITY.md](SECURITY.md) for reporting instructions.
