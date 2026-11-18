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
    equal(#Mock.messages, 3)
    SlashCmdList.MEDIALAB("bogus")
    equal(#Mock.messages, 4)
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

test("favorites persist across reload and mix kinds", function()
    local ML = open()
    local sound = find(ML, "sound", "IG_MAINMENU_OPEN")
    local atlas = find(ML, "atlas", "test-glow")
    ML.UI:ToggleFavorite(sound)
    ML.UI:ToggleFavorite(atlas)
    local saved = ML.db
    ML = Mock.load(saved)
    SlashCmdList.MEDIALAB("tab favorites"); Mock.flush()
    equal(ML.UI.tabId, "favorites")
    equal(#ML.UI.results, 2)
    ML.UI:SetFacet("Sounds")
    equal(#ML.UI.results, 1)
    ML.UI:ToggleFavorite(ML.UI.results[1])
    equal(#ML.UI.results, 0)
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

print(string.format("%d integration tests passed (mocked WoW APIs; in-game rendering needs a client smoke test).", passed))
