"""Raw import: the client's DB2 tables, copied as they are into .cache/client.sqlite.

One SQLite table per DB2 table, named and typed from WoWDBDefs; arrays become
numbered columns (Reagent_0, Reagent_1). The _tables table records what was
read. This is local scratch for building the published database, not an output.
"""

import sqlite3
import struct
import time
from pathlib import Path

from . import listfile

ROOT = Path(__file__).resolve().parents[2]
PATH = ROOT / ".cache" / "client.sqlite"
DBD = ROOT / ".cache" / "dbd"

# What the published database is built from. --all tries every table.
DEFAULT_TABLES = [
    # spells and auras
    "Spell", "SpellName", "SpellMisc", "SpellEffect", "SpellReagents", "SpellDuration", "SpellAuraOptions",
    "SpellCooldowns", "SpellLevels", "SpellCastTimes", "SpellRange", "SpellCategories",
    # items
    "Item", "ItemSparse", "ItemClass", "ItemSubClass", "ItemAppearance", "ItemModifiedAppearance", "ItemEffect",
    # professions
    "SkillLine", "SkillLineAbility", "TradeSkillCategory",
    # creatures
    "Creature", "CreatureDisplayInfo", "CreatureDisplayInfoExtra", "CreatureModelData",
    # other icon users
    "Achievement", "CurrencyTypes", "Mount", "ChrClasses", "ChrRaces", "ChrSpecialization", "Faction",
    "SpellItemEnchantment", "BattlePetSpecies", "CreatureFamily", "SpellShapeshiftForm",
]

SQL_TYPES = {"int": "INTEGER", "float": "REAL", "string": "TEXT"}


def connect(path=PATH):
    path.parent.mkdir(parents=True, exist_ok=True)
    db = sqlite3.connect(path)
    db.execute("CREATE TABLE IF NOT EXISTS _tables (name TEXT PRIMARY KEY, file_id INTEGER, layout TEXT, "
                "rows INTEGER, status TEXT, build TEXT, seconds REAL)")
    return db


def store_table(db, name, fields, rows):
    """Replaces one SQL table with the rows of a DB2 table."""
    columns, decls = [], []
    for field in fields:
        for column in field.columns():
            columns.append(column)
            decls.append(f'"{column}" {SQL_TYPES[field.kind]}')
    db.execute(f'DROP TABLE IF EXISTS "{name}"')
    db.execute(f'CREATE TABLE "{name}" ({", ".join(decls)})')

    def flat(row):
        values = []
        for field in fields:
            value = row.get(field.name)
            values.extend(value if field.count > 1 else [value])
        return values

    marks = ", ".join("?" * len(columns))
    db.executemany(f'INSERT INTO "{name}" VALUES ({marks})', (flat(row) for row in rows))
    if any(field.name == "ID" for field in fields):
        db.execute(f'CREATE INDEX "{name}_ID" ON "{name}" (ID)')


def store_files(db, store):
    """Every file data ID the client ships, so the build can tell what exists."""
    db.execute("DROP TABLE IF EXISTS _files")
    db.execute("CREATE TABLE _files (id INTEGER PRIMARY KEY) WITHOUT ROWID")
    db.executemany("INSERT INTO _files VALUES (?)", ((fdid,) for fdid in store.files))
    db.commit()


def import_tables(store, names, db, db2):
    known = db2.definitions(DBD)
    files = listfile.tables()
    for name in names:
        started = time.time()
        fdid = files.get(name.lower())
        layout, rows, status = None, 0, "ok"
        name = known[name.lower()].stem if name.lower() in known else name
        try:
            if name.lower() not in known:
                raise LookupError("no WoWDBDefs definition")
            if fdid is None or fdid not in store.files:
                raise LookupError("not in this client")
            raw = store.read(fdid, skip_encrypted=True)
            data = db2.read(raw, name, DBD)
            layout = f"{db2.layout_hash(raw):08X}"
            fields = db2.dbd_layout(name, db2.layout_hash(raw), DBD)
            store_table(db, name, fields, data)
            rows = len(data)
        except (LookupError, ValueError, KeyError, struct.error, IndexError) as error:
            status = f"skipped: {error}"
        db.execute("INSERT OR REPLACE INTO _tables VALUES (?, ?, ?, ?, ?, ?, ?)",
                   (name, fdid, layout, rows, status, store.version, round(time.time() - started, 2)))
        db.commit()
        yield name, rows, status


def all_tables(store):
    return sorted(name for name, fdid in listfile.tables().items() if fdid in store.files)
