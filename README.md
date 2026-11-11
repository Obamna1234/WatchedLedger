# WatchedLedger

A private, offline-first tracker for the movies, series, books, audiobooks and
podcasts you've finished, and the ones you want to get to next. It runs on
Android and iPhone, and it's built and distributed only through this GitHub
repo.

- **No accounts, no analytics, no ads, no tracking SDKs.**
- Your library lives in an **encrypted database on your phone**.
- See [PRIVACY.md](PRIVACY.md) for exactly what leaves the device, and when.

> **Status: Stage 3 (search).**
> - **Works now:**
>   - five category tabs with To Watch / Watched lists
>   - ticking (tap or swipe) with undo
>   - an edit screen with rating, note and series progress
>   - sort, filter and a genre fast-scroll index
> - **Smart add:** type a title and it's looked up automatically. It needs no accounts or API keys, and if nothing fits, you can save exactly what you typed.
> - **Search:** every match is highlighted, ▲ ▼ jump between them with a "3 of 12" counter, and you can tick straight from the results.
> - **Coming next:** import/export, backups, app lock, stats, widgets and share-to-app.

---

## Installing

Every release is on the [Releases page](../../releases). Each one has:

| File | For |
|---|---|
| `WatchedLedger-x.y.z.apk` | Android (signed) |
| `WatchedLedger-x.y.z.ipa` | iPhone (unsigned, for sideloading) |
| `SHA256SUMS.txt` | Checksums, so you can verify the downloads |

### Android

