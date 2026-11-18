local addonName, ML = ...
ML.name = addonName

function ML.Print(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cff9ec7e8MediaLab|r  " .. tostring(message))
end

local function tableOr(value) return type(value) == "table" and value or {} end

-- Saved variables are sanitized once here; every other module trusts ML.db.
function ML.Initialize(saved)
    saved = tableOr(saved)
    saved.favorites = tableOr(saved.favorites)
    saved.view = tableOr(saved.view)
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
        ML.Print("/mlab tab <icons|textures|atlases|sounds|controls|fonts|favorites> jumps to a tab.")
        ML.Print("/mlab reset restores the window's size and position.")
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
