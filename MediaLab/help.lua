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
            "Files are the game's images; Atlases are the pieces its interface is drawn from.",
            "Scroll the preview to zoom, drag it to pan, and press Canvas to check it on light or dark.",
        },
        sound = {
            "Press Play to hear a sound, or turn on Auto-play to hear each one as you select it.",
            "Pick the channel it plays on, so the game's volume sliders apply.",
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
            "It also adds the Fonts tab and a Copy button that copies a whole list or the results as a Lua table.",
        },
    },
}
