"""The community listfile (wowdev/wow-listfile): file data IDs to lowercase paths."""

import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PATH = ROOT / ".cache" / "community-listfile.csv"
URL = "https://github.com/wowdev/wow-listfile/releases/latest/download/community-listfile.csv"


def ensure(refresh=False):
    if refresh or not PATH.is_file():
        print(f"downloading {URL}")
        PATH.parent.mkdir(parents=True, exist_ok=True)
        urllib.request.urlretrieve(URL, PATH)
    return PATH


def paths(keep=lambda fdid, path: True):
    """{file data ID: path} for the entries keep() accepts."""
    names = {}
    with open(ensure(), encoding="utf-8", errors="replace") as handle:
        for line in handle:
            fdid, _, path = line.partition(";")
            if fdid.isdigit():
                path = path.strip().lower()
                if keep(int(fdid), path):
                    names[int(fdid)] = path
    return names


def tables():
    """{lowercase DB2 table name: file data ID}, from dbfilesclient/*.db2 entries."""
    found = paths(lambda fdid, path: path.startswith("dbfilesclient/") and path.endswith(".db2"))
    return {path[len("dbfilesclient/"):-len(".db2")]: fdid for fdid, path in found.items()}
