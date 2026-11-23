# MediaLab for addon developers

How MediaLab fits into building an addon: finding the right media in game,
copying the code for it, and using its catalog outside the game. Installing
and the controls are in the [README](../README.md).

## A working loop

1. **Search** the tab for what you need. Icons answer to their file name,
   colors and subject (`sword blue`, `potion green`), atlases to their prefix
   (`common-`, `UI-HUD-`), sounds to their `SOUNDKIT` name, models to their
   model, skin or NPC name (`murloc`, `raptor violet`, `hogger`).
2. **Preview** it. Zoom to **1:1** to see the size you will draw it at, and
   cycle **Canvas** to check the transparency against light and dark frames.
   For a sound, pick the **Channel** your addon will play it on.
3. **Save** the candidates: right-click to favorite, or **Add to list** in the
   inspector. Keep a list per addon or per screen; an entry can be in several.
4. **Copy** the field you need into your code (click it, then **Ctrl+C**).
5. **Copy** a whole list, or any results, when you want them all at once: a
   set of icons for a picker, every atlas with a prefix, the sounds for an
   alert menu. Lua gives one table, grouped by kind:

   ```lua
   local RaidFrameKit = {
       icons = {
           134400, -- inv_misc_questionmark
       },
       atlases = {
           "common-icon-checkmark",
       },
       sounds = {
           SOUNDKIT.IG_MAINMENU_OPEN,
       },
       templates = {
           "UIPanelButtonTemplate",
       },
       models = {
           188, -- murloc sahaugin blue
       },
   }
   ```

   CSV gives one row per entry.

## What you can copy

| Tab | Fields |
| --- | --- |
| Icons, Textures | File ID or path, name, `texture:SetTexture(...)`, `CreateSimpleTextureMarkup(..., 16, 16)`, tags |
| Atlases | Atlas name, `texture:SetAtlas(..., true)`, `CreateAtlasMarkup(..., 16, 16)` |
| Sounds | `SOUNDKIT` name, sound kit ID, `PlaySound(SOUNDKIT..., channel)` |
| Controls | Template name, a `CreateFrame` call using it, the template it inherits |
| Fonts | Font object, `fontString:SetFontObject(...)`, `parent:CreateFontString(nil, "OVERLAY", ...)` |
| Models | Display ID, a `PlayerModel` with `SetDisplayInfo(...)`, `actor:SetModelByCreatureDisplayID(...)`, the model file ID |

Prefer the atlas or the `SOUNDKIT` name over a raw path or ID when one exists:
they survive patches that move files. For models, use the display ID: the bare
model file renders without the display's skin.

## Things to know while you build

- **Sizes.** Atlas sizes are exact, from the client. Addons cannot read a file
  texture's size, so **1:1** assumes 64 x 64 for icons and 256 x 256 for other
  textures. Check large textures in your own frame.
- **Missing art.** The lists come partly from the UI source, which covers other
  game families too. A texture that Forever does not ship shows **?**, or
  renders blank or green. Atlases are checked with `C_Texture.GetAtlasInfo`.
- **Templates.** **Build preview** runs the template's own scripts, once per
  session (WoW cannot delete frames). A template that needs a parent or data
  may raise a Lua error; that tells you what it expects from your code too.
- **NPC names.** The client's files describe models, not NPCs; the server
  sends NPC names. Target an NPC and press **Target** to learn which display
  it uses. If the display cannot be read, the lab searches its model file so
  you can pick the matching skin.
- **Clipboard.** WoW does not let addons write to the clipboard, so every
  copy is select, then **Ctrl+C**.

## The catalog outside the game

Each release ships the catalog as JSON, in `catalog/` and as
`MediaLab-catalog-<version>.zip`. Use it for editor autocomplete, to lint an
addon's texture paths and sound names, or to pick icons by color in a script.
One file per kind, each with its source version and commit:

| File | Items look like |
| --- | --- |
| `icons.json`, `textures.json` | `{"path": "Interface\\Icons\\Ability_Defend"}` |
| `atlases.json` | `{"name": "128-redbutton-exit"}` |
| `sounds.json` | `{"name": "ACCOUNT_STORE_CATEGORY_SELECT", "id": 274968}` |
| `templates.json` | `{"name": ..., "type": "Frame", "inherits": ..., "source": ...}` |
| `fonts.json` | `{"name": ..., "type": "Font", "inherits": ..., "source": ...}` |
| `models.json` | `{"id": 188, "name": "murloc sahaugin blue", "type": "Creature", "family": "murloc", "skins": [...], "model": 125024}` |
| `icons-meta.json` | `{"id": 132089, "name": "ability_ambush", "colors": [...], "subject": ..., "tags": [...], "description": ...}` |

It covers what the UI source references, plus the icon metadata and the
creature models. Releases also ship `MediaLab-data-<version>.sqlite`, the
[game database](data.md): the models, and what uses each icon. The client's
own lists (every icon file ID, atlas sizes and coordinates) can be added with
the live export below.

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

## Building the catalog

### From the UI source

The reference catalog is generated from a checkout of
[wow-ui-source](https://github.com/Gethe/wow-ui-source), read with `git show`
so the checkout is never changed:

```sh
python3 scripts/build-catalog.py \
  --source /path/to/wow-ui-source --ref origin/forever
```

It writes the generated `MediaLab/data/` files and `catalog/*.json`.

### Icon names, colors and tags

Icons are listed by the client as bare file IDs. `MediaLab_Icons` adds, for
about 30,000 of them:

- the **file name** (`inv_ringwod_7d`), from the community
  [wow-listfile](https://github.com/wowdev/wow-listfile);
- **colors** (red, orange, gold, green, teal, blue, purple, pink, brown, gray),
  measured from the icon's pixels in your local game files;
- a **subject**, **tags** and a one-line **description**, written by a local
  vision model.

In the Icons tab these become **Subject** and **Color** filters, tags are
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

### Creature models and the game database

`MediaLab_Models` lists every creature display the client ships (about
14,000): mobs, humanoid NPCs, objects and effects, named from their model and
skin files in the community listfile. It is generated, with
`catalog/models.json`, from the [game database](data.md), which is built from
the data tables in your local game files:

```sh
.venv/bin/python scripts/game-data.py   # seconds
```

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

