# Privacy

Last updated: 2026-09-07

Xana Token Monitor is designed as a local-first usage viewer. It does not operate a hosted service and does not include analytics, advertising, or telemetry code.

## What the app handles

The app may handle:

- Provider names and optional account labels entered by the user.
- API keys entered for supported API providers.
- Usage, quota, reset-time, plan, and account metadata returned by those providers.
- Locally generated timestamps and quota history used by the charts and widgets.

## Where data goes

When the user adds or refreshes a provider, the app sends an authenticated usage request to that provider's configured endpoint. The provider's own privacy policy and terms apply to those requests.

The Codex integration starts the locally installed Codex CLI app server. Codex performs its own ChatGPT authentication and network communication. Xana Token Monitor receives the app-server response needed to display account and quota information; it does not request, export, or persist the Codex access or refresh token.

The app does not send provider data to Xana Token Monitor servers because this project does not operate such a server.

## Local storage

- API keys are stored in the macOS Keychain under the service `com.xana.XanaTokenMonitor.api-keys`.
- Provider configuration and display names are stored in the app's local preferences without API keys.
- Quota history is stored in `~/Library/Application Support/XanaTokenMonitor/quota-history.json`.
- The macOS widget reads the latest provider names and quota snapshot from the app group `group.com.xana.token-monitor`. This snapshot does not contain API keys.

Older development versions stored API keys in the provider preferences. The current code can migrate those legacy values to the Keychain and rewrites the saved configuration without the key when the migration succeeds. Users should still rotate any credential that may have been exposed by an old development build.

## User control

Users can remove a provider in the app. This removes its corresponding Keychain entry and local history. Uninstalling the app alone does not necessarily remove Keychain items; see the uninstall instructions in [README.md](README.md).

## Changes

Material changes to this document will be recorded in the repository history.
