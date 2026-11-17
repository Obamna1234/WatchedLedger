# Privacy

WatchedLedger is built so that your library is nobody's business but yours.

## Never collected

- No accounts or sign-in.
- No analytics, telemetry or usage statistics.
- No ads or advertising identifiers.
- No crash reporting.
- No third-party SDKs that send data anywhere.

## What leaves the device

Only these things are ever sent. Each is sent only while **"Look up titles automatically"** is on and **Offline mode** is off:

| What is sent | To whom | When |
|---|---|---|
| The title text you typed | **Movies:** Wikipedia (Wikimedia Foundation), then iTunes. **Series:** TVmaze, then iTunes if TVmaze finds nothing. **Books:** Open Library (Internet Archive), then Google Books.  **Games:** Wikipedia. **Audiobooks:** iTunes, then Open Library. **Podcasts:** iTunes; Wikipedia only if the name looks misspelled. | When you add a title, import a list (one title at a time), or tap **Look up details** on the Edit screen |
| A person's name (director, author or host) | **Movies:** Wikipedia. **Series:** TVmaze. **Books:** Open Library. **Audiobooks and podcasts:** iTunes. | Only when you tap **More by…** on the Edit screen |
| The TVmaze number of a show | TVmaze | When you open a show's **Episodes** screen, and, only if **New episode reminders** is on, about once a day for the shows you **follow** |
| A link you paste or share into the app | The site it points to, at its public oEmbed address: YouTube, Vimeo, TikTok, Dailymotion, Spotify, SoundCloud or Reddit. Facebook, Instagram and other sites are **not** contacted. | When you add a link, to get its title and thumbnail |
| The title you type (last resort) | Wikidata (Wikimedia Foundation) | Only when the main services find nothing |
| A request for a cover image | Those services' image servers (`*.mzstatic.com`, `static.tvmaze.com`, `covers.openlibrary.org` → `*.archive.org`, `books.google.com`, `upload.wikimedia.org`) | The first time a cover is shown. After that it is cached on the device. |

**Mobile data:** by default nothing is fetched on mobile data (**Settings → Use mobile data → Wi-Fi only**). Titles added on mobile data are saved as typed and looked up automatically once the phone is back on Wi-Fi. You can allow lookups only, or everything, on mobile data.

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

**Home screen widget (Android, optional):** if you add it, the titles it shows are kept in the app's private storage (outside the encrypted database) so the widget can draw them. Remove the widget and they're deleted. While the app lock is on, the widget shows only "Locked".

**Phone-to-phone sync (optional):** only when you start it, and only on your home network. One phone shows a one-time code; everything sent between the phones is encrypted with it (Argon2id + AES-256-GCM). It talks only to private network addresses (192.168.x.x, 10.x.x.x, 172.16–31.x.x), never the internet, and stops listening after one sync or 5 minutes. Offline mode blocks it too.

**Episode reminders (optional, off by default):** the phone schedules its own notifications for the air dates. There is no push server, account or device token. On a locked screen the notification only says "New episode".

**App lock (optional):** your PIN is stored only as a salted hash (PBKDF2) in the phone's secure storage, never in the database or in backups.

## Permissions

| Platform | Permission | Why |
|---|---|---|
| Android | `INTERNET` | Title lookup and covers. Offline mode switches this use off inside the app. |
| Android | `ACCESS_NETWORK_STATE` | To tell Wi-Fi from mobile data for the "Use mobile data" setting. It only reads the connection type; no prompt. |
| Android | `POST_NOTIFICATIONS` | Only for "new episode" reminders, asked when you switch them on. |
| Android | `RECEIVE_BOOT_COMPLETED` | Puts reminders back after the phone restarts. |
| Android | `USE_BIOMETRIC` | Only used if you turn on fingerprint unlock for the app lock. The fingerprint never reaches the app; Android just says yes or no. |
| iOS | Local Network | Asked the first time you sync with another phone. |
| iOS | Notifications | Asked only when you switch on "new episode" reminders. |
| iOS | Face ID | Asked only if you turn on Face ID for the app lock. The app only learns yes or no. |
