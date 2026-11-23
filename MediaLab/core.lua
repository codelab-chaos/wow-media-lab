local addonName, ML = ...
ML.name = addonName

function ML.Print(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cff9ec7e8MediaLab|r  " .. tostring(message))
end

local function tableOr(value) return type(value) == "table" and value or {} end

-- Saved variables are sanitized once here; every other module trusts ML.db.
function ML.Initialize(saved)
    saved = tableOr(saved)
    saved.view = tableOr(saved.view)
    if saved.view.tab == "favorites" then saved.view.tab = ML.ListsTab end -- Favorites became Lists
    if type(saved.view.facets) == "table" then saved.view.facets.favorites = nil end
    ML.Lists.Sanitize(saved)
    ML.Npcs.Sanitize(saved)
    if type(saved.window) ~= "table" then saved.window = nil end
    saved.minimized = saved.minimized == true or nil
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
        ML.Print("/mlab tab <icons|textures|atlases|sounds|controls|fonts|models|lists> jumps to a tab.")
        ML.Print("/mlab target finds your target's model and remembers the NPC's name.")
        ML.Print("/mlab reset restores the window's size and position.")
        ML.Print("/mlab copy copies the current results as Lua, /mlab csv as CSV. /mlab export saves the whole catalog for scripts/import-export.py.")
    end,
    copy = function()
        ML.UI:Show()
        ML.UI:CopyResults("lua")
    end,
    csv = function()
        ML.UI:Show()
        ML.UI:CopyResults("csv")
    end,
    export = function()
        ML.UI:Show()
        local ok, result = ML.Export.Save()
        if not ok then return ML.Print(result) end
        ML.Print(string.format("Exported %d entries. Type /reload to write them to disk, then run scripts/import-export.py.", result))
    end,
    target = function()
        ML.UI:Show()
        ML.UI:FromTarget()
    end,
    reset = function()
        ML.db.window, ML.db.minimized = nil, nil
        ML.UI:ResetWindow()
    end,
    search = function(argument)
        ML.UI:Show()
        ML.UI:Search(argument)
    end,
    tab = function(argument)
        ML.UI:Show()
        if not ML.UI:SelectTabByName(argument) then ML.Print("Unknown tab: " .. argument) end
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
    SLASH_MEDIALAB1 = "/mlab"
    SLASH_MEDIALAB2 = "/medialab"
    SlashCmdList.MEDIALAB = ML.HandleSlash
end)
