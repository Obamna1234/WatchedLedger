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
  - **Decided 2026-11-06:** Claude merges each PR itself once CI is green.
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

- Movies, Series, Books, Audiobooks, Podcasts, Games, Videos (each in its own tab). Games and Videos were added 2026-11-17 (Stage 7).
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

- **Changed 2026-11-18 (Stage 9, owner's choice "stupid simple"):** no add box or tabs at the top. Instead:
  - a **category button** at the top ("🎬 Movies ▾") that lists all categories with counts;
  - the **To Watch / Watched** switch, then a **Search** box and one **Sort & filter** button;
  - a big **Add** button that opens an add sheet (category chips, list switch, title or link, "Have a list? Paste it or import a file");
  - a labelled **bottom bar**: Lists, Folders, Pick, Stats, More (More holds import, backup, reminders, appearance, privacy).
- Original (replaced): text box at the top to add a title, with a selector for category and which list (To Watch / Watched).
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
  - ~~TMDB for movies and series~~ **Changed 2026-11-05 (owner's choice):** no account or API key. Movies come from iTunes Search, series from TVmaze.
  - Open Library (or Google Books) for books and audiobooks
  - iTunes Search API for podcasts
- Use whichever free, reliable options work best and explain the choice.
- If nothing is found (or I don't like the matches), I can keep typing in the "Did you mean…?" box. Then I can either search again or save exactly what I typed as free text.
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
| **1b Core lists complete** ✅ | Edit sheet (title, year, genre, rating, note, series S/E), swipe-left menu (edit/delete), sort & filter, genre fast-scroll bar, done styling |
| **2 Title lookup** ✅ | Single network gate (offline mode, HTTPS, host allowlist), TMDB/Open Library/Google Books/iTunes/TVmaze, "Did you mean…?", cover cache, match-later, full privacy page |
| **3 Search** ✅ | Highlight-all, up/down, "3 of 12", tick from results |
| **4 Import/export + protection** ✅ | Paste/txt/csv import, Samsung Notes helper, review screen, txt/csv/json export, encrypted backup/restore, app lock (PIN/biometric) |
| **5 Extras** ✅ | Smart "Pick something for me", "More by this director/author", stats, home-screen widgets, share-to-app, AltStore/SideStore source feed |
| **6 Tracking & sync** (added 2026-11-17) ✅ | Rewatch/reread diary, reading & listening progress with yearly goals, custom lists & tags, episode tracking with "new episode" reminders, phone-to-phone sync over home Wi-Fi |
| **7 Owner requests after 1.0** (2026-11-17) ✅ | 7a Games (+ Videos) tabs; 7b whole show / season / episode ticks for any series; 7c Samsung Notes `.sdocx` import (tick boxes + strikethrough), any text encoding, status headings, "Not sure" flag; 7d links (oEmbed), Wikidata fallback, open in YouTube/NewPipe/browser, fill-in-yourself path |
| **10 Release gate** (2026-11-19, owner's release checklist) | 10a databases saved by every past release opened by the tests; update-over-last-release test on Android API 24 + 34. 10b beta-first releases, "Release it" only after the owner's yes and green checks, security and privacy review file required per release, daily live lookup check, lookup sheet names sources that didn't answer. 10c on-device tests of the main features (Android API 24 + 34, iPhone simulator), required by "Release it" |
| **9 Simpler navigation** (2026-11-18) | Category button, bottom bar, Add sheet, clearer Folders (New folder, Watching with), picker defaults to everything, higher-contrast theme, import reads more layouts (status words, tables, more CSV columns) |
| **8 Extras picked by the owner** (2026-11-17) ✅ | 8a Recommended by, Watch with, Where to watch, Not out yet + release reminder, shareable folders; 8b Recently deleted (30 days), private items, select several, duplicate cleaner, backup reminder |

### 12a. Features added 2026-11-17 (owner's choice)

**Mobile data setting** (Stage 4)
- Settings → **Use mobile data**. There are three options:
  - **Wi-Fi only** (default)
  - **Wi-Fi + mobile data for lookups only** (a lookup is a few KB)
  - **Wi-Fi + mobile data** (lookups and covers)
- When the current option doesn't allow mobile data:
  - a title added on mobile data is saved as typed;
  - unmatched titles and missing covers are fetched automatically the next time the phone is on Wi-Fi.
- Offline mode still blocks everything.
- This needs the Android `ACCESS_NETWORK_STATE` permission (no prompt; it only tells the app whether it's on Wi-Fi). It is currently removed in the manifest and will be re-allowed for this.

**Import from other apps** (Stage 4)
- Read the export files from Letterboxd, Goodreads, Trakt and IMDb, which you download from each site yourself.
- Ratings, finished dates and reviews/notes carry over where the file has them.
- Everything goes through the same review screen as other imports.

**Rewatch / reread diary** (Stage 6)
- Each item can have several "finished" entries, each with a date, plus an optional rating and note per entry, like a Letterboxd diary.
- There's a diary view by month.
- Stats count every entry.

**Reading & listening progress, yearly goals** (Stage 6)
- **Books:** page (out of total) or %.
- **Audiobooks:** hours and minutes listened (out of total).
- **Yearly goals** per category (e.g. "24 books in 2027"), with progress shown on the Stats screen.

**Custom lists & tags** (Stage 6)
- Free-form tags on any item (e.g. "Halloween", "with Sam", "comfort rewatches").
- Filter by tag on every tab.
- Tags are included in exports and backups.

**Phone-to-phone sync over home Wi-Fi** (Stage 6)
- **As built (2026-11-17):** no lasting pairing. Each sync: one phone shows its home-network address and a one-time 8-character code; the other types them in. Argon2id + AES-256-GCM with that code (same format as backups), private addresses only, one sync or 5 minutes, 5 wrong tries ends it. Chosen over QR so no camera/barcode package is needed. The original plan is kept below for reference.
- **Pairing:** two phones pair once by scanning a QR code, which exchanges a secret key.
- **Syncing:**
  - While both apps are open on the same Wi-Fi, they find each other on the local network and exchange changes.
  - The connection is end-to-end encrypted, with no server or account.
- **Conflicts:** the most recent edit wins per item, and deletions sync too.
- **Permissions:** needs iOS "Local Network" permission and Android local-network access, asked only when sync is turned on.
- **Caveat:** this is the most complex feature and needs both phones. It is built last.

**Smart "Pick something for me"** (Stage 5)
- Picks at random from **your own To Watch list only**, entirely on the phone. It is not a recommendation engine: nothing is sent and nothing is profiled.
- **Filters:**
  - category
  - genre
  - length (e.g. "under 2 hours", "short book", "under 10 hours")
  - mood: "something light" = comedy, animation, family; "something tense" = thriller, horror, mystery; and similar mappings from genre
- **Length data:**
  - Running time, page count and audiobook length are saved during the normal lookup:
    - Wikipedia/iTunes for films
    - TVmaze for episode length
    - Open Library/Google Books for pages
    - iTunes for audiobook duration
  - This needs a new `runtimeMinutes` / `pages` column, added by a schema migration with a test.
  - Existing items are filled in the next time they are looked up.
- "Pick again" re-rolls the choice, and a picked item can be opened or ticked straight away.

**"More by this director / author"** (Stage 5)
- On an item's screen, a button lists other works by the same creator:
  - Wikipedia for directors
  - Open Library for authors
  - iTunes for podcast hosts and narrators
- Only the creator's name is sent; never your list or history.
- Any result can be added to To Watch in one tap.
- It is never automatic, and it is listed on the privacy page.

**Episode tracking + "new episode" reminders** (Stage 6)
- **Following:** follow a series and the app stores its TVmaze show ID.
- **Episode tracking:**
  - Tick individual episodes; the season/episode counters update from this.
  - The full episode list comes from TVmaze (`/shows/{id}/episodes`, no key).
- **Reminders:**
  - When the app is opened (and the network setting allows), it asks TVmaze for upcoming episodes of followed shows only.
  - It then schedules **local notifications** on the phone for those air dates.
  - There is no push server, no account and no device token. Reminders are set by the phone for itself and fire even if the app isn't opened again before the air date.
- **Opt-in:**
  - Off by default.
  - Notification permission is asked only when it is switched on.
  - Respects Offline mode and the mobile data setting.
- **Privacy page:** must state that TVmaze receives the IDs of followed shows (plus the phone's IP address, as with any request), at most about once a day.
- **Limitation:** if a show announces a surprise release date, it is only noticed the next time the app is opened.
- **New dependency** (decided when built): `flutter_local_notifications`, or a small native channel instead.

### 12b. Stage 7–8 notes (2026-11-17)
- **Headings** in imported notes set category and To Watch / Watched only. Genre words in headings are ignored for genre (the owner's headings aren't accurate genres); the lookup decides the genre.
- **Samsung Notes `.sdocx`:** a ZIP holding `note.note`. Body = u32 length + UTF-16LE text, then span records (strikethrough) and paragraph records (type-5 checkbox, ticked flag). Read with our own capped inflater (`zip_reader.dart`), max 60 MB file.
- **Folders** are tags. Sharing sends plain text (title + link per line, footer marking it as from WatchedLedger). Recipients need nothing; WatchedLedger recognises the footer and opens Import. Private items are never shared.
- **YouTube search** opens the YouTube/NewPipe app (no Google API key); the user shares the video back.
- **Personal names** never ship in the app; they only come from the user's data.

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
| Networking (stage 2) | Dart `http` (Dart team) behind one `NetClient` | Enforces offline mode, HTTPS-only, host allowlist, timeouts and size caps. |
| Images (stage 2) | Own small file cache | Avoids `cached_network_image`'s dependency tree. |
| Backups (stage 4) | `cryptography`: Argon2id → AES-256-GCM, `.wlbackup` file | Portable, password-protected. |
| Lock (stage 4) | `local_auth` (Flutter team) + PIN stored only as a PBKDF2-SHA256 hash (120,000 rounds, random salt) in Keystore/Keychain, never in the database or backups | 5 free tries, then a wait of 30 s doubling up to 1 h (survives restarts). Android needs `FlutterFragmentActivity`, an AppCompat launch theme and `androidx.appcompat`. "Hide in recent apps" = `FLAG_SECURE` on Android (via a tiny method channel), a cover screen on iOS. |
| Files (stage 4) | `file_picker` (system picker) | So no storage permission is needed. |
| Connection type (stage 4) | `connectivity_plus` | Tells Wi-Fi from mobile data for the "Use mobile data" setting (default Wi-Fi only). |
| Imports (stage 4) | Own parsers, no package | Plain lists / Samsung Notes (tick marks, strikethrough), WatchedLedger txt/csv, Letterboxd, Goodreads, IMDb, Trakt JSON and any CSV with a Title column. Max 5,000 rows, 10 MB. Everything goes through a review screen; duplicates start unticked. |
| Widgets / share (stage 5) | **No packages.** Android only: a native `AppWidgetProvider` (RemoteViews) fed through a `watchedledger/widget` method channel, and a `SEND text/plain` intent filter read through `watchedledger/share`. | iOS widgets and share sheets need extra Xcode targets and App Groups, which free sideloading (7-day signing, limited App IDs) handles badly. On iPhone: copy the text and paste it into Import. Widget titles are written to app-private storage only while a widget exists, never while the app lock is on. |
| Picker / stats (stage 5) | Plain Dart, on the phone | Mood = groups of genres; length = runtime (movies, audiobooks) or pages (books). Older items are a little more likely. |
| More by… (stage 5) | Same keyless services: Wikipedia "directed by" search, TVmaze crew credits, Open Library author search, iTunes `authorTerm` | Only the person's name is sent, only on tap. |
| Diary / tags / goals (stage 6) | `watch_events` table (one row per finish), tags as a JSON list on the item, goals in `settings_entries` (`goal_<category>_<year>`) | No schema change needed (v2 already had them). |
| Episodes + reminders (stage 6) | TVmaze `/shows/{id}/episodes`; `episode_marks`; native Kotlin (AlarmManager + boot receiver) and Swift (UNUserNotificationCenter) behind `watchedledger/reminders` | No package. Android: `POST_NOTIFICATIONS`, `RECEIVE_BOOT_COMPLETED`. |
| Sync (stage 6) | `dart:io` HttpServer on the Wi-Fi address + `NetClient.postLocal` (private IPv4 only); `mergeSync` (uid, newest `updatedAt`, tombstones, same-title items merged under the smaller uid) | iOS `NSLocalNetworkUsageDescription`. |
| Links (stage 7) | `url_launcher` (Flutter team) for opening links in YouTube/NewPipe/browser (`LaunchMode.externalApplication`, http(s) only); oEmbed (YouTube, Vimeo, TikTok, Dailymotion, Spotify, SoundCloud, Reddit) through `NetClient` for title + thumbnail | Facebook/Instagram oEmbed needs a Meta app token, so those links are saved with the typed title. |
| Samsung Notes (stage 7) | Own `.sdocx` reader, no package | ZIP inflate capped against zip bombs. |
| Safety (stage 8) | `trash` table (JSON copy of item + diary + episode ticks, purged after 30 days); `isPrivate` hidden via `AppLock.privateVisible`; duplicates by a loose title key + year within 1 | Nothing is ever deleted without passing through Recently deleted first. |
| AltStore source (stage 5) | Generated by release.yml, attached to every release | Stable URL: `releases/latest/download/altstore-source.json`. |

### Lookup sources (stage 2)
| Category | Primary | Fallback | Then |
|---|---|---|---|
| Movies | Wikipedia title search (typo-tolerant) | iTunes Search (`media=movie`) | Free text |
| Series | TVmaze | iTunes Search (`media=tvShow`) | Free text |
| Books | Open Library | Google Books (keyless) | Free text |
| Audiobooks | iTunes Search (`media=audiobook`) | Open Library | Free text |
| Podcasts | iTunes Search (`media=podcast`) | If no close match: Wikipedia fixes the spelling, then iTunes again | Wikidata, then free text |
| Games (stage 7) | Wikipedia (video game pages, typo-tolerant) | Wikidata | Free text / fill in yourself |
| Videos (stage 7) | Link oEmbed (no title search) | — | Free text / fill in yourself |

- **2026-11-17:** Wikidata `wbsearchentities` is the last fallback for every category, for niche titles.

- **2026-11-08 change:** Apple's iTunes Search no longer returns movies (verified by the live check: 0 results even for "Inception"), so movies now come from **Wikipedia**. Its title search fixes typos ("Inceptoin" → Inception), and its short descriptions give the year and director ("2010 film by Christopher Nolan"). The page summary gives the genre. Wikipedia rarely provides film posters (they aren't freely licensed), so most movies show the category icon instead of a poster.
- **Every source is keyless: no accounts, no API keys.** A TMDB key could be added later as an optional upgrade for movies, but only if the owner asks.
- **Auto-file:** a title is filed automatically when exactly one result matches the typed title (and year, if one was typed, e.g. "Dune 2021"). Anything ambiguous opens "Did you mean…?".
- **Unreachable lookup:** offline mode, lookups switched off or a network error mean the title is saved as typed (`unmatched`). It can be matched later from the Edit screen ("Look up details").
- **Genre mapping:** messy source genres are mapped onto the curated genre list for each category.
- **Network gate:** every request goes through one `NetClient`, which enforces:
  - offline mode
  - HTTPS only
  - a host allowlist, re-checked on every redirect
  - a 12-second timeout and response size caps
  - a generic `User-Agent: WatchedLedger`; no cookies are sent and nothing identifying is attached
- **Covers:** downloaded through the same gate, checked to really be an image (magic bytes), and cached in app storage. After that they show offline.

### Data model
- **`items`**:
  - id, category, status, title, sortTitle, matchKey, typedTitle, year
  - genre (one primary genre; drives grouping, user-changeable), extraGenres
  - creator, coverUrl, coverFile, source, sourceId, matchState
  - rating (1–5), note (≤200 chars), season, episode
  - addedAt, completedAt, updatedAt
  - v3 (stage 7–8): link, recommendedBy, watchWith (JSON list), whereToWatch, upcoming, releaseDate, isPrivate
- **`trash`** (v3): itemId, title, category, deletedAt, payload (JSON).
- **`episode_marks`**: episode number 0 means "whole season".
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
