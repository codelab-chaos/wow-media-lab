"""The published database, catalog/wow-data.sqlite: curated game facts built
from the raw client import. Each table comes from a builder module that
declares its schema (TABLE) and yields its rows (rows(db)); docs/data.md
documents every table and column, and the tests hold the two together.
"""

import datetime
import json
import sqlite3
import subprocess
from pathlib import Path

from . import icons, models

ROOT = Path(__file__).resolve().parents[2]
PATH = ROOT / "catalog" / "wow-data.sqlite"

# Bump when a published table or column changes shape, so readers can check.
SCHEMA_VERSION = 1

BUILDERS = [models, icons]

META = {
    "name": "meta",
    "description": "Where this database came from: one row per key.",
    "columns": [
        ("key", "TEXT PRIMARY KEY", "`schema_version`, `client_build`, `generated`, `commit` or `sources`"),
        ("value", "TEXT", "Its value; `sources` is a JSON object"),
    ],
}

TABLES = {
    "name": "tables",
    "description": "The published tables, with their row counts.",
    "columns": [
        ("name", "TEXT PRIMARY KEY", "Table name"),
        ("rows", "INTEGER", "Row count"),
        ("description", "TEXT", "What the table holds"),
    ],
}


def schemas():
    return [META, TABLES] + [builder.TABLE for builder in BUILDERS]


def create(db, table):
    columns = ", ".join(f"{name} {kind}" for name, kind, _ in table["columns"])
    db.execute(f"CREATE TABLE {table['name']} ({columns})")
    for index, columns in enumerate(table.get("indexes", [])):
        db.execute(f"CREATE INDEX {table['name']}_{index} ON {table['name']} ({columns})")


def commit_id():
    try:
        head = subprocess.run(["git", "rev-parse", "--short=12", "HEAD"], cwd=ROOT, capture_output=True,
                              text=True, check=True).stdout.strip()
        dirty = subprocess.run(["git", "status", "--porcelain"], cwd=ROOT, capture_output=True, text=True).stdout
        return head + ("-dirty" if dirty.strip() else "")
    except (OSError, subprocess.CalledProcessError):
        return ""


def build(client_path, path=PATH, builders=None):
    """Writes the published database from the client import; returns row counts."""
    if not Path(client_path).is_file():
        raise FileNotFoundError(f"{client_path} missing; run scripts/game-data.py import first")
    builders = BUILDERS if builders is None else builders
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(".tmp")
    temporary.unlink(missing_ok=True)
    db = sqlite3.connect(temporary)
    db.execute("ATTACH DATABASE ? AS client", (str(client_path),))
    counts = {}
    for builder in builders:
        table = builder.TABLE
        create(db, table)
        marks = ", ".join("?" * len(table["columns"]))
        db.executemany(f"INSERT INTO {table['name']} VALUES ({marks})", builder.rows(db))
        counts[table["name"]] = db.execute(f"SELECT COUNT(*) FROM {table['name']}").fetchone()[0]
    client_build = db.execute("SELECT MAX(build) FROM client._tables").fetchone()[0]
    sources = {row[0]: row[1] for row in db.execute("SELECT name, rows FROM client._tables WHERE status = 'ok'")}
    db.commit()
    db.execute("DETACH DATABASE client")

    create(db, META)
    db.executemany("INSERT INTO meta VALUES (?, ?)", [
        ("schema_version", str(SCHEMA_VERSION)),
        ("client_build", client_build or ""),
        ("generated", datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")),
        ("commit", commit_id()),
        ("sources", json.dumps({"tables": sources, "names": "wowdev/wow-listfile", "columns": "wowdev/WoWDBDefs"},
                               sort_keys=True)),
    ])
    create(db, TABLES)
    db.executemany("INSERT INTO tables VALUES (?, ?, ?)",
                   [(b.TABLE["name"], counts[b.TABLE["name"]], b.TABLE["description"]) for b in builders])
    db.commit()
    db.execute("VACUUM")
    db.close()
    temporary.replace(path)
    return counts
