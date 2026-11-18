#!/usr/bin/env python3
"""Build a ZIP that can be extracted directly into Interface/AddOns."""

from pathlib import Path
import re
from zipfile import ZIP_DEFLATED, ZipFile

ROOT = Path(__file__).resolve().parents[1]


def package():
    addon = ROOT / "MediaLab"
    toc = addon / "MediaLab.toc"
    manifest = toc.read_text()
    version = re.search(r"^## Version:\s*(\S+)", manifest, re.M).group(1)
    paths = [toc]
    for line in manifest.splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        path = addon / line.replace("\\", "/")
        if not path.is_file() or not path.resolve().is_relative_to(addon):
            raise ValueError(f"Invalid manifest entry: {line}")
        paths.append(path)
    output = ROOT / "dist" / f"MediaLab-{version}.zip"
    output.parent.mkdir(exist_ok=True)
    with ZipFile(output, "w", ZIP_DEFLATED) as archive:
        for path in paths:
            archive.write(path, path.relative_to(ROOT))
        archive.write(ROOT / "LICENSE", "MediaLab/LICENSE")
    print(output)
    return output


if __name__ == "__main__":
    package()

