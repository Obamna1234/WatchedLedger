# Security and privacy reviews

One file per release, `vX.Y.Z.md`, written **before** the version number is
bumped. The release workflow refuses to publish a version without one.

Each review covers everything changed since the last release
(`git diff vLAST..HEAD`) and is done by a reviewer that didn't write the
changes (for Claude: a separate agent that sees only the diff and this list).

## What every review checks

1. **What leaves the phone.** Every network call goes through `NetClient`, to an
   allowed host, over HTTPS, and sends only the title (or a link). PRIVACY.md and
   the in-app privacy page match the code exactly.
2. **The user's library.** Schema changes have a version bump, a migration and
   a test; nothing deletes user data; backup, restore and the update test still
   pass; enums are only appended.
3. **Untrusted input.** Imports, pasted text, shared links and lookup
   responses are size-capped, cleaned and never run or shown as HTML.
4. **App lock and private items.** Nothing new shows locked or private content
   (widget, notifications, share sheet, recent-apps preview).
5. **Dependencies and build.** New packages are justified and scanned (OSV);
   workflows pin actions by commit; no secrets in the repo or logs.
6. **Permissions.** No new Android permission or iOS entitlement without a reason.

## Result

Each file ends with **Findings** (severity: high / medium / low / none) and
**Fixed before release**. Anything medium or worse is fixed before the beta.
