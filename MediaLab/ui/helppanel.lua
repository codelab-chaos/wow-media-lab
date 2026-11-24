local _, ML = ...

-- The help card, in two modes. "info" (the i button, and the welcome on
-- first open): the welcome, developer mode and feedback. "help" (the ?
-- button): the tab's tips and the switches it has, then Options and the
-- switches found everywhere. Shows ML.Help (help/); owns no text.
local W = ML.Widgets
local T = W.theme
local Help = {}
ML.HelpPanel = Help

local WIDTH, PAD = 520, 16

local function bullets(lines)
    local out = {}
    for _, line in ipairs(lines) do out[#out + 1] = "-  " .. line end
    return table.concat(out, "\n")
end

-- A switch group's items as "Name: what it does" lines.
local function switchLines(group)
    local lines = {}
    for _, item in ipairs(group.items) do lines[#lines + 1] = item[1] .. ":  " .. item[2] end
    return bullets(lines)
end

-- The card's sections, as {heading, text} pairs.
function Help.Sections(mode, tabId, developer)
    local help = ML.Help
    if mode == "info" then
        local version = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata("MediaLab", "Version")
        return {
            {help.welcome.title, bullets(help.welcome.lines)},
            {help.developer.title .. (developer and " (on)" or ""),
                bullets(developer and help.developer.lines or {help.developer.hint})},
            {help.feedback.title, table.concat(help.feedback.lines, "\n")
                .. (version and ("\n\n" .. ML.TITLE .. " " .. version) or "")},
        }
    end
    local tab = ML.TabButtonOf(tabId)
    local sections, tips, groups = {}, {}, {}
    for _, kind in ipairs(tab and tab.kinds or {tabId}) do
        for _, line in ipairs(help.tabs[kind] or {}) do tips[#tips + 1] = line end
        for _, group in ipairs(help.switchesFor[kind] or {}) do groups[#groups + 1] = group end
    end
    if #tips > 0 then sections[#sections + 1] = {tab and tab.label or tabId, bullets(tips)} end
    for _, group in ipairs(help.always) do groups[#groups + 1] = group end
    for _, id in ipairs(groups) do
        local group = help.switches[id]
        sections[#sections + 1] = {group.title, switchLines(group)}
    end
    return sections
end

function Help.Create(parent, onDismiss)
    local frame = W.Panel(parent, T.window)
    frame:SetFrameStrata("DIALOG")
    frame:SetWidth(WIDTH)
    frame:SetPoint("CENTER")
    frame:EnableMouse(true)
    frame.blocks = {}
    frame.dismiss = W.Button(frame, "Got it", 72, onDismiss, 22)
    frame.dismiss:SetPoint("BOTTOMRIGHT", -PAD, PAD)
    frame:Hide()
    Help.frame = frame
    return frame
end

function Help.Render(mode, tabId, developer)
    local frame = Help.frame
    frame.mode = mode
    local y = PAD
    local sections = Help.Sections(mode, tabId, developer)
    for index, section in ipairs(sections) do
        local block = frame.blocks[index]
        if not block then
            block = {heading = W.Label(frame, "", 13, T.accent), body = W.Label(frame, "", 11, T.text)}
            block.body:SetWordWrap(true)
            block.body:SetWidth(WIDTH - PAD * 2)
            frame.blocks[index] = block
        end
        block.heading:SetText(section[1])
        block.heading:SetPoint("TOPLEFT", PAD, -y)
        block.body:SetText(section[2])
        block.body:SetPoint("TOPLEFT", PAD, -(y + 20))
        block.heading:Show()
        block.body:Show()
        y = y + 20 + math.max(14, block.body:GetStringHeight() or 14) + 14
    end
    for index = #sections + 1, #frame.blocks do
        frame.blocks[index].heading:Hide()
        frame.blocks[index].body:Hide()
    end
    frame:SetHeight(y + 22 + PAD)
end

function Help.Show(mode, tabId, developer)
    Help.Render(mode, tabId, developer)
    Help.frame:Show()
end

function Help.Hide()
    if Help.frame then Help.frame:Hide() end
end

-- Whether the card is up, in this mode when one is given.
function Help.IsShown(mode)
    local shown = Help.frame and Help.frame:IsShown() or false
    return shown and (mode == nil or Help.frame.mode == mode)
end
