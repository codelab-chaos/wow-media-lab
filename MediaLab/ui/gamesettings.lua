local _, ML = ...

-- The lab's entry in the game's own Options > AddOns list, like other addons:
-- a short page with a button that opens the lab's Options card. Registered
-- when the client has the Settings API; skipped quietly otherwise.
local W = ML.Widgets
local T = W.theme
local GameSettings = {}
ML.GameSettings = GameSettings

-- Leaves the game's options and shows the lab with its Options card.
function GameSettings.OpenLabOptions()
    if SettingsPanel and SettingsPanel:IsShown() and HideUIPanel then HideUIPanel(SettingsPanel) end
    ML.UI:Show()
    ML.UI:ShowOptions()
end

function GameSettings.Register()
    if GameSettings.category or not (Settings and Settings.RegisterCanvasLayoutCategory) then return end
    local frame = CreateFrame("Frame")
    frame.title = W.Label(frame, ML.TITLE, 16, T.accent)
    frame.title:SetPoint("TOPLEFT", 16, -16)
    frame.text = W.Label(frame, "Choose what loads when the lab opens, in the lab's own Options.", 12, T.text)
    frame.text:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -10)
    frame.open = W.Button(frame, "Open Media Lab options", 180, GameSettings.OpenLabOptions, 24)
    frame.open:SetPoint("TOPLEFT", frame.text, "BOTTOMLEFT", 0, -14)
    frame.commands = W.Label(frame, "Or type /mlab options. /mlab opens the lab.", 11, T.muted)
    frame.commands:SetPoint("TOPLEFT", frame.open, "BOTTOMLEFT", 0, -10)
    local category = Settings.RegisterCanvasLayoutCategory(frame, ML.TITLE)
    Settings.RegisterAddOnCategory(category)
    GameSettings.frame, GameSettings.category = frame, category
    return category
end
