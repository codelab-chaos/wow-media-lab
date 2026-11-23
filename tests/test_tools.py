import importlib.util
from pathlib import Path
import re
import sqlite3
import struct
import sys
import tempfile
import unittest
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parents[1]


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, ROOT / path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


catalog = load("catalog", "scripts/build-catalog.py")
packaging = load("packaging", "scripts/package.py")
release = load("release", "scripts/release.py")
importer = load("importer", "scripts/import-export.py")
icons = load("icons", "scripts/icon-metadata.py")
sys.path.insert(0, str(ROOT / "scripts"))
import db2  # noqa: E402
from gamedata import client, exports, icons as icon_usage, listfile, models, published  # noqa: E402


class ExtractionTests(unittest.TestCase):
    def test_art_from_lua_and_xml(self):
        paths, atlases = catalog.extract_art(r'''
            local path = "Interface\\Tooltips\\UI-Tooltip-Background"
            local other = [[Interface\Buttons\WHITE8X8]]
            texture:SetAtlas("test-atlas")
        ''')
        self.assertEqual(paths, {r"Interface\Tooltips\UI-Tooltip-Background", r"Interface\Buttons\WHITE8X8"})
        self.assertEqual(atlases, {"test-atlas"})
        _, atlases = catalog.extract_art('<Texture atlas="xml-atlas"/>', True)
        self.assertEqual(atlases, {"xml-atlas"})

    def test_rejects_dynamic_paths_and_code_files(self):
        for value in ["Interface\\", r"Interface\Icons\%s", "Interface/Scripts/File.lua"]:
            self.assertIsNone(catalog.texture_path(value), value)

    def test_sound_kits(self):
        rows = catalog.extract_sounds("SOUNDKIT = {\n\tIG_MAINMENU_OPEN = 850,\n\tlower_case = 1,\n\tUI_X = 7,\n}")
        self.assertEqual(rows, [("IG_MAINMENU_OPEN", 850), ("UI_X", 7)])

    def test_templates_need_virtual_and_a_plain_name(self):
        rows = catalog.extract_templates('''
            <Button name="GoodTemplate" inherits="UIPanelButtonTemplate" virtual="true"/>
            <Frame name="$parentChild" virtual="true"/>
            <Frame name="NotVirtual"/>
            <Font name="GameFontTest" virtual="true"><Shadow/></Font>
        ''')
        self.assertEqual(rows, [("GoodTemplate", "Button", "UIPanelButtonTemplate"), ("GameFontTest", "Font", "")])

    def test_mainline_definitions_beat_classic_overrides(self):
        self.assertLess(catalog.source_rank("Blizzard_X/Mainline/A.xml"), catalog.source_rank("Blizzard_X/Classic/A.xml"))


class GeneratedDataTests(unittest.TestCase):
    """The curated Common lists must name things the generated catalog knows."""

    def names(self, path, table):
        text = (ROOT / path).read_text()
        block = re.search(rf"ML\.{table} = \{{(.*?)\n\}}", text, re.S).group(1)
        return set(re.findall(r'^\s*\{"([^"]+)"', block, re.M))

    def common(self, kind):
        text = (ROOT / "MediaLab/data/featured.lua").read_text()
        block = re.search(rf"\b{kind} = \{{(.*?)\}}", text, re.S).group(1)
        return set(re.findall(r'"([^"]+)"', block))

    def test_common_names_exist(self):
        checks = {
            "control": self.names("MediaLab/data/templates.lua", "Templates"),
            "sound": self.names("MediaLab/data/sounds.lua", "SoundKits"),
            "font": self.names("MediaLab/data/templates.lua", "FontTemplates"),
        }
        for kind, known in checks.items():
            self.assertTrue(known, kind)
            self.assertEqual(self.common(kind) - known, set(), kind)


