# CLAUDE.md – Working rules for WatchedLedger

You are building WatchedLedger, a private Flutter app for Android and iOS, distributed through GitHub only. You work directly in this repo and automate the process end to end.

## Source of truth
- `SPEC.md` defines what to build. Follow it in every session.
- If a request conflicts with `SPEC.md`, point it out and ask which wins before changing anything.
- Read `PROGRESS.md` at the start of every session to see what's done and what's next.

## Privacy (non-negotiable)
- Never add analytics, tracking, ads, accounts, crash reporting or cloud services, even if a package or template includes them by default.
- Never commit secrets, keystores, API keys or personal data.

## How to work
- One branch and one pull request per stage. Each PR gets a plain-language summary: what changed, why, and how I can test it.
- After pushing, check the GitHub Actions build. If it fails, read the logs, fix and push again before reporting back.
- Keep dependencies minimal and check them for known vulnerabilities.
- At the end of each stage, update `PROGRESS.md` (Done, Next, Waiting on me, Decisions made) in the same PR. If a decision changes the plan, update `SPEC.md` too.

## Talking to me
- I'm not a professional developer. Explain things in plain language and keep reports short.
- When something needs me (adding GitHub Secrets, signing up for an API key, installing a build on my phone), give exact step-by-step instructions and list it under "Waiting on me" in `PROGRESS.md`.
- Ask before anything hard to undo, like deleting files or rewriting history.

## Technical notes (added by Claude)
- Technical design and stage plan: SPEC.md §12–13.
- Any new network call must go through the single `NetClient` gate, and must be listed on the in-app privacy page and in PRIVACY.md.
- Every new package needs a reason in the PR, plus a row in the SPEC.md §13 table.
- Branch names: `stage-1b-core-lists`, `stage-2-lookup`, …

### Building
- Your cloud workspace usually **can't download Flutter or pub packages**. GitHub Actions is the compiler.
- Verify Flutter and package APIs against source checkouts cloned from GitHub (flutter/flutter at the stable tag, simolus3/drift, etc.) rather than guessing.
- Avoid deprecated APIs. `flutter analyze` fails on infos too.
- Never put literal invisible or bidi characters in source. Use `\uXXXX` escapes (analyzer warning `text_direction_code_point_in_literal`).
- Running the project locally: `bash tool/bootstrap.sh`, then `flutter analyze && flutter test`.
- `*.g.dart` files are generated and are not committed.

### Data safety
- Enums are persisted by index. **Only ever append new values.**
- Schema changes need a `schemaVersion` bump, a migration step and a migration test. Never drop user data.
- Nothing in the app deletes the database file. Recovery only moves it aside.
