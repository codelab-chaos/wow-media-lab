"""The models table: every creature display the client ships, named from the
community listfile (its model file and skin textures)."""

import json

from . import listfile

TABLE = {
    "name": "models",
    "description": "Every creature display the client ships: mobs, humanoid NPCs, objects and effects.",
    "columns": [
        ("id", "INTEGER PRIMARY KEY", "Creature display ID (CreatureDisplayInfo.ID), for SetDisplayInfo"),
        ("name", "TEXT", "Model and skin name from the listfile, like `murloc blue`; `model <file>` if unnamed"),
        ("type", "TEXT", "Creature, Humanoid NPC, Character, Object, Spell effect, Item, Unnamed or Other"),
        ("family", "TEXT", "The model's folder, like `murloc` or `raptor`"),
        ("model_file", "INTEGER", "File data ID of the .m2 model"),
        ("skins", "TEXT", "JSON array of skin texture names"),
    ],
}

# The top folder of a model file decides its type. Character models with
# extended display info are humanoid NPCs dressed by the server.
TYPES = {"creature": "Creature", "character": "Character", "world": "Object", "spells": "Spell effect",
         "item": "Item", "environments": "Object", "dungeons": "Object"}

SKINS = 4  # CreatureDisplayInfo.TextureVariationFileDataID[4]


def stem(path):
    return path.rsplit("/", 1)[-1].rsplit(".", 1)[0]


def skin_label(model_stem, skin):
    """What a skin adds to its model's name: murloc + murlocskinblue -> blue."""
    short = skin
    for prefix in (model_stem, model_stem.rstrip("s")):
        if prefix and short.startswith(prefix):
            short = short[len(prefix):]
            break
    short = short.replace("skin", " ").replace("_", " ").strip()
    return " ".join(short.split()) or skin


def describe(display, model, names):
    model_path = names.get(model, "").removeprefix("models/")
    # Newer files carry placeholder names in the listfile (unk_exp00_7478494).
    if not model_path or "/unk_" in model_path:
        return {"id": display["ID"], "name": f"model {model}", "type": "Unnamed", "family": "unnamed", "skins": []}
    parts = model_path.split("/")
    model_stem = stem(model_path).removesuffix("_hd")
    kind = TYPES.get(parts[0], "Other")
    if kind == "Character" and display["ExtendedDisplayInfoID"]:
        kind = "Humanoid NPC"
    family = parts[1] if len(parts) > 2 else model_stem
    skins = []
    for fdid in display["TextureVariationFileDataID"]:
        if fdid and fdid in names and stem(names[fdid]) not in skins:
            skins.append(stem(names[fdid]))
    if kind in ("Character", "Humanoid NPC") and len(parts) > 3:
        name = f"{parts[1]} {parts[2]}"
    elif skins:
        name = f"{model_stem} {skin_label(model_stem, skins[0])}"
    else:
        name = model_stem
    return {"id": display["ID"], "name": name, "type": kind, "family": family, "skins": skins}


def rows(db):
    """Rows for the models table, from the attached client database."""
    textures = ", ".join(f"d.TextureVariationFileDataID_{i}" for i in range(SKINS))
    displays = db.execute(f"""
        SELECT d.ID, d.ExtendedDisplayInfoID, m.FileDataID, {textures}
        FROM client.CreatureDisplayInfo d
        JOIN client.CreatureModelData m ON m.ID = d.ModelID
        JOIN client._files f ON f.id = m.FileDataID
        ORDER BY d.ID""").fetchall()
    wanted = {row[2] for row in displays} | {fdid for row in displays for fdid in row[3:] if fdid}
    names = listfile.paths(lambda fdid, path: fdid in wanted)
    for row in displays:
        display = {"ID": row[0], "ExtendedDisplayInfoID": row[1], "TextureVariationFileDataID": row[3:]}
        item = describe(display, row[2], names)
        yield (item["id"], item["name"], item["type"], item["family"], row[2], json.dumps(item["skins"]))
