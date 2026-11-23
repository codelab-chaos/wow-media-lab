local _, ML = ...

-- The "which lists is this in" popup, opened from the inspector. One row per
-- list with a check when the entry is in it (click to add or remove), then a
-- row that makes a new list with the entry in it. Rows are made on demand and
-- reused. onChanged() runs after every change.
local W = ML.Widgets
local T = W.theme
local Menu = {}
ML.ListMenu = Menu

local ROW, WIDTH = 22, 200
local CHECK = [[Interface\Buttons\UI-CheckBox-Check]]

local function create(parent)
    local frame = W.Panel(parent, T.window)
    frame:SetWidth(WIDTH)
    frame:SetFrameLevel(parent:GetFrameLevel() + 40)
    frame:EnableMouse(true)
    frame.rows = {}
    return frame
end

local function row(index)
    local frame = Menu.frame
    local item = frame.rows[index]
    if item then return item end
    item = CreateFrame("Button", nil, frame)
    item:SetHeight(ROW)
    item:SetPoint("TOPLEFT", 4, -4 - (index - 1) * ROW)
    item:SetPoint("TOPRIGHT", -4, -4 - (index - 1) * ROW)
    item.check = item:CreateTexture(nil, "ARTWORK")
    item.check:SetSize(16, 16)
    item.check:SetPoint("LEFT", 4, 0)
    item.check:SetTexture(CHECK)
    item.name = W.Label(item, "", 11)
    item.name:SetPoint("LEFT", 24, 0)
    item.name:SetPoint("RIGHT", -6, 0)
    item:SetHighlightTexture(W.WHITE)
    item:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.06)
    item:SetScript("OnClick", function(button) button.action() end)
    frame.rows[index] = item
    return item
end

function Menu.Render()
    local frame, entry = Menu.frame, Menu.entry
    local lists = ML.Lists:All()
    for index, list in ipairs(lists) do
        local item = row(index)
        local member = ML.Lists:Has(list, entry.key)
        item.check:SetShown(member)
        item.name:SetText(list.name)
        item.name:SetTextColor(unpack(member and T.accent or T.text))
        item.action = function()
            ML.Lists:Toggle(list, entry.key)
            Menu.Render()
            Menu.onChanged()
        end
        item:Show()
    end
    local new = row(#lists + 1)
    new.check:Hide()
    new.name:SetText("+ New list...")
    new.name:SetTextColor(unpack(T.muted))
    new.action = function()
        frame:Hide()
        ML.Prompt.Show(Menu.parent, {title = "New list", button = "Create", hint = "It will hold " .. entry.name .. ".",
            onAccept = function(name)
                local list, problem = ML.Lists:Create(name)
                if not list then return problem end
                ML.Lists:Set(list, entry.key, true)
                Menu.onChanged()
            end})
    end
    new:Show()
    for index = #lists + 2, #frame.rows do frame.rows[index]:Hide() end
    frame:SetHeight(8 + (#lists + 1) * ROW)
end

function Menu.Hide()
    if Menu.frame then Menu.frame:Hide() end
end

-- Opens under anchor for entry; a second call for the same anchor closes it.
function Menu.Toggle(parent, anchor, entry, onChanged)
    Menu.frame = Menu.frame or create(parent)
    local frame = Menu.frame
    if frame:IsShown() and Menu.anchor == anchor and Menu.entry == entry then return frame:Hide() end
    Menu.parent, Menu.anchor, Menu.entry, Menu.onChanged = parent, anchor, entry, onChanged
    frame:ClearAllPoints()
    frame:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -4)
    Menu.Render()
    frame:Show()
    return frame
end
