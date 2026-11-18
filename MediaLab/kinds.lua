local _, ML = ...

-- The tab registry. Every media type is described here as data; the catalog,
-- browser and inspector read these fields instead of special-casing a kind.
--   layout   "grid" shows thumbnails, "rows" shows a list
--   cell     base thumbnail size in UI units for grid layouts
--   visual   entries render as images (thumbnails, zoomable preview)
--   preview  which inspector preview renders the selection
ML.Kinds = {
    {id = "icon", label = "Icons", noun = "icons", layout = "grid", cell = 48, visual = true, preview = "image",
        facetGroups = {"Type", "Subject", "Color"}},
    {id = "texture", label = "Textures", noun = "textures", layout = "grid", cell = 112, visual = true, caption = true, preview = "image"},
    {id = "atlas", label = "Atlases", noun = "atlases", layout = "grid", cell = 112, visual = true, caption = true, preview = "image"},
    {id = "sound", label = "Sounds", noun = "sounds", layout = "rows", preview = "sound"},
    {id = "control", label = "Controls", noun = "templates", layout = "rows", preview = "control"},
    {id = "font", label = "Fonts", noun = "fonts", layout = "rows", preview = "font"},
}

ML.Tabs = {}
ML.KindById = {}
for _, kind in ipairs(ML.Kinds) do
    ML.Tabs[#ML.Tabs + 1] = kind
    ML.KindById[kind.id] = kind
end
-- Favorites is a tab without its own kind: it lists saved entries of every kind.
ML.Tabs[#ML.Tabs + 1] = {id = "favorites", label = "Favorites", noun = "favorites", layout = "rows"}

-- Build order: small, fast lists first so their tabs are usable immediately.
ML.IndexOrder = {"sound", "control", "font", "atlas", "texture", "icon"}

-- Grid thumbnail zoom steps (multipliers of a kind's base cell size).
ML.ThumbScales = {0.75, 1, 1.5, 2}

-- Preview zoom limits for image previews.
ML.Zoom = {min = 0.125, max = 16, step = 1.25}

ML.Canvases = {
    {id = "Dark", color = {0.035, 0.045, 0.06, 1}},
    {id = "Checker", color = {0.06, 0.07, 0.085, 1}, checker = {0.11, 0.13, 0.16, 1}},
    {id = "Light", color = {0.82, 0.84, 0.87, 1}},
}

ML.SoundChannels = {"Master", "SFX", "Music", "Ambience", "Dialog"}

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
