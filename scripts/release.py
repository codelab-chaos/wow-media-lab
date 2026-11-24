#!/usr/bin/env python3
"""Prepare a release: bump versions, optionally refresh the data, run the checks, package.

    python3 scripts/release.py 0.2.0 [--interface 16002] [--sync]

The notes under "## Unreleased" in CHANGELOG.md become the version's section
(it stops if there are none), and are written to dist/MediaLab-<version>-notes.md
for the GitHub release and the CurseForge changelog.

--sync regenerates the data files from the Codex of Azeroth first
(scripts/sync-codex.py). It never commits, tags or deploys; it prints what to do next.
"""

import argparse
import datetime
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOC = ROOT / "MediaLab" / "MediaLab.toc"
TOCS = [TOC] + [ROOT / name / f"{name}.toc" for name in ("MediaLab_Icons", "MediaLab_Models", "MediaLab_Sounds")]
README = ROOT / "README.md"
CHANGELOG = ROOT / "CHANGELOG.md"
UNRELEASED = "## Unreleased"

CHECKS = [
    "find MediaLab tests -name '*.lua' -print0 | xargs -0 -n1 luac5.1 -p",
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


def section(text, heading):
    """The body under a '## heading' line, up to the next '## ' line, or None."""
    match = re.search(rf"^## {re.escape(heading)}\b[^\n]*\n(.*?)(?=^## |\Z)", text, re.M | re.S)
    return match.group(1).strip() if match else None


def release_changelog(text, version, date):
    """Moves the Unreleased notes under a new '## version (date)' heading."""
    if section(text, version) is not None:
        return text
    notes = section(text, "Unreleased")
    if not notes:
        raise ValueError(f"CHANGELOG.md has nothing under {UNRELEASED}; write the notes for {version} first")
    return text.replace(UNRELEASED + "\n", f"{UNRELEASED}\n\n## {version} ({date})\n", 1)


def write_notes(version):
    notes = section(CHANGELOG.read_text(), version)
    path = ROOT / "dist" / f"MediaLab-{version}-notes.md"
    path.parent.mkdir(exist_ok=True)
    path.write_text(notes + "\n")
    print(path)


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
    parser.add_argument("--sync", action="store_true", help="refresh the data from the Codex of Azeroth first")
    args = parser.parse_args()
    if not re.fullmatch(r"\d+\.\d+\.\d+", args.version):
        sys.exit("version must look like 1.2.3")

    try:
        changelog = release_changelog(CHANGELOG.read_text(), args.version, datetime.date.today().isoformat())
    except ValueError as problem:
        sys.exit(f"release stopped: {problem}")
    CHANGELOG.write_text(changelog)
    old = current("Version")
    for toc in TOCS:
        toc.write_text(bump_toc(toc.read_text(), args.version, args.interface))
    README.write_text(bump_readme(README.read_text(), old, args.version, args.interface))
    print(f"version {old} -> {args.version}, interface {current('Interface')}")
    if args.sync:
        run("python3 scripts/sync-codex.py")
    for command in CHECKS:
        run(command)
    run("python3 scripts/package.py")
    write_notes(args.version)
    print("\nReady. Review `git diff`, then commit, deploy (scripts/deploy.sh) and smoke test in game.")


if __name__ == "__main__":
    main()
