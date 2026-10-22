# Monarque Absolu – Absolute Monarch

A Crusader Kings III mod that gives you the tools of an all-powerful sovereign: legendary traits, title seizing, instant construction, a perfect bloodline and more, through character interactions and decisions. Names (mod, traits, confirmation buttons) stay in French in every language; descriptions and actions are translated.

- **Game version:** CK3 1.20.* (Crozier), every DLC supported up to By God Alone, none required
- **Languages:** English, French, German, Spanish, Polish, Russian, Japanese, Korean, Simplified Chinese
- **Steam Workshop:** https://steamcommunity.com/sharedfiles/filedetails/?id=3813333986 (description: [docs/workshop_description.bbcode](docs/workshop_description.bbcode), BBCode)
- **Paradox Mods:** https://mods.paradoxplaza.com/mods/161949/Any (description: [docs/paradox_mods_description.txt](docs/paradox_mods_description.txt) and [docs/paradox_mods_short_description.txt](docs/paradox_mods_short_description.txt), plain text to paste as is)

## Repository layout

| Path | Content |
|---|---|
| `descriptor.mod`, `thumbnail.png`, `common/`, `localization/` | The mod itself |
| `common/scripted_effects/mqa_building_effects.txt`, `mqa_lifestyle_effects.txt` | **Generated**, do not edit by hand |
| `tools/generate_building_effects.ps1` | Rebuilds the building effects from the installed game files |
| `tools/generate_lifestyle_effects.ps1` | Rebuilds the perk unlock effect from the installed game files |
| `tools/check_localization.ps1` | Checks the 9 languages: same keys, UTF-8 BOM, no broken quotes |
| `tools/publish_release.ps1`, `publish_github.ps1`, `publish_steam.ps1`, `publish_paradox.ps1` | Publish the GitHub tag/release and existing Steam/Paradox items, including change notes |
| `tools/build_release.ps1` | Copies only the mod files into the game's mod folder, ready to upload |
| `art/thumbnail.svg` | Source of the thumbnail |
| `docs/` | Publication texts; `docs/patch_notes/<version>.txt` holds the patch note to paste on each upload |
| `CHANGELOG.md` | Version history |

All keys use the `mqa_` prefix.

All tooling uses **PowerShell 7.4+** (`pwsh`; tested with 7.6.7 on macOS Arm64). Python, shell scripts and third-party PowerShell modules are not required. The Steam ABI bridge is C# loaded by `Add-Type`; a separate .NET SDK is not needed. CK3 game scripts retain the game's required `.txt` format.

Run the offline regression suite:

```powershell
pwsh -File tools/tests/Test-Scripts.ps1
# Also check generation against the installed game, writing only temporary files
pwsh -File tools/tests/Test-Scripts.ps1 -TestInstalledGame
```

## After a game update

```powershell
pwsh -File tools/generate_building_effects.ps1
pwsh -File tools/generate_lifestyle_effects.ps1
pwsh -File tools/check_localization.ps1
```

Use `-GamePath /path/to/Crusader Kings III/game` to override the default installation and `-OutputPath /tmp/effects.txt` to generate into a temporary file. Both generators preserve UTF-8 BOM and LF line endings.

The generator prints the building priority it computed from the game's levy and tax values, and writes it at the top of the generated file.

## Playing from the repository

Create `Documents/Paradox Interactive/Crusader Kings III/mod/monarque_absolu_dev.mod`:

```
name="Monarque Absolu (dev)"
path="/path/to/this/repository"
supported_version="1.20.*"
```

## Publishing

```powershell
# Validate only (no network or authentication)
pwsh -File tools/publish_release.ps1 all
# After committing and pushing the release to main, publish to GitHub, Steam and Paradox
pwsh -File tools/publish_release.ps1 all -Publish
```

GitHub creates and pushes an annotated version tag, then publishes a release with the matching notes using `gh`. A clean working tree and a release commit already pushed to `main` are required. Existing tags/releases are checked before reuse. Steam uses the running client's session through the official Steamworks library bundled with CK3. Paradox uses the session saved by the launcher and its publication API. See [docs/publishing.md](docs/publishing.md) for prerequisites, per-platform commands, verification and API details. No credentials belong in the repository.

To update the local game mod folder separately:

```powershell
pwsh -File tools/build_release.ps1
```

Manual launcher uploads remain possible: choose the built **Monarque Absolu** entry, never the repository/dev entry. Use Steam ID `3813333986` or Paradox Mods ID `161949`, the descriptions in `docs/`, and the matching `docs/patch_notes/<version>.txt`. The launcher's Steam uploader does not send change notes; add them on the item's Steam changelog page when using that manual path.
