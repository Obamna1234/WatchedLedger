# WatchedLedger – Progress

Maintained by Claude. Updated at the end of every stage, in the same pull request as the work.

## Status
**Stage 1a (foundation) is written but not yet compiled.** The first real build happens in GitHub Actions once the repo exists.
**Stage 1b (core lists complete) is in progress.**

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

## Next
- **Stage 1b:**
  - an edit sheet covering title, year, genre, 1–5 star rating, one-line note and series season/episode
  - swipe left opens an Edit/Delete menu
  - sort and filter by genre, year, date added, date watched, rating and A–Z
  - a genre fast-scroll bar
- First green CI run, then tag `v0.1.0`.

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
- **2026-11-04 Spec files merged:** SPEC.md now records all of these decisions (§13) plus the stage plan (§12).
