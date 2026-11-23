local _, ML = ...

-- What the lab says about itself: the welcome card, a few tips per tab, and
-- what developer mode adds. Plain data; ui/helppanel.lua shows it. The README
-- tells the same story in the same words (the tests check every line is there).
ML.Help = {
    welcome = {
        title = "Welcome to WoW Media Lab",
        lines = {
            "Look through the game's icons, textures, sounds and creature models, all in one window.",
            "Type in the search box to find anything: a name, a color, a subject or an ID.",
            "Right-click anything to add it to your Favorites or one of your lists.",
            "Press ? in the title bar any time for tips about the tab you are on.",
        },
    },
    tabs = {
        icon = {
            "Search by what an icon shows (sword, potion, wolf) or by color (blue, gold).",
            "Filter by subject or color in the left column.",
            "Hold Ctrl and scroll over the grid to make the thumbnails bigger or smaller.",
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
            "Drag a model to turn it, scroll to zoom, and press the animation button to see it move.",
            "Target any NPC and press Target to jump to its model; the lab remembers the name.",
        },
        lists = {
            "Favorites and your own lists, with any kind of media in them.",
            "Ctrl+click or Shift+click to pick several things, then right-click to add them all at once.",
            "Press New to start a list, and Add to list in the right panel to fill it.",
        },
    },
    feedback = {
        title = "Ideas or bugs?",
        lines = {
            "Tell us on the project page: github.com/codelab-chaos/wow-media-lab/issues",
        },
    },
    developer = {
        title = "Developer mode",
        hint = "Making an addon? Press Dev in the title bar for the code behind each entry.",
        lines = {
            "Developer mode adds the code for each entry: SetTexture, SetAtlas, PlaySound, CreateFrame and more.",
            "It also adds a Copy button that copies a whole list or the results as a Lua table.",
        },
    },
}
