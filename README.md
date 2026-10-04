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
| `tools/generate_building_effects.py` | Rebuilds the building effects from the installed game files |
| `tools/generate_lifestyle_effects.py` | Rebuilds the perk unlock effect from the installed game files |
| `tools/check_localization.py` | Checks the 9 languages: same keys, UTF-8 BOM, no broken quotes |
| `tools/build_release.sh` | Copies only the mod files into the game's mod folder, ready to upload |
| `art/thumbnail.svg` | Source of the thumbnail |
| `docs/` | Publication texts |

All keys use the `mqa_` prefix.

## After a game update

```sh
python3 tools/generate_building_effects.py
python3 tools/generate_lifestyle_effects.py
python3 tools/check_localization.py
```

The generator prints the building priority it computed from the game's levy and tax values, and writes it at the top of the generated file.

## Playing from the repository

Create `Documents/Paradox Interactive/Crusader Kings III/mod/monarque_absolu_dev.mod`:

```
name="Monarque Absolu (dev)"
path="/path/to/this/repository"
supported_version="1.20.*"
```

## Publishing

```sh
sh tools/build_release.sh
```

Then upload **Monarque Absolu** from the launcher (*All installed mods → Upload Mod*), never the dev entry: the repository folder also contains `.git`, `tools/` and `art/`. After the first upload, copy the `remote_file_id` line the launcher adds to the built `descriptor.mod` back into the repository's `descriptor.mod`, so later uploads update the same item. The Paradox Mods ID (161949) is not stored in the descriptor: type it in the launcher's *Mod ID* field when updating there, and clear that field's Steam ID first. The launcher pre-fills the Paradox Mods description with the text saved at the previous upload: replace it with docs/paradox_mods_description.txt every time, or the website text gets overwritten.
