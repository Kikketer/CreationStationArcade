#!/usr/bin/env python3
"""arcade-regen-games.py — rebuild games.json for a games directory.

Usage: arcade-regen-games.py <games-dir>

Scans <games-dir> for *.js game files and rewrites <games-dir>/games.json:

- Existing entries for files that still exist are preserved (manual edits
  to name/author/playerCount/image survive).
- Entries with an empty "file" are decorative tiles (e.g. a per-machine
  "Your Game Here" card) — preserved and kept at the end of the list.
- Entries pointing at files that no longer exist are dropped.
- New .js files get an entry with name/author split from the camelCase
  filename (LouisaMushrooms.js -> author "Louisa", name "Mushrooms") and
  playerCount 1.
- If <games-dir>/usb-meta.json exists, its per-file overrides
  (name/author/playerCount/image) are applied last — that's how USB-sidecar
  metadata wins over stale entries.
"""

import json
import os
import re
import sys

META_KEYS = ("name", "author", "playerCount", "image")


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__.strip())
        return 2

    games_dir = sys.argv[1]
    output_path = os.path.join(games_dir, "games.json")
    meta_path = os.path.join(games_dir, "usb-meta.json")

    existing = []
    if os.path.isfile(output_path):
        try:
            with open(output_path) as f:
                existing = json.load(f)
        except (json.JSONDecodeError, IOError):
            existing = []

    existing_by_file = {e["file"]: e for e in existing if e.get("file")}
    # Decorative tiles: entries with no file (or a file that isn't a .js game)
    tiles = [e for e in existing if not e.get("file")]

    meta = {}
    if os.path.isfile(meta_path):
        try:
            with open(meta_path) as f:
                meta = json.load(f)
        except (json.JSONDecodeError, IOError):
            meta = {}

    js_files = sorted(
        f
        for f in os.listdir(games_dir)
        if f.endswith(".js")
        and os.path.isfile(os.path.join(games_dir, f))
        and not f.startswith(".")
    )

    result = []
    for fname in js_files:
        stem = fname[:-3]
        words = re.sub(r"([a-z])([A-Z])", r"\1 \2", stem)
        words = re.sub(r"([A-Z])([A-Z][a-z])", r"\1 \2", words).split()
        entry = dict(
            existing_by_file.get(fname)
            or {
                "name": " ".join(words[1:]) if len(words) > 1 else stem,
                "author": words[0] if words else "",
                "playerCount": 1,
                "file": fname,
            }
        )
        entry["file"] = fname
        overrides = meta.get(fname) or {}
        entry.update({k: overrides[k] for k in META_KEYS if k in overrides})
        result.append(entry)

    result.extend(tiles)

    with open(output_path, "w") as f:
        json.dump(result, f, indent=2)
        f.write("\n")

    print(f"Regenerated {output_path}: {len(result)} entries ({len(tiles)} tile(s))")
    return 0


if __name__ == "__main__":
    sys.exit(main())