class PackagingTests(unittest.TestCase):
    def test_zip_has_manifest_and_exactly_its_declared_files(self):
        output = packaging.package()
        expected = {}
        for name in packaging.ADDONS:
            toc = (ROOT / name / f"{name}.toc").read_text()
            expected[f"{name}/{name}.toc"] = ROOT / name / f"{name}.toc"
            expected[f"{name}/LICENSE"] = ROOT / "LICENSE"
            for line in toc.splitlines():
                if line and not line.startswith("#"):
                    entry = f"{name}/" + line.replace("\\", "/")
                    expected[entry] = ROOT / entry
        with ZipFile(output) as archive:
            self.assertEqual(set(archive.namelist()), set(expected))
            self.assertIsNone(archive.testzip())
            for name, source in expected.items():
                self.assertEqual(archive.read(name), source.read_bytes())

    def test_icon_data_addon_loads_on_demand(self):
        toc = (ROOT / "MediaLab_Icons/MediaLab_Icons.toc").read_text()
        self.assertIn("## LoadOnDemand: 1", toc)
        self.assertTrue((ROOT / "MediaLab_Icons/data.lua").read_text().startswith("-- Generated"))

    def test_model_data_addon_loads_on_demand(self):
        toc = (ROOT / "MediaLab_Models/MediaLab_Models.toc").read_text()
        self.assertIn("## LoadOnDemand: 1", toc)
        self.assertTrue((ROOT / "MediaLab_Models/data.lua").read_text().startswith("-- Generated"))

    def test_export_addon_loads_on_demand_and_owns_the_export_variable(self):
        toc = (ROOT / "MediaLab_Export/MediaLab_Export.toc").read_text()
        self.assertIn("## LoadOnDemand: 1", toc)
        self.assertIn("## SavedVariables: MediaLabExport", toc)
        self.assertNotIn("MediaLabExport", (ROOT / "MediaLab/MediaLab.toc").read_text())


class JsonCatalogTests(unittest.TestCase):
    KINDS = {"icons", "textures", "atlases", "sounds", "templates", "fonts"}
    # Built from the local game files rather than the UI source.
    GAME_FILES = {"icons-meta", "models"}

    def test_json_matches_the_addon_data_and_ships_as_its_own_zip(self):
        import json
        documents = {path.stem: json.loads(path.read_text()) for path in (ROOT / "catalog").glob("*.json")}
        self.assertEqual(set(documents) - self.GAME_FILES, self.KINDS)
        self.assertEqual(documents["models"]["count"], len(documents["models"]["items"]))
        for name in self.GAME_FILES:
            documents.pop(name, None)
        for kind, document in documents.items():
            self.assertEqual(document["count"], len(document["items"]), kind)
            self.assertTrue(document["source"]["commit"], kind)
        lua = (ROOT / "MediaLab/data/sounds.lua").read_text()
        self.assertIn('{"%s", %d}' % (documents["sounds"]["items"][0]["name"], documents["sounds"]["items"][0]["id"]), lua)
        with ZipFile(packaging.package_catalog()) as archive:
            names = set(archive.namelist())
            self.assertLessEqual({f"MediaLab-catalog/{kind}.json" for kind in self.KINDS} | {"MediaLab-catalog/LICENSE"}, names)
            extra = names - {f"MediaLab-catalog/{kind}.json" for kind in self.KINDS} - {"MediaLab-catalog/LICENSE"}
            optional = {f"MediaLab-catalog/{name}.json" for name in self.GAME_FILES}
            self.assertTrue(all(name in optional or name.startswith("MediaLab-catalog/client/") for name in extra), extra)


class IconMetadataTests(unittest.TestCase):
    def test_tags_drop_filler_colors_and_duplicates(self):
        self.assertEqual(icons.clean_tags(["Ring ", "icon", "Gold", "ring", "World of Warcraft", "healing."], "x"),
                         ["ring", "healing"])

    def test_category_is_the_first_name_word(self):
        self.assertEqual(icons.category("inv_ringwod_7d"), "inv")
        self.assertEqual(icons.category("questionmark"), "other")

    def test_lua_strings_escape_quotes_and_backslashes(self):
        self.assertEqual(icons.lua_string('a "b" \\ c\nd'), '"a \\"b\\" \\\\ c d"')


