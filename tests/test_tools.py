import importlib.util
from pathlib import Path
import re
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

    def test_export_addon_loads_on_demand_and_owns_the_export_variable(self):
        toc = (ROOT / "MediaLab_Export/MediaLab_Export.toc").read_text()
        self.assertIn("## LoadOnDemand: 1", toc)
        self.assertIn("## SavedVariables: MediaLabExport", toc)
        self.assertNotIn("MediaLabExport", (ROOT / "MediaLab/MediaLab.toc").read_text())


class JsonCatalogTests(unittest.TestCase):
    KINDS = {"icons", "textures", "atlases", "sounds", "templates", "fonts"}

    def test_json_matches_the_addon_data_and_ships_as_its_own_zip(self):
        import json
        documents = {path.stem: json.loads(path.read_text()) for path in (ROOT / "catalog").glob("*.json")}
        self.assertEqual(set(documents) - {"icons-meta"}, self.KINDS)
        documents.pop("icons-meta", None)
        for kind, document in documents.items():
            self.assertEqual(document["count"], len(document["items"]), kind)
            self.assertTrue(document["source"]["commit"], kind)
        lua = (ROOT / "MediaLab/data/sounds.lua").read_text()
        self.assertIn('{"%s", %d}' % (documents["sounds"]["items"][0]["name"], documents["sounds"]["items"][0]["id"]), lua)
        with ZipFile(packaging.package_catalog()) as archive:
            names = set(archive.namelist())
            self.assertLessEqual({f"MediaLab-catalog/{kind}.json" for kind in self.KINDS} | {"MediaLab-catalog/LICENSE"}, names)
            extra = names - {f"MediaLab-catalog/{kind}.json" for kind in self.KINDS} - {"MediaLab-catalog/LICENSE"}
            optional = {"MediaLab-catalog/icons-meta.json"}
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


if __name__ == "__main__":
    unittest.main()
