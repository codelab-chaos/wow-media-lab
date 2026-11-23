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
    equal(#Mock.messages, 5)
    SlashCmdList.MEDIALAB("bogus")
    equal(#Mock.messages, 6)
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
    preview.channel.scripts.OnClick()
    equal(ML.db.view.channel, "SFX")
    assert(ML.UI.inspector.fields[3].box:GetText():find('"SFX"', 1, true), "snippet follows channel")
    preview.play.scripts.OnClick()
    equal(Mock.stopped[1], 1, "previous sound stopped first")
    preview.auto.scripts.OnClick()
    ML.UI:Select(find(ML, "sound", "IG_MAINMENU_CLOSE"))
    equal(Mock.sounds[#Mock.sounds].id, 851)
    local before = #Mock.sounds
    ML.UI.browser.handlers.onPlay(entry)
    equal(#Mock.sounds, before + 1, "row Play plays once even with auto-play on")
    assert(not preview:Play({id = 404, name = "Silent"}))
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

test("built controls open at actual size, zoom, fit and pan, and reset per template", function()
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
    equal(preview:CurrentZoom(), 1, "view resets when the template changes")
    equal(preview.panX, 0)
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

test("image preview zooms within limits, pans, and resets per image", function()
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
    assert(not image.zoom and image.panX == 0, "new image starts fitted")
    ML.UI:SelectTab("texture")
    ML.UI:Select(ML.UI.results[1])
    assert(image.note:GetText():find("assumes 256 x 256", 1, true))
    image.canvasButton.scripts.OnClick()
    equal(ML.db.view.canvas, "Checker")
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

test("minimize keeps the title bar, restore and reset bring the body back", function()
    local ML = open()
    local frame = ML.UI.frame
    frame:SetSize(1000, 640)
    ML.UI:SaveWindow()
    local top = frame:GetTop()
    ML.UI.minimize.scripts.OnClick()
    assert(ML.db.minimized and not ML.UI.body.shown)
    equal(frame:GetHeight(), 30)
    equal(frame:GetTop(), top, "title bar stays put")
    ML.UI:SaveWindow()
    ML.UI.minimize.scripts.OnClick()
    equal(frame:GetHeight(), 640, "height restored")
    assert(ML.UI.body.shown)
    ML.UI:SetMinimized(true)
    local saved = ML.db
    ML = Mock.load(saved)
    SlashCmdList.MEDIALAB(""); Mock.flush()
    assert(not ML.UI.body.shown, "minimized state survives reload")
    SlashCmdList.MEDIALAB("reset")
    assert(ML.UI.body.shown)
    equal(ML.UI.frame:GetWidth(), 1120)
end)

test("grid thumbnails zoom and paging stays in range", function()
    local ML = open()
    ML.UI:SelectTab("texture")
    local browser = ML.UI.browser
    local small = browser:PageSize()
    ML.UI.thumbButton.scripts.OnClick()
    assert(browser:PageSize() < small, "bigger thumbnails show fewer per page")
    browser:Page(1)
    local first = browser:Range()
    assert(first > 1)
    for _ = 1, 500 do browser:Page(1) end
    local _, last, count = browser:Range()
    equal(last, count)
    browser:Page(-1000)
    equal((browser:Range()), 1)
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
    equal(preview.model.facing, 0)
    equal(preview.model.camDistance, 1)
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

test("players see media first; developer mode adds code, Fonts and Copy, and persists", function()
    local ML = open()
    local function shownTabs()
        local labels = {}
        for _, button in ipairs(ML.UI.tabButtons) do
            if button.shown then labels[#labels + 1] = button.tab.label end
        end
        return table.concat(labels, ",")
    end
    equal(shownTabs(), "Icons,Textures,Models,Sounds,Controls,Lists")
    assert(not ML.UI:SelectTab("font"), "Fonts needs developer mode")
    assert(not ML.UI.copyButton.shown, "no Copy button for players")
    SlashCmdList.MEDIALAB("dev")
    assert(Mock.messages[#Mock.messages]:find("Developer mode on", 1, true))
    equal(shownTabs(), "Icons,Textures,Models,Sounds,Controls,Fonts,Lists")
    assert(ML.UI.copyButton.shown and ML.UI.devButton.active, "Copy and an active Dev button")
    assert(ML.UI:SelectTab("font"))
    local saved = ML.db
    ML = Mock.load(saved)
    SlashCmdList.MEDIALAB("")
    Mock.flush()
    equal(ML.UI.tabId, "font", "developer mode and the tab survive a reload")
    ML.UI:SetDeveloper(false)
    equal(ML.UI.tabId, "icon", "leaving developer mode leaves its tab")
end)

test("atlases live in the Textures tab, behind a Files and Atlases switch", function()
    local ML = open()
    local textures
    for _, button in ipairs(ML.UI.tabButtons) do if button.tab.id == "texture" then textures = button end end
    local C = ML.Catalog
    assert(textures.text:GetText():find(tostring(C:TabCount("texture") + C:TabCount("atlas")), 1, true), "counts both")
    ML.UI:SelectTab("icon")
    for _, button in ipairs(ML.UI.viewButtons) do assert(not button.shown, "no switch outside Textures") end
    textures.scripts.OnClick(textures)
    equal(ML.UI.tabId, "texture")
    local atlases = ML.UI.viewButtons[2]
    equal(atlases.text:GetText(), "Atlases")
    atlases.scripts.OnClick(atlases)
    equal(ML.UI.tabId, "atlas")
    assert(textures.active and atlases.active, "the Textures tab stays lit on its Atlases view")
    ML.UI:SelectTab("sound")
    textures.scripts.OnClick(textures)
    equal(ML.UI.tabId, "atlas", "the tab remembers its view")
    SlashCmdList.MEDIALAB("tab atlases")
    equal(ML.UI.tabId, "atlas")
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
    equal(blocks[2].heading:GetText(), "Textures")
    assert(blocks[2].body:GetText():find(ML.Help.tabs.texture[1], 1, true), "tips of the whole tab")
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