class ImportExportTests(unittest.TestCase):
    def test_converts_a_saved_variables_export_with_gaps_into_json(self):
        import json
        import tempfile
        with tempfile.TemporaryDirectory() as folder:
            counts = importer.convert(ROOT / "tests/fixtures/MediaLab_Export.lua", Path(folder))
            self.assertEqual(counts, {"atlases": 1, "icons": 1, "sounds": 0})
            atlases = json.loads((Path(folder) / "atlases.json").read_text())
            self.assertEqual(atlases["source"]["client"]["build"], "70888")
            item = atlases["items"][0]
            self.assertEqual((item["name"], item["width"], item["left"], item["facets"]), ("test-glow", 256, 0.125, "Test"))
            self.assertNotIn("file", item)
            self.assertEqual(json.loads((Path(folder) / "sounds.json").read_text())["items"], [])
            self.assertEqual(json.loads((Path(folder) / "icons.json").read_text())["items"][0]["value"], 134400)


class ReleaseTests(unittest.TestCase):
    def test_bumps_only_the_version_and_interface_lines(self):
        toc = "## Interface: 16001\n## Title: MediaLab\n## Version: 0.1.0\ncore.lua\n"
        self.assertEqual(release.bump_toc(toc, "0.2.0"), toc.replace("0.1.0", "0.2.0"))
        bumped = release.bump_toc(toc, "0.2.0", "16002")
        self.assertIn("## Interface: 16002", bumped)
        readme = "interface **16001**. Version **0.1.0**.\n`dist/MediaLab-0.1.0.zip`"
        self.assertEqual(release.bump_readme(readme, "0.1.0", "0.2.0", "16002"),
                         "interface **16002**. Version **0.2.0**.\n`dist/MediaLab-0.2.0.zip`")

    def test_catalog_doc_facts_match_the_json(self):
        readme = (ROOT / "docs" / "addon-dev.md").read_text()
        self.assertEqual(release.sync_catalog_facts(readme, release.load_catalog()), readme)
        stale = readme.replace("- 888 `SOUNDKIT`", "- 1 `SOUNDKIT`")
        self.assertEqual(release.sync_catalog_facts(stale, release.load_catalog()), readme)



def wdc5(fields, storage, sections, records, record_size, flags=0, layout=0x7275F5F6, id_index=0):
    """A minimal WDC5 file: storage is [(offset_bits, size_bits)] of plain fields,
    sections is [(data, count, string_size, records_end, map_count)] laid out
    after the header with their file offsets filled in."""
    header_size = 136 + 68 + 40 * len(sections) + 4 * fields + 24 * len(storage)
    out, offset, headers = b"", header_size, b""
    for data, count, string_size, records_end, map_count, tail in sections:
        headers += struct.pack("<Q8I", 0, offset, count, string_size,
                               offset + records_end if records_end else 0, 0, 0, map_count, 0)
        out += data(offset) + tail(offset)
        offset = header_size + len(out)
    head = b"WDC5" + struct.pack("<I", 5) + b"\0" * 128
    head += struct.pack("<9IHH7I", records, fields, record_size, sum(s[2] for s in sections), 0, layout, 0, 0, 0,
                        flags, id_index, fields, 0, 0, 24 * len(storage), 0, 0, len(sections))
    head += headers + b"\0" * (4 * fields)
    head += b"".join(struct.pack("<HHIIIII", o, b, 0, 0, 0, 0, 0) for o, b in storage)
    return head + out


