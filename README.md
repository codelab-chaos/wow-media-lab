# WoW Media Lab 🧪

**Look through the game's icons, textures, sounds and creature models, all in one window.**

Hunting for the perfect icon for a macro? Want to hear what that sound is
called, or watch a murloc dance? WoW Media Lab lets you search, preview and
collect everything the game draws and plays, without leaving the game.

Made for **WoW Forever** (interface **16001**). Version **0.1.0**.

## What you can do

- **Find any icon by what it looks like.** Nearly 28,000 icons, searchable by
  what they show and by color: `sword`, `wolf`, `potion green`.
- **Meet the whole bestiary.** Turn, zoom and animate over 14,000 creature
  models, and target any NPC to see which model it uses.
- **Hear the game's sounds.** Over 23,000 of them: creatures, spells, music,
  ambience and the interface, one click each.
- **Browse the game's art.** Its textures and the pieces its windows are
  drawn from, zoomed and on any background.
- **Keep what you like.** Right-click anything to favorite it or put it in
  your own lists, one at a time or a whole selection at once.

## Install

Install **WoW Media Lab** from CurseForge, or download the zip from
[Releases](https://github.com/codelab-chaos/wow-media-lab/releases) and
extract it into `World of Warcraft/_forever_/Interface/AddOns/`. It brings
four folders: `MediaLab`, and three data folders (`MediaLab_Icons`,
`MediaLab_Models`, `MediaLab_Sounds`) that load only when you open those tabs.

Restart the game after installing, and make sure **WoW Media Lab** is
enabled in the AddOns list.

## Open it

Type **`/mlab`** (or `/medialab`), or click it in the addon menu by the
minimap. The first time, a welcome card says hello:

> **Welcome to WoW Media Lab**
>
> - Look through the game's icons, textures, sounds and creature models, all in one window.
> - Type in the search box to find anything: a name, a color, a subject or an ID.
> - Right-click anything to add it to your Favorites or one of your lists.
> - Press ? in the title bar any time for tips about the tab you are on.

The first time it opens each session, the lab counts its libraries in (the
sounds, models and icons take a moment); press **Browse now** to start on the
tabs that are already done.

Drag the title bar to move the window and the corner to resize it. Want a
bigger preview, or longer filter names? Drag the edge of the preview or the
filter column (double-click an edge to reset it). Hover a filter to see its
full name.

- **_** minimizes the lab to a small icon docked at the edge of your screen.
  Click the icon to bring it back, or drag it along the edge, or to another
  edge, where it snaps.
- **The square** maximizes it to fill the screen; click it again (or
  double-click the title bar) to go back.
- **x** or Escape closes it.

## A quick tour

### Icons

Search by what an icon shows (sword, potion, wolf) or by color (blue, gold).
Filter by subject or color in the left column. Hover an icon to read what it
shows.
Hold Ctrl and scroll over the grid to make the thumbnails bigger or smaller.
The **-**, **100%** and **+** buttons above the results do the same (click
the percentage to reset it). Icons, texture files and atlases each remember
their own zoom.

### Textures

Files are the game's images; Atlases are the pieces its interface is drawn from.
Switch between them with **Files** and **Atlases** above the results.
Scroll the preview to zoom, drag it to pan, and press Canvas to check it on light or dark.
Filter by shape (square, wide, tall), or drag the size handles to the sizes you want.
The handles snap to the usual sizes (16, 32, 64 up to 4096 pixels, on the
longer side); click the size shown above them to go back to any size.

### Models

Drag a model to turn it, scroll to zoom, and press the animation button to see it move.
Stand, walk, run, attack, roar, dance: you get the ones that model has.
Target any NPC and press Target to jump to its model; the lab remembers the name.
After that you can search Models by the NPC's name, or filter to **Seen in
game**.

### Sounds

Press Play to hear a sound, or turn on Auto-play to hear each one as you select it.
Pick the channel it plays on, so the game's volume sliders apply.
Filter by Creature, Spell, Music or Ambience in the left column, or search for a creature by name.
The game doesn't name most of its sounds, so each one is named after its
sound files, like `mmurlocattack`.

### Fonts

Type your own sample text to see it in any of the game's fonts.
Each font shows its file, size and outline, and your sample is remembered.

### Controls (a bonus)

These are the building blocks of the game's windows: buttons, frames, sliders.
Press Build preview to see a live copy of one.

### Favorites and lists

Favorites and your own lists, with any kind of media in them.
Right-click anything for the lists menu: Favorites, then your lists by name
(a check when it is in one), then **+ New list...** and **Manage lists...**
Ctrl+click or Shift+click to pick several things, then right-click to add them all at once.
Like in a file browser, Ctrl+click adds or removes one and Shift+click picks
everything between two clicks; a strip under the results shows what you
picked. Press New to start a list, and Add to list in the right panel to fill it.
Something can be in as many lists as you like.

## Commands

| Command | Does |
| --- | --- |
| `/mlab` | Opens and closes the lab |
| `/mlab search <words>` | Searches the tab you are on |
| `/mlab tab <name>` | Jumps to a tab: icons, textures, atlases, models, sounds, controls, fonts, lists |
| `/mlab target` | Finds your target's model and remembers its name |
| `/mlab reset` | Puts the window back in the middle at its normal size |
| `/mlab dock <edge>` | Where it minimizes to: left, right, top or bottom |
| `/mlab dev` | Turns developer mode on or off |
| `/mlab help` | Lists these in chat |

## Making addons?

Making an addon? Press Dev in the title bar for the code behind each entry.

Developer mode adds the code for each entry: SetTexture, SetAtlas, PlaySound, CreateFrame and more.
It also adds a Copy button that copies a whole list or the results as a Lua table.

The [developer guide](docs/addon-dev.md) has the details: every field you can
copy, building a list for your addon, and what to watch out for.

## Good to know

- **Nothing from Blizzard is bundled.** The pictures and sounds come from
  your own game; the addon only knows their names and numbers.
- **It stays out of the way.** Nothing loads until you open it, and the big
  icon and model lists load only when you visit those tabs.
- **It saves very little:** your lists, the NPC names you capture, where the
  window sits, and your settings.
- **Some art may be missing.** The lab lists what the game's interface files
  mention, plus everything the game itself can list. A texture the game
  doesn't have shows as **?**, blank or green.

## Feedback

Ideas or bugs? Tell us on the project page: github.com/codelab-chaos/wow-media-lab/issues

That's the [issue tracker](https://github.com/codelab-chaos/wow-media-lab/issues) on
GitHub. Screenshots and the tab you were on help a lot. The same link is in
the lab's **?** card and in `/mlab help`.

## Thanks

Icon and model names come from the community
[wow-listfile](https://github.com/wowdev/wow-listfile), and the game's data
tables are read with layouts from
[WoWDBDefs](https://github.com/wowdev/WoWDBDefs). Working on the addon itself
is in [docs/development.md](docs/development.md).

## License

[MIT](LICENSE). The game's artwork and audio belong to Blizzard Entertainment
and are not covered by this license.
