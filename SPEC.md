# WatchedLedger – Project Spec

Private media tracker app for Android and iPhone, built and distributed through GitHub only.

This file is the source of truth for the project. If a request conflicts with it, flag the conflict and ask before changing anything.

---

## 1. Goal

A private, secure, notepad-style app for tracking movies, series, books, audiobooks and podcasts I've watched, read or listened to, plus what I want to get to next.

It replaces my current Samsung Notes checklist, which is slow and tedious (tap box, strikethrough, scroll forever).

## 2. Distribution

- Personal project distributed via GitHub only. Not published to the Play Store or App Store.
- Repo name: `watchedledger`.
- Explain whether a private or public repo makes more sense, including GitHub Actions free-minute limits (macOS runners use more minutes).
- **Decided: public repo** (`Obamna1234/WatchedLedger`). Public repos get unmetered Actions minutes, including macOS. A private repo on the free plan gets 2,000 minutes a month, and each macOS minute counts as 10, so you'd get roughly 15–20 iOS builds a month. Nothing secret lives in the code, because keys stay in GitHub Secrets or on the device.

## 2a. How we work (Claude automates the process)

- Claude has access to the GitHub repo and does the work end to end: creates and edits all files, commits, pushes, and sets up the build workflows. I don't write code or upload files by hand.
- Work on a branch per stage and open a pull request with a plain-language summary of what changed and how to test it. I review and merge (or tell Claude to merge).
- Use clear commit messages. Never commit secrets, keystores, API keys or personal data.
- Things only I can do (Claude must give me exact step-by-step instructions when needed):
  - adding GitHub Secrets (signing keystore, API keys)
  - signing up for lookup API keys (e.g. TMDB)
  - installing builds on my phone
- After each stage, check that the GitHub Actions build passes. If it fails, read the logs, fix it and push again before reporting back.
- Claude keeps `SPEC.md`, `PROGRESS.md` and `CLAUDE.md` in the repo up to date itself. If we agree on a change to the plan, update `SPEC.md` in the same pull request and note the decision in `PROGRESS.md`.

## 3. Tech & build

- Flutter, so one codebase builds both Android and iOS.
- Local database only (e.g. Drift/SQLite or Isar). No cloud backend.
- GitHub Actions workflows that build automatically on every push/tag:
  - a signed release Android APK, attached to a GitHub Release
  - an unsigned iOS `.ipa` on a macOS runner, for sideloading
- Signing keys and API keys stored as GitHub Secrets, never committed to the repo.
- Explain the free ways to install the iOS build without a paid Apple Developer account (e.g. AltStore or SideStore with 7-day re-signing) and what each requires.
- README with build, install and update steps for both platforms.

## 4. Privacy & security (top priority, non-negotiable)

- No accounts, no analytics, no ads, no crash-reporting or tracking SDKs.
- All data stays on the device. No cloud sync by default; backups are files I control and save wherever I choose.
- The only data that leaves the device is the title text sent to lookup services, plus cover image downloads. Nothing identifying.
- Offline mode toggle that disables all network access entirely.
- In-app privacy page stating exactly what leaves the device and when.
- Minimum permissions only. HTTPS only. Code obfuscation/minification enabled.
- Validate and sanitise all pasted text, imported files and API responses.
- Optional app lock: PIN or fingerprint/Face ID.
- Keep dependencies minimal and flag any with known vulnerabilities.

## 5. Categories

- Movies, Series, Books, Audiobooks, Podcasts (each in its own tab).
- Items grouped automatically by genre within each tab.
- Each item shows a cover/poster thumbnail, title and release year, for quick visual checks.
- Cover images are cached locally after first download so they work offline.

## 6. Two lists per category

- "To Watch" (To Read / To Listen) and "Watched" (completed).
- Each item has a tick box. Ticking moves it from To Watch to Watched under the correct category and genre, shown visually as done (strikethrough or faded). Unticking moves it back.
- Swipe right on an item to tick it; swipe left to edit or delete.
- Undo snackbar after any tick, move or delete.
- Auto-save the date an item was ticked ("Watched March 2026").
- Optional personal star rating and a one-line note per item.
- Series progress: track which season/episode I'm up to.

## 7. Main screen

- Text box at the top to add a title, with a selector for category and which list (To Watch / Watched).
- Scrollable list below, grouped by genre, with a fast-scroll bar on the side.
- Sort and filter by genre, release year, date added, date watched, rating or A–Z.
- Duplicate warning if I add something already on any list.

## 8. Search