class Db2Tests(unittest.TestCase):
    DBD = ("COLUMNS\nint ID\nlocstring Name_lang\nint Count\nfloat Scale\n\n"
           "LAYOUT 00000001\nBUILD 1.0.0.1\n$id$ID<32>\nOld<8>\n\n"
           "LAYOUT 0000000A, 7275F5F6\nBUILD 1.60.1.71037\n$id$ID<32>\nName_lang\nCount<16>\nScale\n")

    def cache(self, folder):
        (Path(folder) / "Thing.dbd").write_text(self.DBD)
        (Path(folder) / ".complete").write_text("")
        return folder

    def test_reads_bitpacked_fields_across_bytes(self):
        data = (0b101 << 6 | 0b11).to_bytes(2, "little")
        self.assertEqual(db2.bits(data, 0, 2), 0b11)
        self.assertEqual(db2.bits(data, 6, 3), 0b101)

    def test_picks_the_layout_by_hash_with_types_and_skips_noninline_fields(self):
        with tempfile.TemporaryDirectory() as folder:
            (Path(folder) / "Other.dbd").write_text(
                "COLUMNS\nint ID\nint ModelID\nint Tex\nint ParentID\n\n"
                "LAYOUT 7275F5F6\n$noninline,id$ID<32>\nModelID<u16>\nTex<32>[4]\n$noninline,relation$ParentID<32>\n")
            (Path(folder) / ".complete").write_text("")
            layout = db2.dbd_layout("Other", 0x7275F5F6, folder)
        self.assertEqual([(f.name, f.is_id, f.inline, f.count, f.size, f.signed) for f in layout],
                         [("ID", True, False, 1, 32, True), ("ModelID", False, True, 1, 16, False),
                          ("Tex", False, True, 4, 32, True), ("ParentID", False, False, 1, 32, True)])
        self.assertEqual(layout[2].columns(), ["Tex_0", "Tex_1", "Tex_2", "Tex_3"])

    def test_reads_strings_relative_to_their_field(self):
        # Two 12-byte records (ID, Name offset, Count int16 + pad... as 32 bits, Scale float);
        # the string table follows them: "\0Alpha\0Beta\0".
        strings = b"\0Alpha\0Beta\0"
        def record(index, row_id, target, count, scale):
            return struct.pack("<IIhhf", row_id, target - (index * 16 + 4), count, 0, scale)
        body = record(0, 1, 32 + 1, -2, 1.5) + record(1, 2, 32 + 7, 7, 0.25)
        raw = wdc5(4, [(0, 32), (32, 32), (64, 16), (96, 32)],
                   [(lambda _: body + strings, 2, len(strings), 0, 0, lambda _: b"")], 2, 16)
        with tempfile.TemporaryDirectory() as folder:
            rows = db2.read(raw, "Thing", self.cache(folder))
        self.assertEqual(rows, [{"ID": 1, "Name_lang": "Alpha", "Count": -2, "Scale": 1.5},
                                {"ID": 2, "Name_lang": "Beta", "Count": 7, "Scale": 0.25}])

    def test_reads_sparse_records_through_the_offset_map(self):
        records = [struct.pack("<I", 5) + b"Five\0" + struct.pack("<hf", 3, 2.0),
                   struct.pack("<I", 9) + b"Nine\0" + struct.pack("<hf", -1, 0.5)]
        data = b"".join(records)
        def tail(offset):
            starts = [offset, offset + len(records[0])]
            return (b"".join(struct.pack("<IH", start, len(r)) for start, r in zip(starts, records))
                    + struct.pack("<2I", 5, 9))
        raw = wdc5(4, [(0, 32), (32, 0), (64, 16), (80, 32)],
                   [(lambda _: data, 2, 0, len(data), 2, tail)], 2, 0, flags=1)
        with tempfile.TemporaryDirectory() as folder:
            rows = db2.read(raw, "Thing", self.cache(folder))
        self.assertEqual(rows, [{"ID": 5, "Name_lang": "Five", "Count": 3, "Scale": 2.0},
                                {"ID": 9, "Name_lang": "Nine", "Count": -1, "Scale": 0.5}])


class ModelTests(unittest.TestCase):
    def test_names_a_display_by_model_and_skin(self):
        names = {1: "creature/murloc/murloc.m2", 2: "creature/murloc/murlocskinblue.blp",
                 3: "character/orc/male/orcmale_hd.m2", 4: "models/creature/unk_exp00_9/9.m2"}
        display = {"ID": 10, "ExtendedDisplayInfoID": 0, "TextureVariationFileDataID": [2, 0, 0, 0]}
        self.assertEqual(models.describe(display, 1, names),
                         {"id": 10, "name": "murloc blue", "type": "Creature", "family": "murloc",
                          "skins": ["murlocskinblue"]})
        npc = models.describe({**display, "ExtendedDisplayInfoID": 5, "TextureVariationFileDataID": [0] * 4}, 3, names)
        self.assertEqual((npc["name"], npc["type"], npc["family"]), ("orc male", "Humanoid NPC", "orc"))
        self.assertEqual(models.describe(display, 4, names)["type"], "Unnamed")
        self.assertEqual(models.skin_label("thunderlizard", "thunderbeastskinred"), "thunderbeast red")


