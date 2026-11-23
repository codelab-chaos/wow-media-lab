local Mock = dofile("tests/wow.lua")
local passed = 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if not ok then error(name .. ": " .. tostring(err), 0) end
    passed = passed + 1
    print("ok - " .. name)
end
local function equal(actual, expected, message)
    assert(actual == expected, (message or "") .. " " .. tostring(actual) .. " ~= " .. tostring(expected))
end
local function open()
    local ML = Mock.load()
    SlashCmdList.MEDIALAB("")
    Mock.flush()
    return ML
end
local function find(ML, kind, value) return ML.Catalog.byKey[ML.Catalog:Key(kind, value)] end

test("manifest loads lazily: no window or indexing until opened", function()
    local ML = Mock.load()
    assert(not ML.UI.frame and not ML.Catalog.started)
    SlashCmdList.MEDIALAB("help")
    equal(#Mock.messages, 6)
    assert(Mock.messages[6]:find("github.com/codelab-chaos/wow-media-lab/issues", 1, true), "help ends with the feedback link")
    SlashCmdList.MEDIALAB("bogus")
    equal(#Mock.messages, 7)
end)

test("opening indexes every kind in batches and reuses a bounded cell pool", function()
    local ML = Mock.load()
    SlashCmdList.MEDIALAB("")
    assert(ML.UI.frame:IsShown() and not ML.Catalog.ready, "indexing should be incremental")
    Mock.flush()
    local C = ML.Catalog
    assert(C.ready and not C.error)
    assert(not C.worker.scripts.OnUpdate, "indexer stops when done")
    for _, kind in ipairs(ML.Kinds) do assert(C:Count(kind.id) > 0, kind.id .. " is empty") end
    assert(C:Count("texture") > 900, "non-icon UI source textures")
    assert(C:Count("sound") > 800, "generated sound kits merge with runtime SOUNDKIT")
    assert(find(ML, "sound", "UI_TEST_ONLY_RUNTIME"), "runtime-only sound kit present")
    equal(UISpecialFrames[1], "MediaLabFrame")
    assert(ML.UI.inspector.entry, "first result selected")
    ML.UI:SelectTab("icon")
    assert(#ML.UI.browser.cells <= 400)
    SlashCmdList.MEDIALAB("")
    assert(not ML.UI.frame:IsShown())
end)

test("runtime lists win and duplicates collapse with merged facets", function()
    local ML = open()
    local icon = find(ML, "icon", 134400)
    assert(icon.facetSet["Spell icons"] and icon.facetSet["Item icons"], "numeric icon merged across lists")
    local path = find(ML, "icon", "interface/icons/inv_misc_map_01.blp")
    assert(path, "icon paths normalize")
    equal(ML.Catalog:Count("control"), 6, "control list comes from C_XMLUtil, fonts excluded")
    equal(find(ML, "control", "UIPanelButtonTemplate").source, "Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.xml")
    assert(not find(ML, "font", "NotLoadedFont"), "unloaded fonts are skipped")
    equal(ML.Catalog:Count("atlas"), 3)
end)

test("fallback data is used and validated when native APIs are missing", function()
    local ML = Mock.load()
    C_Texture.GetAtlasElements, C_XMLUtil, SOUNDKIT, GetFonts = nil, nil, nil, nil
    SlashCmdList.MEDIALAB(""); Mock.flush()
    local C = ML.Catalog
    assert(C.ready and not C.error)
    equal(C:Count("atlas"), 1, "only atlases the client knows survive")
    assert(C:Count("control") > 3000)
    assert(C:Count("sound") > 800)
    equal(C:Count("font"), 3, "fallback fonts validated against loaded objects")
end)

test("search needs every literal word and never treats input as a pattern", function()
    local ML = open()
    ML.UI:SelectTab("sound")
    SlashCmdList.MEDIALAB("search mainmenu open")
    Mock.flush()
    assert(#ML.UI.results > 0)
    for _, entry in ipairs(ML.UI.results) do
        assert(entry.search:find("mainmenu", 1, true) and entry.search:find("open", 1, true))
    end
    ML.UI:Search("850")
    equal(ML.UI.results[1].value, "IG_MAINMENU_OPEN", "IDs are searchable")
    ML.UI:Search("[%.*(")
    equal(#ML.UI.results, 0)
    ML.UI.search.box:Type("ig_mainmenu_close")
    Mock.flush()
    equal(#ML.UI.results, 1, "typing searches after a short delay")
end)

test("facets filter a tab, Common leads, counts are exact", function()
    local ML = open()
    ML.UI:SelectTab("control")
    local facets = ML.Catalog:Facets("control")
    equal(facets[1].name, "Common")
    equal(facets[1].count, 3)
    ML.UI:SetFacet("Button")
    equal(#ML.UI.results, 1)
    equal(ML.UI.results[1].value, "UIPanelButtonTemplate")
    ML.UI:SetFacet(nil)
    equal(#ML.UI.results, 6)
    local textures = ML.Catalog:Facets("texture")
    local seen = {}
    for _, facet in ipairs(textures) do
        assert(not seen[facet.name:lower()], "folder facet split by casing: " .. facet.name)
        seen[facet.name:lower()] = true
    end
end)

test("old favorites become the first list, and the Favorites tab name still works", function()
    local ML = Mock.load({favorites = {["sound:IG_MAINMENU_OPEN"] = true}, view = {tab = "favorites", facets = {favorites = "Sounds"}}})
    equal(#ML.db.lists, 1)
    equal(ML.db.lists[1].name, "Favorites")
    assert(ML.db.lists[1].keys["sound:IG_MAINMENU_OPEN"])
    equal(ML.db.favorites, nil)
    SlashCmdList.MEDIALAB(""); Mock.flush()
    equal(ML.UI.tabId, "lists")
    equal(#ML.UI.results, 1)
    SlashCmdList.MEDIALAB("tab favorites")
    equal(ML.UI.tabId, "lists")
end)

test("Favorites is built in; an entry can sit in many lists; lists persist, rename and delete", function()
    local ML = open()
    equal(#ML.db.lists, 1)
    equal(ML.Lists:Favorites().name, "Favorites")
    local sound = find(ML, "sound", "IG_MAINMENU_OPEN")
    local atlas = find(ML, "atlas", "test-glow")
    -- Right-click toggles Favorites, whatever list is picked.
    ML.UI:ToggleFavorite(atlas)
    assert(ML.Catalog:IsFavorite(atlas))
    ML.UI:NewList()
    ML.Prompt.frame.input.box:SetText("Raid kit")
    ML.Prompt.Accept()
    equal(ML.UI.tabId, "lists")
    local kit = ML.Lists:Named("raid kit")
    ML.Lists:Set(kit, sound.key, true)
    ML.Lists:Set(kit, atlas.key, true)
    ML.UI:ToggleFavorite(sound)
    assert(ML.Catalog:IsFavorite(sound), "right-click still means Favorites")
    equal(#ML.Lists:Of(atlas.key), 2)
    -- Names are unique, ignoring case; the prompt stays open with the reason.
    ML.UI:NewList()
    ML.Prompt.frame.input.box:SetText("FAVORITES")
    ML.Prompt.Accept()
    assert(ML.Prompt.frame.message:GetText():find("already exists", 1, true))
    assert(ML.Prompt.frame:IsShown())
    -- Favorites cannot be renamed or deleted.
    equal(ML.Lists:Delete(ML.Lists.FAVORITES), false)
    assert(not ML.Lists:Rename(ML.Lists.FAVORITES, "Mine"))

    ML = Mock.load(ML.db)
    SlashCmdList.MEDIALAB("tab lists"); Mock.flush()
    equal(#ML.UI.results, 2, "All saved")
    ML.UI:SetFacet("list:1")
    equal(#ML.UI.results, 2, "Favorites")
    assert(not ML.UI.listActions.delete:IsEnabled(), "Favorites has no Delete")
    equal(ML.UI.facetButtons[2].name:GetText(), "Favorites")
    equal(ML.UI.facetButtons[3].name:GetText(), "Raid kit")
    equal(ML.UI.facetButtons[3].count:GetText(), "2")

    kit = ML.Lists:Named("Raid kit")
    ML.UI:SetFacet(ML.Lists.Facet(kit))
    assert(ML.UI.listActions.delete:IsEnabled())
    ML.UI:RenameList(kit)
    ML.Prompt.frame.input.box:SetText("UI kit")
    ML.Prompt.Accept()
    equal(kit.name, "UI kit")
    local delete = ML.UI.listActions.delete
    delete.scripts.OnClick(delete)
    assert(ML.Lists:Get(kit.id), "the first click only arms Delete")
    delete.scripts.OnClick(delete)
    equal(ML.Lists:Get(kit.id), nil)
    equal(#ML.UI.results, 2, "back to All saved; Favorites keeps its entries")
end)

test("the inspector stars favorites and its list menu adds to any list and makes new ones", function()
    local ML = open()
    ML.UI:SelectTab("atlas")
    local atlas = find(ML, "atlas", "test-glow")
    ML.UI:Select(atlas)
    local star, button = ML.UI.inspector.favorite, ML.UI.inspector.lists
    star.scripts.OnClick(star)
    assert(ML.Catalog:IsFavorite(atlas))
    equal(button.text:GetText(), "In 1 list")
    button.scripts.OnClick(button)
    local menu = ML.ListMenu.frame
    assert(menu:IsShown())
    equal(menu.rows[1].name:GetText(), "Favorites")
    assert(menu.rows[1].check:IsShown())
    local new = menu.rows[2]
    equal(new.name:GetText(), "+ New list...")
    new.scripts.OnClick(new)
    ML.Prompt.frame.input.box:SetText("Borders")
    ML.Prompt.Accept()
    equal(button.text:GetText(), "In 2 lists")
    ML.Lists:Create("Glows")
    button.scripts.OnClick(button)
    equal(menu.rows[3].name:GetText(), "Glows")
    assert(not menu.rows[3].check:IsShown())
    menu.rows[3].scripts.OnClick(menu.rows[3])
    assert(menu.rows[3].check:IsShown())
    equal(button.text:GetText(), "In 3 lists")
    menu.rows[1].scripts.OnClick(menu.rows[1])
    assert(not ML.Catalog:IsFavorite(atlas), "the menu unfavorites too")
    equal(#ML.Lists:Of(atlas.key), 2)
end)

test("saved variables of any shape load and the whole lab still works", function()
    -- A hand-edited or foreign MediaLabDB: every setting gets each wrong type.
    local junk = {42, "junk", true, {1, 2, {x = 1}}, -1}
    local viewKeys = {"tab", "thumb", "thumbScales", "sizes", "repeatMode", "canvas", "channel", "copyFormat", "sample", "autoplay", "modelAnimation",
        "inspectorWidth", "facetWidth", "facets", "views", "zooms", "modelDistance"}
    for _, value in ipairs(junk) do
        local view = {facets = {icon = value, [5] = value}, views = {texture = value, [value] = "atlas"}}
        for _, key in ipairs(viewKeys) do if key ~= "facets" and key ~= "views" then view[key] = value end end
        local saved = {
            view = view, favorites = value, nextListId = value, minimized = value, maximized = value,
            developer = value, welcomed = value, counts = {icon = value, [5] = value, sound = -3},
            lists = {value, {id = value, name = value, keys = value}, {id = 7, name = "Kept", keys = {[5] = true, ["icon:134400"] = value, ["sound:IG_MAINMENU_OPEN"] = true}}},
            npcs = {[value] = value, [12] = {name = value, display = value}},
            window = {point = value, relativePoint = value, x = value, width = value},
            dock = {side = value, at = value},
        }
        local ML = Mock.load(saved)
        SlashCmdList.MEDIALAB("")
        Mock.flush()
        assert(ML.UI.frame:IsShown(), "opens with " .. tostring(value))
        equal(ML.Lists:Get(7).name, "Kept", "good lists survive next to bad ones")
        for _, tab in ipairs(ML.Tabs) do
            ML.UI:SelectTab(tab.id)
            local holder = ML.UI.browser.cells[1]
            if not (holder and holder.shown) then holder = ML.UI.browser.rows[1] end
            if holder and holder.shown and holder.entry then
                holder.scripts.OnClick(holder, "LeftButton")
                holder.scripts.OnClick(holder, "RightButton")
                ML.ListMenu.Hide()
            end
        end
        ML.UI.zoomControl.into.scripts.OnClick(ML.UI.zoomControl.into)
        ML.UI:SelectTab("texture")
        local image = ML.UI.inspector.previews.image
        if image then image.canvasButton.scripts.OnClick(image.canvasButton) end
        ML.UI:SelectTab("sound")
        ML.UI.browser.rows[1].play.scripts.OnClick(ML.UI.browser.rows[1].play)
        ML.UI:SetDeveloper(true)
        ML.UI:SelectTab("font")
        ML.UI:CopyResults("lua")
        ML.UI:CopyResults("csv")
        ML.UI:SetMaximized(true)
        ML.UI:SetMaximized(false)
        ML.UI:SetMinimized(true)
        ML.Dock.button.scripts.OnClick(ML.Dock.button)
        ML.UI:ToggleHelp()
        ML.UI.splitters.inspector.scripts.OnDoubleClick(ML.UI.splitters.inspector)
    end
end)

test("textures and atlases filter by shape and by a size range that snaps to popular sizes", function()
    local ML = open()
    ML.UI:SelectTab("atlas")
    local glow = find(ML, "atlas", "test-glow")
    equal(glow.width, 256); equal(glow.height, 128)
    assert(glow.facetSet["Shape: Wide"], "256 x 128 is wide")
    local facets = ML.Catalog:Facets("atlas")
    local firstShape, firstPlain
    for index, facet in ipairs(facets) do
        if ML.Catalog.FacetGroup(facet.name) == "Shape" then firstShape = firstShape or index
        elseif facet.name ~= "Common" then firstPlain = firstPlain or index end
    end
    assert(firstShape and firstPlain and firstShape < firstPlain, "SHAPE comes before the plain filters on Textures")
    ML.UI:SelectTab("texture")
    local range = ML.UI.sizeRange
    assert(range.frame.shown, "the size range shows on Textures")
    equal(range.value.text:GetText(), "Any")
    -- Drag the low handle to the 64 groove and the high one to 256.
    local track = range.track
    local function at(stop)
        for index, value in ipairs(ML.SizeStops) do
            if value == stop then return track:GetLeft() + (index - 1) / (#ML.SizeStops - 1) * track:GetWidth() + 2 end
        end
    end
    Mock.cursorX = at(64)
    range.handles[1].scripts.OnMouseDown(range.handles[1])
    range.handles[1].scripts.OnMouseUp(range.handles[1])
    Mock.cursorX = at(256)
    range.handles[2].scripts.OnMouseDown(range.handles[2])
    range.handles[2].scripts.OnMouseUp(range.handles[2])
    equal(range.value.text:GetText(), "64 to 256 px", "the handles snap to the grooves")
    assert(#ML.UI.results > 0)
    for _, entry in ipairs(ML.UI.results) do
        local longer = math.max(entry.width, entry.height)
        assert(longer >= 64 and longer <= 256, entry.name)
    end
    local all = #ML.Catalog:Filter("texture", nil, "")
    assert(#ML.UI.results < all, "the range narrows the results")
    ML.UI:SetFacet("Shape: Square")
    for _, entry in ipairs(ML.UI.results) do assert(entry.facetSet["Shape: Square"]) end
    ML.UI:SelectTab("atlas")
    equal(ML.UI.sizeRange.value.text:GetText(), "Any", "each view has its own range")
    ML.UI:SelectTab("model")
    assert(not ML.UI.sizeRange.frame.shown, "models have no size")
    local saved = ML.db
    ML = Mock.load(saved)
    SlashCmdList.MEDIALAB(""); Mock.flush()
    ML.UI:SelectTab("texture")
    equal(ML.UI.sizeRange.value.text:GetText(), "64 to 256 px", "the range survives a reload")
    ML.UI.sizeRange.value.scripts.OnClick(ML.UI.sizeRange.value)
    equal(ML.UI.sizeRange.value.text:GetText(), "Any")
    equal(ML.db.view.sizes.texture, nil)
end)

test("sounds list every sound kit the client can play, not just the SOUNDKIT names", function()
    local ML = open()
    assert(Mock.loaded.MediaLab_Sounds, "the sound data loads with the Sounds tab")
    equal(MediaLabSounds, nil, "global released")
    local murloc = find(ML, "sound", 417)
    equal(murloc.name, "mmurlocattack")
    assert(murloc.facetSet.Creature and murloc.facetSet["Folder: Murloc"])
    local open = find(ML, "sound", "IG_MAINMENU_OPEN")
    assert(open.facetSet.Interface and open.facetSet["Prefix: IG"], "a named kit keeps its SOUNDKIT name")
    equal(find(ML, "sound", 850), nil, "and is not listed twice under its ID")
    ML.UI:SelectTab("sound")
    ML.UI:Search("murloc")
    equal(#ML.UI.results, 2)
    ML.UI:Select(murloc)
    ML.UI.inspector.previews.sound.play.scripts.OnClick(ML.UI.inspector.previews.sound.play)
    equal(Mock.sounds[#Mock.sounds].id, 417, "plays by kit ID")
    ML.UI:SetDeveloper(true)
    local fields = ML.Snippets.For(murloc, {channel = "SFX"})
    equal(fields[3].text, 'PlaySound(417, "SFX")', "code uses the ID when there is no SOUNDKIT name")
    ML.Lists:ToggleFavorite(murloc.key)
    equal(murloc.key, "sound:417")
    assert(ML.Catalog:IsFavorite(murloc), "kits by ID can be saved like anything else")
end)

test("the loading card counts every library in, then fades out", function()
    local ML = Mock.load()
    SlashCmdList.MEDIALAB("")
    local card = ML.Loader.frame
    assert(card.shown, "shows while the lab fills")
    equal(#card.rows, #ML.IndexOrder)
    equal(card.rows[1].name:GetText(), "Sounds")
    assert(card.rows[1].source:GetText():find("MediaLab_Sounds", 1, true), "says where it comes from")
    local worker = ML.Catalog.worker
    for _ = 1, 3 do worker.scripts.OnUpdate(worker) end
    card.scripts.OnUpdate(card, 0.1)
    assert(card.line:GetText() ~= "", "says what it is doing")
    assert(card.total:GetText():find("entries so far", 1, true))
    Mock.flush()
    assert(not card.shown, "fades out once everything is in")
    assert(ML.db.counts.icon > 0 and ML.db.counts.sound > 0, "remembers how many of each for next time")
    -- Next session: the bars know the totals.
    ML = Mock.load(ML.db)
    SlashCmdList.MEDIALAB("")
    card = ML.Loader.frame
    local worker2 = ML.Catalog.worker
    for _ = 1, 3 do worker2.scripts.OnUpdate(worker2) end
    ML.UI:RenderLoader()
    local sounds = card.rows[1]
    assert(sounds.count:GetText():find(" / " .. ML.Loader.Format(ML.db.counts.sound), 1, true) or sounds.fraction == 1,
        "counts read 'so far / last time'")
    card.browse.scripts.OnClick(card.browse)
    assert(not card.shown, "Browse now hides it early")
    Mock.flush()
    assert(ML.Catalog.ready)
    equal(ML.Loader.Format(1234567), "1,234,567")
end)

test("selection works like a file browser: click, Ctrl+click and Shift+click", function()
    local ML = open()
    local S = ML.Selection
    local results = {{key = "a"}, {key = "b"}, {key = "c"}, {key = "d"}, {key = "e"}}
    S:Click(results[2], {}, results)
    equal(S:Count(), 1)
    S:Click(results[4], {shift = true}, results)
    equal(S:Count(), 3, "Shift picks the range b..d")
    assert(S:Has(results[3]))
    S:Click(results[1], {ctrl = true}, results)
    equal(S:Count(), 4, "Ctrl adds one")
    local focus = S:Click(results[3], {ctrl = true}, results)
    assert(not S:Has(results[3]), "Ctrl takes one out")
    equal(focus, results[1], "and the inspector moves to the last one still picked")
    S:Click(results[5], {ctrl = true, shift = true}, results)
    equal(S:Count(), 5, "Ctrl+Shift adds the range from the last click")
    S:Click(results[2], {}, results)
    equal(S:Count(), 1, "a plain click starts over")
end)

test("right-click opens the lists menu on every kind, for one entry or the whole selection", function()
    local ML = open()
    local list = ML.Lists:Create("Gnomes")
    -- A grid tile (icons) and a list row (sounds) both open the menu.
    for _, tab in ipairs({"icon", "sound"}) do
        ML.UI:SelectTab(tab)
        local holder = tab == "icon" and ML.UI.browser.cells[1] or ML.UI.browser.rows[1]
        holder.scripts.OnClick(holder, "RightButton")
        local menu = ML.ListMenu.frame
        assert(menu:IsShown(), tab .. " opens the menu")
        local labels = {}
        for _, row in ipairs(menu.rows) do if row:IsShown() then labels[#labels + 1] = row.name:GetText() end end
        equal(table.concat(labels, ","), "Favorites,Gnomes,+ New list...,Manage lists...")
        assert(menu.rows[1].star.shown or menu.rows[1].icon.shown, "Favorites has its star")
        equal(ML.UI.inspector.entry, holder.entry, "right-click picks what it was on")
        ML.ListMenu.Hide()
    end
    -- Three sounds, picked with Shift, then one already in Gnomes: a dash.
    local rows = ML.UI.browser.rows
    rows[1].scripts.OnClick(rows[1], "LeftButton")
    Mock.shift = true
    rows[3].scripts.OnClick(rows[3], "LeftButton")
    Mock.shift = false
    equal(ML.Selection:Count(), 3)
    assert(ML.UI.tray.shown and ML.UI.tray.label:GetText():find("^3 selected:"), "the strip lists the selection")
    assert(rows[2].picked.shown, "picked rows are tinted")
    ML.Lists:Set(list, rows[2].entry.key, true)
    rows[2].scripts.OnClick(rows[2], "RightButton")
    local menu = ML.ListMenu.frame
    equal(menu.rows[1].name:GetText(), "3 selected")
    local gnomes = menu.rows[3]
    equal(gnomes.name:GetText(), "Gnomes")
    assert(gnomes.partial.shown and not gnomes.check.shown, "some are in Gnomes: a dash")
    gnomes.scripts.OnClick(gnomes)
    assert(gnomes.check.shown, "a click adds them all")
    for index = 1, 3 do assert(ML.Lists:Has(list, rows[index].entry.key)) end
    gnomes.scripts.OnClick(gnomes)
    for index = 1, 3 do assert(not ML.Lists:Has(list, rows[index].entry.key), "and again removes them all") end
    local favorite = menu.rows[2]
    favorite.scripts.OnClick(favorite)
    for index = 1, 3 do assert(ML.Lists:IsFavorite(rows[index].entry.key)) end
    -- New list from the menu holds the whole selection.
    local new
    for _, row in ipairs(menu.rows) do if row:IsShown() and row.name:GetText() == "+ New list..." then new = row end end
    new.scripts.OnClick(new)
    ML.Prompt.frame.input.box:SetText("QParty sounds")
    ML.Prompt.Accept()
    equal(ML.Catalog:SavedCount(ML.Lists:Named("QParty sounds")), 3)
    -- Copy takes the selection, and Clear keeps only the inspected entry.
    ML.UI:SetDeveloper(true)
    ML.UI.copyButton.scripts.OnClick(ML.UI.copyButton)
    assert(ML.CopyDialog.frame.title:GetText():find("Selected media", 1, true))
    ML.UI.tray.clear.scripts.OnClick(ML.UI.tray.clear)
    equal(ML.Selection:Count(), 1)
    assert(not ML.UI.tray.shown)
    -- Manage lists jumps to the Lists tab.
    rows[1].scripts.OnClick(rows[1], "RightButton")
    local manage
    for _, row in ipairs(menu.rows) do if row:IsShown() and row.name:GetText() == "Manage lists..." then manage = row end end
    manage.scripts.OnClick(manage)
    equal(ML.UI.tabId, ML.ListsTab)
end)

test("a list copies as one Lua table of every asset, grouped by kind", function()
    local ML = open()
    local list = ML.Lists:Create("Raid frame kit")
    for _, ref in ipairs({{"icon", 134400}, {"atlas", "test-glow"}, {"sound", "IG_MAINMENU_OPEN"},
        {"control", "UIPanelButtonTemplate"}, {"font", "GameFontNormal"}}) do
        local entry = assert(find(ML, ref[1], ref[2]), ref[1])
        ML.Lists:Set(list, entry.key, true)
    end
    ML.UI:SelectTab("lists")
    ML.UI:SetFacet(ML.Lists.Facet(list))
    SlashCmdList.MEDIALAB("copy")
    local dialog = ML.CopyDialog.frame
    local text = dialog.field.value
    assert(text:find("^local RaidFrameKit = {\n"), text)
    assert(text:find("    icons = {\n        134400,", 1, true), text)
    assert(text:find('    atlases = {\n        "test-glow",', 1, true), text)
    assert(text:find("    sounds = {\n        SOUNDKIT.IG_MAINMENU_OPEN,", 1, true), text)
    assert(text:find('    templates = {\n        "UIPanelButtonTemplate",', 1, true), text)
    local chunk = assert(loadstring(text .. "\nreturn RaidFrameKit"))
    setfenv(chunk, {SOUNDKIT = {IG_MAINMENU_OPEN = 850}})
    local kit = chunk()
    equal(kit.sounds[1], 850)
    equal(kit.fonts[1], "GameFontNormal")
    equal(dialog.title:GetText(), "Copy Raid frame kit")
    -- The same dialog switches to CSV and remembers it.
    dialog.formats[2].scripts.OnClick(dialog.formats[2])
    assert(dialog.field.value:find("^kind,name,value,id\n"), dialog.field.value)
    equal(ML.db.view.copyFormat, "csv")
    ML.UI:CopyResults()
    assert(dialog.field.value:find("^kind,name,value,id\n"), "the Copy button reopens in the last format")
    dialog.formats[1].scripts.OnClick(dialog.formats[1])
    equal(ML.db.view.copyFormat, "lua")
    assert(dialog.field.value:find("^local RaidFrameKit"), "back to Lua")
    equal(ML.Export.Identifier("9 lives!"), "_9Lives")
    equal(ML.Export.Identifier("  "), "media")
end)

test("every Lua snippet compiles for every kind", function()
    local ML = open()
    for _, kind in ipairs(ML.Kinds) do
        for _, entry in ipairs(ML.Catalog.byKind[kind.id]) do
            local fields = ML.Snippets.For(entry, {channel = "SFX"})
            assert(fields[1].text ~= "", kind.id .. " has a reference field")
            for _, field in ipairs(fields) do
                if field.label == "Lua" or field.label == "Inline text" or field.label == "New text" then
                    assert(loadstring(field.text), kind.id .. " snippet: " .. field.text)
                end
            end
        end
    end
    local sound = ML.Snippets.For(find(ML, "sound", "IG_MAINMENU_OPEN"), {channel = "SFX"})
    equal(sound[3].text, 'PlaySound(SOUNDKIT.IG_MAINMENU_OPEN, "SFX")')
    equal(ML.Snippets.For(find(ML, "icon", 134400))[1].text, "134400")
end)

test("copy fields select their text and refuse edits", function()
    local ML = open()
    ML.UI:SelectTab("atlas")
    ML.UI:Select(find(ML, "atlas", "test-glow"))
    local field = ML.UI.inspector.fields[1]
    equal(field.box:GetText(), "test-glow")
    field.copy.scripts.OnClick()
    assert(field.box.focus)
    field.box:Type("oops")
    equal(field.box:GetText(), "test-glow")
    assert(ML.UI.inspector.hint:GetText():find("Ctrl+C", 1, true))
end)

test("sounds play, stop, honor the channel and auto-play", function()
    local ML = open()
    ML.UI:SetDeveloper(true)
    ML.UI:SelectTab("sound")
    local entry = find(ML, "sound", "IG_MAINMENU_OPEN")
    ML.UI:Select(entry)
    equal(#Mock.sounds, 0, "no sound without asking")
    local preview = ML.UI.inspector.previews.sound
    preview.play.scripts.OnClick()
    equal(Mock.sounds[1].id, 850)
    equal(Mock.sounds[1].channel, "Master")
    equal(preview.play.text:GetText(), "Stop", "Play becomes Stop while it plays")
    preview.play.scripts.OnClick()
    equal(Mock.stopped[1], 1, "and stops it")
    preview.channel.scripts.OnClick()
    equal(ML.db.view.channel, "SFX")
    assert(ML.UI.inspector.fields[3].box:GetText():find('"SFX"', 1, true), "snippet follows channel")
    local auto
    for _, button in ipairs(preview.switches) do if button.switch.key == "autoplay" then auto = button end end
    auto.scripts.OnClick(auto)
    ML.UI:Select(find(ML, "sound", "IG_MAINMENU_CLOSE"))
    equal(Mock.sounds[#Mock.sounds].id, 851)
    local before = #Mock.sounds
    ML.UI.browser.handlers.onPlay(entry)
    equal(#Mock.sounds, before + 1, "row Play plays once even with auto-play on")
    assert(not preview:Play({id = 404, name = "Silent", key = "sound:404"}))
    assert(preview.status:GetText():find("did not play", 1, true))
end)

test("sound rows show a waveform, play on hover, and step and play through the results", function()
    local ML = open()
    ML.UI:SelectTab("sound")
    ML.UI:Search("murloc")
    local rows = ML.UI.browser.rows
    equal(rows[1]:GetHeight(), 40, "sound rows are two lines tall")
    local murloc = rows[1].entry.id == 417 and rows[1] or rows[2]
    assert(murloc.wave.frame.shown and #murloc.wave.bars == 16, "a bar per waveform step")
    assert(murloc.meta:GetText():find("0.8 s", 1, true) and murloc.meta:GetText():find("3 variations", 1, true))
    -- Hover play: rest on the row, then leave.
    local count = #Mock.sounds
    murloc.scripts.OnEnter(murloc)
    for _, timer in ipairs(Mock.timers) do -- just the hover delay, not the running sound
        if not timer.cancelled and not timer.done then timer.done = true; timer.callback() end
    end
    equal(#Mock.sounds, count + 1, "resting on a row plays it")
    equal(ML.SoundPlayer.source, "hover")
    Mock.now = Mock.now + 0.4
    ML.SoundPlayer:Tick()
    assert(murloc.wave.head.shown, "the playhead moves across the row")
    murloc.scripts.OnLeave(murloc)
    assert(not ML.SoundPlayer:IsPlaying(), "moving off stops a hover-played sound")
    -- The preview: details, the Name field, previous and next.
    local entry = find(ML, "sound", 417)
    ML.UI:Select(entry)
    local preview = ML.UI.inspector.previews.sound
    assert(preview.details:GetText():find("Played by: Creature murloc: Attack", 1, true))
    assert(preview.details:GetText():find("3 variations", 1, true))
    equal(ML.UI.inspector.fields[1].box:GetText(), "mmurlocattack", "a kit's Name is its name, not its ID")
    preview.nextButton.scripts.OnClick(preview.nextButton)
    equal(ML.UI.inspector.entry.id, 418, "Next picks and plays the next sound")
    equal(Mock.sounds[#Mock.sounds].id, 418)
    preview.previous.scripts.OnClick(preview.previous)
    equal(ML.UI.inspector.entry.id, 417)
    -- Play through: when a sound of known length ends, the next one plays.
    local through
    for _, button in ipairs(preview.switches) do if button.switch.key == "playThrough" then through = button end end
    through.scripts.OnClick(through)
    ML.SoundPlayer:Play(entry, "click")
    Mock.now = Mock.now + 2
    ML.SoundPlayer:Tick()
    equal(ML.UI.inspector.entry.id, 418, "the next sound plays when this one ends")
    -- The game's finished event ends a sound too.
    local handle = ML.SoundPlayer.handle
    through.scripts.OnClick(through)
    ML.SoundPlayer.ticker.scripts.OnEvent(ML.SoundPlayer.ticker, "SOUNDKIT_FINISHED", handle)
    assert(not ML.SoundPlayer:IsPlaying())
end)

test("controls build once on request, never in combat, and survive failures", function()
    local ML = open()
    ML.UI:SelectTab("control")
    local button = find(ML, "control", "UIPanelButtonTemplate")
    ML.UI:Select(button)
    local preview = ML.UI.inspector.previews.control
    assert(preview.info:GetText():find("120 x 22", 1, true), "template info shown")
    local count = #Mock.frames
    ML.UI:Select(button)
    equal(#Mock.frames, count, "selecting does not build")
    Mock.combat = true
    assert(not preview:Build())
    Mock.combat = false
    local widget = assert(preview:Build())
    equal(widget.template, "UIPanelButtonTemplate")
    equal(preview:Build(), widget, "built once and reused")
    assert(not preview.build:IsEnabled())
    ML.UI:Select(find(ML, "control", "GameFontNormalTemplate"))
    local text = assert(preview:Build())
    equal(text.kind, "FontString")
    assert(not widget.shown, "previous instance hidden")
    ML.UI:Select(find(ML, "control", "BrokenTemplate"))
    assert(not preview:Build())
    assert(preview.message:GetText():find("could not build", 1, true))
    ML.UI:Select(find(ML, "control", "TestAnimTemplate"))
    assert(not preview.build:IsEnabled(), "animation groups have no visual preview")
end)

test("built controls open at actual size, zoom, fit and pan, and keep the zoom per template", function()
    local ML = open()
    ML.UI:SelectTab("control")
    local button = find(ML, "control", "UIPanelButtonTemplate")
    ML.UI:Select(button)
    local preview = ML.UI.inspector.previews.control
    equal(preview.zoomLabel:GetText(), "", "nothing to zoom before building")
    local widget = assert(preview:Build())
    widget:SetSize(160, 26)
    preview:Layout()
    assert(preview.fitZoom > 1, "a small button could be enlarged to fit")
    equal(preview:CurrentZoom(), 1, "opens at actual size")
    equal(preview.holder.scale, 1)
    preview.stage.scripts.OnMouseWheel(preview.stage, 1)
    equal(preview:CurrentZoom(), ML.Zoom.step)
    equal(preview.holder.scale, ML.Zoom.step)
    preview:Fit()
    equal(preview:CurrentZoom(), preview.fitZoom)
    assert(preview.zoomLabel:GetText():find("fit", 1, true))
    preview:SetZoom(1)
    Mock.cursorX, Mock.cursorY = 0, 0
    preview.stage.scripts.OnMouseDown(preview.stage)
    Mock.cursorX, Mock.cursorY = 30, -10
    preview:Drag()
    preview.stage.scripts.OnMouseUp(preview.stage)
    equal(preview.panX, 30); equal(preview.panY, -10)
    local _, _, _, x, y = preview.holder:GetPoint()
    equal(x, 30); equal(y, -10)
    preview:SetZoom(1000)
    equal(preview:CurrentZoom(), ML.Zoom.max, "zoom is clamped")
    ML.UI:Select(find(ML, "control", "InputBoxTemplate"))
    ML.UI:Select(button)
    equal(preview:CurrentZoom(), ML.Zoom.max, "the zoom carries over to the next template")
    equal(preview.panX, 0, "the pan re-centers")
    preview:ResetView() -- no remembered zoom: the default
    widget:SetSize(4000, 2000)
    preview:Layout()
    assert(preview:CurrentZoom() < 1, "large controls shrink to fit by default")
end)

test("the scrollbar shows position and size, drags and pages", function()
    local ML = open()
    ML.UI:SelectTab("sound")
    local browser = ML.UI.browser
    local entries = {}
    for index = 1, 500 do
        entries[index] = {key = "sound:fake" .. index, kind = "sound", name = "FAKE_" .. index, value = "FAKE_" .. index,
            id = index, facets = {"Fake"}}
    end
    browser:SetData(entries, {mode = "rows"})
    local total, rows, maxRow = browser:RowSpan()
    equal(total, 500)
    assert(browser.track:IsShown(), "long lists show the scrollbar")
    local trackHeight = browser.track:GetHeight()
    local thumbHeight = browser.thumb:GetHeight()
    assert(thumbHeight >= 24 and thumbHeight < trackHeight, "thumb is proportional")
    local _, _, _, _, y = browser.thumb:GetPoint()
    equal(y, 0, "thumb starts at the top")
    -- Drag the thumb to the bottom of the track.
    Mock.cursorX, Mock.cursorY = 0, 500
    browser.thumb.scripts.OnMouseDown(browser.thumb)
    Mock.cursorY = 500 - trackHeight
    browser:DragThumb()
    browser.thumb.scripts.OnMouseUp(browser.thumb)
    equal(browser:FirstRow(), maxRow, "dragging to the end reaches the last page")
    _, _, _, _, y = browser.thumb:GetPoint()
    assert(math.abs(-y - (trackHeight - thumbHeight)) < 0.01, "thumb sits at the bottom")
    -- Click the track above the thumb: one page up.
    Mock.cursorY = 100000
    browser.track.scripts.OnClick(browser.track)
    equal(browser:FirstRow(), maxRow - rows)
    browser:SetData({entries[1], entries[2]}, {mode = "rows"})
    assert(not browser.track:IsShown(), "short lists hide it")
end)

test("image preview zooms within limits, pans, and keeps its zoom per kind", function()
    local ML = open()
    ML.UI:SelectTab("atlas")
    ML.UI:Select(find(ML, "atlas", "test-background"))
    local image = ML.UI.inspector.previews.image
    assert(image.note:GetText():find("256 x 128 native", 1, true))
    for _ = 1, 40 do image.stage.scripts.OnMouseWheel(image.stage, 1) end
    equal(image:CurrentZoom(), ML.Zoom.max)
    for _ = 1, 80 do image.stage.scripts.OnMouseWheel(image.stage, -1) end
    equal(image:CurrentZoom(), ML.Zoom.min)
    image:SetZoom(1)
    equal(image.art.width, 256)
    Mock.cursorX, Mock.cursorY = 0, 0
    image.stage.scripts.OnMouseDown(image.stage)
    Mock.cursorX, Mock.cursorY = 30, -10
    image.stage.scripts.OnUpdate(image.stage)
    image.stage.scripts.OnMouseUp(image.stage)
    equal(image.panX, 30); equal(image.panY, -10)
    ML.UI:Select(find(ML, "atlas", "test-glow"))
    equal(image:CurrentZoom(), 1, "the next atlas keeps the zoom")
    equal(image.panX, 0, "and re-centers")
    ML.UI:SelectTab("icon")
    ML.UI:Select(find(ML, "icon", 134400))
    assert(image.zoom == nil, "icons keep their own zoom (none set yet)")
    image:Fit()
    ML.UI:SelectTab("atlas")
    ML.UI:Select(find(ML, "atlas", "test-background"))
    equal(image:CurrentZoom(), 1, "back on atlases, their zoom is still 1:1")
    equal(ML.db.view.zooms.atlas, 1)
    equal(ML.db.view.zooms.icon, "fit")
    ML.UI:SelectTab("texture")
    local sized, unsized
    for _, entry in ipairs(ML.UI.results) do
        if entry.width and not sized then sized = entry end
        if not entry.width and not unsized then unsized = entry end
    end
    ML.UI:Select(sized)
    assert(image.note:GetText():find(sized.width .. " x " .. sized.height .. " native, from the game's files", 1, true),
        "a texture's real size, from the shipped data")
    ML.UI:Select(unsized)
    assert(image.note:GetText():find("assumes 256 x 256", 1, true), "an unknown size is still assumed")
    image.canvasButton.scripts.OnClick()
    equal(ML.db.view.canvas, "Checker")
end)

test("the image preview repeats an image across, down or both, edge to edge", function()
    local ML = open()
    ML.UI:SelectTab("atlas")
    ML.UI:Select(find(ML, "atlas", "test-glow"))
    local image = ML.UI.inspector.previews.image
    image:SetZoom(1)
    equal(image.repeatButton.text:GetText(), "Repeat: Off")
    image.repeatButton.scripts.OnClick(image.repeatButton)
    equal(image.repeatButton.text:GetText(), "Repeat: Across")
    equal(image.copyCount, 2, "two copies beside the original")
    local _, _, _, leftX = image.copies[1]:GetPoint()
    local _, _, _, artX = image.art:GetPoint()
    equal(artX - leftX, 256, "copies sit edge to edge at the image's width")
    image.repeatButton.scripts.OnClick(image.repeatButton)
    image.repeatButton.scripts.OnClick(image.repeatButton)
    equal(image.repeatButton.text:GetText(), "Repeat: Both")
    equal(image.copyCount, 8, "a 3 x 3 tile")
    image:Fit()
    assert(image:CurrentZoom() * 256 * 3 <= image.stage:GetWidth(), "Fit takes in the whole tile")
    image.repeatButton.scripts.OnClick(image.repeatButton)
    equal(image.repeatButton.text:GetText(), "Repeat: Off")
    equal(image.copyCount, 0)
    equal(ML.db.view.repeatMode, nil)
end)

test("fonts render the saved sample text", function()
    local ML = open()
    ML.UI:SetDeveloper(true)
    ML.UI:SelectTab("font")
    ML.UI:Select(find(ML, "font", "SystemFont_Large"))
    local preview = ML.UI.inspector.previews.font
    equal(preview.sample.fontObject, _G.SystemFont_Large)
    assert(preview.info:GetText():find("16.0", 1, true))
    assert(preview.sample:GetText():find("^The quick brown fox"))
    assert(preview.sample:GetText():find("Lorem ipsum", 1, true))
    preview.input.box:Type("Hello")
    assert(preview.sample:GetText():find("^Hello\n\nABC"))
    assert(preview.sample:GetText():find("laborum.$"))
    equal(ML.db.view.sample, "Hello")
end)

test("minimize docks an icon at a screen edge; it brings the window back, even after a reload", function()
    local ML = open()
    ML.UI.minimize.scripts.OnClick()
    assert(ML.db.minimized and not ML.UI.frame.shown, "the window hides")
    local dock = ML.Dock.button
    assert(dock.shown, "an icon docks")
    equal(ML.db.dock.side, "right")
    assert(dock.points.RIGHT, "on the right edge by default")
    dock.scripts.OnClick(dock)
    assert(ML.UI.frame.shown and not dock.shown and not ML.db.minimized, "the icon restores the window")
    ML.UI:SetMinimized(true)
    SlashCmdList.MEDIALAB("dock top")
    assert(dock.points.TOP, "/mlab dock moves it to another edge")
    SlashCmdList.MEDIALAB("dock sideways")
    assert(Mock.messages[#Mock.messages]:find("left, right, top or bottom", 1, true))
    local saved = ML.db
    ML = Mock.load(saved)
    assert(ML.Dock.button.shown and not ML.UI.frame, "after a reload only the icon comes back")
    ML.Dock.button.scripts.OnClick(ML.Dock.button)
    Mock.flush()
    assert(ML.UI.frame.shown and ML.UI.inspector.entry, "and opens the lab on click")
end)

test("the dock snaps to the nearest edge, kept off the corners", function()
    local ML = Mock.load()
    local side, at = ML.Dock.Nearest(30, 540, 1920, 1080)
    equal(side, "left"); equal(at, 0.5)
    side, at = ML.Dock.Nearest(960, 1070, 1920, 1080)
    equal(side, "top"); equal(at, 0.5)
    side, at = ML.Dock.Nearest(1915, 2, 1920, 1080)
    assert(side == "right" or side == "bottom")
    assert(at >= 0.04 and at <= 0.96, "never in a corner")
    equal(ML.Initialize({dock = {side = "nowhere", at = 9}}).dock.side, "right", "bad saved edges fall back")
end)

test("maximize fills the screen and restores the size and place it had", function()
    local ML = open()
    local frame = ML.UI.frame
    frame:SetSize(1000, 640)
    ML.UI:SaveWindow()
    ML.UI.maximize.scripts.OnClick()
    assert(ML.db.maximized and ML.UI.maximize.back.shown, "two squares when maximized")
    equal(frame:GetWidth(), 1920 - 16)
    equal(frame:GetHeight(), 1080 - 16)
    assert(not ML.UI.resizeGrip.shown, "no resizing a maximized window")
    ML.UI:SaveWindow()
    equal(ML.db.window.width, 1000, "the restore size is kept")
    local saved = ML.db
    ML = Mock.load(saved)
    SlashCmdList.MEDIALAB(""); Mock.flush()
    equal(ML.UI.frame:GetWidth(), 1904, "maximized survives a reload")
    ML.UI.maximize.scripts.OnClick()
    equal(ML.UI.frame:GetWidth(), 1000)
    equal(ML.UI.frame:GetHeight(), 640)
    assert(not ML.UI.maximize.back.shown and ML.UI.resizeGrip.shown)
    ML.UI:SetMaximized(true)
    SlashCmdList.MEDIALAB("reset")
    assert(not ML.db.maximized)
    equal(ML.UI.frame:GetWidth(), 1120)
end)

test("grid thumbnails zoom smoothly, per tab, and paging stays in range", function()
    local ML = open()
    ML.UI:SelectTab("texture")
    local browser, control = ML.UI.browser, ML.UI.zoomControl
    assert(control.shown, "grid tabs show the zoom control")
    equal(control.label.text:GetText(), "100%")
    local small = browser:PageSize()
    control.into.scripts.OnClick(control.into)
    assert(browser:PageSize() < small, "bigger thumbnails show fewer per page")
    equal(control.label.text:GetText(), "115%")
    -- Ctrl+wheel over the grid zooms; the wheel alone scrolls.
    Mock.ctrl = true
    browser.frame.scripts.OnMouseWheel(browser.frame, 1)
    Mock.ctrl = false
    equal(control.label.text:GetText(), "132%")
    for _ = 1, 40 do control.into.scripts.OnClick(control.into) end
    equal(control.label.text:GetText(), "400%", "stops at the largest")
    control.label.scripts.OnClick(control.label)
    equal(control.label.text:GetText(), "100%", "the percentage resets it")
    equal(ML.db.view.thumbScales.texture, nil, "100% is not saved")
    for _ = 1, 3 do control.out.scripts.OnClick(control.out) end
    ML.UI:SelectTab("icon")
    equal(control.label.text:GetText(), "100%", "each tab keeps its own zoom")
    ML.UI:SelectTab("sound")
    assert(not control.shown, "lists have no zoom")
    ML.UI:SelectTab("texture")
    browser:Page(1)
    local first = browser:Range()
    assert(first > 1)
    for _ = 1, 500 do browser:Page(1) end
    local _, last, count = browser:Range()
    equal(last, count)
    browser:Page(-1000)
    equal((browser:Range()), 1)
    local saved = ML.db
    ML = Mock.load(saved)
    SlashCmdList.MEDIALAB(""); Mock.flush()
    ML.UI:SelectTab("texture")
    equal(ML.UI.zoomControl.label.text:GetText(), "66%", "zoom survives a reload")
end)

test("icon metadata names, tags, describes and groups icons, merging paths into file IDs", function()
    local ML = open()
    assert(Mock.loaded.MediaLab_Icons)
    equal(MediaLabIconMeta, nil, "global released")
    local mark = find(ML, "icon", 134400)
    equal(mark.name, "inv_misc_questionmark")
    equal(mark.tags, "question mark, unknown, help")
    equal(mark.description, "A red question mark.")
    assert(mark.facetSet["Color: Red"] and mark.facetSet["Subject: Symbol"] and not mark.facetSet["Type: inv"])
    local sword = find(ML, "icon", 135274)
    assert(sword, "path entry became its file ID")
    equal(find(ML, "icon", "Interface\\Icons\\INV_Sword_04"), nil)
    assert(sword.facetSet["Item icons"])
    equal(#ML.Catalog:Filter("icon", nil, "longsword"), 0, "descriptions are display only")
    equal(ML.Catalog:Filter("icon", nil, "blade")[1], sword)
    equal(ML.Catalog:Filter("icon", "Color: Gray", "")[2] ~= nil, true)
    local facets = ML.Catalog:Facets("icon")
    local seen, last = {}, 0
    local order = {Subject = 1, Color = 2}
    for _, facet in ipairs(facets) do
        local rank = order[facet.name:match("^(%a+): ")] or 0
        assert(rank >= last, "grouped facets follow facetGroups: " .. facet.name)
        last = rank
    end
    ML.UI:SelectTab("icon")
    ML.UI:Select(mark)
    equal(ML.UI.inspector.subtitle:GetText(), "A red question mark.")
    local function labels()
        local shown = {}
        for _, field in ipairs(ML.UI.inspector.fields) do if field:IsShown() then shown[#shown + 1] = field.caption:GetText() end end
        return table.concat(shown, ",")
    end
    equal(labels(), "File ID,Tags", "players see the reference, not the code")
    ML.UI:SetDeveloper(true)
    equal(labels(), "File ID,Lua,Inline text,Tags")
end)

test("icons still index without the metadata addon", function()
    local ML = Mock.load()
    Mock.iconMeta = nil
    SlashCmdList.MEDIALAB("")
    Mock.flush()
    equal(find(ML, "icon", 134400).name, "File 134400")
end)

test("models index creature displays by family and skin, and preview in 3D", function()
    local ML = open()
    assert(Mock.loaded.MediaLab_Models)
    equal(MediaLabModels, nil, "global released")
    local blue = find(ML, "model", 1693)
    equal(blue.name, "murloc blue")
    equal(blue.model, 123456)
    equal(blue.tags, "murlocskinblue")
    assert(blue.facetSet.Creature and blue.facetSet["Family: Murloc"])
    equal(#ML.Catalog:Filter("model", "Family: Murloc", ""), 2)
    equal(ML.Catalog:Filter("model", nil, "murlocskingreen")[1], find(ML, "model", 1694))
    ML.UI:SelectTab("models")
    ML.UI:Select(blue)
    local preview = ML.UI.inspector.previews.model
    equal(preview.model.displayInfo, 1693)
    equal(preview.model.animationId, 0)
    local function labels()
        local shown = {}
        for _, field in ipairs(ML.UI.inspector.fields) do if field:IsShown() then shown[#shown + 1] = field.caption:GetText() end end
        return table.concat(shown, ",")
    end
    equal(labels(), "Display ID")
    ML.UI:SetDeveloper(true)
    equal(labels(), "Display ID,Lua,Model scene,Model file (no skin)")
    -- Animations skip what the model lacks (the mock has Stand, Walk, Death).
    preview:NextAnimation(); equal(preview.model.animationId, 4)
    preview:NextAnimation(); equal(preview.model.animationId, 1)
    preview:NextAnimation(); equal(preview.model.animationId, 0)
    -- Drag turns, the wheel zooms within limits, a new selection resets the view.
    Mock.cursorX = 100
    preview.model.scripts.OnMouseDown(preview.model)
    Mock.cursorX = 200
    preview.model.scripts.OnUpdate(preview.model)
    assert(preview.model.facing > 1, "dragging turns the model")
    preview.model.scripts.OnMouseUp(preview.model)
    for _ = 1, 40 do preview.model.scripts.OnMouseWheel(preview.model, -1) end
    equal(preview.model.camDistance, ML.ModelCamera.max)
    ML.UI:Select(find(ML, "model", 1694))
    equal(preview.model.facing, 0, "the next model faces forward")
    equal(preview.model.camDistance, ML.ModelCamera.max, "and keeps the camera distance")
    equal(ML.db.view.modelDistance, ML.ModelCamera.max)
    local reset
    for _, child in ipairs(Mock.frames) do
        if child.text and child.text.GetText and child.text:GetText() == "Reset" and child.scripts.OnClick then reset = child end
    end
    reset.scripts.OnClick(reset)
    equal(preview.model.camDistance, 1, "Reset goes back to the default distance")
    equal(ML.db.view.modelDistance, nil)
    local lua = ML.Export.Lua({blue}, "Mobs")
    assert(lua:find("models = {\n        1693, -- murloc blue", 1, true), lua)
end)

test("targeting an NPC names its display, which search and the Seen facet then find", function()
    local ML = open()
    SlashCmdList.MEDIALAB("target")
    Mock.flush()
    assert(Mock.messages[#Mock.messages]:find("Target an NPC first", 1, true))
    Mock.target = {name = "Rogue Pal", guid = "Player-1-0ABC", player = true}
    SlashCmdList.MEDIALAB("target")
    Mock.flush()
    assert(Mock.messages[#Mock.messages]:find("is a player", 1, true))
    Mock.target = {name = "Murloc Raider", guid = "Creature-0-1-2-3-515-0000ABCD", display = 1693, model = 123456}
    SlashCmdList.MEDIALAB("target")
    Mock.flush()
    equal(ML.db.npcs[515].name, "Murloc Raider")
    equal(ML.db.npcs[515].display, 1693)
    local blue = find(ML, "model", 1693)
    equal(ML.UI.tabId, "model")
    equal(ML.UI.inspector.entry, blue)
    equal(blue.description, "Seen as Murloc Raider")
    assert(blue.facetSet[ML.Sources.SEEN])
    equal(ML.Catalog:Filter("model", nil, "raider")[1], blue)
    assert(ML.UI.inspector.previews.model.note:GetText():find("Murloc Raider (creature 515) uses display 1693", 1, true))
    -- Saved, and applied again on the next session.
    local saved = ML.db
    ML = Mock.load(saved)
    SlashCmdList.MEDIALAB("")
    Mock.flush()
    equal(find(ML, "model", 1693).description, "Seen as Murloc Raider")
    -- Without a readable display, the model file narrows the skins.
    Mock.target = {name = "Murloc Oracle", guid = "Creature-0-1-2-3-517-0000ABCE", model = 123456}
    SlashCmdList.MEDIALAB("target")
    Mock.flush()
    equal(ML.UI.query, "123456")
    equal(#ML.UI.results, 2)
    assert(Mock.messages[#Mock.messages]:find("pick the matching skin", 1, true))
end)

test("csv copies the current results with one shape per kind, capped and escaped", function()
    local ML = open()
    ML.UI:SelectTab("sound")
    SlashCmdList.MEDIALAB("csv")
    local field = ML.CopyDialog.frame.field
    assert(field.value:find("^name,id,facets\n"), field.value)
    assert(field.value:find("IG_MAINMENU_OPEN,850,", 1, true))
    local entries = {}
    for index = 1, ML.Export.CSV_LIMIT + 5 do
        entries[index] = {kind = "sound", name = 'A,"B"' .. index, id = index, facets = {"UI"}}
    end
    local text, shown, total = ML.Export.Csv(entries)
    equal(shown, ML.Export.CSV_LIMIT); equal(total, ML.Export.CSV_LIMIT + 5)
    assert(text:find('\n"A,""B""1",1,UI\n', 1, true), text:sub(1, 80))
    local mixed = ML.Export.Csv({find(ML, "sound", "IG_MAINMENU_OPEN"), find(ML, "atlas", "test-glow")})
    equal(mixed, "kind,name,value,id\nsound,IG_MAINMENU_OPEN,IG_MAINMENU_OPEN,850\natlas,test-glow,test-glow,")
end)

test("players see every tab; developer mode adds code and Copy, and persists", function()
    local ML = open()
    local function shownTabs()
        local labels = {}
        for _, button in ipairs(ML.UI.tabButtons) do
            if button.shown then labels[#labels + 1] = button.tab.label end
        end
        return table.concat(labels, ",")
    end
    equal(shownTabs(), "Icons,Textures,Atlases,Models,Sounds,Controls,Fonts,Lists", "Fonts is for everyone")
    assert(ML.UI:SelectTab("font"))
    assert(not ML.UI.copyButton.shown, "no Copy button for players")
    SlashCmdList.MEDIALAB("dev")
    assert(Mock.messages[#Mock.messages]:find("Developer mode on", 1, true))
    equal(shownTabs(), "Icons,Textures,Atlases,Models,Sounds,Controls,Fonts,Lists", "the same tabs")
    assert(ML.UI.copyButton.shown and ML.UI.devButton.active, "Copy and an active Dev button")
    local saved = ML.db
    ML = Mock.load(saved)
    SlashCmdList.MEDIALAB("")
    Mock.flush()
    equal(ML.UI.tabId, "font", "the tab survives a reload")
    assert(ML.db.developer and ML.UI.copyButton.shown, "and so does developer mode")
    ML.UI:SetDeveloper(false)
    equal(ML.UI.tabId, "font", "leaving developer mode keeps you where you are")
    assert(not ML.UI.copyButton.shown)
end)

test("atlases have their own tab, and Find a filter narrows a long filter list", function()
    local ML = open()
    local atlases
    for _, button in ipairs(ML.UI.tabButtons) do if button.tab.id == "atlas" then atlases = button end end
    assert(atlases and atlases.shown, "an Atlases tab, like every other kind")
    atlases.scripts.OnClick(atlases)
    equal(ML.UI.tabId, "atlas")
    for _, button in ipairs(ML.UI.viewButtons) do assert(not button.shown, "no Files / Atlases switch") end
    SlashCmdList.MEDIALAB("tab atlases")
    equal(ML.UI.tabId, "atlas")
    -- Find a filter, on the sound folders.
    ML.UI:SelectTab("sound")
    local function shown()
        local rows = {}
        for _, item in ipairs(ML.UI.facetButtons) do if item.shown then rows[#rows + 1] = item.name:GetText() end end
        return table.concat(rows, ",")
    end
    local all = shown()
    ML.UI.facetFind.box:Type("murl")
    equal(shown(), "All,FOLDER,Murloc", "only matching filters, under their heading")
    ML.UI:SelectTab("texture")
    equal(ML.UI.facetFind.box:GetText(), "", "a new tab starts unfiltered")
    -- The size range sits at the top, above the list.
    assert(ML.UI.sizeRange.frame.points.TOPLEFT, "the size range is anchored to the top")
    local _, _, _, _, listTop = ML.UI.facetList:GetPoint()
    assert(listTop < -48, "the filter list starts below it")
    assert(#all > 0)
end)

test("the welcome card shows once, and ? shows tips for the tab", function()
    local ML = open()
    local card = ML.HelpPanel.frame
    assert(card.shown, "welcome on first open")
    equal(card.blocks[1].heading:GetText(), ML.Help.welcome.title)
    assert(card.blocks[3].body:GetText():find(ML.Help.developer.hint, 1, true), "players get the hint")
    card.dismiss.scripts.OnClick(card.dismiss)
    assert(not card.shown and ML.db.welcomed)
    ML = Mock.load(ML.db)
    SlashCmdList.MEDIALAB("")
    Mock.flush()
    assert(not ML.HelpPanel.frame.shown, "not again after Got it")
    ML.UI:SelectTab("atlas")
    ML.UI.helpButton.scripts.OnClick(ML.UI.helpButton)
    local blocks = ML.HelpPanel.frame.blocks
    equal(blocks[2].heading:GetText(), "Atlases")
    assert(blocks[2].body:GetText():find(ML.Help.tabs.atlas[1], 1, true), "tips of the tab")
    ML.UI:SetDeveloper(true)
    assert(blocks[3].body:GetText():find(ML.Help.developer.lines[1], 1, true), "developer tips when on")
end)

test("both side columns widen by dragging their inner edge, within bounds, and remember it", function()
    local ML = open()
    local inspector, filters = ML.UI.inspector.frame, ML.UI.facetColumn
    local preview, edge = ML.UI.splitters.inspector, ML.UI.splitters.facets
    equal(inspector:GetWidth(), 330)
    equal(filters:GetWidth(), 190)
    Mock.cursorX = 800
    preview.scripts.OnMouseDown(preview)
    Mock.cursorX = 600
    preview.scripts.OnUpdate(preview)
    equal(inspector:GetWidth(), 530, "dragging the preview's left edge left widens it")
    Mock.cursorX = -5000
    preview.scripts.OnUpdate(preview)
    equal(inspector:GetWidth(), ML.UI:ColumnMax("inspector"), "never crowds out the results")
    Mock.cursorX = 700
    preview.scripts.OnUpdate(preview)
    preview.scripts.OnMouseUp(preview)
    equal(ML.db.view.inspectorWidth, 430)
    Mock.cursorX = 100
    edge.scripts.OnMouseDown(edge)
    Mock.cursorX = 160
    edge.scripts.OnUpdate(edge)
    edge.scripts.OnMouseUp(edge)
    equal(filters:GetWidth(), 250, "dragging the filters' right edge right widens them")
    equal(ML.UI.listActions.rename:GetWidth(), math.floor((250 - 16) / 3), "list buttons share the width")
    local room = ML.UI.frame:GetWidth() - 44 - filters:GetWidth() - inspector:GetWidth()
    assert(room >= 300, "the results keep their minimum")
    ML = Mock.load(ML.db)
    SlashCmdList.MEDIALAB("")
    Mock.flush()
    equal(ML.UI.inspector.frame:GetWidth(), 430, "widths survive a reload")
    equal(ML.UI.facetColumn:GetWidth(), 250)
    for _, name in ipairs({"inspector", "facets"}) do
        local handle = ML.UI.splitters[name]
        handle.scripts.OnDoubleClick(handle)
    end
    equal(ML.UI.inspector.frame:GetWidth(), 330)
    equal(ML.UI.facetColumn:GetWidth(), 190)
    equal(ML.db.view.inspectorWidth, nil, "defaults are not saved")
    equal(ML.db.view.facetWidth, nil)
end)

test("the Lists tab counts lists, then entries across them", function()
    local ML = open()
    local function badge()
        for _, button in ipairs(ML.UI.tabButtons) do
            if button.tab.id == ML.ListsTab then return button.text:GetText() end
        end
    end
    equal(badge(), "Lists  1:0", "Favorites is always a list")
    local keys = {}
    for _, ref in ipairs({{"icon", 134400}, {"sound", "IG_MAINMENU_OPEN"}, {"atlas", "test-glow"}, {"model", 1693}}) do
        local entry = find(ML, ref[1], ref[2])
        ML.UI:ToggleFavorite(entry)
        keys[#keys + 1] = entry.key
    end
    equal(badge(), "Lists  1:4")
    local list = ML.Lists:Create("Same four")
    for _, key in ipairs(keys) do ML.Lists:Set(list, key, true) end
    ML.UI:RefreshSaved()
    equal(badge(), "Lists  2:8", "an entry counts once per list")
end)

test("grouped filters show bare names under a heading", function()
    local ML = open()
    ML.UI:SelectTab("model")
    local rows = {}
    for _, item in ipairs(ML.UI.facetButtons) do
        if item.shown then rows[#rows + 1] = {text = item.name:GetText(), facet = item.facet, heading = item.mouse == false} end
    end
    local heading, murloc
    for index, row in ipairs(rows) do
        if row.text == "FAMILY" then heading = index end
        if row.text == "Murloc" then murloc = row end
    end
    assert(heading and rows[heading].heading, "a FAMILY heading that cannot be clicked")
    assert(murloc and murloc.facet == "Family: Murloc", "Murloc filters by its family")
    for _, row in ipairs(rows) do assert(not row.text:find("Family:", 1, true), row.text) end
    local blue = find(ML, "model", 1693)
    equal(ML.Catalog.FacetLabels(blue.facets), "Creature, Murloc")
    local murlocButton
    for _, item in ipairs(ML.UI.facetButtons) do if item.facet == "Family: Murloc" then murlocButton = item end end
    equal(murlocButton.tip, "Murloc", "hovering shows the full name")
end)

print(string.format("%d integration tests passed (mocked WoW APIs; in-game rendering needs a client smoke test).", passed))
