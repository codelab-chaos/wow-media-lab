# Working on MediaLab

Checks, code layout, data, deploying and releasing. Using MediaLab to build
other addons is in [addon-dev.md](addon-dev.md).

## Checks and layout

From this folder, with Lua 5.1 and Python 3.9+:

```sh
rg --files MediaLab tests -g '*.lua' -0 | xargs -0 -n1 luac5.1 -p
lua5.1 tests/run.lua
python3 -m unittest discover -s tests -p 'test_*.py' -v
python3 scripts/package.py
```

Code layout (one job per file):

| File | Responsibility |
| --- | --- |
| `core.lua` | Saved variables, slash commands, load event |
| `kinds.lua` | Tab registry and option lists, as data (which tab a kind lives under, developer-only kinds) |
| `help.lua` | The welcome card and tips, as data; the README uses the same words |
| `data/*.lua` | Generated references and the curated Common lists |
| `sources.lua` | One provider per kind: client APIs first, generated data as fallback |
| `catalog.lua` | Entry store, batched indexing, search, filters |
| `lists.lua` | Named lists of entry keys; one entry in any number of lists |
| `selection.lua` | The picked entries: click, Ctrl+click, Shift+click |
| `npcs.lua` | NPC names learned from your target, and the target's display |
| `snippets.lua` | Copyable fields and Lua per kind |
| `export.lua` | Rows per kind for CSV and the Lua table |
| `ui/widgets.lua` | Flat widget primitives and the read-only copy field |
| `ui/art.lua` | Painting image entries onto textures |
| `ui/browser.lua` | Grid and list rendering with a reused cell pool |
| `ui/previews.lua` | Image, sound, control and font previews |
| `ui/modelpreview.lua` | The 3D creature model preview |
| `ui/inspector.lua` | Selection details, preview host, copy fields |
| `ui/copydialog.lua` | The Copy popup, Lua or CSV |
| `ui/prompt.lua` | The one-line name prompt |
| `ui/listmenu.lua` | The lists menu (right-click and Add to list), for one entry or a selection |
| `ui/helppanel.lua` | The welcome and tips card |
| `ui/dock.lua` | The minimized lab: an icon docked at a screen edge |
| `ui/rangeslider.lua` | The two-handle size range that snaps to popular sizes |
| `ui/loader.lua` | The loading card: a bar and count per library while the catalog fills |
| `ui/window.lua` | Window, tabs, search, filter column, wiring |
| `MediaLab_Icons/` | Load-on-demand icon names, colors and descriptions (generated) |
| `MediaLab_Models/` | Load-on-demand creature displays (generated) |
| `MediaLab_Sounds/` | Load-on-demand sound kit names and categories (generated) |

Adding a media type means adding a row to `ML.Kinds`, a provider in
`sources.lua` and a snippet builder in `snippets.lua`, and pointing its
`preview` at an existing or new preview.

## Data

MediaLab reads nothing from the game files itself. Its lists ship as
generated files, committed here, so the addon and this repo stand alone:

| File | Holds |
| --- | --- |
| `MediaLab/data/art.lua` | Texture paths and fallback atlas names from the UI source |
| `MediaLab/data/sounds.lua` | `SOUNDKIT` names and IDs |
| `MediaLab/data/templates.lua` | XML templates and font objects |
| `MediaLab_Icons/data.lua` | Every icon's name, colors, subject, tags and description |
| `MediaLab_Models/data.lua` | Every creature display's name, type, family and skins |
| `MediaLab_Sounds/data.lua` | Every sound kit's name, category, folder and `SOUNDKIT` name |
| `MediaLab/data/featured.lua` | Hand-picked Common lists (not generated) |

They are generated from the [Codex of Azeroth](https://github.com/codelab-chaos/codex-of-azeroth),
the project that reads the game and the UI source. With the codex next to
this folder (or `CODEX_DIR` pointing at it) and its database built:

```sh
python3 scripts/sync-codex.py
```

Each output is one row in its `OUTPUTS` list: the file, the codex tables and
columns it reads, and how it is rendered. It checks those columns before
writing anything. At runtime the client's own lists come first (every icon
the client knows, every atlas), and this data names and describes them.

For local installation, set `WOW_ADDONS_DIR` or put your AddOns path on the
first line of the ignored `.deploy-target`, then run `scripts/deploy.sh`
(`--dry-run` to preview). It changes only the installed MediaLab folders and
leaves saved variables alone. `/reload` is enough after editing existing Lua
files; restart the client after adding files or changing the `.toc`.

To cut a release, run `python3 scripts/release.py <version>`. Add
`--interface <number>` when a patch changes it, and `--sync` to refresh the
data from the codex first. It bumps the `.toc` and README, runs every check
and packages the zip. It never commits or deploys.

In-game smoke test: enable `/console scriptErrors 1`, restart, open `/mlab`.
Watch the loading card count each library in (it fades when done; Browse
now hides it early), then on a second open check the bars show "so far / last
time". Read the welcome card and press **Got it**; press **?** on a few tabs. Visit
every tab, search and filter, switch Textures between **Files** and
**Atlases**, Ctrl+scroll the grid and use - / 100% / + (each tab keeps its zoom),
filter Textures by Wide and drag the size handles to 64 and 256, zoom and pan both, play and stop a sound, change its channel,
build `UIPanelButtonTemplate` from Controls > Common, turn and zoom a model
and cycle its animations, target an NPC and press **Target**, save something
to two lists. Shift+click and Ctrl+click a few entries on two tabs, check the
strip under the results, right-click one and add them all to a list. Press **Dev**: the code fields, the Fonts tab (type a sample)
and **Copy** appear; copy a field with Ctrl+C and a list as Lua. Drag the
filter and preview columns wider, maximize and restore (button and
title-bar double-click), minimize to the dock, drag the dock icon to another
edge and click it, resize, `/reload` and confirm the lists, the NPC name, developer mode,
placement, the preview width, and that the welcome card stays away.
The tests cannot verify the game's renderer or that every listed image
exists, so run this before each release.


## Storage and performance

No artwork, audio or external libraries are bundled. Only lists, captured
NPC names, window placement, the open tab and preview settings are saved in
`MediaLabDB`. It is cleaned once at load (`ML.Initialize` in `core.lua`, with
`Lists.Sanitize`, `Npcs.Sanitize` and `Dock.Sanitize`): each setting has a type
and, where it matters, a set of allowed values, and anything else is dropped
so the default applies. A hand-edited file, or one from an older or newer
version, loads without errors; the tests load junk into every setting and
click through the whole lab. A new setting gets a row in `viewRules()`.

The window and catalog are built when first opened. Indexing runs in small
batches across frames (sounds and controls first, icons last), and only the
visible cells are created and reused.

