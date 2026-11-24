# The lab's guide

Everything the lab's built-in help says, in one place: the tips for each tab
and what every button and switch does. In the lab, press **?** for the tab
you are on, or **i** for the welcome. Back to the [README](../README.md).

## Welcome to WoW Media Lab

- Look through the game's icons, textures, sounds and creature models, all in one window.
- Type in the search box to find anything: a name, a color, a subject or an ID.
- Right-click anything to add it to your Favorites or one of your lists.
- Press ? in the title bar any time for help with the tab you are on and its switches.

## Tips for each tab

### Icons

- Search by what an icon shows (sword, potion, wolf) or by color (blue, gold).
- Filter by subject or color in the left column.
- Hold Ctrl and scroll over the grid to scale the thumbnails up or down.

### Textures

- Texture files are whole images the game draws from: frames, backgrounds, borders.
- Scroll the preview to zoom, drag it to pan, and press Canvas to check it on light or dark.
- Filter by shape (square, wide, tall), or drag the size handles to the sizes you want.

### Atlases

- Atlases are the pieces the game's interface is drawn from, each cut to an exact size.
- Filter by shape or size the same way as textures, and zoom the preview to see the detail.

### Models

- Drag a model to turn it any way, middle-drag to move it, scroll to zoom, and press the animation button to see it move.
- Target any NPC and press Target to jump to its model; the lab remembers the name.

### Sounds

- Rest the pointer on a sound to hear it, or press Play; Play through moves on to the next one when it ends.
- The waveform shows how loud a sound is over time, and a playhead follows it while it plays.
- Pick the channel it plays on, so the game's volume sliders apply.
- Filter by Creature, Spell, Music or Ambience in the left column, or search for a creature by name.

### Controls

- These are the building blocks of the game's windows: buttons, frames, sliders.
- Press Build preview to see a live copy of one.

### Fonts

- Type your own sample text to see it in any of the game's fonts.

### Lists

- Favorites and your own lists, with any kind of media in them.
- Ctrl+click or Shift+click to pick several things, then right-click to add them all at once.
- Press New to start a list, and Add to list in the right panel to fill it.

## Developer mode

Making an addon? Press Dev in the title bar for the code behind each entry.

- Developer mode adds the code for each entry: SetTexture, SetAtlas, PlaySound, CreateFrame and more.
- It also adds a Copy button that copies a whole list or the results as a Lua table.

## Every switch

### Everywhere

- **Search**: Type a name, a color, a subject or an ID; every word has to match. The box glows while a search is on; Clear empties it.
- **Filters**: The left column narrows the tab; the filter in use is named at the top, and x clears it. Find a filter shortens a long list, and dragging its edge widens it.
- **Click, Ctrl+click, Shift+click**: Pick one, add or remove one, or pick everything between two clicks.
- **Right-click**: Favorite anything or put it in a list, one at a time or the whole selection.
- **< and >**: Page through the results, or scroll the mouse wheel.
- **Dev**: Developer mode: the code behind each entry, and Copy.
- **Gear**: Options: pick what loads when the lab opens.
- **?**: This help, for the tab you are on.
- **i**: About the lab: the welcome, developer mode and where to send ideas.
- **_ and the square**: Minimize to an icon at the edge of the screen, or fill the screen.

### Thumbnails

- **- 100% +**: Scale the thumbnails down or up; click the percentage to go back to 100%. Or Ctrl+scroll the grid.

### Shape and size

- **Square, Wide, Tall**: Keep only images of that shape.
- **Size handles**: Drag them to the sizes you want; they snap to 16, 32, 64 and up. Click the size above them for any size.

### Image preview

- **- + and the wheel**: Zoom in and out; drag the image to pan.
- **1:1**: Show it at the size the game draws it.
- **Fit**: Fit the whole image in the preview.
- **Canvas**: Change the background (dark, checkered or light) to see transparent edges.
- **Repeat**: Show copies side by side, stacked, or tiled 3 by 3, to check that the edges line up.

### Model preview

- **Drag**: Turn the model with either button: across spins it, up and down tilts it, Shift+drag rolls it.
- **Middle-drag and the wheel**: Move the model, and zoom.
- **Animation**: Step through the moves this model has: stand, walk, attack, dance.
- **Reset**: Put the turn, zoom and position back.
- **Canvas**: Change the background behind the model.
- **Target**: Find your target's model and remember the NPC's name.

### Sound player

- **Play and Stop**: Play the sound, or stop it. Clicking a row's waveform plays it too.
- **< and > in the preview**: Play the previous or next sound in the results.
- **Channel**: Which of the game's volume sliders it obeys. A muted channel plays nothing.
- **Hover play**: Play a sound when the pointer rests on its row; it stops when you move off.
- **Auto-play**: Play each sound as soon as you select it.
- **Play through**: When a sound ends, play the next one in the results.

### Controls

- **Build preview**: Make a live copy of the control. Each one is built once per session.

### Fonts

- **Sample text**: Type your own text to see it in every font; it is remembered.

### Lists

- **New, Rename, Delete**: Make a list, or rename or delete the one picked; deleting takes two clicks.
- **Add to list and ***: In the right panel: put what you are looking at in a list, or favorite it.
- **Manage lists**: The right-click menu's last line jumps here.

### Options

- **A checkbox per tab**: Untick a tab you never use and it no longer loads, so the lab opens faster. Everything is on to start with.
- **Load now**: On a tab you turned off: load it for this session only.

## Ideas or bugs?

Tell us on the project page: github.com/codelab-chaos/wow-media-lab/issues
