#!/usr/bin/env python3
"""Convert an in-game /mlab export into JSON files under catalog/client/.

    python3 scripts/import-export.py [--input <MediaLab_Export.lua>]

Without --input it looks next to the AddOns folder named by WOW_ADDONS_DIR or
.deploy-target: WTF/Account/*/SavedVariables/MediaLab_Export.lua (newest wins).
The game only writes that file on /reload or logout after /mlab export.
"""

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "catalog" / "client"
# In-game kind ids -> the file names the source catalog already uses.
FILES = {"icon": "icons", "texture": "textures", "atlas": "atlases", "sound": "sounds",
         "control": "templates", "font": "fonts"}


def find_export():
    addons = os.environ.get("WOW_ADDONS_DIR")
    target = ROOT / ".deploy-target"
    if not addons and target.is_file():
        addons = target.read_text().splitlines()[0].strip()
    if not addons:
        sys.exit("Pass --input, or set WOW_ADDONS_DIR / .deploy-target.")
    game = Path(addons).parent.parent
    found = sorted(game.glob("WTF/Account/*/SavedVariables/MediaLab_Export.lua"), key=lambda p: p.stat().st_mtime)
    if not found:
        sys.exit(f"No MediaLab_Export.lua under {game}/WTF. Run /mlab export in game, then /reload.")
    return found[-1]


def convert(path, output=OUTPUT):
    result = subprocess.run(["lua5.1", str(ROOT / "scripts" / "sv2json.lua"), str(path)],
                            capture_output=True, text=True, check=True)
    data = json.loads(result.stdout)
    output.mkdir(parents=True, exist_ok=True)
    source = {"client": data.get("client"), "addonVersion": data.get("addonVersion"), "exported": data.get("exported")}
    written = {}
    for kind, block in sorted(data["kinds"].items()):
        name = FILES.get(kind, kind)
        document = {"kind": name, "source": source, "fields": block["fields"],
                    "count": len(block["items"]), "items": block["items"]}
        (output / f"{name}.json").write_text(json.dumps(document, indent=1) + "\n")
        written[name] = document["count"]
    return written


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--input", type=Path)
    args = parser.parse_args()
    path = args.input or find_export()
    counts = convert(path)
    print(f"{path} -> {OUTPUT}")
    for name, count in counts.items():
        print(f"  {name}: {count:,}")
