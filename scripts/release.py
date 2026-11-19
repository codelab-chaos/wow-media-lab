#!/usr/bin/env python3
"""Prepare a release: bump versions, refresh the catalog, run the checks, package.

    python3 scripts/release.py 0.2.0 [--interface 16002] [--fetch] [--skip-catalog]

It never commits, tags or deploys; it prints what to do next.
"""

import argparse
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOC = ROOT / "MediaLab" / "MediaLab.toc"
TOCS = [TOC, ROOT / "MediaLab_Export" / "MediaLab_Export.toc", ROOT / "MediaLab_Icons" / "MediaLab_Icons.toc"]
README = ROOT / "README.md"
CATALOG_DOC = ROOT / "docs" / "addon-dev.md"  # quotes the catalog counts
# A wow-ui-source checkout: WOW_UI_SOURCE, or ../../hub/wow-ui-source.
SOURCE = Path(os.environ.get("WOW_UI_SOURCE") or ROOT.parent.parent / "hub" / "wow-ui-source")

CHECKS = [
    "rg --files MediaLab MediaLab_Export tests scripts -g '*.lua' -0 | xargs -0 -n1 luac5.1 -p",
    "lua5.1 tests/run.lua",
    "python3 -m unittest discover -s tests -p 'test_*.py'",
]


def bump_toc(text, version, interface=None):
    text = re.sub(r"^(## Version:\s*)\S+", rf"\g<1>{version}", text, count=1, flags=re.M)
    if interface:
        text = re.sub(r"^(## Interface:\s*)\S+", rf"\g<1>{interface}", text, count=1, flags=re.M)
    return text


def bump_readme(text, old, new, interface=None):
    text = text.replace(f"Version **{old}**", f"Version **{new}**")
    text = text.replace(f"MediaLab-{old}.zip", f"MediaLab-{new}.zip")
    if interface:
        text = re.sub(r"interface \*\*\d+\*\*", f"interface **{interface}**", text)
    return text


# Lines in CATALOG_DOC that quote the generated catalog: (line prefix pattern, JSON kinds summed).
CATALOG_FACTS = [
    (r"literal texture paths", ["icons", "textures"]),
    (r"atlas names", ["atlases"]),
    (r"`SOUNDKIT` names", ["sounds"]),
    (r"virtual templates", ["templates"]),
    (r"font objects", ["fonts"]),
]


def sync_catalog_facts(text, documents):
    """Rewrites the catalog doc's source version, commit and counts from catalog/*.json."""
    source = documents["sounds"]["source"]
    text = re.sub(r"\(version `[^`]+`, commit `[0-9a-f]+`\)",
                  f"(version `{source['version']}`, commit `{source['commit'][:12]}`)", text)
    for label, kinds in CATALOG_FACTS:
        count = sum(documents[kind]["count"] for kind in kinds)
        text = re.sub(rf"^- [\d,]+ ({label})", rf"- {count:,} \g<1>", text, flags=re.M)
    return text


def load_catalog():
    import json
    return {path.stem: json.loads(path.read_text()) for path in (ROOT / "catalog").glob("*.json")}


def current(field):
    return re.search(rf"^## {field}:\s*(\S+)", TOC.read_text(), re.M).group(1)


def run(command):
    print(f"$ {command}", flush=True)
    if subprocess.run(command, shell=True, cwd=ROOT).returncode:
        sys.exit(f"release stopped: {command} failed")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("version", help="new addon version, e.g. 0.2.0")
    parser.add_argument("--interface", help="new ## Interface number, when the game patch changed it")
    parser.add_argument("--fetch", action="store_true", help="git fetch the UI source before regenerating")
    parser.add_argument("--skip-catalog", action="store_true", help="keep the current generated data")
    args = parser.parse_args()
    if not re.fullmatch(r"\d+\.\d+\.\d+", args.version):
        sys.exit("version must look like 1.2.3")

    old = current("Version")
    for toc in TOCS:
        toc.write_text(bump_toc(toc.read_text(), args.version, args.interface))
    README.write_text(bump_readme(README.read_text(), old, args.version, args.interface))
    print(f"version {old} -> {args.version}, interface {current('Interface')}")

    if not args.skip_catalog:
        if args.fetch:
            run(f"git -C {SOURCE} fetch origin forever")
        run("python3 scripts/build-catalog.py")
        CATALOG_DOC.write_text(sync_catalog_facts(CATALOG_DOC.read_text(), load_catalog()))
    for command in CHECKS:
        run(command)
    run("python3 scripts/package.py")
    print("\nReady. Review `git diff`, then commit, deploy (scripts/deploy.sh) and smoke test in game.")


if __name__ == "__main__":
    main()
