# Monarque Absolu – Absolute Monarch

A Crusader Kings III mod that gives you the tools of an all-powerful sovereign: legendary traits, title seizing, instant construction, a perfect bloodline and more, through character interactions and decisions. Names (mod, traits, confirmation buttons) stay in French in every language; descriptions and actions are translated.

- **Mod version:** 1.0.6; see [release notes](docs/patch_notes/1.0.6.txt).
- **Game version:** CK3 1.20.* (Crozier), every DLC supported up to By God Alone, none required
- **Languages:** English, French, German, Spanish, Polish, Russian, Japanese, Korean, Simplified Chinese
- **Steam Workshop:** https://steamcommunity.com/sharedfiles/filedetails/?id=3813333986 (description: [docs/workshop_description.bbcode](docs/workshop_description.bbcode), BBCode)
- **Paradox Mods:** https://mods.paradoxplaza.com/mods/161949/Any (description: [docs/paradox_mods_description.html](docs/paradox_mods_description.html) and [docs/paradox_mods_short_description.txt](docs/paradox_mods_short_description.txt), HTML for the publication API)

## Repository layout

| Path | Content |
|---|---|
| `descriptor.mod`, `thumbnail.png`, `common/`, `localization/` | The mod itself |
| `common/scripted_effects/mqa_building_effects.txt`, `mqa_lifestyle_effects.txt` | **Generated**, do not edit by hand |
| `tools/generate_building_effects.ps1` | Rebuilds the building effects from the installed game files |
| `tools/generate_holding_requirements.ps1` | Copies first-level temple/temple-citadel/city/castle requirements into the foundation triggers |
| `tools/generate_epidemic_fix.ps1` | Regenerates the expired-epidemic guard for vanilla event 1110 |
| `tools/generate_mandala_completion_fix.ps1` | Regenerates three native building-file replacements and two guarded, audited mandala reward effects |
| `tools/generate_lifestyle_effects.ps1` | Rebuilds the perk unlock effect from the installed game files |
| `tools/check_localization.ps1` | Checks the 9 languages: same keys, UTF-8 BOM, no broken quotes |
| `tools/publish_release.ps1`, `publish_github.ps1`, `publish_steam.ps1`, `publish_paradox.ps1` | Publish the GitHub tag/release and existing Steam/Paradox items, including change notes |
| `tools/build_release.ps1` | Copies only the mod files into the game's mod folder, ready to upload |
| `art/thumbnail.svg` | Source of the thumbnail |
| `docs/` | Publication texts; `docs/patch_notes/<version>.txt` holds the patch note to paste on each upload |
| `CHANGELOG.md` | Version history |

All keys use the `mqa_` prefix.

Deliberate vanilla-key exceptions are `pam_county_has_actor_primary_site_trigger` in `common/scripted_triggers/zz_mqa_pam_saint_performance_triggers.txt` (the decision-screen freeze identified by live CPU sampling), and `epidemic_events.1110` in `events/zz_mqa_epidemic_events.txt` (an expired epidemic target in a tooltip, with explicit `id_override_priority = 1` above vanilla's default 0).

The mod also replaces `common/buildings/00_castle_buildings.txt`, `00_temple_buildings.txt` and `temple_citadel_buildings.txt` at their native paths. These generated copies change only eight reward callbacks: castle levels 3–4, ordinary temple levels 2–4 and temple-citadel levels 2–4. A living payer is preserved; an absent payer can fall back to a living county holder, matching the native mandala fallback. An existing deceased payer is skipped rather than reassigned. The rest of each completion callback is retained.

`common/scripted_effects/zz_mqa_mandala_reward_effects.txt` overrides only `mandala_upgraded_temple_holding_effect` and `creator_mandala_upgraded_regular_holding_piety_effect`. It guards the primary and secondary recipients against death and adds audits around the original piety payments. Native eligibility, amounts and allocations are preserved; no manual extra payment or persistent duplicate-suppression flag is added. `MQA_REWARD PAYMENT` identifies an executed payment allocation, followed by a piety-change marker and a scope dump identifying the recipient and root province. The ordinary building decision additionally reports whether it changed buildings, whether the actor's piety changed and whether the actor received audited payments. See [the repair and audit notes](docs/mandala_completion_fix_2026-11-01.md). The game installation is untouched.

Regenerate and review these replacements after game updates. Other mods editing any of the three building files may conflict at file level, even outside the eight changed callbacks; mods redefining either reward effect may also conflict. Also review compatibility with mods overriding the saint trigger or epidemic event; equal event priorities conflict and a higher priority supersedes ours.

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
pwsh -File tools/generate_holding_requirements.ps1
pwsh -File tools/generate_epidemic_fix.ps1
pwsh -File tools/generate_mandala_completion_fix.ps1
pwsh -File tools/generate_lifestyle_effects.ps1
pwsh -File tools/check_localization.ps1
```

Use `-GamePath /path/to/Crusader Kings III/game` to override the default installation and `-OutputPath /tmp/effects.txt` to generate into a temporary file. All generators preserve UTF-8 BOM and LF line endings.

For `generate_mandala_completion_fix.ps1`, `-OutputPath` is the building output directory containing three replacement files, not a single file. The reward-effect output is written to its sibling `scripted_effects/zz_mqa_mandala_reward_effects.txt`; use `-RewardOutputPath /tmp/rewards.txt` to override that location. Run `pwsh -File tools/tests/Test-Scripts.ps1 -TestInstalledGame` after regeneration to check them against the installed source. Review gameplay changes in the new source before publishing regenerated files.

The generator prints the building priority it computed from the game's levy and tax values, and writes it at the top of the generated file.

The domain builder now offers four independent decisions under the same show/hide toggle:

| Decision | Scope and effect |
| --- | --- |
| Fortify and arm the domain | Fill building slots and upgrade existing holdings in personally held counties (including vassal barons), plus personal baronies outside those counties. Preserve the fortifications/levies/income priority, replacement of lower-priority buildings, four upgrade and three fill passes. No foundation, conversion or explicit donation. |
| Found new holdings | In personally held counties, fill empty non-capital baronies with a missing government-appropriate temple (temple-citadel for mandala), a missing city, then castles, subject to vanilla first-level requirements. No extra building improvements or explicit donations; the engine may assign some holders automatically. Tribal and nomadic governments are excluded. |
| Convert holdings to castles | Convert eligible controlled personal tribal, nomadic and herder holdings, including county capitals, when the ruler is neither tribal nor of the steppe. No foundation, building upgrade passes or explicit donation. |
| Grant secondary baronies | Donate eligible personally held secondary cities, temples, castles and temple-citadels, including existing holdings, to generated nobles of the ruler's culture, faith and rite as direct vassals. No construction or conversion. |

Each decision executes once after confirmation, uses static UI text in all nine languages, and records its own diagnostic run. Active constructions are protected. Donations additionally protect county capitals, leased titles and clergy temple leases; other barons keep their titles. Titles are snapshotted, queued in one shared transaction, resolved once, then verified individually. Dream home remains a separate unchanged domicile action. No combined action is provided. If performing everything, use conversion, foundation, improvements, then grants. See [the test procedure](docs/testing_building_decisions.md).

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
