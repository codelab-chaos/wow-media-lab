"""The icon_usage table: which spells, items, professions and others use each icon.

Data driven: every client table that names an icon is one row in SOURCES, a
query returning (icon, ref, name). A source whose tables were not imported is
skipped.
"""

TABLE = {
    "name": "icon_usage",
    "description": "What uses each icon: one row per icon and user.",
    "columns": [
        ("icon", "INTEGER", "Icon file data ID, as in the Icons tab"),
        ("kind", "TEXT", "What uses it: spell, item, profession, achievement, enchant, currency, ..."),
        ("ref", "INTEGER", "The user's ID in its own table (spell ID, item ID, skill line ID, ...)"),
        ("name", "TEXT", "The user's name, when the client has one"),
    ],
    "indexes": ["icon", "kind, ref"],
}

SOURCES = [
    {"kind": "spell", "tables": ["SpellMisc", "SpellName"],
     "sql": "SELECT m.SpellIconFileDataID, m.SpellID, n.Name_lang FROM client.SpellMisc m "
            "LEFT JOIN client.SpellName n ON n.ID = m.SpellID"},
    {"kind": "spell", "tables": ["SpellMisc", "SpellName"],
     "sql": "SELECT m.ActiveIconFileDataID, m.SpellID, n.Name_lang FROM client.SpellMisc m "
            "LEFT JOIN client.SpellName n ON n.ID = m.SpellID"},
    # An item's own icon, else its default appearance's.
    {"kind": "item", "tables": ["Item", "ItemSparse", "ItemModifiedAppearance", "ItemAppearance"],
     "sql": "SELECT COALESCE(NULLIF(i.IconFileDataID, 0), a.DefaultIconFileDataID), i.ID, s.Display_lang "
            "FROM client.Item i LEFT JOIN client.ItemSparse s ON s.ID = i.ID "
            "LEFT JOIN (SELECT ItemID, ItemAppearanceID, MIN(OrderIndex) FROM client.ItemModifiedAppearance "
            "GROUP BY ItemID) m ON m.ItemID = i.ID "
            "LEFT JOIN client.ItemAppearance a ON a.ID = m.ItemAppearanceID"},
    {"kind": "profession", "tables": ["SkillLine"],
     "sql": "SELECT SpellIconFileID, ID, DisplayName_lang FROM client.SkillLine"},
    {"kind": "achievement", "tables": ["Achievement"],
     "sql": "SELECT IconFileID, ID, Title_lang FROM client.Achievement"},
    {"kind": "enchant", "tables": ["SpellItemEnchantment"],
     "sql": "SELECT IconFileDataID, ID, Name_lang FROM client.SpellItemEnchantment"},
    {"kind": "currency", "tables": ["CurrencyTypes"],
     "sql": "SELECT InventoryIconFileID, ID, Name_lang FROM client.CurrencyTypes"},
    {"kind": "class", "tables": ["ChrClasses"],
     "sql": "SELECT IconFileDataID, ID, Name_lang FROM client.ChrClasses"},
    {"kind": "specialization", "tables": ["ChrSpecialization"],
     "sql": "SELECT SpellIconFileID, ID, Name_lang FROM client.ChrSpecialization"},
    {"kind": "pet family", "tables": ["CreatureFamily"],
     "sql": "SELECT IconFileID, ID, Name_lang FROM client.CreatureFamily"},
    {"kind": "battle pet", "tables": ["BattlePetSpecies"],
     "sql": "SELECT IconFileDataID, ID, NULL FROM client.BattlePetSpecies"},
    {"kind": "shapeshift", "tables": ["SpellShapeshiftForm"],
     "sql": "SELECT AttackIconFileID, ID, Name_lang FROM client.SpellShapeshiftForm"},
]


def rows(db):
    present = {row[0] for row in db.execute("SELECT name FROM client._tables WHERE status = 'ok'")}
    seen = set()
    for source in SOURCES:
        if not set(source["tables"]) <= present:
            continue
        for icon, ref, name in db.execute(source["sql"]):
            key = (icon, source["kind"], ref)
            if icon and icon > 0 and key not in seen:
                seen.add(key)
                yield (icon, source["kind"], ref, name or None)
