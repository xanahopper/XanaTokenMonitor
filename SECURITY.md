# Security Policy

## Reporting a vulnerability

Please do not open a public issue containing credentials, access tokens, private keys, or a reproducible exploit that could affect users.

Use GitHub's private vulnerability reporting feature if it is enabled for this repository. Otherwise, contact the repository owner through a private GitHub channel and include:

- A short description of the issue.
- Affected version or commit.
- Reproduction steps or a minimal proof of concept.
- Any suggested mitigation.

Please redact all secrets from reports and rotate credentials that may have been exposed.

## Credential safety

Do not commit API keys, Codex authentication files, certificates, provisioning profiles, or notarization credentials. Use the macOS Keychain for local provider credentials and GitHub Actions secrets for future release automation.
