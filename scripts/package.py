#!/usr/bin/env python3
"""Build a ZIP that can be extracted directly into Interface/AddOns."""

from pathlib import Path
import re
from zipfile import ZIP_DEFLATED, ZipFile

ROOT = Path(__file__).resolve().parents[1]


# Addon folders shipped in the release zip, each with its own .toc manifest.
ADDONS = ["MediaLab", "MediaLab_Export"]


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


def package_catalog():
    """The JSON catalog as its own download, for tools and authors outside the game."""
    folder = ROOT / "catalog"
    files = sorted(folder.glob("**/*.json"))
    if not files:
        raise FileNotFoundError("No catalog/*.json; run scripts/build-catalog.py first")
    output = ROOT / "dist" / f"MediaLab-catalog-{version()}.zip"
    output.parent.mkdir(exist_ok=True)
    with ZipFile(output, "w", ZIP_DEFLATED) as archive:
        for path in files:
            archive.write(path, Path("MediaLab-catalog") / path.relative_to(folder))
        archive.write(ROOT / "LICENSE", "MediaLab-catalog/LICENSE")
    print(output)
    return output


if __name__ == "__main__":
    package()
    package_catalog()

