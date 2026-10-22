# Publishing Monarque Absolu

The publisher creates a version tag and release on GitHub and updates the existing mod items: Steam Workshop `3813333986` (CK3 app `1158310`) and Paradox Mods `161949`. It never creates a new mod. GitHub releases use the repository `jrmbbch/ck3-monarque-absolu`.

## Commands

From the repository root, validate the package without signing in or contacting any service:

```sh
python3 tools/publish_release.py all
```

After committing and pushing the release changes to `main`, publish to all three services:

```sh
python3 tools/publish_release.py all --publish
```

Publish to one service only:

```sh
python3 tools/publish_release.py github --publish
python3 tools/publish_release.py steam --publish
python3 tools/publish_release.py paradox --publish
```

The version comes from `descriptor.mod`; the matching `docs/patch_notes/<version>.txt` must exist. Descriptions come from `docs/workshop_description.bbcode` and `docs/paradox_mods_description.txt`, with the Paradox short description from its separate file. Only `common/`, `events/`, `localization/`, `descriptor.mod` and `thumbnail.png` are staged in a temporary directory. The repository, tools and authentication data are never included. This does not modify the installed development or release mod folders.

A successful Steam callback confirms the upload. Paradox is polled until the mod is published, its timestamp changes and the new notes appear on its latest version. A timeout means status is unknown: verify the remote item before retrying. Publication runs in order: GitHub, Steam, Paradox. Any failure stops the command before later services are called. Completed services are not rolled back. If a service fails, retry that service and any later services individually after checking their state. GitHub verifies and reuses an existing tag/release when the commit and notes match. Paradox skips an upload when the latest version already has the exact release notes. Steam does not skip duplicate submissions.

## GitHub prerequisites and implementation

Install GitHub CLI (`gh`) and authenticate with `gh auth login`. Prepare the next version by updating `descriptor.mod`, `CHANGELOG.md`, `docs/patch_notes/<version>.txt` and the relevant mod/description files, then commit and push those changes to `main`. The publisher does not create commits or push branch changes.

`all --publish` includes GitHub; `github --publish` runs that step alone. The dry run shows the planned tag and release without contacting GitHub or requiring a clean working tree. Actual publication requires:

- a clean working tree, including no untracked files;
- `origin` pointing to this GitHub repository;
- local `HEAD` matching the current remote `main` commit;
- any existing local or remote version tag resolving to that same commit.

The script creates an annotated `v<version>` tag at the exact commit and pushes only that tag. It then calls `gh release create --verify-tag --notes-file docs/patch_notes/<version>.txt`, with `v<version>` as the release title. GitHub supplies its standard source archives; no additional release asset is attached. The script reads back the published release and verifies its tag, release type and notes. A GitHub failure prevents any Steam or Paradox upload in that run.

A matching published release is reused unchanged. A tag on another commit, a draft/prerelease, or different release notes causes an error instead of moving a tag or overwriting a release. If tag publication succeeds but release creation fails, rerunning reuses the tag. GitHub API errors other than a confirmed release-not-found (HTTP 404) stop publication.

The already published `v1.0.5` remains on its original release commit. Later tooling commits therefore cannot republish it through `all --publish`: prepare the next version instead, or use an individual Steam/Paradox command when intentionally updating one of those mod items.

## Steam prerequisites and implementation

Open Steam and sign in with the Workshop item's owner account. CK3 must be installed on this Mac; no SteamCMD install or separate password is needed. The script loads the official `libsteam_api.dylib` bundled with CK3 and uses `StartItemUpdate`, `SetItemContent`, `SetItemDescription`, `SetItemPreview`, then `SubmitItemUpdate` with the change notes. Item tags and visibility are preserved.

Default library path:

```
~/Library/Application Support/Steam/steamapps/common/Crusader Kings III/binaries/ck3.app/Contents/Frameworks/libsteam_api.dylib
```

Use `--steam-library /absolute/path/libsteam_api.dylib` for another installation. Python and the library must support the same CPU architecture. The installed CK3 library supports Apple Silicon. The script uses the `SteamUGC_v016` flat API and manual callback dispatch; callback buffer sizes come from Steam's completion event. If the library changes incompatibly, update the bindings rather than substituting interface versions blindly.

References: [Valve Workshop integration](https://partner.steamgames.com/doc/features/workshop/implementation), [ISteamUGC](https://partner.steamgames.com/doc/api/ISteamUGC), [manual callback dispatch](https://partner.steamgames.com/doc/sdk/api#manual_dispatch).

## Paradox prerequisites and implementation

Sign in to the Paradox Launcher with **Remember me**. The script reads its saved encrypted renewal token, renews the session using the launcher's authentication endpoint, and verifies that the account has publication permission on mod `161949`. It never prints tokens, reads passwords, or sends authentication to another host. If Paradox rotates the renewal token, the saved launcher session is updated in the same encrypted format. Alternatively, provide an existing session token through the `PDX_SESSION_TOKEN` environment variable; do not put it in the repository or command arguments.

This is an **undocumented API**, inspected in the locally installed Paradox Launcher **2026.13**. It may need adapting after a launcher or backend update. The adapter uses the LFv1 publication flow used by CK3, not the launcher's separate LFv1.1 API:

| Operation | Request |
|---|---|
| Renew saved session | `PUT /accounts/sessions/launcher-v2`, renewal Authorization header |
| Check publication permission and read status/history | Authenticated `GET /mods?modId=161949`, requiring `actions.canPublish: true` |
| Send ZIP | `PUT /mods/content/ck3/<remote-name>/content/<filename>.zip` |
| Commit update and notes | `POST /mods/publishUpdate` |

All requests go to `https://api.paradox-interactive.com`. Authenticated mod requests use the launcher's JSON session Authorization header. The content path uses the existing mod's opaque `name` from metadata; the commit uses numeric `modId`. Payload fields mirror `PdxPublisherStrategyV1._prepareBeforePublish`: `modName`, `gameName`, `contentFileName`, `os`, `arch`, `longDescription`, `shortDescription`, `displayName`, `tags`, `recommendedGameVersion`, `changelogEntry`, plus `modId`. The current thumbnail is preserved. Publication rights are checked on the destination metadata itself: the backend search for `onlyModsByMe` can temporarily omit the mod after a successful update, so it is not used as an ownership check. The update response can omit `modId`, so success is checked against the subsequent metadata and changelog rather than assuming that response field exists.

The script reads the launcher's storage-format key from its installed `app.asar`; no token or encryption key is committed here. Reading the archive is data inspection only, with no execution or modification of launcher code.

## Version 1.0.5

Published through these scripts to both existing items on 22 October 2026. Steam returned `EResult=1`; Paradox advanced from internal version 5 to 6 and published the 1.0.5 notes. Paradox's internal sequence number is separate from the mod's semantic version in `descriptor.mod`.
