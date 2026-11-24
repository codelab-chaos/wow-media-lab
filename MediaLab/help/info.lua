local _, ML = ...

-- The help, as plain data in this folder: info.lua (the (i) card: the
-- welcome, developer mode, feedback), tabs.lua (a few tips per tab) and
-- switches.lua (what every button and switch does). ui/helppanel.lua shows it.
-- The README tells the same story in the same words; the tests check that
-- every line is there.
ML.Help = ML.Help or {}

ML.Help.welcome = {
    title = "Welcome to WoW Media Lab",
    lines = {
        "Look through the game's icons, textures, sounds and creature models, all in one window.",
        "Type in the search box to find anything: a name, a color, a subject or an ID.",
        "Right-click anything to add it to your Favorites or one of your lists.",
        "Press ? in the title bar any time for help with the tab you are on and its switches.",
    },
}

ML.Help.developer = {
    title = "Developer mode",
    hint = "Making an addon? Press Dev in the title bar for the code behind each entry.",
    lines = {
        "Developer mode adds the code for each entry: SetTexture, SetAtlas, PlaySound, CreateFrame and more.",
        "It also adds a Copy button that copies a whole list or the results as a Lua table.",
    },
}

ML.Help.feedback = {
    title = "Ideas or bugs?",
    lines = {
        "Tell us on the project page: github.com/codelab-chaos/wow-media-lab/issues",
    },
}
