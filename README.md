# MediaLab

A media lab for addon authors, inside the game. Browse the icons, textures,
atlases, sounds, control templates and fonts your addon can use, preview them,
and copy their names, IDs and ready-to-paste Lua.

MediaLab targets **WoW Forever**, interface **16001**. Version **0.1.0**.

MediaLab is an independent project. Its offline tools (catalog builder, CASC
reader, icon metadata, JSON catalog) are useful on their own and may be used
by other projects, but MediaLab never depends on them.

## Open the lab

1. Copy the `MediaLab`, `MediaLab_Icons` and `MediaLab_Export` folders into
   `World of Warcraft/_forever_/Interface/AddOns/`, or extract
   `dist/MediaLab-0.1.0.zip` there. The other two are optional and load only
   when needed: `MediaLab_Icons` when the lab indexes icons, `MediaLab_Export`
   when you export.
2. Restart the client after the first installation and enable **MediaLab**.
3. Enter **`/mlab`** or **`/medialab`**. There is also an addon compartment entry.

Drag the title bar to move the window, drag the lower-right corner to resize
it, and press **_** to minimize it to its title bar. Escape closes it.
`/mlab reset` restores the default size and position.

## Tabs

| Tab | What it lists | Preview |
| --- | --- | --- |
| Icons | The client's spell and item icon lists, plus icon paths from the UI source | Zoomable image |
| Textures | Texture paths referenced by the UI source | Zoomable image |
| Atlases | The client's atlas list (`C_Texture.GetAtlasElements`) | Zoomable image, exact size |
| Sounds | `SOUNDKIT` names and IDs | Play, stop, channel, auto-play |
| Controls | XML templates (`C_XMLUtil.GetTemplates`) | Type, size, source; live build on request |
| Fonts | Font objects (`GetFonts`) | Editable sample text, file, size, flags |
| Favorites | Anything you right-clicked, across tabs | Same as its own tab |

- **Search** matches every word literally against the name, path, ID, type and
  filters. It covers the current tab.
- **Filter** (left column) narrows a tab by type: icon list, texture folder,
  atlas prefix, sound prefix (`IG`, `UI`, ...), widget type (Button, EditBox,
  Slider, ...) or font family. **Common** is a hand-picked starter set. Scroll
  the column with the mouse wheel when it is long.
- **Size** cycles the thumbnail zoom on grid tabs. The wheel scrolls results,
  and the scrollbar on the right shows where you are: drag its thumb, or click
  the track to page.
- **CSV** (or `/mlab csv`) shows the current results as CSV to copy, up to
  500 rows. Each tab has its own columns (atlases include size and texture
  coordinates, controls their type and size, fonts their file and size).

## Inspect and copy

Click an entry to inspect it. Right-click it, or press **Favorite**, to save it.

- **Images:** mouse wheel or **-**/**+** zooms (12% to 1600%), drag pans,
  **1:1** shows actual size, **Fit** fits it to the stage. **Canvas** cycles dark,
  checker and light backgrounds to show transparency. Atlas sizes come from the
  client. Addons cannot read a file texture's size, so 1:1 assumes 64 x 64 for
  icons and 256 x 256 for other textures.
- **Sounds:** **Play** and **Stop**. **Channel** picks which volume slider the
  sound obeys. **Auto-play** plays each sound as you select it. Rows also have
  their own Play button.
- **Controls:** **Build preview** creates one live instance of the template.
  It opens at actual size (shrunk to fit if larger than the stage); zoom with
  the mouse wheel or **-**/**+**, **1:1** for actual size, **Fit** to fill the
  stage, and drag the stage to pan.
  WoW cannot delete frames, so each template is built once per session and
  reused. Building runs the template's own scripts. Some templates expect a
  parent or data that a preview cannot supply and may report a Lua error.
  Building is disabled in combat.
- **Fonts:** type your own sample text. It is remembered.

The fields under the preview hold the reference (name, path, file ID or sound
kit ID) and Lua snippets: `SetTexture`, `SetAtlas`, inline text markup,
`PlaySound`, `CreateFrame` with the template, `SetFontObject`. Click a field or
its **Copy** button to select it, then press **Ctrl+C**. WoW does not let addons
write to the clipboard themselves.

## Where the data comes from