- Works like Samsung Notes / a PDF viewer: type a word and every match is highlighted in the list.
- Up/down arrows to jump between matches, with a "3 of 12" counter.
- Can tick an item straight from a search result.

## 9. Smart title lookup

- When I add a title, look it up to confirm the correct name, year, genre and cover image, then file it automatically.
- If misspelled or ambiguous, show a "Did you mean…?" list with cover, title and year to pick from.
- Sources:
  - TMDB for movies and series
  - Open Library (or Google Books) for books and audiobooks
  - iTunes Search API for podcasts
- Use whichever free, reliable options work best and explain the choice.
- If a source returns nothing, try a fallback source, then let me save the title manually.
- If offline or lookups are disabled, save the title as typed and let me match it later.

## 10. Import & export

- Paste a large block of text (one title per line) to bulk import.
- Import `.txt` and `.csv` files.
- Samsung Notes helper: paste my existing checklist and detect which items were already ticked/crossed off, putting them in Watched.
- All imports go through the lookup, then a review screen where I confirm matches, fix mistakes and skip duplicates before saving.
- Export to `.txt`, `.csv` and `.json`.
- Encrypted, password-protected backup file I can save anywhere and restore.

## 11. Extras

- "Pick something for me" random picker from my To Watch list, with an optional category/genre filter.
- Stats screen: totals per year, top genres, books read this year, etc.
- Home screen widget (Android and iOS) showing the next few To Watch items and a quick-add button.
- Share-to-app: share a link or text from Netflix, IMDb, Goodreads, a podcast app or a browser into WatchedLedger and it adds the title automatically.
- Light mode, dark mode and an AMOLED pure-black theme.

## 12. Build order

1. Core lists and local database
2. Title lookup
3. Search
4. Import and export
5. Extras
6. GitHub Actions workflows for both platforms (can be set up early so every stage produces a test build)

Agreed staging. Workflows were built first, so every stage produces installable builds.

| Stage | Contents |
|---|---|
| **1a Foundation** ✅ | Encrypted database, tabs, To Watch/Watched, quick add, duplicate warning, tick/swipe/undo, themes, CI + release workflows, README/PRIVACY/SECURITY |
| **1b Core lists complete** ✅ (awaiting CI) | Edit sheet (title, year, genre, rating, note, series S/E), swipe-left menu (edit/delete), sort & filter, genre fast-scroll bar, done styling |
| **2 Title lookup** | Single network gate (offline mode, HTTPS, host allowlist), TMDB/Open Library/Google Books/iTunes/TVmaze, "Did you mean…?", cover cache, match-later, full privacy page |
| **3 Search** | Highlight-all, up/down, "3 of 12", tick from results |
| **4 Import/export + protection** | Paste/txt/csv import, Samsung Notes helper, review screen, txt/csv/json export, encrypted backup/restore, app lock (PIN/biometric) |
| **5 Extras** | Random picker, stats, home-screen widgets, share-to-app, AltStore/SideStore source feed |

---

## 13. Technical design (agreed — keep in sync with the code)

### Stack
| Area | Choice | Why |
|---|---|---|
| Framework | Flutter stable **3.47.x**, Dart ≥ 3.10 | One codebase. CI pins `3.47.x`. |
| Database | **Drift 2.35 + sqlite3 3.x** | Typed, relational, with safe migrations. Isar was rejected: the original is unmaintained, and its fork has almost no users. |
| Encryption at rest | **SQLite3MultipleCiphers** (`hooks: user_defines: sqlite3: source: sqlite3mc`) | Drift's recommended replacement for SQLCipher. The 256-bit random key lives in `flutter_secure_storage` (Android Keystore; iOS Keychain set to `first_unlock_this_device`). The app refuses to run without cipher support. |
| State | Plain Flutter (`InheritedWidget` `AppScope`, `ChangeNotifier`) | No Riverpod. Fewer dependencies. |
| Settings | Stored in the encrypted database (`settings_entries` table) | No shared_preferences. |
| Networking (stage 2) | Dart `http` behind one `NetClient` | Enforces offline mode, HTTPS-only, host allowlist, timeouts and size caps. |
| Images (stage 2) | Own small file cache | Avoids `cached_network_image`'s dependency tree. |
| Backups (stage 4) | `cryptography`: Argon2id → AES-256-GCM, `.wlbackup` file | Portable, password-protected. |
| Lock (stage 4) | `local_auth` + PIN stored only as a slow hash | |
| Files (stage 4) | `file_picker` (system picker) | So no storage permission is needed. |
| Widgets / share (stage 5) | `home_widget`, `share_handler` + native Kotlin/SwiftUI | |

