#!/usr/bin/env python3
"""Prints puzzles from a generated pack as ASCII grids: preview.py PACK.json [index ...]

Indices are zero based, as in the pack; `d12` is the daily puzzle at index 12. Levels are also
labelled with their number in the game, which counts from 1."""
import json
import sys


def render(level):
    cells = {}
    for w in level["words"]:
        dr, dc = (0, 1) if w["d"] == "a" else (1, 0)
        for k, ch in enumerate(w["w"]):
            cells[(w["r"] + dr * k, w["c"] + dc * k)] = ch
    rows = max(r for r, _ in cells) + 1
    cols = max(c for _, c in cells) + 1
    lines = [" ".join(cells.get((r, c), "·") for c in range(cols)) for r in range(rows)]
    words = ", ".join(w["w"] for w in level["words"])
    return (f"letters {level['letters']}  grid {rows}x{cols}  words({len(level['words'])}): {words}\n"
            f"bonus({len(level['bonus'])}): {' '.join(level['bonus'][:30])}\n" + "\n".join(lines))


def parse(arg: str, pack) -> tuple[str, int]:
    """The series and index an argument names, or exits saying why it names none."""
    name, digits = ("daily", arg[1:]) if arg.startswith("d") else ("levels", arg)
    # Digits only: Python would read "-1" as the last puzzle, labelled level 0.
    if not digits.isdigit():
        sys.exit(f"{arg}: expected an index such as 12 or d12")
    i = int(digits)
    if i >= len(pack[name]):
        sys.exit(f"{arg}: the pack has {len(pack[name])} {name} puzzles (indices 0–{len(pack[name]) - 1})")
    return name, i


if __name__ == "__main__":
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    pack = json.load(open(sys.argv[1], encoding="utf-8"))
    for name, i in [parse(arg, pack) for arg in sys.argv[2:]]:
        if name == "daily":
            print(f"\n=== daily index {i}"); print(render(pack["daily"][i]))
        else:
            print(f"\n=== level index {i} (Level {i + 1} in the game)"); print(render(pack["levels"][i]))
