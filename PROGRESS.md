# WatchedLedger – Progress

Maintained by Claude. Updated at the end of every stage, in the same pull request as the work.

## Status
**Stages 1 and 2 are merged into `main`** (PRs #1–#3, 2026-11-06).
**Stage 3 (search) is merged** (PR #4, 2026-11-06): analyzer clean, 48 tests passing.
**Stage 4 (import/export and protection) is merged** (2026-11-17) and released as **v0.2.0**.
**Stage 5 (extras) is merged** (2026-11-17) and released as **v0.3.0**.
**Stage 6 (tracking and sync) is merged** (2026-11-17) and released as **v1.0.0**.
**Stages 7 and 8 (your requests after 1.0) are merged** (2026-11-17) and released as **v1.1.0**.
**Stage 9 (simpler navigation) is merged** (2026-11-18) and released as **v1.2.0**.
**Stage 10 (release checklist) is merged** (2026-11-19). **v1.3.0 is out as a beta**; it becomes the normal release when you say "release it".

## Done
- **Proposal:** structure, packages and tech choices, written up in SPEC.md §13.
- **Stage 1a, foundation:**
  - **Encryption:** the Drift database is encrypted with SQLite3MultipleCiphers, and its key is kept in Keystore/Keychain.
  - **Lost key:** a recovery screen appears if the database key is missing or wrong.
  - **Lists:** five category tabs, each with To Watch / Watched lists.
  - **Adding:** a quick-add bar with a category and list selector, plus a duplicate warning that checks across all lists.
  - **Ticking and deleting:** tap the box or swipe right to tick or untick; completion dates are stamped ("Watched March 2026"). Swipe left to delete. All of these have Undo.
  - **Grouping:** items are grouped by genre, with a scrollbar.
  - **Themes and settings:** light, dark and AMOLED black. The offline-mode setting is stored but has nothing to block yet. A first privacy page.
  - **Android hardening:** INTERNET is the only permission; system backup is off; HTTPS only; R8 minify and obfuscation.
  - **Workflows:** CI on every push, Release on `v*` tags, OSV scan, Dependabot, Actions pinned to SHAs.
  - **Docs:** README (install, update and build steps for both platforms), PRIVACY.md, SECURITY.md.
  - **Tests:** sanitiser, database and recovery-screen tests.

- **Stage 1b, core lists complete:**
  - **Edit screen:** tap any item. You can change the title, category, list, year, genre (typed, or picked from a list), director/author/host, 1–5 star rating, a one-line note, and the finished date. Series also get season/episode counters.
  - **Swipe left** opens an Edit / Delete menu.
  - **Undo** works after saving an edit, after moving an item between categories or lists, and after deleting.
  - **Sort:** A–Z, release year, date added, date finished or rating, with a reverse option and grouping by genre on or off.
  - **Filter:** by genre, minimum rating, release-year range, year added, and year finished (Watched list only). A banner shows "showing X of Y".
  - **Fast-scroll index** down the right edge: genres, letters, decades, years or ratings depending on the sort. Drag along it to jump; a bubble shows where you are.
  - **Item rows** show year · creator · S/E progress · stars · finished date · note.
  - **Tests:** sorting, filtering and sectioning.

- **Stage 2, title lookup:**
  - **Smart add:** a title is looked up when you add it, using keyless services only: iTunes for movies, audiobooks and podcasts; TVmaze for series; Open Library and Google Books for books. If a source finds nothing, the next one is tried.
  - **Auto-file:** if exactly one result matches what you typed, it's filed automatically with the proper name, year, genre, creator and cover. Typing a year ("Dune 2021") picks the right version.
  - **"Did you mean…?":** shown when there are several matches or none. It lists results with cover, title and year. You can keep typing and search again, or save exactly what you typed as free text.
  - **No connection:** if offline, if lookups are switched off, or if the network fails, the title is saved as typed. It can be matched later with **Edit → Look up details**.
  - **Covers:** downloaded once, checked to really be images, and stored on the phone, so they show offline.
  - **Network gate:** one place in the code makes every request. It enforces Offline mode, HTTPS only and an allowlist of hosts (checked on redirects too), with time and size limits, a generic app name and no cookies.
  - **Settings:** a new "Look up titles automatically" switch.
  - **Privacy:** the privacy page and PRIVACY.md now list exactly which service gets what, and when.
  - **Undo** after adding a title.
  - **Tests:** network gate, each service's parsing (including malformed and hostile data), fallback, auto-file rules and genre mapping.

- **Stage 3, search:**
  - **Search bar:** tap 🔍 at the top. Every match in the visible list is highlighted as you type, ignoring capitals and accents ("amelie" finds "Amélie"). It searches titles, director/author/host and notes.
  - **Jumping:** ▲ / ▼ (or Enter) jump between matches, with a "3 of 12" counter. The list scrolls so the current match is in the middle, shaded.
  - **Tick from results:** tick, swipe and edit all work straight from the results, and the counter keeps up as items move.
  - **"Also in" chips:** these show matches in your other lists and tabs ("Watched · 2", "Books › To Read · 1"). Tap one to jump there.
  - **Back button** closes search.
  - **Tests:** matching (accents, emoji), highlighting and counter logic.

- **Misspelling test (2026-11-08):**
  - **Live check:** a new "Live lookup check" workflow sends correct and misspelled titles to the real services every week and whenever lookup code changes. It writes a results table to the run's page.
  - **Bug it found:** Apple's iTunes returns no movies at all any more. Movies now come from Wikipedia, which fixes typos ("Inceptoin" → Inception, "The Godfathr" → The Godfather) and gives year, director and genre.
  - **Podcast typos** ("Hardcore Histroy") are now fixed via Wikipedia, then looked up on iTunes.
  - **Screen test:** the add box and "Did you mean…?" sheet are now tested end to end: pick the fix, retype and search again, save as typed, exact match filed automatically, offline sends nothing.

- **Stage 4, import/export and protection:**
  - **Use mobile data** setting, **Wi-Fi only by default**. Titles added on mobile data or offline are saved as typed and looked up automatically back on Wi-Fi.
  - **Import** (Settings → Import, export and backup → Import titles): paste a list or pick a .txt / .csv / .json file. Understands Samsung Notes-style ticks and crossed-out lines, and the export files from **Letterboxd, Goodreads, IMDb and Trakt** (ratings, dates read/watched, authors, pages, tags).
  - **Review screen:** every title is looked up one at a time, then you check the list: fix a match, switch To Watch / Watched, change category, skip. Duplicates start unticked.
  - **Export** to .txt, .csv or .json (spreadsheet cells are guarded against formula tricks).
  - **Encrypted backup and restore:** password-protected file (Argon2id + AES-256), saved wherever you choose. Restore can merge or replace.
  - **App lock (optional):** PIN, plus fingerprint / Face ID if you want. Locks immediately or after 1/5/15 minutes away. Waits get longer after 5 wrong tries. "Hide in recent apps" blanks the app switcher (and blocks screenshots on Android).
  - Database upgraded to version 2, ready for Stage 6 (existing data kept; migration tested).

- **Stage 5, extras:**
  - **Pick something for me** (🎲): from your own lists, with category, mood, length and genre filters. Doesn't repeat itself; older items come up a bit more.
  - **Stats** (📊): per category, month and year, top genres, average rating, pages read, hours watched/listened.
  - **More by…** on the Edit screen: other work by the same director, author or host, with one-tap add. Only the name is sent.
  - **Share to the app (Android):** share from Netflix, IMDb, Goodreads, a podcast app or a browser. The title is read from the shared text, looked up, and you confirm.
  - **Home screen widget (Android):** "Up next" with your newest 5 titles and a + button. It says "Locked" while the app lock is on.
  - **App icon** and an **AltStore/SideStore source** so iPhone updates show up in those apps.
  - Book lookups now save page counts.

- **Stage 6, tracking and sync:**
  - **Diary:** every finish is an entry (date, optional rating and note). "Watched again / Read again" on the Edit screen; a month-by-month Diary screen (📊 → Diary); stats count every entry. Older finished items got their entry automatically.
  - **Tags:** add any tags on the Edit screen (suggests ones you've used); filter by tag on every tab; included in exports, backups and sync.
  - **Progress:** books (page of total, or %), audiobooks (h:mm of total), shown on the To Read / To Listen rows.
  - **Yearly goals** per category on the Stats screen.
  - **Episodes:** for series matched with TVmaze, tick episodes one by one (or a whole season, or "everything up to here"); S/E counters follow.
  - **New episode reminders** (off by default): follow a show, switch reminders on in Settings, and the phone schedules a notification for each upcoming air date. TVmaze only sees the followed shows' numbers, about once a day.
  - **Sync two phones** on home Wi-Fi: one shows an address and a one-time code, the other types them in. Encrypted end to end; newest edit wins; deletions sync.

- **Final pass (2026-11-17):** Claude re-checked the riskier new code. It found and fixed one bug: Undo after ticking or unticking now keeps the diary right, and there's a test for it. The 30-second demo video was re-recorded with the new features.

- **Stage 7, games, seasons, Samsung Notes and links:**
  - **Games tab** (To Play / Played) for every console, looked up on Wikipedia with "Did you mean…?" for typos. **Videos tab** for YouTube, Facebook, Instagram, TikTok and other clips.
  - **Seasons:** for any series, tick the whole show, whole seasons or single episodes (Edit → Seasons & episodes). Works even when the show isn't on TVmaze.
  - **Samsung Notes files:** import the .sdocx file itself (Samsung Notes: ⋮ → Save as file → Samsung Notes file). Ticked boxes and crossed-out lines are read from the file. Headings like "Watched" or "To watch" set the list; the genre words in headings only group the review screen. Anything the app isn't sure about is marked "Not sure" so you can check it, and each heading has "All watched / All to watch" buttons.
  - **Any text file** (UTF-8, UTF-16, with or without BOM) can be imported; binary files are refused.
  - **Niche titles:** Wikidata is now the last fallback for every category. Paste or share a link from YouTube, Vimeo, TikTok, Dailymotion, Spotify, SoundCloud or Reddit and the title and thumbnail are filled in; other social links (Facebook, Instagram, X…) are saved to Videos. "Not listed? Fill in the details yourself" opens the editor with tap-to-choose presets.
  - **Open links** in the YouTube, NewPipe or browser app (▶ on the row). "Search YouTube" opens the YouTube or NewPipe app; share the video back to add it.
- **Stage 8, extras you picked:**
  - Recommended by, Watch with and Where to watch on every item, with filters.
  - **Not out yet** with a release date, shown at the top, and a reminder on the day.
  - **Folders you can share:** a plain message with titles and links (the other person doesn't need the app; if they have it, they can import the folder).
  - **Recently deleted** (30 days), **private items** (hidden behind the app lock PIN), **select several** (long-press), **find duplicates** (Settings) and a monthly **backup reminder**.

- **Stage 9, simpler to use (2026-11-18):**
  - One **category button** at the top replaces the seven tabs; tap it to switch (it shows how much is in each).
  - **Bottom bar with labels:** Lists, Folders, Pick, Stats, More. Settings, import and backup live under More.
  - **Big Add button:** pick the category with one tap, To Watch or Watched, type a title or paste a link. "Have a list?" goes straight to Import.
  - **Folders:** a "New folder" button, then tick what goes in it. "Watching with" groups everything you plan to watch with one person.
  - **Pick** now chooses from everything by default, keeps mood/length/genre tucked away, and says why when there's nothing to pick.
  - **Easier to read:** bolder titles, higher contrast, coloured bands for each genre group.
  - **Import** also understands "Title - watched", "Title (seen)", "Title - to watch", table rows with a ✓, and spreadsheet columns like "Movie", "Seen?" or "Date read".

- **Stage 10, release gate (from your release checklist, 2026-11-19):**
  - **10a, your data:** a database saved by every past version (0.1.0 to 1.2.0) is kept in the tests and opened by each new version. A new **update test** installs the new version over the last release on Android emulators (oldest supported and newest), and checks nothing is lost and the encryption key still works.
  - **10b, releases:** new versions go out as a **beta** first. They become the normal release only when you say "release it", and only if every check on that exact build passed. Each release needs a written security and privacy review first. The real-lookup check now runs every day. When a lookup service doesn't answer, the app names it.

  - **10c, on real devices:** the main features are tested on the built app on Android emulators (oldest supported and newest) and an iPhone simulator. That covers adding, ticking and Undo in every category, saving as typed when offline, search, importing a pasted list, sharing into the app, the app lock (including a wrong PIN) and "Hide in recent apps". Backup files, exports and the home screen widget are covered by the regular tests, because a test can't use the phone's file picker.
  - **What the device tests caught (fixed):** the PIN lock screen's OK and Delete buttons couldn't appear (they need a layer the lock screen didn't have), so a PIN couldn't be submitted. This was already in 1.2.0. A package update published on 18 November would also have stopped new Android builds from opening the library. That package is now pinned to the version 1.2.0 used.

- **Security and privacy review for 1.3.0** (`docs/reviews/v1.3.0.md`, by a separate reviewer): nothing medium or worse. The four small findings were fixed anyway:
  - the database key can never appear in an error message or log;
  - "Release it" only works from main;
  - betas are never treated as the last release;
  - the demo video's speed setting only accepts a number.

## Next
- The 1.3.0 beta: try it, then say "release it".
- Ideas for later, only if you want them: QR pairing for sync, iPhone widget and share sheet (needs a paid Apple account to be practical), more lookup sources.

## Waiting on me (owner)
- [ ] **Try the 1.3.0 beta**, then tell Claude "release it" (or what's wrong). Steps:
  1. On your Android phone, open the GitHub page **Obamna1234/WatchedLedger → Releases** and find **WatchedLedger 1.3.0 (beta)**.
  2. Under **Assets**, tap the `.apk` file and open it when it has downloaded. Choose **Update** (not uninstall): your library stays.
  3. Check what you use most: add, tick, search, import. If you use the PIN lock, check you can unlock with the PIN.
- [x] Add the WatchedLedger repo to the Claude GitHub App.
- [x] Switched on auto-merge, automatic branch deletion and Dependabot security updates (2026-11-17).
- [ ] Optional: **Code → Branches**, delete old merged `stage-…` branches with the 🗑 icon. Keep `main` and `demo-recordings`.
- [x] Android signing key created and the 4 GitHub Secrets added (2026-11-11). **Keep the `.jks` file and its password backed up.**
- [x] Samsung Notes sample sent (2026-11-17). It was used only to check the importer and is not stored in the repo.
- [ ] Optional: tell Claude which iPhone and iOS version you have, and whether you use a Mac or a Windows PC, so the README can lead with the right sideloading tool.

## Decisions made
- **2026-11-19 Optional extra lock on releases:** you could make GitHub ask you to approve every "Release it" run (a protected Environment). Not set up; say if you want it.
- **2026-11-19 Package pin:** `jni` 1.1.2 and `jni_flutter` 1.0.4+1 are pinned (`dependency_overrides` in pubspec.yaml), because jni 1.2.0 broke `path_provider_android` on Android. Remove the pin when `path_provider_android` is updated for it.
- **2026-11-19 Beta first:** you chose "beta first, I say yes". A version bump publishes a pre-release. "Release it" (a workflow I run when you say so) makes it the normal release. AltStore/SideStore only see normal releases.
- **2026-11-19 Update test uses debug builds** of the last release's code and the new code, signed with the same test key, because a test can't drive the signed release app. The database, its encryption key and the update path are the same as in real updates.
- **2026-11-18 Navigation:** the owner picked the "bottom bar" layout over home tiles or decluttered tabs. This replaces SPEC §7's add box at the top. Swiping sideways no longer changes category (it clashed with swipe-to-tick).
- **2026-11-17 Enums appended:** `game` (5) and `video` (6) added to the end of the category list; database schema v3 adds link, people, where-to-watch, not-out-yet, private columns and the `trash` table (migration tested).
- **2026-11-17 Headings in imported notes** only decide the category and grouping, never the genre (your headings' genre words aren't real genres). The genre comes from the lookup.
- **2026-11-17 YouTube search** opens the YouTube or NewPipe app rather than searching from inside WatchedLedger: searching YouTube in-app would need a Google API key tied to an account. Sharing the video back adds it.
- **2026-11-17 Links** only via oEmbed (title and thumbnail) from sites that offer it without a key. Facebook and Instagram need a Meta account for that, so their links are saved with the title you type.
- **2026-11-17 New dependency `url_launcher`** (Flutter team) to open links in other apps.
- **2026-11-17 Personal names** (people you watch with) only ever come from your own data, never from the app.
- **2026-11-17 Shared folders** are plain text messages: no server, no link-shortener, nothing hosted. Private items are never included.
- **2026-11-17 Private items** need the app lock to actually hide; without a PIN there's nothing to hide them behind, and the app says so.
- **2026-11-17 Sync uses a typed one-time code instead of QR pairing** (a change from SPEC §12a). Why: scanning a QR code needs a camera and barcode package (the common ones pull in Google ML Kit); a permanent pairing key and always-on discovery add risk. Now: one tap on each phone per sync, 8-character code (about 40 bits) stretched with Argon2id, AES-256-GCM, private addresses only, one sync or 5 minutes, 5 wrong tries and it stops. Can be revisited if you want QR.
- **2026-11-17 Reminders are native code, not `flutter_local_notifications`:** its current version needs a newer Android build setup (compileSdk 37, desugaring). A small Kotlin + Swift piece does the job: inexact alarms (no "exact alarm" permission), restored after a reboot.
- **2026-11-17 Diary entries for deleted items** are kept until the next app start so Undo can bring everything back, then tidied away.
- **2026-11-17 Widget and share are Android-only.** On iPhone they need extra app parts (extensions) that free sideloading handles badly. On iPhone, copy and paste into Import instead.
- **2026-11-17 No packages for widget/share:** small native Kotlin pieces instead of `home_widget` / `share_handler`, so fewer dependencies.
- **2026-11-17 App icon** drawn by Claude (a ledger page with a green tick).
- **2026-11-17 Import:** own parsers, no new package. Unmatched imported titles are saved as typed and matched in the background later. Imports never overwrite existing items.
- **2026-11-17 App lock PIN** is kept in Keystore/Keychain, not in the database, so a restored backup can't switch the lock on without a PIN. Forgetting the PIN means reinstalling, which erases the library, so the app tells you to keep a backup.
- **2026-11-17 Mobile data:** Wi-Fi only by default. New permission `ACCESS_NETWORK_STATE` (connection type only). Fingerprint unlock adds `USE_BIOMETRIC`.
- **2026-11-03 Public repo.** Its GitHub Actions minutes are free, including macOS.
- **2026-11-03 Drift + sqlite3 with SQLite3MultipleCiphers** for encryption at rest. Isar was rejected (unmaintained).
- **2026-11-03 No state-management package.** Plain Flutter; 5 runtime dependencies.
- **2026-11-03 TMDB key** will be pasted into the app's settings by the owner, not baked into the build.
- **2026-11-03 Builds:** pushes produce artifacts; `vX.Y.Z` tags produce a Release. The build number is time-based.
- **2026-11-03 Genres:** one primary genre per item. Podcasts are tracked as whole shows. Series progress uses simple S/E counters.
- **2026-11-03 Platform folders** are generated in CI by `tool/bootstrap.sh`; only customised files are committed.
- **2026-11-04 Sort and filter choices** are kept while the app is open and reset when it restarts. They can be made to stick later if wanted.
- **2026-11-04 Tapping an item opens Edit.** Only the tick box (or a swipe right) ticks it, so you can't tick by accident.
- **2026-11-04 Repo name** is `Obamna1234/WatchedLedger`. The internal package name stays lowercase `watchedledger`, which Flutter requires.
- **2026-11-17 Also added:**
  - **Smart picker** (Stage 5): picks from your own list, on the phone only.
  - **"More by this director/author"** (Stage 5): only the creator's name is sent.
  - **Episode tracking and reminders** (Stage 6): opt-in, phone-scheduled reminders, TVmaze sees only followed show IDs.
- **2026-11-17 New features chosen by the owner:**
  - Stage 4: the mobile data setting (default Wi-Fi only) and imports from Letterboxd, Goodreads, Trakt and IMDb.
  - New Stage 6: rewatch diary, progress and goals, tags, and Wi-Fi phone sync.
  - Details are in SPEC.md §12a.
- **2026-11-17 Demo video:** the "Demo video" workflow drives the real app on an Android emulator (integration_test/demo_test.dart) and records it. `tool/demo/make_video.py` cuts a captioned 30-second video, published to the `demo-recordings` branch. Re-run it after big changes.
- **2026-11-11 Releases are automatic:** bumping `version:` in pubspec.yaml on main publishes vX.Y.Z. Claude can't push tags through its GitHub connection, so this keeps releases hands-off.
- **2026-11-11 Signing key** was generated by Claude at the owner's request and given to the owner. Certificate SHA-256: `89:7B:41:40:75:FE:24:2F:4A:9D:4B:71:62:29:53:3A:2E:86:62:5F:C0:94:73:54:07:14:55:0F:EA:2D:BC:7F`. Every release must match this.
- **2026-11-08 Movies come from Wikipedia** (iTunes stopped answering movie searches). The trade-off: most movies have no poster, because Wikipedia only shares freely licensed images.
- **2026-11-06 Merging:** Claude merges pull requests once CI is green, as the owner asked. PRs use merge commits, so history is kept.
- **2026-11-06 Search** covers the visible list (after any filter), with chips for matches in other lists. It matches titles, creators and notes.
- **2026-11-05 No accounts for lookups (owner's choice).** Movies use iTunes; series use TVmaze, then iTunes. TMDB was dropped. If nothing matches, you can keep typing and save it as free text.
- **2026-11-05 New dependency: `http`** (Dart team), needed for the network gate.
- **2026-11-05 Auto-file** only when exactly one result matches the typed title (and year, if one was given). Otherwise you choose.
- **2026-11-05 Commits use GitHub's private noreply email** (`…@users.noreply.github.com`), so your real email is never published.
- **2026-11-04 Spec files merged:** SPEC.md now records all of these decisions (§13) plus the stage plan (§12).