1. Open the latest release on your phone and tap the `.apk` file.
2. The first time, Android asks you to allow installs from your browser or file manager ("Install unknown apps"). Allow it for that one app, then install.
3. **To update:** install the newer `.apk` over the top. Your data is kept.
   - This works because every release is signed with the same key.
   - Android refuses an update signed with a different key, which is why the signing key must never be lost (see [Signing key](#android-signing-key)).

> APKs from the **Actions** tab (built on every push) are test builds.
> - They are signed with the release key only if the secrets are set up.
> - Otherwise they use a throwaway debug key and **won't install over a release build**.

### iPhone (free Apple ID, no paid developer account)

The `.ipa` is unsigned. A sideloading tool signs it with your own Apple ID. Apple's rules for free Apple IDs apply to every tool:

- **Apps expire after 7 days** unless refreshed (re-signed). Your data is *not* lost when an app expires. The app just won't open until it's refreshed.
- **At most 3 sideloaded apps** can be active at once. The sideloading tool counts as one of them.
- **At most 10 new App IDs per 7 days.**
  - WatchedLedger uses 1 today.
  - It will use about 3 once the home-screen widget and share extension arrive.

Pick one tool:

| Tool | What you need | How refreshing works | Good if… |
|---|---|---|---|
| **[SideStore](https://sidestore.io)** | A computer for the one-time setup, plus the free **LocalDevVPN** app from the App Store | Refreshes on the phone itself, in the background or with a tap. The VPN lets the phone sign apps without a computer. | You don't want to depend on a computer every week. |
| **[AltStore Classic](https://altstore.io)** | **AltServer** running on a Mac or Windows PC | AltServer refreshes the apps whenever the phone and computer are on the same Wi-Fi (at least once a week). | Your computer is usually on at home. |
| **[Sideloadly](https://sideloadly.io)** | A Mac or Windows PC | Manual: re-install from the computer before 7 days are up. Not open source. | You only want a quick test install. |

**Installing with SideStore or AltStore:**

1. Set up the tool by following its official guide.
2. On the iPhone, download the `.ipa` from the release page.
3. Open SideStore/AltStore and go to **My Apps → +**. Pick the `.ipa`.
4. If iOS asks, go to **Settings → General → VPN & Device Management**, tap your Apple ID, and tap **Trust**.
5. On iOS 16 or later, also turn on **Settings → Privacy & Security → Developer Mode** and restart.

**Updating:** install the new `.ipa` the same way, with the **same Apple ID**. It replaces the old app and keeps your data.

> ⚠️ **Always use the same Apple ID.**
> - The key that unlocks your encrypted library is stored in the iOS Keychain under your Apple ID's signing team.
> - If you re-sign with a *different* Apple ID, the app can't read its key. It will show a recovery screen (your data isn't deleted).
> - Re-installing with the original Apple ID fixes it.
> - Make regular backups once that feature arrives.

---

## How builds work

| Trigger | What happens |
|---|---|
| Push to any branch | `CI` workflow: analyze → test → dependency scan → build the APK and IPA. Download them from the run's **Artifacts** (kept 14 days). |
| New `version:` in `pubspec.yaml` lands on `main` (or a `vX.Y.Z` tag is pushed) | `Release` workflow: the same build with the real signing key required, then a tag and a GitHub Release with the APK, the IPA and checksums. |

This repo is **public**, so GitHub Actions minutes are free and unmetered, including the macOS runner the iOS build needs. In a private repo on the free plan, each macOS minute uses up 10 of the 2,000 free monthly minutes.

### Making a release

Change `version:` in `pubspec.yaml` (for example `0.1.0+1` → `0.2.0+1`) and merge that into `main`. The **Release** workflow notices the new version, then builds, signs, tags `v0.2.0` and publishes the GitHub Release automatically. Pushing a `vX.Y.Z` tag by hand also works.

The version name comes from `pubspec.yaml` (or the tag). The build number comes from the build time, so it always goes up, and Android accepts each new APK as an update.

### Security checks in CI

- **OSV-Scanner** checks every resolved package (`pubspec.lock`) against the OSV vulnerability database.
  - A release can't be published if a known vulnerability is found.
  - The downloaded scanner binary is verified against its published checksum.
- **Dependabot** opens weekly pull requests for outdated packages and Actions.
- Every third-party Action is pinned to a full commit SHA.
- Release builds use R8 code shrinking (Android) and Dart `--obfuscate` (both platforms).
  - The symbol files needed to read crash traces are uploaded as private workflow artifacts, never shipped in the app.

---

## One-time setup

### Android signing key

1. **Create a key.** You need a Java JDK for `keytool`. Do this on your own computer, never on a shared machine:

   ```bash
   keytool -genkeypair -v -keystore watchedledger-release.jks \
     -alias watchedledger -keyalg RSA -keysize 4096 -validity 36500
   ```

   Pick a strong password and use the same one when asked for the key password.

2. **Back it up.** Store the `.jks` file and its password in your password manager *and* one offline place. If you lose it, you can't update the installed app: you'd have to uninstall, which wipes its data, and reinstall.

3. **Add four repository secrets.** Go to **Settings → Secrets and variables → Actions → New repository secret**:

   | Secret | Value |
   |---|---|
   | `ANDROID_KEYSTORE_BASE64` | The output of `base64 -w0 watchedledger-release.jks` (macOS: `base64 -i watchedledger-release.jks`) |
   | `ANDROID_KEYSTORE_PASSWORD` | The keystore password |
   | `ANDROID_KEY_ALIAS` | `watchedledger` |
   | `ANDROID_KEY_PASSWORD` | The key password |

4. **Never commit the `.jks` file.** `.gitignore` already blocks `*.jks`, `*.keystore` and `key.properties`.

Each build prints the APK's signing-certificate SHA-256 in the run summary. Note it down after your first release so you can spot a wrongly signed build.

### Lookup services

Nothing to set up: every lookup service is free and needs no account or key.

| Category | Looked up with |
|---|---|
| Movies | Wikipedia, then iTunes |
| Series | TVmaze, then iTunes |
| Books | Open Library, then Google Books |
| Audiobooks | iTunes, then Open Library |
| Podcasts | iTunes (Wikipedia helps with misspelled names) |

See [PRIVACY.md](PRIVACY.md) for exactly what is sent.

---

## Building it yourself

The repo commits only the platform files it customises:

- **Android:** signing, permissions, network security, backup rules.
- **iOS:** `Info.plist`.

`tool/bootstrap.sh` fills in the rest of the standard Flutter boilerplate and generates the database code.

```bash
# Requires Flutter 3.47 (stable) and, for iOS, Xcode on a Mac.
git clone https://github.com/Obamna1234/WatchedLedger.git
cd WatchedLedger
bash tool/bootstrap.sh          # flutter create (missing files only) + pub get + build_runner
flutter test
flutter run                     # on a connected phone or emulator
```

To build a signed release APK locally, set the signing variables first:

```bash
export WL_KEYSTORE_PATH=/path/to/watchedledger-release.jks
export WL_KEYSTORE_PASSWORD=... WL_KEY_ALIAS=watchedledger WL_KEY_PASSWORD=...
flutter build apk --release --obfuscate --split-debug-info=build/debug-info
```

---

## Project layout

```
lib/
  core/        sanitising, theme, settings, app-wide scope
  data/
    db/        Drift tables + encrypted open/recovery
    models.dart
  features/    home, add, lists, settings, privacy, recovery
test/          sanitiser, database and widget tests
tool/          bootstrap script
.github/       CI, release and Dependabot config
```

## Tech choices

| Area | Choice | Why |
|---|---|---|
| UI | Flutter | One codebase for Android and iOS. |
| Database | Drift on SQLite | Typed queries and safe migrations. |
| Encryption at rest | SQLite3MultipleCiphers | The whole database file is encrypted. The 256-bit key is random and kept in Keystore/Keychain. |
| State | Flutter's own `InheritedWidget` / `ChangeNotifier` | No extra state-management package. |
| Runtime dependencies | 6 in total: `drift`, `sqlite3`, `path`, `path_provider`, `flutter_secure_storage`, `http` | Kept deliberately few. |
