#!/usr/bin/env python3
"""Generate common/scripted_effects/mqa_building_effects.txt from the game files.

The building decisions used to rely on hand-written building lists, which went
stale with every DLC. This script rebuilds the effects from the installed game,
so new buildings are picked up by simply running it again after a patch:

    python3 tools/generate_building_effects.py [path/to/Crusader Kings III/game]

Generated effects:
- mqa_b_upgrade_province_buildings_effect (province scope): upgrades every
  existing building to the last level of its chain.
- mqa_b_priority_fill_province_effect (province scope, needs scope:holder):
  fills the province's existing building slots by priority (most levies first,
  gold as a tiebreaker, then gold only), replacing lower-ranked buildings.
  Buildings giving neither levies nor gold are never built and replaced first.
  Only buildings the game allows (its own can_construct_potential) are used.
- mqa_b_construct_domicile_effect (domicile scope): fills free external slots,
  army buildings first, then gold and resources, then the rest.
- mqa_b_upgrade_domicile_effect (domicile scope): upgrades every domicile
  building along its track, stopping where the track branches into
  specializations so the player keeps that choice.

The ranking is printed when the script runs and written as a comment in the
generated file.
"""
import re
import sys
from collections import defaultdict
from pathlib import Path

DEFAULT_GAME = Path.home() / "Library/Application Support/Steam/steamapps/common/Crusader Kings III/game"
OUTPUT = Path(__file__).resolve().parent.parent / "common/scripted_effects/mqa_building_effects.txt"

# Files holding the regular buildings players construct in free slots.
# Special, duchy capital, great project and nomad buildings are left out of construction.
REGULAR_FILES = [
    "00_common_buildings.txt",
    "00_standard_economy_buildings.txt",
    "00_standard_fortification_buildings.txt",
    "00_standard_military_buildings.txt",
    "00_temple_buildings.txt",
    "00_tribal_buildings.txt",
    "00_city_buildings.txt",
    "temple_citadel_buildings.txt",
]
# Main buildings of holdings: upgraded, never constructed.
HOLDING_MAIN = {"castle", "city", "temple", "tribe", "temple_citadel"}
# Cosmetic buildings that must not be touched.
SKIPPED_FILES = {"99_background_graphics_buildings.txt"}
# Buildings whose level is driven by another mechanic (great project contributions,
# oath quests): forcing their level could break that mechanic.
# Built before everything else: the fortification of the holding. Regular holdings get
# the one matching the terrain (each terrain allows exactly one, through the game's own
# terrain triggers); tribal holdings get palisades, or idjang forts under a wanua
# government; temple citadels get their citadel shrine.
FORTIFICATIONS = ["ramparts", "curtain_walls", "watchtowers", "hill_forts",
                  "palisades", "idjang_forts", "citadel_shrine"]
NOT_UPGRADED_FILES = {"tgp_great_project_buildings.txt", "pam_buildings.txt", "99_ach_buildings.txt"}


def strip_comments(text):
    return re.sub(r"#[^\n]*", "", text)


def top_level_blocks(text):
    """Yield (key, body) for every 'key = { ... }' at depth 0."""
    pattern = re.compile(r"^([A-Za-z0-9_]+)\s*=\s*\{", re.M)
    position = 0
    while True:
        match = pattern.search(text, position)
        if not match:
            return
        depth, index = 0, match.end() - 1
        for index in range(match.end() - 1, len(text)):
            if text[index] == "{":
                depth += 1
            elif text[index] == "}":
                depth -= 1
                if depth == 0:
                    break
        yield match.group(1), text[match.end():index]
        position = index + 1


def inner_block(body, key):
    """Return the content of 'key = { ... }' directly inside body, or None."""
    match = re.search(r"(?m)^\t" + re.escape(key) + r"\s*=\s*\{", body)
    if not match:
        return None
    depth = 0
    for index in range(match.end() - 1, len(body)):
        if body[index] == "{":
            depth += 1
        elif body[index] == "}":
            depth -= 1
            if depth == 0:
                return body[match.end():index]
    return None


def field(body, key):
    match = re.search(r"(?m)^\t" + re.escape(key) + r"\s*=\s*([A-Za-z0-9_@.\-]+)", body)
    return match.group(1) if match else None


def reindent(block, depth):
    lines = [line.strip() for line in block.strip().splitlines() if line.strip()]
    out, level = [], depth
    for line in lines:
        if line.startswith("}"):
            level -= 1
        out.append("\t" * level + line)
        level += line.count("{") - line.count("}") + (1 if line.startswith("}") else 0)
    return out


