# WatchedLedger – Progress

Maintained by Claude. Updated at the end of every stage, in the same pull request as the work.

## Status
**Stages 1a and 1b are written but not yet compiled.** The first real build happens in GitHub Actions once Claude can push to the repo.

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

## Next
- First green CI run for both stages, then tag `v0.1.0`.
- **Stage 2, title lookup:** needs a TMDB key from you first.

## Waiting on me (owner)
- [ ] **Add the WatchedLedger repo to the Claude GitHub App** (github.com/settings/installations → Claude → Configure → Repository access) so Claude can push.
- [ ] **Create the Android signing key and add the 4 GitHub Secrets.** Exact steps are in README → "Android signing key". Back the `.jks` file up.
- [ ] Before Stage 2: a free TMDB account and API key (Claude will send exact steps).
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
- **2026-11-04 Spec files merged:** SPEC.md now records all of these decisions (§13) plus the stage plan (§12).
