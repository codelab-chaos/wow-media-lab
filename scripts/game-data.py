#!/usr/bin/env python3
"""Game data from the local client, into one published SQLite database.

    .venv/bin/python scripts/game-data.py            # import, then build
    .venv/bin/python scripts/game-data.py import [--all] [--tables Spell Item]
    .venv/bin/python scripts/game-data.py build

import  copies the client's DB2 tables (local CASC, read only; columns from
        WoWDBDefs) into .cache/client.sqlite. Local scratch, never shipped.
build   builds catalog/wow-data.sqlite from it (the published tables are
        described in docs/data.md), then writes the exports generated from it:
        catalog/models.json and MediaLab_Models/data.lua.

Only facts are read and written: IDs, names, numbers. No artwork or audio.
"""

import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
import db2  # noqa: E402
from casc import Casc, game_root  # noqa: E402
from gamedata import client, exports, published  # noqa: E402


def run_import(args):
    store = Casc(game_root(ROOT))
    names = client.all_tables(store) if args.all else (args.tables or client.DEFAULT_TABLES)
    db = client.connect()
    client.store_files(db, store)
    loaded = skipped = 0
    for name, rows, status in client.import_tables(store, names, db, db2):
        if status == "ok":
            loaded += 1
        else:
            skipped += 1
        if status != "ok" or not args.all:
            print(f"  {name}: {rows:,} rows" if status == "ok" else f"  {name}: {status}")
    db.close()
    print(f"import: {loaded} tables from client {store.version} -> {client.PATH.relative_to(ROOT)}"
          f" ({skipped} skipped)")


def run_build(_args):
    counts = published.build(client.PATH, published.PATH)
    print("build: " + ", ".join(f"{name} {rows:,}" for name, rows in counts.items())
          + f" -> {published.PATH.relative_to(ROOT)}")
    for line in exports.write_all(published.PATH):
        print(f"export: {line}")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("step", nargs="?", choices=["import", "build"], help="one step; both when omitted")
    parser.add_argument("--all", action="store_true", help="import every table the client ships")
    parser.add_argument("--tables", nargs="+", help="import only these tables")
    args = parser.parse_args()
    if args.step in (None, "import"):
        run_import(args)
    if args.step in (None, "build"):
        run_build(args)


if __name__ == "__main__":
    main()