class Values:
    """Resolves the numeric script values and @constants buildings use for levies and taxes."""

    def __init__(self, game):
        self.constants, self.values = {}, {}
        for folder in ("common/script_values", "common/buildings"):
            for path in (game / folder).glob("*.txt"):
                text = strip_comments(path.read_text(encoding="utf-8-sig"))
                for m in re.finditer(r"^\s*@([A-Za-z0-9_]+)\s*=\s*([^\n]+?)\s*$", text, re.M):
                    self.constants[m.group(1)] = m.group(2)
                if folder == "common/script_values":
                    pattern = r"^([A-Za-z0-9_]+)\s*=\s*(@\[[^\]\n]*\]|@[A-Za-z0-9_]+|-?[0-9.]+)\s*$"
                    for m in re.finditer(pattern, text, re.M):
                        self.values[m.group(1)] = m.group(2)

    def resolve(self, token, depth=0):
        if token is None or depth > 30:
            return 0.0
        token = token.strip()
        try:
            return float(token)
        except ValueError:
            pass
        if token.startswith("@["):
            expression = re.sub(r"[A-Za-z_][A-Za-z0-9_]*",
                                lambda m: repr(self.resolve("@" + m.group(0), depth + 1)), token[2:-1])
            try:
                return float(eval(expression, {"__builtins__": {}}))
            except Exception:
                return 0.0
        if token.startswith("@"):
            return self.resolve(self.constants.get(token[1:]), depth + 1)
        return self.resolve(self.values.get(token), depth + 1)


def load_province_buildings(game):
    buildings = {}
    for path in sorted((game / "common/buildings").glob("*.txt")):
        if path.name in SKIPPED_FILES:
            continue
        text = strip_comments(path.read_text(encoding="utf-8-sig"))
        for key, body in top_level_blocks(text):
            province_modifier = inner_block(body, "province_modifier") or ""
            income = re.search(r"monthly_income\s*=\s*(\S+)", province_modifier)
            buildings[key] = {
                "file": path.name,
                "next": field(body, "next_building"),
                "potential": inner_block(body, "can_construct_potential"),
                "can_construct": inner_block(body, "can_construct"),
                "levy_token": field(body, "levy"),
                "gold_token": income.group(1) if income else None,
            }
    return buildings


def province_chains(buildings):
    """Return {root: [level1, level2, ...]} following next_building."""
    has_previous = {b["next"] for b in buildings.values() if b["next"]}
    chains = {}
    for key in buildings:
        if key in has_previous:
            continue
        chain = [key]
        while buildings[chain[-1]]["next"] in buildings:
            chain.append(buildings[chain[-1]]["next"])
        chains[key] = chain
    return chains


def regular_families(buildings, chains, values):
    """Constructible regular families with their requirement, levels and max-level yields."""
    families = []
    for root, chain in chains.items():
        family = re.sub(r"_01$", "", root)
        building = buildings[root]
        if building["file"] not in REGULAR_FILES or family in HOLDING_MAIN or not root.endswith("_01"):
            continue
        requirement = building["potential"] if building["potential"] and building["potential"].strip() \
            else building["can_construct"]
        if not requirement or not requirement.strip():
            continue
        top = buildings[chain[-1]]
        families.append({
            "name": family,
            "chain": chain,
            "requirement": requirement,
            "levy": values.resolve(top["levy_token"]) if top["levy_token"] else 0.0,
            "gold": values.resolve(top["gold_token"]) if top["gold_token"] else 0.0,
        })
    return families


def load_domicile_buildings(game):
    buildings = {}
    for path in sorted((game / "common/domiciles/buildings").glob("*.txt")):
        text = strip_comments(path.read_text(encoding="utf-8-sig"))
        for key, body in top_level_blocks(text):
            allowed = re.search(r"allowed_domicile_types\s*=\s*\{([^}]*)\}", body)
            buildings[key] = {
                "previous": field(body, "previous_building"),
                "slot": field(body, "slot_type") or "external",
                "types": allowed.group(1).split() if allowed else [],
                "modifiers": (inner_block(body, "character_modifier") or "") + (inner_block(body, "province_modifier") or ""),
            }
    return buildings


ARMY_MODIFIER = re.compile(r"men_at_arms|maa_|knight|levy|garrison|stationed|army_|prowess|advantage|_damage_(mult|add)|"
                           r"_toughness_(mult|add)|_pursuit_|_screen_|_siege_value_|movement_speed|supply")
