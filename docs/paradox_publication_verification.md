# Paradox publication verification

## Read-only command

```powershell
pwsh -File tools/check_paradox_publication.ps1 -TimeoutSeconds 60
pwsh -File tools/check_paradox_publication.ps1 -TimeoutSeconds 0
```

The command reads the current descriptor and its matching release notes. It does not authenticate, renew the launcher session, stage game files, upload archives or edit metadata. The default polling window is 30 seconds; zero performs one immediate public read. An in-flight HTTP request can outlast the polling window up to the HTTP client's timeout. The publication command retains its configurable window, defaulting to 300 seconds.

## Evidence and freshness

Every metadata read uses a unique `_mqa_check` query value. GET requests send `Cache-Control: no-cache, no-store, max-age=0` and `Pragma: no-cache`. These request cache freshness but cannot guarantee synchronous backend state. Authenticated reads still check destination identity and publication permission. Confirmation polls public metadata without a session to check reader-visible notes.

Confirmation requires:

- the expected CK3 mod identity;
- public state `published` and a valid latest internal version number;
- the complete expected notes attached to that latest version.

Line endings and surrounding whitespace are normalized. Edited notes, empty/missing versions and notes matching only an older history entry do not confirm publication. Paradox's internal version number is separate from the semantic version in the descriptor.

Matching latest public notes confirm publication even when `updating` remains true or `latestUpdate` has not changed. Those flags cannot negate the affirmative public evidence. If processing is still reported, description edits are deferred; that does not prevent confirming the version and notes.

Old notes, a processing flag, missing metadata and failed public reads are inconclusive. The verifier retries within its window. At expiration it exits nonzero with **publication not confirmed / status unknown**, never a definitive negative claim. The upload may already be public or still processing. Use the read-only command again rather than resending an archive. Unexpected mod identity remains a hard error.

## Upload preflight and retries

The publisher reads both authenticated and public metadata before uploading. If the expected release is public, it skips the archive even when authenticated metadata lags. Descriptions are synchronized only when both observations permit edits. If either read reports processing, or authenticated metadata already carries the expected latest notes, it waits for public confirmation instead of sending another archive.

After accepting a new upload, verification is read-only. A success or timeout never causes an automatic second submission. This reduces duplicate uploads based on delayed observations; it does not make the undocumented API transactional or prove absence from a stale negative response. The note-based check also does not verify the remote archive's byte-for-byte contents.

## Incident and validation

During 1.0.6 publication, accepted upload requests were followed by repeated old-version/processing metadata. The user could see the new release, and a later read confirmed internal version 7 with the exact 1.0.6 notes. The observations do not establish whether caching, propagation delay or a state transition caused the discrepancy. The previous verifier also required a changed timestamp and cleared processing flag, and its results were reported too categorically. The correction avoids those additional negative conditions once public notes match and provides an explicit uncertainty result otherwise.

The new command was run against the published 1.0.6 and confirmed its exact notes, without authentication or uploading. The focused offline suite uses fixtures and mocks for nine cases:

1. Unique read URLs, cache headers, public reads without credentials, unchanged mutation request payloads.
2. Exact public notes with a lagging processing flag or unchanged timestamp, including CRLF notes.
3. Old, edited, history-only or malformed matches and wrong identity rejection.
4. Repeated stale reads followed by public confirmation, without authentication or writes.
5. An expired window that reports uncertainty without submitting anything.
6. Failed public reads remaining unknown or recovering on a later read.
7. An already public release with lagging metadata causing no upload or unsafe description edit.
8. A pending update finishing without another archive.
9. A single new upload followed by public success or uncertain timeout, with exactly one archive PUT and one publish POST.

Run `pwsh -File tools/tests/Test-ParadoxPublication.ps1`. The main regression suite runs it too; `Test-ParadoxDescriptions.ps1` separately covers metadata-only description edits. No gameplay files, existing release notes or published tags are changed by this tooling fix.