The client's own lists are used whenever the API exists, so the catalog
matches the game you are running. A catalog generated from the
[Forever UI source](https://github.com/Gethe/wow-ui-source/tree/forever)
(version `1.60.1.70888`, commit `4cd0ab752a77`) fills in what the client
cannot enumerate and adds metadata:

- 1,111 literal texture paths (icon paths go to the Icons tab)
- 3,827 atlas names, used only if `C_Texture.GetAtlasElements` is missing,
  and validated in game
- 888 `SOUNDKIT` names and IDs, merged with the client's `SOUNDKIT` table
- 3,169 virtual templates with their tag, parent template and source file
- 497 font objects, kept only when loaded in the client

This is an exploration tool, not a complete listing of the game's files. Paths
that Blizzard code builds at runtime, and art no UI file references, are
missing. The UI source snapshot also covers other game families, so a listed
texture is not a guarantee that Forever ships it. Atlases are checked with
`C_Texture.GetAtlasInfo`; file textures are only tried by the renderer, and a
missing one shows **?**, or sometimes renders blank or solid green.

The same catalog ships as JSON for use outside the game, in `catalog/` and as
`dist/MediaLab-catalog-<version>.zip`: one file per kind (`icons`, `textures`,
`atlases`, `sounds`, `templates`, `fonts`), each with its source version and
commit. It covers what the UI source references.

### Icon names, colors and tags

Icons are listed by the client as bare file IDs. `MediaLab_Icons` adds, for
about 30,000 of them:

- the **file name** (`inv_ringwod_7d`), from the community
  [wow-listfile](https://github.com/wowdev/wow-listfile);
- **colors** (red, orange, gold, green, teal, blue, purple, pink, brown, gray),
  measured from the icon's pixels in your local game files;
- a **subject**, **tags** and a one-line **description**, written by a local
  vision model.

In the Icons tab these become **Type** (the name's first word: `inv`,
`spell`, `ability`...), **Subject** and **Color** filters, tags are
searchable, and the description shows in the tooltip and inspector. The same
data ships as `catalog/icons-meta.json`. No artwork is stored.

Rebuilding it (after a patch, only new icons are processed):

```sh
python3 -m venv .venv && .venv/bin/pip install pillow
.venv/bin/python scripts/icon-metadata.py names colors   # minutes
.venv/bin/python scripts/icon-metadata.py vision --workers 4   # hours
.venv/bin/python scripts/icon-metadata.py merge
```

`names` downloads the listfile into `.cache/` (`--refresh-listfile` after a
patch). `colors` reads the game's CASC storage directly (`scripts/casc.py`,
read only). `vision` needs [LM Studio](https://lmstudio.ai) serving a vision
model on the local network (default `qwen/qwen3.5-9b`; `--model`, `--url` or
`LMSTUDIO_URL` to change). Each stage caches its results in `.cache/icons/`,
so it can stop and resume.

### Live client lists

The live client lists (every spell and item icon file ID, atlas sizes and
coordinates, template sizes, font files) exist only in game. To export them:

1. Enable **MediaLab Export** in the AddOns list. It loads only when you
   export, so it adds nothing to normal logins.
2. Open the lab, wait for **Ready**, then enter `/mlab export`.
3. `/reload` (or log out). The game writes
   `WTF/Account/<account>/SavedVariables/MediaLab_Export.lua`.
4. Run `python3 scripts/import-export.py`. It writes `catalog/client/*.json`,
   tagged with the client build, and the catalog zip includes them.

No artwork, audio or external libraries are bundled. Only favorites, window
placement, the open tab and preview settings are saved in `MediaLabDB`;
exports go to `MediaLabExport`, owned by the export addon.

The window and catalog are built when first opened. Indexing runs in small
batches across frames (sounds and controls first, icons last), and only the
visible cells are created and reused.

## Development

From this folder, with Lua 5.1 and Python 3.9+:

```sh
rg --files MediaLab MediaLab_Export tests scripts -g '*.lua' -0 | xargs -0 -n1 luac5.1 -p
lua5.1 tests/run.lua
python3 -m unittest discover -s tests -p 'test_*.py' -v
python3 scripts/package.py
```

Code layout (one job per file):

| File | Responsibility |
| --- | --- |
| `core.lua` | Saved variables, slash commands, load event |
| `kinds.lua` | Tab registry and option lists, as data |
| `data/*.lua` | Generated references and the curated Common lists |
| `sources.lua` | One provider per kind: client APIs first, generated data as fallback |
| `catalog.lua` | Entry store, batched indexing, search, filters, favorites |
| `snippets.lua` | Copyable fields and Lua per kind |
| `export.lua` | Rows per kind for `/mlab export` snapshots and CSV |
| `ui/widgets.lua` | Flat widget primitives and the read-only copy field |
| `ui/art.lua` | Painting image entries onto textures |
| `ui/browser.lua` | Grid and list rendering with a reused cell pool |
| `ui/previews.lua` | Image, sound, control and font previews |
| `ui/inspector.lua` | Selection details, preview host, copy fields |
| `ui/csvdialog.lua` | The Copy as CSV popup |
| `ui/window.lua` | Window, tabs, search, filter column, wiring |
| `MediaLab_Export/` | Load-on-demand addon that only owns `MediaLabExport` |
| `MediaLab_Icons/` | Load-on-demand icon metadata generated by `scripts/icon-metadata.py` |

Adding a media type means adding a row to `ML.Kinds`, a provider in
`sources.lua` and a snippet builder in `snippets.lua`, and pointing its
`preview` at an existing or new preview.

Regenerate the reference catalog without changing the source checkout:

```sh
python3 scripts/build-catalog.py \
  --source /home/chadneff/git/hub/wow-ui-source --ref origin/forever
```

For local installation, set `WOW_ADDONS_DIR` or put your AddOns path on the
first line of the ignored `.deploy-target`, then run `scripts/deploy.sh`
(`--dry-run` to preview). It changes only the installed `MediaLab` folder and
leaves saved variables alone. `/reload` is enough after editing existing Lua
files; restart the client after adding files or changing the `.toc`.

To cut a release, run `python3 scripts/release.py <version>`. Add
`--interface <number>` when a patch changes it, and `--fetch` to update the UI
source first. It bumps the `.toc` and README, regenerates the catalog (and the
README's counts), runs every check and packages both zips. It never commits or
deploys.

In-game smoke test: enable `/console scriptErrors 1`, restart, open `/mlab`.
Visit every tab, search and filter, zoom and pan an atlas and a texture, play
and stop a sound, change its channel, build `UIPanelButtonTemplate` from
Controls > Common, type a font sample, copy a field with Ctrl+C, favorite
something, minimize, resize, `/reload` and confirm favorites and placement.
The tests cannot verify the game's renderer or that every listed image
exists, so run this before each release.

## License

[MIT](LICENSE). Blizzard's artwork and audio remain part of the installed game
and are not covered by this project's license.
