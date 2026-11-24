local _, ML = ...

-- What every button and switch does, in groups of {name, what it does}. The ?
-- card shows the groups for the tab you are on (ML.Help.switchesFor) and then
-- Everywhere; the README's "Every switch" section has each group in the same
-- words.
ML.Help = ML.Help or {}

ML.Help.switches = {
    everywhere = {
        title = "Everywhere",
        items = {
            {"Search", "Type a name, a color, a subject or an ID; every word has to match. Clear empties it."},
            {"Filters", "The left column narrows the tab. Find a filter shortens a long list, and dragging its edge widens it."},
            {"Click, Ctrl+click, Shift+click", "Pick one, add or remove one, or pick everything between two clicks."},
            {"Right-click", "Favorite anything or put it in a list, one at a time or the whole selection."},
            {"< and >", "Page through the results, or scroll the mouse wheel."},
            {"Dev", "Developer mode: the code behind each entry, and Copy."},
            {"Gear", "Options: pick what loads when the lab opens."},
            {"?", "This help, for the tab you are on."},
            {"i", "About the lab: the welcome, developer mode and where to send ideas."},
            {"_ and the square", "Minimize to an icon at the edge of the screen, or fill the screen."},
        },
    },
    grid = {
        title = "Thumbnails",
        items = {
            {"- 100% +", "Scale the thumbnails down or up; click the percentage to go back to 100%. Or Ctrl+scroll the grid."},
        },
    },
    sized = {
        title = "Shape and size",
        items = {
            {"Square, Wide, Tall", "Keep only images of that shape."},
            {"Size handles", "Drag them to the sizes you want; they snap to 16, 32, 64 and up. Click the size above them for any size."},
        },
    },
    image = {
        title = "Image preview",
        items = {
            {"- + and the wheel", "Zoom in and out; drag the image to pan."},
            {"1:1", "Show it at the size the game draws it."},
            {"Fit", "Fit the whole image in the preview."},
            {"Canvas", "Change the background (dark, checkered or light) to see transparent edges."},
            {"Repeat", "Show copies side by side, stacked, or tiled 3 by 3, to check that the edges line up."},
        },
    },
    model = {
        title = "Model preview",
        items = {
            {"Drag", "Turn the model with either button: across spins it, up and down tilts it, Shift+drag rolls it."},
            {"Middle-drag and the wheel", "Move the model, and zoom."},
            {"Animation", "Step through the moves this model has: stand, walk, attack, dance."},
            {"Reset", "Put the turn, zoom and position back."},
            {"Canvas", "Change the background behind the model."},
            {"Target", "Find your target's model and remember the NPC's name."},
        },
    },
    sound = {
        title = "Sound player",
        items = {
            {"Play and Stop", "Play the sound, or stop it. Clicking a row's waveform plays it too."},
            {"< and > in the preview", "Play the previous or next sound in the results."},
            {"Channel", "Which of the game's volume sliders it obeys. A muted channel plays nothing."},
            {"Hover play", "Play a sound when the pointer rests on its row; it stops when you move off."},
            {"Auto-play", "Play each sound as soon as you select it."},
            {"Play through", "When a sound ends, play the next one in the results."},
        },
    },
    control = {
        title = "Controls",
        items = {
            {"Build preview", "Make a live copy of the control. Each one is built once per session."},
        },
    },
    font = {
        title = "Fonts",
        items = {
            {"Sample text", "Type your own text to see it in every font; it is remembered."},
        },
    },
    lists = {
        title = "Lists",
        items = {
            {"New, Rename, Delete", "Make a list, or rename or delete the one picked; deleting takes two clicks."},
            {"Add to list and *", "In the right panel: put what you are looking at in a list, or favorite it."},
            {"Manage lists", "The right-click menu's last line jumps here."},
        },
    },
    options = {
        title = "Options",
        items = {
            {"A checkbox per tab", "Untick a tab you never use and it no longer loads, so the lab opens faster. Everything is on to start with."},
            {"Load now", "On a tab you turned off: load it for this session only."},
        },
    },
}

-- The groups each tab's ? card shows, before Options and Everywhere.
ML.Help.switchesFor = {
    icon = {"grid", "image"},
    texture = {"grid", "sized", "image"},
    atlas = {"grid", "sized", "image"},
    model = {"model"},
    sound = {"sound"},
    control = {"control"},
    font = {"font"},
    lists = {"lists"},
}

-- Shown on every tab, after its own groups.
ML.Help.always = {"options", "everywhere"}

-- The README's order for the "Every switch" section.
ML.Help.switchOrder = {"everywhere", "grid", "sized", "image", "model", "sound", "control", "font", "lists", "options"}
