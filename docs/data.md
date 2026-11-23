# The game database

`wow-data.sqlite` holds facts about the game, read from your local client's own
data tables: creature models today, and what uses each icon. It is one
[SQLite](https://sqlite.org) file you can query from any language, the
`sqlite3` shell, or a database browser. MediaLab's model data and
`catalog/models.json` are generated from it. Other tools (an addon studio, a
profession planner) can read it directly.

It ships with each release as `MediaLab-data-<version>.sqlite`. It holds IDs,
names and numbers only, never artwork or audio. This page describes
schema version **1**.

## Example queries

What uses the Fireball icon:

```sql
SELECT kind, ref, name FROM icon_usage WHERE icon = 135812;
```

Every murloc, with its skins:

```sql
SELECT id, name, skins FROM models WHERE family = 'murloc' ORDER BY name;
```

How many icons something in the game uses (about 4,700 of the client's
30,000; an icon missing from `icon_usage` is unused):

```sql
SELECT COUNT(DISTINCT icon) FROM icon_usage;
```

Which client build and schema a file was built from:

```sql
SELECT key, value FROM meta;
```

## Tables

Every table is listed in `tables` with its row count. When a table or column
changes shape, `meta.schema_version` goes up; check it before relying on a
column.

### `meta`

Where this database came from: one row per key.

| Column | Type | Meaning |
| --- | --- | --- |
| `key` | TEXT | `schema_version`, `client_build`, `generated` (UTC), `commit` (of this repo) or `sources` |
| `value` | TEXT | Its value; `sources` is a JSON object of the client tables read, with row counts |

### `tables`

The published tables, with their row counts.

| Column | Type | Meaning |
| --- | --- | --- |
| `name` | TEXT | Table name |
| `rows` | INTEGER | Row count |
| `description` | TEXT | What the table holds |

### `models`

Every creature display the client ships: mobs, humanoid NPCs, objects and
effects. These are what the Models tab lists.

| Column | Type | Meaning |
| --- | --- | --- |
| `id` | INTEGER | Creature display ID, for `PlayerModel:SetDisplayInfo` |
| `name` | TEXT | Model and skin name from the listfile, like `murloc blue`; `model <file>` if unnamed |
| `type` | TEXT | Creature, Humanoid NPC, Character, Object, Spell effect, Item, Unnamed or Other |
| `family` | TEXT | The model's folder, like `murloc` or `raptor` |
| `model_file` | INTEGER | File data ID of the `.m2` model (renders without the skin) |
| `skins` | TEXT | JSON array of skin texture names |

NPC names are not in the client's files (the server sends them), so they are
not here; MediaLab learns them in game from your target.

### `icon_usage`

What uses each icon: one row per icon and user. Spells, items, professions,
achievements, enchants, currencies, classes, specializations, pet families,
battle pets and shapeshift forms.

| Column | Type | Meaning |
| --- | --- | --- |
| `icon` | INTEGER | Icon file data ID, as in the Icons tab |
| `kind` | TEXT | What uses it: `spell`, `item`, `profession`, `achievement`, `enchant`, ... |
| `ref` | INTEGER | The user's ID in its own table: spell ID, item ID, skill line ID, ... |
| `name` | TEXT | The user's name, when the client has one |

An item without its own icon uses its default appearance's icon.

## Building it

From your own game install (read only), with Python 3:

```sh
.venv/bin/python scripts/game-data.py            # seconds
```

It runs two steps, which can also run alone:

1. `import` copies the client's data tables (DB2 files, read from the game's
   local storage by `scripts/casc.py` and `scripts/db2.py`) into
   `.cache/client.sqlite`, one SQL table per client table, with column names
   from [WoWDBDefs](https://github.com/wowdev/WoWDBDefs). `--all` imports
   every table the client ships (about 1,160) for exploring; `--tables` picks
   some. This file is local scratch and is never shipped.
2. `build` writes `catalog/wow-data.sqlite` from it, then the files generated
   from that: `catalog/models.json` and `MediaLab_Models/data.lua`.

Names of models come from the community
[wow-listfile](https://github.com/wowdev/wow-listfile), downloaded once into
`.cache/`. Sections of tables the client cannot decrypt yet (unreleased
content) are skipped.

### Adding a table

Each published table is one module in `scripts/gamedata/` that declares its
schema (`TABLE`: name, description, columns) and yields its rows from the
client import. Add the module to `BUILDERS` in `published.py`, list any client
tables it reads in `client.DEFAULT_TABLES`, document it here, and bump
`SCHEMA_VERSION` if an existing table changed. The tests check that this page
documents every table and column.

A new icon user is one row in `SOURCES` in `scripts/gamedata/icons.py`.
