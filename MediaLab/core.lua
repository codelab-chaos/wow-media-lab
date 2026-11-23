local addonName, ML = ...
ML.name = addonName

ML.TITLE = "WoW Media Lab"
ML.ICON = [[Interface\Icons\trade_alchemy]] -- the lab's beaker
ML.SITE = "github.com/codelab-chaos/wow-media-lab"

function ML.Print(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cff9ec7e8Media Lab|r  " .. tostring(message))
end

local function tableOr(value) return type(value) == "table" and value or {} end

local function ids(list, key)
    local set = {}
    for _, item in ipairs(list) do set[key and item[key] or item] = true end
    return set
end

-- Every view setting, the type it must have, and for some the values it may
-- take. Anything else (a hand edit, another version's file) is dropped, so
-- the default applies. Settings not listed here are left alone. Built when
-- first needed: the allowed values come from kinds.lua, which loads later.
local function viewRules() return {
    tab = {type = "string"}, thumb = {type = "number"}, sample = {type = "string"},
    autoplay = {type = "boolean"}, modelAnimation = {type = "number"},
    inspectorWidth = {type = "number"}, facetWidth = {type = "number"},
    canvas = {type = "string", values = ids(ML.Canvases, "id")},
    channel = {type = "string", values = ids(ML.SoundChannels)},
    copyFormat = {type = "string", values = ids(ML.CopyFormats, "id")},
    facets = {type = "table", strings = true}, views = {type = "table", strings = true},
} end
local ANCHORS = ids({"TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT"})

local function cleanView(view)
    for key, rule in pairs(viewRules()) do
        local value = view[key]
        if value ~= nil and (type(value) ~= rule.type or (rule.values and not rule.values[value])) then
            view[key] = nil
        elseif rule.strings and value then
            for name, item in pairs(value) do
                if type(name) ~= "string" or type(item) ~= "string" then value[name] = nil end
            end
        end
    end
    if type(view.thumb) == "number" and not ML.ThumbScales[view.thumb] then view.thumb = nil end
    return view
end

-- The window's restore place: numbers and real anchor names, or none at all.
local function cleanWindow(window)
    if type(window) ~= "table" then return nil end
    if window.point ~= nil and not (ANCHORS[window.point] and ANCHORS[window.relativePoint]) then return nil end
    for _, key in ipairs({"x", "y", "width", "height"}) do
        if window[key] ~= nil and type(window[key]) ~= "number" then window[key] = nil end
    end
    return window
end

-- Saved variables are sanitized once here; every other module trusts ML.db.
function ML.Initialize(saved)
    saved = tableOr(saved)
    saved.view = tableOr(saved.view)
    if saved.view.tab == "favorites" then saved.view.tab = ML.ListsTab end -- Favorites became Lists
    if type(saved.view.facets) == "table" then saved.view.facets.favorites = nil end
    cleanView(saved.view)
    ML.Lists.Sanitize(saved)
    ML.Npcs.Sanitize(saved)
    saved.window = cleanWindow(saved.window)
    saved.minimized = saved.minimized == true or nil -- docked as an icon at a screen edge
    saved.maximized = saved.maximized == true or nil -- filling the screen
    ML.Dock.Sanitize(saved)
    saved.developer = saved.developer == true or nil -- code fields, Fonts and Copy
    saved.welcomed = saved.welcomed == true or nil   -- the welcome card was dismissed
    ML.db = saved
    return saved
end

function ML.Toggle()
    if ML.db then ML.UI:Toggle() end
end

function MediaLab_OnAddonCompartmentClick()
    ML.Toggle()
end

local commands = {
    [""] = function() ML.Toggle() end,
    help = function()
        ML.Print("/mlab opens the lab. /mlab search <words> searches the current tab.")
        ML.Print("/mlab tab <icons|textures|atlases|models|sounds|controls|lists> jumps to a tab.")
        ML.Print("/mlab target finds your target's model and remembers the NPC's name.")
        ML.Print("/mlab reset restores the window's size and position. /mlab dock <left|right|top|bottom> picks where it minimizes to.")
        ML.Print("/mlab dev turns developer mode on or off: code to copy, the Fonts tab, /mlab copy and /mlab csv.")
        ML.Print("Ideas or bugs? " .. ML.SITE .. "/issues")
    end,
    dev = function()
        ML.UI:Show()
        ML.UI:SetDeveloper(not ML.db.developer)
        ML.Print(ML.db.developer and "Developer mode on: code fields, the Fonts tab and Copy."
            or "Developer mode off.")
    end,
    copy = function()
        ML.UI:Show()
        ML.UI:CopyResults("lua")
    end,
    csv = function()
        ML.UI:Show()
        ML.UI:CopyResults("csv")
    end,
    target = function()
        ML.UI:Show()
        ML.UI:FromTarget()
    end,
    reset = function()
        ML.db.window, ML.db.minimized, ML.db.maximized = nil, nil, nil
        ML.UI:ResetWindow()
    end,
    dock = function(argument)
        if not ML.Dock.SetSide(argument:lower()) then
            return ML.Print("/mlab dock left, right, top or bottom: where the minimized lab sits.")
        end
        ML.Print("When minimized, the lab docks to the " .. argument:lower() .. " edge.")
    end,
    search = function(argument)
        ML.UI:Show()
        ML.UI:Search(argument)
    end,
    tab = function(argument)
        ML.UI:Show()
        if ML.UI:SelectTabByName(argument) then return end
        local wanted = argument:lower()
        for _, button in ipairs(ML.TabBar) do
            if button.developer and (button.id == wanted or button.label:lower() == wanted) then
                return ML.Print(button.label .. " is part of developer mode: /mlab dev turns it on.")
            end
        end
        ML.Print("Unknown tab: " .. argument)
    end,
}

function ML.HandleSlash(message)
    local command, argument = tostring(message or ""):match("^%s*(%S*)%s*(.-)%s*$")
    local handler = commands[command:lower()]
    if handler then handler(argument) else ML.Print("Unknown command. Try /mlab help.") end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(self, _, name)
    if name ~= addonName then return end
    self:UnregisterEvent("ADDON_LOADED")
    MediaLabDB = ML.Initialize(MediaLabDB)
    if ML.db.minimized then ML.Dock.Show(function() ML.UI:Show() end) end
    SLASH_MEDIALAB1 = "/mlab"
    SLASH_MEDIALAB2 = "/medialab"
    SlashCmdList.MEDIALAB = ML.HandleSlash
end)
