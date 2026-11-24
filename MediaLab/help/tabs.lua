local _, ML = ...

-- A few tips per tab, by kind id (lists for the Lists tab): the ? card shows
-- the ones for the tab you are on, and the README's tour tells them too.
ML.Help = ML.Help or {}

ML.Help.tabs = {
    icon = {
        "Search by what an icon shows (sword, potion, wolf) or by color (blue, gold).",
        "Filter by subject or color in the left column.",
        "Hold Ctrl and scroll over the grid to scale the thumbnails up or down.",
    },
    texture = {
        "Texture files are whole images the game draws from: frames, backgrounds, borders.",
        "Scroll the preview to zoom, drag it to pan, and press Canvas to check it on light or dark.",
        "Filter by shape (square, wide, tall), or drag the size handles to the sizes you want.",
    },
    atlas = {
        "Atlases are the pieces the game's interface is drawn from, each cut to an exact size.",
        "Filter by shape or size the same way as textures, and zoom the preview to see the detail.",
    },
    sound = {
        "Rest the pointer on a sound to hear it, or press Play; Play through moves on to the next one when it ends.",
        "The waveform shows how loud a sound is over time, and a playhead follows it while it plays.",
        "Pick the channel it plays on, so the game's volume sliders apply.",
        "Filter by Creature, Spell, Music or Ambience in the left column, or search for a creature by name.",
    },
    control = {
        "These are the building blocks of the game's windows: buttons, frames, sliders.",
        "Press Build preview to see a live copy of one.",
    },
    font = {
        "Type your own sample text to see it in any of the game's fonts.",
    },
    model = {
        "Drag a model to turn it, right-drag to move it, scroll to zoom, and press the animation button to see it move.",
        "Target any NPC and press Target to jump to its model; the lab remembers the name.",
    },
    lists = {
        "Favorites and your own lists, with any kind of media in them.",
        "Ctrl+click or Shift+click to pick several things, then right-click to add them all at once.",
        "Press New to start a list, and Add to list in the right panel to fill it.",
    },
}
