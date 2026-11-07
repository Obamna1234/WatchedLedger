# Privacy

WatchedLedger is built so that your library is nobody's business but yours.

## Never collected

- No accounts or sign-in.
- No analytics, telemetry or usage statistics.
- No ads or advertising identifiers.
- No crash reporting.
- No third-party SDKs that send data anywhere.

## What leaves the device

Only two things are ever sent. Each is sent only while **"Look up titles automatically"** is on and **Offline mode** is off:

| What is sent | To whom | When |
|---|---|---|
| The title text you typed | **Movies:** Wikipedia (Wikimedia Foundation), then iTunes. **Series:** TVmaze, then iTunes if TVmaze finds nothing. **Books:** Open Library (Internet Archive), then Google Books. **Audiobooks:** iTunes, then Open Library. **Podcasts:** iTunes; Wikipedia only if the name looks misspelled. | When you add a title, or tap **Look up details** on the Edit screen |
| A request for a cover image | Those services' image servers (`*.mzstatic.com`, `static.tvmaze.com`, `covers.openlibrary.org` → `*.archive.org`, `books.google.com`, `upload.wikimedia.org`) | The first time a cover is shown. After that it is cached on the device. |

These requests carry nothing that identifies you:

- no account or API key (every service is used keyless),
- no device ID,
- no list contents beyond the one title being looked up,
- no cookies.

The app identifies itself only as `WatchedLedger`. Like any internet request, the service can see your IP address.

All traffic goes through one gate in the code (`NetClient`), which:

- refuses everything while Offline mode is on;
- only allows HTTPS to the hosts listed above, and checks every redirect again;
- limits time and size, so a misbehaving server can't hang the app or flood it.

Everything a service sends back is cleaned and checked before it is stored. A cover is only saved if the file really is an image.

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
