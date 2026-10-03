#!/usr/bin/env python3
"""Generate common/scripted_effects/mqa_lifestyle_effects.txt from the game files.

mqa_unlock_all_perks_effect (character scope) unlocks every lifestyle perk of the
installed game, parents before children so each perk's own effect runs as in a normal
game (the last perk of a tree grants its trait). Wanderer perks are only added with
Wandering Nobles. Run again after a game update:

    python3 tools/generate_lifestyle_effects.py [path/to/Crusader Kings III/game]
"""
import re
import sys
from pathlib import Path

from generate_building_effects import DEFAULT_GAME, strip_comments, top_level_blocks

OUTPUT = Path(__file__).resolve().parent.parent / "common/scripted_effects/mqa_lifestyle_effects.txt"


def load_perks(game):
    perks = {}
    for path in sorted((game / "common/lifestyle_perks").glob("*.txt")):
        text = strip_comments(path.read_text(encoding="utf-8-sig"))
        for key, body in top_level_blocks(text):
            lifestyle = re.search(r"(?m)^\tlifestyle\s*=\s*(\w+)", body)
            perks[key] = {
                "parents": re.findall(r"(?m)^\tparent\s*=\s*(\w+)", body),
                "lifestyle": lifestyle.group(1) if lifestyle else "",
                "file": path.name,
            }
    return perks


def ordered(perks):
    """Parents before children, in file order otherwise."""
    done, out = set(), []

    def visit(key):
        if key in done or key not in perks:
            return
        done.add(key)
        for parent in perks[key]["parents"]:
            visit(parent)
        out.append(key)

    for key in perks:
        visit(key)
    return out


def generate(game):
    perks = load_perks(game)
    keys = ordered(perks)
    regular = [k for k in keys if perks[k]["lifestyle"] != "wanderer_lifestyle"]
    wanderer = [k for k in keys if perks[k]["lifestyle"] == "wanderer_lifestyle"]

    def unlock(key, depth):
        tab = "\t" * depth
        return [f"{tab}if = {{", f"{tab}\tlimit = {{ NOT = {{ has_perk = {key} }} }}", f"{tab}\tadd_perk = {key}", f"{tab}}}"]

    out = [
        "# GENERATED FILE, DO NOT EDIT BY HAND.",
        "# Built from the game files by tools/generate_lifestyle_effects.py.",
        "",
        "# Character scope. Unlocks every lifestyle perk, parents first.",
        "mqa_unlock_all_perks_effect = {",
    ]
    for key in regular:
        out += unlock(key, 1)
    if wanderer:
        out += ["\tif = {", "\t\tlimit = { has_dlc_feature = wandering_nobles }"]
        for key in wanderer:
            out += unlock(key, 2)
        out += ["\t}"]
    out += ["}", ""]
    OUTPUT.write_text("﻿" + "\n".join(out), encoding="utf-8")
    print(f"{len(regular)} perks, {len(wanderer)} wanderer perks -> {OUTPUT}")


if __name__ == "__main__":
    generate(Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_GAME)
