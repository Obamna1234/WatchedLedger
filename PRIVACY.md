# Privacy

WatchedLedger is built so that your library is nobody's business but yours.

## Never collected

- No accounts or sign-in.
- No analytics, telemetry or usage statistics.
- No ads or advertising identifiers.
- No crash reporting.
- No third-party SDKs that send data anywhere.

## What leaves the device

**This version: nothing.** The current release makes no network requests.

**Once title lookup is added (Phase 3),** only the following will ever be sent. Each one happens only when you add or re-match a title, or when a cover is first displayed.

| What is sent | To whom | When |
|---|---|---|
| The title text you typed | TMDB (movies, series), Open Library or Google Books (books), iTunes Search (audiobooks, podcasts), TVmaze (series fallback) | When a title is looked up |
| A request for a cover image | The image servers of those same services | The first time a cover is shown. After that it is cached on the device. |

These requests carry nothing that identifies you:

- no account,
- no device ID,
- no list contents beyond the one title being looked up,
- no cookies.

Like any internet request, the service can see your IP address. All requests use HTTPS. Turning on **Offline mode** in Settings blocks every one of them.

## On the device

Your library is stored in a database file that is fully encrypted (SQLite3MultipleCiphers).

- The random 256-bit key is kept in the phone's secure hardware-backed storage: the Android Keystore or the iOS Keychain.
- The key is marked "this device only" and is never synced.

Device backups:

- **Android:** cloud backup and device-to-device transfer are switched off for this app.
- **iPhone:** an iCloud device backup could contain the encrypted file but never its key, so the backup can't be read.

Backups are encrypted files that you create yourself and save wherever you choose.

## Permissions

| Platform | Permission | Why |
|---|---|---|
| Android | `INTERNET` | Title lookup and covers. Offline mode switches this use off inside the app. |
| iOS | None yet | Face ID will be requested only if you turn on the optional app lock. |