RESOURCE_MODIFIER = re.compile(r"gold|income|tax|herd|provision|influence|merit|treasury|prestige|piety|renown")


def domicile_priority(buildings, tracks):
    """External building tracks per domicile type: army first, then gold and resources, then the rest."""
    by_type = defaultdict(list)
    for track in tracks:
        root = track[0]
        if buildings[root]["slot"] != "external" or buildings[root]["previous"] in buildings:
            continue
        keys = re.findall(r"([a-z_]+)\s*=", "".join(buildings[level]["modifiers"] for level in track))
        army = sum(1 for k in keys if ARMY_MODIFIER.search(k))
        resources = sum(1 for k in keys if RESOURCE_MODIFIER.search(k))
        group = 0 if army else (1 if resources else 2)
        for domicile_type in buildings[root]["types"]:
            by_type[domicile_type].append((group, -army, -resources, root))
    return {t: [entry[3] for entry in sorted(entries)] for t, entries in sorted(by_type.items())}


def domicile_tracks(buildings):
    """Linear upgrade tracks: successors in the same slot type, stopping at branches."""
    successors = defaultdict(list)
    for key, building in buildings.items():
        if building["previous"] in buildings:
            successors[building["previous"]].append(key)

    def stem(key):
        return re.sub(r"_\d+$", "", key)

    def linear_next(key):
        # Next level of the same building only: same slot type and same name without the
        # level number. A successor with another name is a specialization (for instance
        # chancery_01 -> chancery_legation_01), which stays the player's choice.
        same_slot = [s for s in successors[key] if buildings[s]["slot"] == buildings[key]["slot"]]
        same_building = [s for s in same_slot if stem(s) == stem(key)]
        return same_building[0] if len(same_slot) == 1 and len(same_building) == 1 else None

    def track_from(start):
        track = [start]
        while linear_next(track[-1]):
            track.append(linear_next(track[-1]))
        return track

    order = {"main": 0, "external": 1, "internal": 2}
    roots = [k for k, b in buildings.items()
             if b["previous"] not in buildings or buildings[b["previous"]]["slot"] != b["slot"]]
    # Specializations reached after a branch start tracks of their own.
    branches = [k for k, b in buildings.items()
                if b["previous"] in buildings and buildings[b["previous"]]["slot"] == b["slot"]
                and not linear_next(b["previous"])]
    starts = sorted(roots, key=lambda k: (order.get(buildings[k]["slot"], 3), k)) + sorted(branches)
    return [track for track in map(track_from, starts) if len(track) > 1]


