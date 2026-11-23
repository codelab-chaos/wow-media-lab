local _, ML = ...

-- The help card: the welcome on first open, then the tips for the tab you are
-- on, and what developer mode adds. Shows ML.Help (help.lua); owns no text.
local W = ML.Widgets
local T = W.theme
local Help = {}
ML.HelpPanel = Help

local WIDTH, PAD = 460, 16

local function bullets(lines)
    local out = {}
    for _, line in ipairs(lines) do out[#out + 1] = "-  " .. line end
    return table.concat(out, "\n")
end

-- The card's sections for a tab, as {heading, text} pairs.
function Help.Sections(tabId, developer)
    local help = ML.Help
    local tab = ML.TabButtonOf(tabId)
    local sections = {{help.welcome.title, bullets(help.welcome.lines)}}
    local tips = {}
    for _, kind in ipairs(tab and tab.kinds or {tabId}) do
        for _, line in ipairs(help.tabs[kind] or {}) do tips[#tips + 1] = line end
    end
    if #tips > 0 then sections[#sections + 1] = {tab and tab.label or tabId, bullets(tips)} end
    sections[#sections + 1] = {help.developer.title .. (developer and " (on)" or ""),
        bullets(developer and help.developer.lines or {help.developer.hint})}
    sections[#sections + 1] = {help.feedback.title, table.concat(help.feedback.lines, "\n")}
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

function Help.Render(tabId, developer)
    local frame = Help.frame
    local y = PAD
    for index, section in ipairs(Help.Sections(tabId, developer)) do
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
    for index = #Help.Sections(tabId, developer) + 1, #frame.blocks do
        frame.blocks[index].heading:Hide()
        frame.blocks[index].body:Hide()
    end
    frame:SetHeight(y + 22 + PAD)
end

function Help.Show(tabId, developer)
    Help.Render(tabId, developer)
    Help.frame:Show()
end

function Help.Hide()
    if Help.frame then Help.frame:Hide() end
end

function Help.IsShown()
    return Help.frame and Help.frame:IsShown() or false
end
