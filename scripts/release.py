#!/usr/bin/env python3
"""Prepare a release: bump versions, optionally refresh the data, run the checks, package.

    python3 scripts/release.py 0.2.0 [--interface 16002] [--sync]

--sync regenerates the data files from the Codex of Azeroth first
(scripts/sync-codex.py). It never commits, tags or deploys; it prints what to do next.
"""

import argparse
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOC = ROOT / "MediaLab" / "MediaLab.toc"
TOCS = [TOC] + [ROOT / name / f"{name}.toc" for name in ("MediaLab_Icons", "MediaLab_Models", "MediaLab_Sounds")]
README = ROOT / "README.md"

CHECKS = [
    "rg --files MediaLab tests -g '*.lua' -0 | xargs -0 -n1 luac5.1 -p",
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
    print("\nReady. Review `git diff`, then commit, deploy (scripts/deploy.sh) and smoke test in game.")


if __name__ == "__main__":
    main()