class PublishedDatabaseTests(unittest.TestCase):
    """The published database built from a tiny client import."""

    def client(self, path):
        db = client.connect(path)
        F = db2.Field
        client.store_table(db, "CreatureModelData", [F("ID"), F("FileDataID")], [{"ID": 7, "FileDataID": 1}])
        client.store_table(db, "CreatureDisplayInfo",
                           [F("ID"), F("ModelID"), F("ExtendedDisplayInfoID"), F("TextureVariationFileDataID", count=4)],
                           [{"ID": 10, "ModelID": 7, "ExtendedDisplayInfoID": 0, "TextureVariationFileDataID": [2, 0, 0, 0]},
                            {"ID": 11, "ModelID": 99, "ExtendedDisplayInfoID": 0, "TextureVariationFileDataID": [0] * 4}])
        client.store_table(db, "SpellMisc", [F("ID"), F("SpellID"), F("SpellIconFileDataID"), F("ActiveIconFileDataID")],
                           [{"ID": 1, "SpellID": 133, "SpellIconFileDataID": 135812, "ActiveIconFileDataID": 0}])
        client.store_table(db, "SpellName", [F("ID"), F("Name_lang", kind="string")], [{"ID": 133, "Name_lang": "Fireball"}])
        db.execute("CREATE TABLE _files (id INTEGER PRIMARY KEY)")
        db.executemany("INSERT INTO _files VALUES (?)", [(1,), (2,)])
        db.executemany("INSERT INTO _tables VALUES (?, 0, '', 1, 'ok', '1.60.1.71037', 0)",
                       [("CreatureModelData",), ("CreatureDisplayInfo",), ("SpellMisc",), ("SpellName",)])
        db.commit()
        db.close()

    def test_builds_tables_meta_and_exports(self):
        names = {1: "creature/murloc/murloc.m2", 2: "creature/murloc/murlocskinblue.blp"}
        original = listfile.paths
        listfile.paths = lambda keep=None: names
        try:
            with tempfile.TemporaryDirectory() as folder:
                raw, out = Path(folder) / "client.sqlite", Path(folder) / "wow-data.sqlite"
                self.client(raw)
                counts = published.build(raw, out)
                self.assertEqual(counts, {"models": 1, "icon_usage": 1})  # display 11's model is not shipped
                db = sqlite3.connect(out)
                self.assertEqual(db.execute("SELECT * FROM models").fetchall(),
                                 [(10, "murloc blue", "Creature", "murloc", 1, '["murlocskinblue"]')])
                self.assertEqual(db.execute("SELECT * FROM icon_usage").fetchall(), [(135812, "spell", 133, "Fireball")])
                meta = dict(db.execute("SELECT key, value FROM meta"))
                self.assertEqual((meta["schema_version"], meta["client_build"]), ("1", "1.60.1.71037"))
                self.assertEqual(db.execute("SELECT name, rows FROM tables").fetchall(), [("models", 1), ("icon_usage", 1)])
                exports.models_json(db, Path(folder) / "models.json")
                exports.models_addon(db, Path(folder) / "data.lua")
                db.close()
                self.assertIn('[10]="murloc blue\tCreature\tmurloc\t1\tmurlocskinblue",',
                              (Path(folder) / "data.lua").read_text())
                import json
                document = json.loads((Path(folder) / "models.json").read_text())
                self.assertEqual((document["count"], document["source"]["client"]), (1, "1.60.1.71037"))
                self.assertEqual(document["items"][0]["model"], 1)
        finally:
            listfile.paths = original

    def test_docs_describe_every_published_table_and_column(self):
        text = (ROOT / "docs" / "data.md").read_text()
        for table in published.schemas():
            self.assertIn(f"### `{table['name']}`", text)
            for name, _kind, _doc in table["columns"]:
                self.assertIn(f"| `{name}` |", text, f"{table['name']}.{name}")
        self.assertIn(f"schema version **{published.SCHEMA_VERSION}**", text)

    def test_icon_sources_name_their_tables(self):
        for source in icon_usage.SOURCES:
            for table in source["tables"]:
                self.assertIn(f"client.{table}", source["sql"], source["kind"])
                self.assertIn(table, client.DEFAULT_TABLES, table)


if __name__ == "__main__":
    unittest.main()
