# MediaLab

A media browser for addon makers, inside the game. Find the icon, texture,
atlas, sound, control template or font your addon needs, preview it, and copy
its name, ID or a ready-to-paste line of Lua.

MediaLab targets **WoW Forever**, interface **16001**. Version **0.1.0**.

## Why it helps

- **Find art without leaving the game.** Search every icon by name, color or
  subject ("sword", "blue", "potion"), and every atlas by its prefix.
- **See it the way your addon will.** Zoom to actual size, check transparency
  on dark, checker or light backgrounds, and read an atlas's exact size.
- **Hear it first.** Play any `SOUNDKIT` sound on the channel you plan to use.
- **Try a template before you build on it.** Build a live copy of an XML
  template and see its size and type.
- **Copy, don't type.** Every entry comes with the snippet you would write:
  `SetTexture`, `SetAtlas`, inline text markup, `PlaySound`,
  `CreateFrame` with the template, `SetFontObject`.
- **Take it outside the game.** Export the current results as CSV, or use the
  [JSON catalog](docs/addon-dev.md#the-catalog-outside-the-game) that ships
  with each release.

## Install

Install **MediaLab** from CurseForge, or extract the release zip into
`World of Warcraft/_forever_/Interface/AddOns/`. It brings three folders:

- `MediaLab`, the lab itself;
- `MediaLab_Icons`, icon names, colors and tags, loaded when the lab indexes icons;
- `MediaLab_Export`, loaded only when you export.

Restart the client after the first install and enable **MediaLab**.

## Open the lab

Enter **`/mlab`** or **`/medialab`**, or use the addon compartment entry.

Drag the title bar to move the window, drag the lower-right corner to resize
it, and press **_** to minimize it to its title bar. Escape closes it.
`/mlab reset` restores the default size and position.

## Tabs

| Tab | What it lists | Preview |
| --- | --- | --- |
| Icons | Every spell and item icon, with names, colors and subjects | Zoomable image |
| Textures | Texture paths used by the game's UI | Zoomable image |
| Atlases | The client's atlases | Zoomable image, exact size |
| Sounds | `SOUNDKIT` names and IDs | Play, stop, channel, auto-play |
| Controls | XML templates | Type, size, source; live build on request |
| Fonts | Font objects | Editable sample text, file, size, flags |
| Favorites | Anything you right-clicked, across tabs | Same as its own tab |

- **Search** matches every word against the name, path, ID, type and tags on
  the current tab.
- **Filter** (left column) narrows a tab: icon subject or color, texture
  folder, atlas prefix, sound prefix, widget type or font family. **Common**
  is a hand-picked starter set.
- **Size** cycles the thumbnail zoom on grid tabs.
- **CSV** (or `/mlab csv`) shows the current results as CSV to copy, up to
  500 rows.

## Inspect and copy

Click an entry to inspect it. Right-click it, or press **Favorite**, to save it.

- **Images:** mouse wheel or **-**/**+** zooms, drag pans, **1:1** shows actual
  size, **Fit** fits it to the stage. **Canvas** cycles dark, checker and light
  backgrounds. Addons cannot read a file texture's size, so 1:1 assumes
  64 x 64 for icons and 256 x 256 for other textures.
- **Sounds:** **Play** and **Stop**. **Channel** picks which volume slider the
  sound obeys. **Auto-play** plays each sound as you select it.
- **Controls:** **Build preview** creates one live instance of the template.
  WoW cannot delete frames, so each template is built once per session. Some
  templates expect a parent or data a preview cannot supply and may report a
  Lua error. Building is off in combat.
- **Fonts:** type your own sample text. It is remembered.

The fields under the preview hold the reference and the Lua snippets. Click a
field or its **Copy** button, then press **Ctrl+C** (WoW does not let addons
write to the clipboard).

## Good to know

- MediaLab lists what the client and the game's UI files reference. Art that
  is built at runtime, or that no UI file mentions, is missing. A texture that
  does not exist in Forever shows **?**, or renders blank or green.
- No Blizzard artwork or audio is bundled. Everything is shown from your own
  game files.
- Only favorites, window placement, the open tab and preview settings are
  saved.

More for addon developers (the copy fields, the JSON catalog and how it is
built) is in [docs/addon-dev.md](docs/addon-dev.md). Working on MediaLab
itself is in [docs/development.md](docs/development.md).

## License

[MIT](LICENSE). Blizzard's artwork and audio remain part of the installed game
and are not covered by this project's license.
