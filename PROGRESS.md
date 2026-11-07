# WatchedLedger – Progress

Maintained by Claude. Updated at the end of every stage, in the same pull request as the work.

## Status
**Stages 1 and 2 are merged into `main`** (PRs #1–#3, 2026-11-06).
**Stage 3 (search) is merged** (PR #4, 2026-11-06): analyzer clean, 48 tests passing.

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

## Next
- Tag `v0.1.0` for the first signed Release, once the signing secrets are added.
- **Stage 4, import/export and protection:**
  - paste a list, or import .txt / .csv files
  - the Samsung Notes helper
  - a review screen
  - export to .txt / .csv / .json
  - encrypted backup and restore
  - app lock (PIN or fingerprint/Face ID)

## Waiting on me (owner)
- [x] Add the WatchedLedger repo to the Claude GitHub App.
- [ ] **Switch on 4 GitHub settings.** Claude can't change repo settings: GitHub blocks that through Claude's connection. Steps:
  1. **Settings → General**, scroll to **Pull Requests**. Tick **Allow auto-merge** and **Automatically delete head branches**.
  2. **Settings → Advanced Security** (it may be called **Code security**). Click **Enable** for **Dependabot alerts**, **Dependabot security updates** and **Private vulnerability reporting**.
  3. Optional: **Code → Branches**. Delete the old `stage-1a-foundation`, `stage-1b-core-lists` and `stage-2-lookup` branches with the 🗑 icon. They're already merged.
- [ ] **Create the Android signing key and add the 4 GitHub Secrets.** Exact steps are in README → "Android signing key". Back the `.jks` file up.
- [ ] Before Stage 4: paste 5–10 lines copied from the Samsung Notes checklist, with fake titles, some ticked and some not.
- [ ] Optional: tell Claude which iPhone and iOS version you have, and whether you use a Mac or a Windows PC, so the README can lead with the right sideloading tool.

## Decisions made
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
- **2026-11-08 Movies come from Wikipedia** (iTunes stopped answering movie searches). The trade-off: most movies have no poster, because Wikipedia only shares freely licensed images.
- **2026-11-06 Merging:** Claude merges pull requests once CI is green, as the owner asked. PRs use merge commits, so history is kept.
- **2026-11-06 Search** covers the visible list (after any filter), with chips for matches in other lists. It matches titles, creators and notes.
- **2026-11-05 No accounts for lookups (owner's choice).** Movies use iTunes; series use TVmaze, then iTunes. TMDB was dropped. If nothing matches, you can keep typing and save it as free text.
- **2026-11-05 New dependency: `http`** (Dart team), needed for the network gate.
- **2026-11-05 Auto-file** only when exactly one result matches the typed title (and year, if one was given). Otherwise you choose.
- **2026-11-05 Commits use GitHub's private noreply email** (`…@users.noreply.github.com`), so your real email is never published.
- **2026-11-04 Spec files merged:** SPEC.md now records all of these decisions (§13) plus the stage plan (§12).
