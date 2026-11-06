# Security

## Reporting a problem

Please use GitHub's **private vulnerability reporting**: Security tab → *Report a vulnerability*. Don't open a public issue.

## Design summary

- **Data at rest**
  - The database is encrypted with SQLite3MultipleCiphers using a random 256-bit key held in the Android Keystore or iOS Keychain (this device only).
  - The app refuses to start rather than fall back to an unencrypted database.
- **Network**
  - HTTPS only. Android trusts only the system certificate authorities (user-installed CAs are ignored).
  - iOS keeps App Transport Security at its strict default.
  - All future network access goes through one gate that enforces Offline mode.
- **Input handling**
  - All text is cleaned before it is stored: typed, pasted, imported, shared-in, or received from lookup APIs.
  - Cleaning strips control characters, zero-width characters and bidirectional-override characters, and caps the length.
- **Permissions:** the minimum needed. See [PRIVACY.md](PRIVACY.md).
- **Backups:** Android system backup is disabled. Your own backups will be encrypted with a password you choose (Argon2id + AES-256-GCM).
- **Build**
  - R8 shrinking and Dart obfuscation for release builds.
  - Signing keys exist only as GitHub Secrets and are deleted from the runner after use.
- **Supply chain**
  - Few dependencies, all from the Dart/Flutter teams or the established Drift and secure-storage maintainers.
  - OSV-Scanner runs on every build and blocks releases with known vulnerabilities.
  - Dependabot raises weekly update PRs.
  - GitHub Actions are pinned to commit SHAs.

## Known limits

- Obfuscation slows down reverse engineering. It does not prevent it. Nothing secret is shipped inside the app, so there is nothing to extract.
- iOS builds are unsigned until you sideload them, and your sideloading tool signs them with your own Apple ID.
