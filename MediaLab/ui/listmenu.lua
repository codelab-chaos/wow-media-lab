local _, ML = ...

-- The lists menu, from a right-click in the results or Add to list in the
-- inspector. It acts on one entry or a whole selection:
--   Favorite, then every other list (a check when all the entries are in it,
--   a dash when some are; a click adds them all, or removes them all when all
--   are in), then + New list... (made with the entries in it) and Manage lists.
-- Rows are made on demand and reused. onChanged() runs after every change.
local W = ML.Widgets
local T = W.theme
local Menu = {}
ML.ListMenu = Menu

local ROW, WIDTH = 22, 220
local CHECK = [[Interface\Buttons\UI-CheckBox-Check]]
local STAR = "auctionhouse-icon-favorite"

-- The star atlas when this client has it, else a plain * (Favorites stays recognizable).
local function hasStar()
    local ok, info = pcall(C_Texture and C_Texture.GetAtlasInfo or error, STAR)
    return ok and info ~= nil
end

local function create(parent)
    local frame = W.Panel(parent, T.window)
    frame:SetWidth(WIDTH)
    frame:SetFrameStrata("DIALOG")
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame.rows = {}
    frame.divider = frame:CreateTexture(nil, "ARTWORK")
    frame.divider:SetHeight(1)
    frame.divider:SetColorTexture(unpack(T.border))
    return frame
end

local function row(index)
    local frame = Menu.frame
    local item = frame.rows[index]
    if item then return item end
    item = CreateFrame("Button", nil, frame)
    item:SetHeight(ROW)
    item.check = item:CreateTexture(nil, "ARTWORK")
    item.check:SetSize(16, 16)
    item.check:SetPoint("LEFT", 4, 0)
    item.check:SetTexture(CHECK)
    item.partial = W.Label(item, "-", 14, T.accent)
    item.partial:SetPoint("CENTER", item.check, "CENTER")
    item.icon = item:CreateTexture(nil, "ARTWORK")
    item.icon:SetSize(14, 14)
    item.icon:SetPoint("LEFT", 24, 0)
    item.star = W.Label(item, "*", 14, T.accent)
    item.star:SetPoint("LEFT", 26, -2)
    item.name = W.Label(item, "", 11)
    item.name:SetPoint("RIGHT", -6, 0)
    item:SetHighlightTexture(W.WHITE)
    item:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.06)
    item:SetScript("OnClick", function(button) if button.action then button.action() end end)
    frame.rows[index] = item
    return item
end

-- "all", "some" or "none" of the entries in the list.
function Menu.State(list, entries)
    local inside = 0
    for _, entry in ipairs(entries) do if ML.Lists:Has(list, entry.key) then inside = inside + 1 end end
    return inside == 0 and "none" or inside == #entries and "all" or "some"
end

-- Adds every entry, or removes every entry when all are already in.
function Menu.Apply(list, entries)
    local add = Menu.State(list, entries) ~= "all"
    for _, entry in ipairs(entries) do ML.Lists:Set(list, entry.key, add) end
end

local function place(item, y, text, color, icon)
    item:ClearAllPoints()
    item:SetPoint("TOPLEFT", 4, -y)
    item:SetPoint("TOPRIGHT", -4, -y)
    item.name:SetText(text)
    item.name:SetTextColor(unpack(color or T.text))
    local atlas = icon and hasStar()
    item.icon:SetShown(atlas and true or false)
    item.star:SetShown(icon ~= nil and not atlas)
    if atlas then item.icon:SetAtlas(icon) end
    item.name:ClearAllPoints()
    item.name:SetPoint("LEFT", icon and 42 or 24, 0)
    item.name:SetPoint("RIGHT", -6, 0)
    item:Show()
end

function Menu.Render()
    local frame, entries = Menu.frame, Menu.entries
    local index, y = 0, 4
    local function next(text, color, icon)
        index = index + 1
        local item = row(index)
        place(item, y, text, color, icon)
        y = y + ROW
        return item
    end
    if #entries > 1 then
        local header = next(#entries .. " selected", T.muted)
        header.check:Hide(); header.partial:Hide(); header.action = nil
        header:EnableMouse(false)
    end
    for _, list in ipairs(ML.Lists:All()) do
        local builtIn = ML.Lists.IsBuiltIn(list)
        local item = next(list.name, nil, builtIn and STAR or nil)
        item:EnableMouse(true)
        local state = Menu.State(list, entries)
        item.check:SetShown(state == "all")
        item.partial:SetShown(state == "some")
        item.name:SetTextColor(unpack(state ~= "none" and T.accent or T.text))
        item.action = function()
            Menu.Apply(list, entries)
            Menu.Render()
            Menu.onChanged()
        end
    end
    frame.divider:ClearAllPoints()
    frame.divider:SetPoint("TOPLEFT", 8, -(y + 3))
    frame.divider:SetPoint("TOPRIGHT", -8, -(y + 3))
    y = y + 7
    local new = next("+ New list...", T.muted)
    new:EnableMouse(true)
    new.check:Hide(); new.partial:Hide()
    new.action = function()
        frame:Hide()
        local holds = #entries == 1 and entries[1].name or (#entries .. " entries")
        ML.Prompt.Show(Menu.parent, {title = "New list", button = "Create", hint = "It will hold " .. holds .. ".",
            onAccept = function(name)
                local list, problem = ML.Lists:Create(name)
                if not list then return problem end
                for _, entry in ipairs(entries) do ML.Lists:Set(list, entry.key, true) end
                Menu.onChanged()
            end})
    end
    local manage = next("Manage lists...", T.muted)
    manage:EnableMouse(true)
    manage.check:Hide(); manage.partial:Hide()
    manage.action = function()
        frame:Hide()
        if Menu.onManage then Menu.onManage() end
    end
    for extra = index + 1, #frame.rows do frame.rows[extra]:Hide() end
    frame:SetHeight(y + 4)
end

function Menu.Hide()
    if Menu.frame then Menu.frame:Hide() end
end

function Menu.IsShown() return Menu.frame ~= nil and Menu.frame:IsShown() end

-- request: {entries, anchor (a frame to hang under) or at the cursor,
-- onChanged(), onManage()}. A second call for the same anchor closes it.
function Menu.Open(parent, request)
    Menu.frame = Menu.frame or create(parent)
    local frame = Menu.frame
    if request.anchor and frame:IsShown() and Menu.anchor == request.anchor then return frame:Hide() end
    Menu.parent, Menu.anchor, Menu.entries = parent, request.anchor, request.entries
    Menu.onChanged, Menu.onManage = request.onChanged, request.onManage
    frame:ClearAllPoints()
    if request.anchor then
        frame:SetPoint("TOPRIGHT", request.anchor, "BOTTOMRIGHT", 0, -4)
    else
        local x, y = GetCursorPosition()
        local scale = frame:GetEffectiveScale()
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale, y / scale)
    end
    Menu.Render()
    frame:Show()
    return frame
end
