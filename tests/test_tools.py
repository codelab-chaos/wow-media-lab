import importlib.util
from pathlib import Path
import sqlite3
import tempfile
import unittest
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parents[1]


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, ROOT / path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


packaging = load("packaging", "scripts/package.py")
release = load("release", "scripts/release.py")
sync = load("sync", "scripts/sync-codex.py")


class DataAddonTests(unittest.TestCase):
    def test_data_addons_load_on_demand_and_are_generated(self):
        for name in ("MediaLab_Icons", "MediaLab_Models"):
            self.assertIn("## LoadOnDemand: 1", (ROOT / name / f"{name}.toc").read_text(), name)
            self.assertTrue((ROOT / name / "data.lua").read_text().startswith(sync.HEADER), name)

    def test_every_generated_file_is_in_the_repo(self):
        for output in sync.OUTPUTS:
            self.assertTrue((ROOT / output["path"]).read_text().startswith(sync.HEADER), output["path"])


def codex_fixture():
    """A tiny codex database with every table and column MediaLab reads."""
    db = sqlite3.connect(":memory:")
    db.executescript("""
        CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
        INSERT INTO meta VALUES ('schema_version', '4'), ('client_build', '1.60.1.71037'),
            ('ui_source_version', '1.60.1.71037'), ('ui_source_commit', 'abc123');
        CREATE TABLE textures (path TEXT PRIMARY KEY, is_icon INTEGER NOT NULL);
        INSERT INTO textures VALUES ('Interface\\Buttons\\WHITE8X8', 0), ('Interface\\AchievementFrame\\X', 0);
        CREATE TABLE atlases (name TEXT PRIMARY KEY);
        INSERT INTO atlases VALUES ('common-icon-checkmark');
        CREATE TABLE sound_kits (name TEXT PRIMARY KEY, id INTEGER NOT NULL);
        INSERT INTO sound_kits VALUES ('IG_MAINMENU_OPEN', 850);
        CREATE TABLE templates (name TEXT PRIMARY KEY, type TEXT, inherits TEXT, source TEXT);
        INSERT INTO templates VALUES ('UIPanelButtonTemplate', 'Button', '', 'X.xml'), ('GameFontNormal', 'Font', '', 'F.xml');
        CREATE TABLE icons (id INTEGER PRIMARY KEY, name TEXT, colors TEXT, subject TEXT, tags TEXT, description TEXT);
        INSERT INTO icons VALUES (134400, 'inv_misc_questionmark', '["red","gray"]', 'symbol', '["question mark"]', 'A "red" mark.'),
                                 (135274, 'inv_sword_04', '["gray"]', NULL, '[]', NULL);
        CREATE TABLE models (id INTEGER PRIMARY KEY, name TEXT, type TEXT, family TEXT, model_file INTEGER, skins TEXT);
        INSERT INTO models VALUES (10, 'murloc blue', 'Creature', 'murloc', 1, '["murlocskinblue"]');
    """)
    return db


class SyncCodexTests(unittest.TestCase):
    def test_renders_every_data_file_from_the_codex(self):
        db = codex_fixture()
        meta = dict(db.execute("SELECT key, value FROM meta"))
        sync.check(db)
        art = sync.art(db, meta)
        self.assertIn('ML.SourceCommit = "abc123"', art)
        self.assertLess(art.index("AchievementFrame"), art.index("WHITE8X8"))  # case-insensitive path order
        self.assertIn('{"IG_MAINMENU_OPEN", 850},', sync.sounds(db, meta))
        templates = sync.templates(db, meta)
        self.assertLess(templates.index("ML.Templates"), templates.index("UIPanelButtonTemplate"))
        self.assertGreater(templates.index('"GameFontNormal"'), templates.index("ML.FontTemplates"))
        icons = sync.icons(db, meta)
        self.assertIn('[134400]="inv_misc_questionmark\tred,gray\tsymbol\tquestion mark\tA \\"red\\" mark.",', icons)
        self.assertIn('[135274]="inv_sword_04\tgray\t\t\t",', icons)
        self.assertIn('[10]="murloc blue\tCreature\tmurloc\t1\tmurlocskinblue",', sync.models(db, meta))

    def test_writes_the_files_into_a_tree(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "codex.sqlite"
            disk = sqlite3.connect(path)
            codex_fixture().backup(disk)
            disk.close()
            meta, written = sync.sync(path, Path(folder))
            self.assertEqual(meta["client_build"], "1.60.1.71037")
            self.assertEqual([name for name, _ in written], [output["path"] for output in sync.OUTPUTS])

    def test_refuses_a_codex_without_the_columns_it_reads(self):
        db = codex_fixture()
        db.execute("ALTER TABLE icons RENAME COLUMN tags TO labels")
        with self.assertRaises(SystemExit) as raised:
            sync.check(db)
        self.assertIn("icons: no tags", str(raised.exception))


class PackageTests(unittest.TestCase):
    def test_zip_holds_each_addon_with_its_manifest_and_license(self):
        with ZipFile(packaging.package()) as archive:
            names = set(archive.namelist())
        for addon in packaging.ADDONS:
            self.assertIn(f"{addon}/{addon}.toc", names)
            self.assertIn(f"{addon}/LICENSE", names)
        self.assertFalse(any(name.startswith("MediaLab_Export") for name in names))


class ReleaseTests(unittest.TestCase):
    def test_bumps_only_the_version_and_interface_lines(self):
        toc = "## Interface: 16001\n## Title: MediaLab\n## Version: 0.1.0\ncore.lua\n"
        self.assertEqual(release.bump_toc(toc, "0.2.0"), toc.replace("0.1.0", "0.2.0"))
        self.assertIn("## Interface: 16002", release.bump_toc(toc, "0.2.0", "16002"))
        readme = "interface **16001**. Version **0.1.0**.\n`dist/MediaLab-0.1.0.zip`"
        self.assertEqual(release.bump_readme(readme, "0.1.0", "0.2.0", "16002"),
                         "interface **16002**. Version **0.2.0**.\n`dist/MediaLab-0.2.0.zip`")


if __name__ == "__main__":
    unittest.main()