### Lookup sources (stage 2)
| Category | Primary | Fallback | Then |
|---|---|---|---|
| Movies | TMDB | iTunes Search (`media=movie`) | Manual |
| Series | TMDB | TVmaze | Manual |
| Books | Open Library | Google Books (keyless) | Manual |
| Audiobooks | iTunes Search (`media=audiobook`) | Open Library | Manual |
| Podcasts | iTunes Search (`media=podcast`) | — | Manual |

- The TMDB key is **pasted into the app's settings by the owner**, so it is never baked into the published APK.
- The TMDB attribution notice is shown on the About/Privacy page.
- Messy source genres are mapped onto a curated genre list per category.

### Data model
- **`items`**:
  - id, category, status, title, sortTitle, matchKey, typedTitle, year
  - genre (one primary genre; drives grouping, user-changeable), extraGenres
  - creator, coverUrl, coverFile, source, sourceId, matchState
  - rating (1–5), note (≤200 chars), season, episode
  - addedAt, completedAt, updatedAt
- Enums are stored by index. **Only ever append to them.**
- **Duplicate detection** uses `matchKey`: lower-case, accents folded, punctuation and spaces removed, leading The/A/An dropped. So "Spider-Man" = "spiderman".
- **Podcasts** are tracked as whole shows. The note field can hold "up to ep. 140".
- **Series progress** is simple season/episode counters.

### Platform hardening
- **Android:**
  - Permission `INTERNET` only. Tracking permissions are explicitly removed in the manifest.
  - `allowBackup=false` plus data-extraction rules that exclude everything.
  - Cleartext disabled; system CAs only.
  - R8 minify + shrink resources; Dart `--obfuscate`; Google's dependency-metadata block is excluded from the APK.
  - minSdk 24.
- **iOS:**
  - App Transport Security left strict.
  - No usage strings until a feature needs them (Face ID arrives in stage 4).
  - Bundle id `app.watchedledger`, display name "WatchedLedger".
- **Lost key:** if the database key is missing or wrong (e.g. the iPhone app was re-signed with a different Apple ID), a recovery screen appears. "Start fresh" renames the old file and never deletes it.

### Build & release (GitHub Actions)
- Platform folders are **not fully committed**. Only customised files are (Android manifest, Gradle, network/backup XML, MainActivity; iOS Info.plist). `tool/bootstrap.sh` runs `flutter create` (which fills in missing files and never overwrites), then `pub get` and `build_runner`.
- **`build.yml`** is a reusable workflow with five jobs:
  - version
  - OSV dependency scan (checksum-verified scanner)
  - Android: analyze, test, signed APK, prints the cert SHA-256
  - iOS: unsigned IPA on `macos-latest`
  - debug-symbol artifacts
- **`ci.yml`** runs on every branch push and every PR; the APK and IPA come out as artifacts kept 14 days.
- **`release.yml`** runs on tag `vX.Y.Z` and publishes a GitHub Release with the APK, IPA and `SHA256SUMS.txt`. It refuses to publish without the signing key.
- Build number = minutes since the epoch, so it always increases and Android always accepts the update.
- All Actions are pinned to commit SHAs. Dependabot runs weekly for pub and Actions.
- **Secrets:** `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`.

### iOS install without a paid account
- Free Apple ID limits: 7-day signing, 3 active apps, 10 App IDs per 7 days. The widget and share extension each add an App ID.
- **SideStore** needs a computer once, plus LocalDevVPN; it refreshes on the phone. **AltStore Classic** needs AltServer on a Mac/PC, on the same Wi-Fi weekly. **Sideloadly** needs a Mac/PC and refreshes manually.
- Always re-sign with the **same Apple ID**. The Keychain key is tied to it.
- Risk: sideloaders rewrite App Group identifiers, so the iOS widget and share extension (stage 5) may need workarounds.

### Defaults adopted (owner may change)
- Each push builds test artifacts; only a version tag creates a Release.
- One primary genre per item.
- Encrypted database on.
- Podcasts are tracked as whole shows.
- Series progress uses simple S/E counters.

### Tooling note for Claude
Claude's cloud workspace **cannot download Flutter or pub packages** (Google's servers are blocked), so GitHub Actions is the compiler. Verify APIs against source checkouts of the Flutter SDK and packages, which come from GitHub. Expect to fix CI failures from logs.
