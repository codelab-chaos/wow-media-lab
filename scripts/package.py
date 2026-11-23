#!/usr/bin/env python3
"""Build the release zip: extract it into Interface/AddOns and it works."""

from pathlib import Path
import re
from zipfile import ZIP_DEFLATED, ZipFile

ROOT = Path(__file__).resolve().parents[1]

# Addon folders shipped in the release zip, each with its own .toc manifest.
ADDONS = ["MediaLab", "MediaLab_Icons", "MediaLab_Models", "MediaLab_Sounds"]


def manifest_files(name):
    addon = ROOT / name
    toc = addon / f"{name}.toc"
    paths = [toc]
    for line in toc.read_text().splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        path = addon / line.replace("\\", "/")
        if not path.is_file() or not path.resolve().is_relative_to(addon):
            raise ValueError(f"Invalid manifest entry in {name}: {line}")
        paths.append(path)
    return paths


def version():
    return re.search(r"^## Version:\s*(\S+)", (ROOT / "MediaLab" / "MediaLab.toc").read_text(), re.M).group(1)


def package():
    output = ROOT / "dist" / f"MediaLab-{version()}.zip"
    output.parent.mkdir(exist_ok=True)
    with ZipFile(output, "w", ZIP_DEFLATED) as archive:
        for name in ADDONS:
            for path in manifest_files(name):
                archive.write(path, path.relative_to(ROOT))
            archive.write(ROOT / "LICENSE", f"{name}/LICENSE")
    print(output)
    return output


if __name__ == "__main__":
    package()