def generate(game):
    version = "unknown"
    settings = game.parent / "launcher/launcher-settings.json"
    if settings.exists():
        match = re.search(r'"rawVersion":\s*"([^"]+)"', settings.read_text(encoding="utf-8"))
        version = match.group(1) if match else version

    buildings = load_province_buildings(game)
    chains = province_chains(buildings)
    families = regular_families(buildings, chains, Values(game))
    forts = [f for name in FORTIFICATIONS for f in families if f["name"] == name]
    others = [f for f in families if f["name"] not in FORTIFICATIONS]
    ranked = forts + sorted((f for f in others if f["levy"] > 0 or f["gold"] > 0),
                            key=lambda f: (-f["levy"], -f["gold"], f["name"]))
    dropped = sorted((f for f in others if f["levy"] <= 0 and f["gold"] <= 0), key=lambda f: f["name"])

    out = [
        "# GENERATED FILE, DO NOT EDIT BY HAND.",
        f"# Built from the game files of CK3 {version} by tools/generate_building_effects.py.",
        "# Run the script again after a game update to pick up new buildings.",
        "",
        "# Priority used by mqa_b_priority_fill_province_effect (yields at maximum level,",
        "# before culture, terrain and holding bonuses):",
        "#   rank  building                levies  gold/month",
    ]
    for rank, family in enumerate(ranked, start=1):
        out.append(f"#   {rank:>4}  {family['name']:<22}{family['levy']:>8.0f}{family['gold']:>12.2f}")
    out.append("#   never built, replaced first: " + ", ".join(f["name"] for f in dropped))
    out.append("")

    out += [
        "# Province scope. Upgrades every existing building to the last level of its chain.",
        "mqa_b_upgrade_province_buildings_effect = {",
    ]
    upgradable = 0
    for root, chain in sorted(chains.items()):
        if len(chain) < 2 or buildings[root]["file"] in NOT_UPGRADED_FILES:
            continue
        upgradable += 1
        out += ["\tif = {", "\t\tlimit = {", "\t\t\tOR = {"]
        out += [f"\t\t\t\thas_building = {level}" for level in chain[:-1]]
        out += ["\t\t\t}", "\t\t}", f"\t\tadd_building = {chain[-1]}", "\t}"]
    out += ["}", ""]

    out.append("# Province scope. Remove a regular building, whatever its level.")
    for family in ranked + dropped:
        out.append(f"mqa_b_remove_{family['name']}_effect = {{")
        for level in family["chain"]:
            out += ["\tif = {", f"\t\tlimit = {{ has_building = {level} }}", f"\t\tremove_building = {level}", "\t}"]
        out += ["}"]
    out.append("")

    out += [
        "# Province scope, scope:holder must be the holder of the barony.",
        "# Goes down the priority list. Each building the game allows here (its own",
        "# can_construct_potential, or can_construct when there is none) and that is missing",
        "# is built at maximum level in a free slot; when no slot is free, the worst-ranked",
        "# building below it is removed to make room. No slot is ever added.",
        "# Innovation requirements are deliberately ignored, as in the original mod.",
        "mqa_b_priority_fill_province_effect = {",
    ]
    for rank, family in enumerate(ranked):
        victims = dropped + list(reversed(ranked[rank + 1:]))
        out += ["\tif = {", "\t\tlimit = {", f"\t\t\tNOT = {{ has_building_or_higher = {family['chain'][0]} }}"]
        out += reindent(family["requirement"], 3)
        out += ["\t\t}"]
        if victims:
            out += ["\t\tif = {", "\t\t\tlimit = { free_building_slots < 1 }"]
            for index, victim in enumerate(victims):
                keyword = "if" if index == 0 else "else_if"
                out += [
                    f"\t\t\t{keyword} = {{",
                    f"\t\t\t\tlimit = {{ has_building_or_higher = {victim['chain'][0]} }}",
                    f"\t\t\t\tmqa_b_remove_{victim['name']}_effect = yes",
                    "\t\t\t}",
                ]
            out += ["\t\t}"]
        out += [
            "\t\tif = {",
            "\t\t\tlimit = { free_building_slots > 0 }",
            f"\t\t\tadd_building = {family['chain'][-1]}",
            "\t\t}",
            "\t}",
        ]
    out += ["}", ""]

    domicile_buildings = load_domicile_buildings(game)
    tracks = domicile_tracks(domicile_buildings)
    priorities = domicile_priority(domicile_buildings, tracks)
    out += [
        "# Domicile scope. Builds missing external buildings in free external slots, in order:",
        "# buildings with army bonuses first, then gold and resources, then the rest.",
        "# The game still checks each building's own requirements.",
        "mqa_b_construct_domicile_effect = {",
    ]
    for domicile_type, roots in priorities.items():
        out += ["\tif = {", f"\t\tlimit = {{ is_domicile_type = {domicile_type} }}"]
        for root in roots:
            out += [
                "\t\tif = {",
                "\t\t\tlimit = {",
                "\t\t\t\tfree_external_domicile_building_slots >= 1",
                f"\t\t\t\tNOT = {{ has_domicile_building_or_higher = {root} }}",
                "\t\t\t}",
                f"\t\t\tadd_domicile_building = {root}",
                "\t\t}",
            ]
        out += ["\t}"]
    out += ["}", ""]

    out += [
        "# Domicile scope. Upgrades every domicile building along its track, one level at a time",
        "# (main building first). Stops where a track branches into specializations.",
        "mqa_b_upgrade_domicile_effect = {",
    ]
    for track in tracks:
        for current, following in zip(track, track[1:]):
            out += [
                "\tif = {",
                f"\t\tlimit = {{ has_domicile_building = {current} }}",
                f"\t\tadd_domicile_building = {following}",
                "\t}",
            ]
    out += ["}", ""]

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text("﻿" + "\n".join(out), encoding="utf-8")
    print(f"CK3 {version}: {upgradable} upgradable building chains, {len(ranked)} ranked and "
          f"{len(dropped)} dropped building families, {len(tracks)} domicile tracks -> {OUTPUT}")
    for rank, family in enumerate(ranked, start=1):
        print(f"  {rank:>3}. {family['name']:<22} levies {family['levy']:>5.0f}  gold {family['gold']:.2f}")
    print("  dropped: " + ", ".join(f["name"] for f in dropped))


if __name__ == "__main__":
    generate(Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_GAME)
