# Changelog

What changed in each version of WoW Media Lab, newest first. New work goes
under **Unreleased**; `scripts/release.py` turns that into the version's
heading and uses it for the release notes.

## Unreleased

## 0.2.0 (2026-11-23)

The lab is now for everyone, not just addon makers, with creature models, every
sound in the game and a proper sound player.

### New

- **Models tab.** Turn, move, zoom and animate over 14,000 creature models. Target
  an NPC and press **Target** to find its model; the lab remembers the name so
  you can search for it later, or filter to **Seen in game**.
- **Every sound.** Over 23,000 sounds instead of about 900, sorted into
  Creature, Spell, Music, Ambience and the interface, and named after their
  sound files.
- **A sound player.** Rest the pointer on a sound to hear it. Each sound shows
  its waveform, with a playhead that follows it. The preview steps through the
  results with **<** and **>**, and has **Hover play**, **Auto-play** and
  **Play through** switches. It also shows how long a sound is, how many
  variations it has and what plays it (a creature's attack, a zone's music).
- **Icons by what they show.** Search nearly 28,000 icons by subject and color
  (`sword`, `potion green`), with a one-line description on hover.
- **Lists.** Right-click anything for Favorites and your own lists. Ctrl+click
  and Shift+click pick several at once, like in a file browser, and a strip
  under the results shows what you picked. The Lists tab counts your lists and
  everything in them.
- **Scale the thumbnails.** Ctrl+scroll over the grid, or use **-**,
  **100%** and **+**. Icons, textures and atlases each remember their own. The
  spacing scales with them, so small thumbnails sit close together.
- **Shape and size filters** for textures and atlases: square, wide or tall,
  and a size range that snaps to the usual sizes.
- **Find a filter.** A box at the top of the filter column narrows a long
  list of filters as you type.
- **Repeat** in the image preview tiles a texture side by side, stacked or 3 by
  3, to check that a border or background lines up with itself.
- **Maximize**, and **minimize** to a small icon docked at the edge of the
  screen (`/mlab dock left|right|top|bottom`).
- **Wider columns.** Drag the edge of the preview or the filter column; double
  click to reset it.
- **A loading card** that counts each library in, with **Browse now** to start
  on the tabs that are ready.
- **Help.** **?** in the title bar explains the tab you are on and every
  button and switch on it; **i** shows the welcome, developer mode and where
  to send ideas. The README's new "Every switch" section has the same words.
- **Options.** The gear in the title bar, `/mlab options`, or **WoW Media
  Lab** in the game's Options under AddOns: untick a tab you never use and it
  no longer loads, so the lab opens faster. The loading card shows it as
  Disabled, and the tab offers **Load now** for the session.

### Changed

- **Developer mode.** The code fields and **Copy** are behind **Dev** in the
  title bar (`/mlab dev`), so the lab is simpler for players. Fonts stays a
  tab for everyone.
- Filters show their names under headings (FAMILY, FOLDER, ...) instead of a
  prefix on every row, with the full name on hover.
- The previews keep their zoom from one entry to the next.
- Tabs: Icons, Textures, Atlases, Models, Sounds, Controls, Fonts, Lists.

### Fixed

- Saved settings that were edited by hand, or that came from an older version,
  load without errors.
- The Textures tab opens textures again for players who last used atlases
  there in 0.1.

## 0.1.0

The first version: icons, textures, atlases, sounds, control templates and
fonts in one window, with search, filters, favorites, zoomable previews, sound
playback and copyable names, IDs and Lua for addon authors.
