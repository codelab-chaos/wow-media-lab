# WoW Media Lab for addon developers

How the lab fits into building an addon: finding the right media in game and
copying the code for it. Installing and the everyday controls are in the
[README](../README.md).

## Turn on developer mode

Press **Dev** in the title bar, or type `/mlab dev`. It adds:

- the code behind every entry in the right panel, ready to paste;
- the **Fonts** tab;
- **Copy** in the toolbar, which copies the results or a whole list.

It is remembered, so it stays on until you turn it off.

## A working loop

1. **Search** the tab for what you need. Icons answer to their file name,
   colors and subject (`sword blue`, `potion green`), atlases to their prefix
   (`common-`, `UI-HUD-`), sounds to their `SOUNDKIT` name, models to their
   model, skin or NPC name (`murloc`, `raptor violet`, `hogger`).
2. **Preview** it. Zoom to **1:1** to see the size you will draw it at, and
   cycle **Canvas** to check the transparency against light and dark frames.
   For a sound, pick the **Channel** your addon will play it on.
3. **Save** the candidates: right-click for the lists menu, or **Add to list**
   in the right panel. Ctrl+click and Shift+click pick several at once. Keep a
   list per addon or per screen; an entry can be in several.
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

   CSV gives one row per entry. `/mlab copy` and `/mlab csv` do the same.
   With several entries picked, Copy takes just those.

## What you can copy

| Tab | Fields |
| --- | --- |
| Icons, Textures (Files) | File ID or path, `texture:SetTexture(...)`, `CreateSimpleTextureMarkup(..., 16, 16)`, tags |
| Textures (Atlases) | Atlas name, `texture:SetAtlas(..., true)`, `CreateAtlasMarkup(..., 16, 16)` |
| Sounds | `SOUNDKIT` name (when it has one), sound kit ID, `PlaySound(SOUNDKIT... or ID, channel)` |
| Controls | Template name, a `CreateFrame` call using it, the template it inherits |
| Fonts | Font object, `fontString:SetFontObject(...)`, `parent:CreateFontString(nil, "OVERLAY", ...)` |
| Models | Display ID, a `PlayerModel` with `SetDisplayInfo(...)`, `actor:SetModelByCreatureDisplayID(...)`, the model file ID |

Without developer mode, the right panel shows only the reference: the file
ID, path, atlas, sound or template name, or display ID.

Prefer the atlas or the `SOUNDKIT` name over a raw path or ID when one exists:
they survive patches that move files. For models, use the display ID: the bare
model file renders without the display's skin.

## Things to know while you build

- **Sizes.** Atlas sizes are exact, from the client. Addons cannot read a file
  texture's size, so the lab ships the sizes of the UI's texture files, read
  from the game's files; **1:1** and the size filter use them. Icons, and the
  few textures without a known size, assume 64 x 64 and 256 x 256.
- **Missing art.** Texture paths come partly from Blizzard's UI source, which
  covers other game families too. A texture that Forever does not ship shows
  **?**, or renders blank or green. Atlases are checked with
  `C_Texture.GetAtlasInfo`.
- **Templates.** **Build preview** runs the template's own scripts, once per
  session (WoW cannot delete frames). A template that needs a parent or data
  may raise a Lua error; that tells you what it expects from your code too.
  Building is off in combat.
- **NPC names.** The client's files describe models, not NPCs; the server
  sends NPC names. Target an NPC and press **Target** to learn which display
  it uses. If the display cannot be read, the lab searches its model file so
  you can pick the matching skin.
- **Clipboard.** WoW does not let addons write to the clipboard, so every
  copy is select, then **Ctrl+C**.

## Where the lists come from

The client's own lists come first, so the lab matches the game you are
running: every icon and atlas the client can enumerate, the live `SOUNDKIT`
table, the loaded font objects. Data shipped with the addon fills in what the
client cannot list and adds the names and descriptions:

- about 1,100 texture paths (with their sizes), 3,800 atlas names, 890
  `SOUNDKIT` names and 3,600 templates and font objects that Blizzard's UI
  source references;
- about 23,000 sound kits, named from their sound files, with a category
  (Creature, Spell, Music, Ambience, ...) and folder;
- a name, colors, subject, tags and a one-line description for about 30,000
  icons;
- a name, type, family and skins for about 14,000 creature displays.

It is generated from the
[Codex of Azeroth](https://github.com/codelab-chaos/codex-of-azeroth), a
separate project that reads the game's files and the UI source into one
database. Facts only: names, paths and IDs. If you want that data outside the
game (for editor autocomplete, or to lint an addon's texture paths and sound
names), use the codex database directly.
