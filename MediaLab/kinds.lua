local _, ML = ...

-- The tab registry. Every media type is described here as data; the catalog,
-- browser and inspector read these fields instead of special-casing a kind.
--   layout   "grid" shows thumbnails, "rows" shows a list
--   cell     base thumbnail size in UI units for grid layouts
--   visual   entries render as images (thumbnails, zoomable preview)
--   preview  which inspector preview renders the selection
--   detail   what a row shows on the right: "id" for the ID, else the first facet
--   tab      the tab button it lives under, when that is another kind's (atlases
--            are textures); view names it inside that tab
--   developer  shown only in developer mode
ML.Kinds = {
    {id = "icon", label = "Icons", noun = "icons", layout = "grid", cell = 48, visual = true, preview = "image",
        facetGroups = {"Subject", "Color"}},
    {id = "texture", label = "Textures", noun = "textures", layout = "grid", cell = 112, visual = true, caption = true,
        preview = "image", view = "Files"},
    {id = "atlas", label = "Atlases", noun = "atlases", layout = "grid", cell = 112, visual = true, caption = true,
        preview = "image", tab = "texture", view = "Atlases"},
    {id = "model", label = "Models", noun = "models", layout = "rows", preview = "model", detail = "id",
        facetGroups = {"Family"}},
    {id = "sound", label = "Sounds", noun = "sounds", layout = "rows", preview = "sound", detail = "id"},
    {id = "control", label = "Controls", noun = "templates", layout = "rows", preview = "control"},
    {id = "font", label = "Fonts", noun = "fonts", layout = "rows", preview = "font", developer = true},
}

ML.Tabs = {}
ML.KindById = {}
for _, kind in ipairs(ML.Kinds) do
    ML.Tabs[#ML.Tabs + 1] = kind
    ML.KindById[kind.id] = kind
end
-- Lists is a tab without its own kind: it shows the entries saved to lists
-- (lists.lua), of every kind. Its filter column lists the lists.
ML.ListsTab = "lists"
ML.Tabs[#ML.Tabs + 1] = {id = ML.ListsTab, label = "Lists", noun = "saved entries", layout = "rows",
    aliases = {"favorites", "list"}}

-- The tab bar: one button per tab, holding the kinds that live under it in
-- order (Textures holds Files and Atlases). Built from the fields above.
ML.TabBar = {}
local buttons = {}
for _, tab in ipairs(ML.Tabs) do
    local owner = tab.tab or tab.id
    local button = buttons[owner]
    if not button then
        button = {id = owner, label = tab.label, kinds = {}, developer = tab.developer}
        buttons[owner] = button
        ML.TabBar[#ML.TabBar + 1] = button
    end
    button.kinds[#button.kinds + 1] = tab.id
end
function ML.TabButtonOf(tabId)
    local tab = ML.KindById[tabId]
    return buttons[tab and tab.tab or tabId]
end

-- The formats the Copy dialog offers for a set of entries, in button order.
ML.CopyFormats = {
    {id = "lua", label = "Lua", hint = "A Lua table of every entry, grouped by kind."},
    {id = "csv", label = "CSV", hint = "One row per entry."},
}

-- Build order: small, fast lists first so their tabs are usable immediately.
ML.IndexOrder = {"sound", "control", "font", "atlas", "texture", "model", "icon"}

-- Grid thumbnail zoom, per tab: a multiple of the kind's base cell size, from
-- min to max; each wheel notch or - / + press multiplies or divides by step.
ML.ThumbZoom = {min = 0.5, max = 4, step = 1.15}

-- Preview zoom limits for image previews.
ML.Zoom = {min = 0.125, max = 16, step = 1.25}

ML.Canvases = {
    {id = "Dark", color = {0.035, 0.045, 0.06, 1}},
    {id = "Checker", color = {0.06, 0.07, 0.085, 1}, checker = {0.11, 0.13, 0.16, 1}},
    {id = "Light", color = {0.82, 0.84, 0.87, 1}},
}

ML.SoundChannels = {"Master", "SFX", "Music", "Ambience", "Dialog"}

-- Animations the model preview cycles through (AnimationData IDs). Ones a
-- model does not have are skipped.
ML.ModelAnimations = {
    {id = 0, label = "Stand"}, {id = 4, label = "Walk"}, {id = 5, label = "Run"},
    {id = 16, label = "Attack"}, {id = 74, label = "Roar"}, {id = 60, label = "Talk"},
    {id = 69, label = "Dance"}, {id = 1, label = "Death"},
}

-- Model preview camera: distance scale limits and step for the wheel, and
-- how fast dragging turns the model (radians per UI unit).
ML.ModelCamera = {min = 0.4, max = 4, step = 1.15, turn = 0.012}

-- Font preview text, top to bottom. The headline is replaced by the user's own
-- sample when they type one; the rest always follows.
ML.FontSamples = {
    headline = "The quick brown fox jumps over the lazy dog.",
    blocks = {
        "ABCDEFGHIJKLMNOPQRSTUVWXYZ\nabcdefghijklmnopqrstuvwxyz\n0123456789  . , : ; ! ? ' \" ( ) [ ] { } < > + - = * / & % $ # @",
        "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat.",
        "Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.",
    },
}

-- Frame types CreateFrame accepts for template previews. Region templates
-- (textures, font strings, lines) are built with their own constructors.
ML.RegionTypes = {Texture = "CreateTexture", FontString = "CreateFontString", Line = "CreateLine"}
ML.UnbuildableTypes = {AnimationGroup = true, Font = true, FontFamily = true}
