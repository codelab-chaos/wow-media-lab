local _, ML = ...

-- The minimized lab: a small icon docked to an edge of the screen. Click it
-- to bring the window back; drag it along the edge, or to another edge, where
-- it snaps. Saved in ML.db.dock as {side, at}: the edge, and how far along it
-- (0 to 1). Cheap to create, so it can come back at login without the window.
local W = ML.Widgets
local T = W.theme
local Dock = {}
ML.Dock = Dock

Dock.SIZE = 38
Dock.ICON = ML.ICON
Dock.DEFAULT = {side = "right", at = 0.5}
-- Each edge: the anchor point, and whether "at" runs along x or y.
Dock.SIDES = {
    left = {point = "LEFT", along = "y"}, right = {point = "RIGHT", along = "y"},
    top = {point = "TOP", along = "x"}, bottom = {point = "BOTTOM", along = "x"},
}
local MARGIN = 0.04 -- keeps the icon off the corners

function Dock.Sanitize(saved)
    local dock = type(saved.dock) == "table" and saved.dock or {}
    local at = tonumber(dock.at)
    saved.dock = {side = Dock.SIDES[dock.side] and dock.side or Dock.DEFAULT.side,
        at = at and W.Clamp(at, MARGIN, 1 - MARGIN) or Dock.DEFAULT.at}
    return saved
end

-- The edge nearest a point on a screen of width x height, and how far along it.
function Dock.Nearest(x, y, width, height)
    local distances = {left = x, right = width - x, bottom = y, top = height - y}
    local side = "left"
    for name, distance in pairs(distances) do
        if distance < distances[side] or (distance == distances[side] and name < side) then side = name end
    end
    local at = Dock.SIDES[side].along == "y" and y / height or x / width
    return side, W.Clamp(at, MARGIN, 1 - MARGIN)
end

function Dock.Place()
    local button, dock = Dock.button, ML.db.dock
    local spec = Dock.SIDES[dock.side]
    local offset = dock.at - 0.5
    button:ClearAllPoints()
    if spec.along == "y" then
        button:SetPoint(spec.point, UIParent, spec.point, 0, offset * UIParent:GetHeight())
    else
        button:SetPoint(spec.point, UIParent, spec.point, offset * UIParent:GetWidth(), 0)
    end
end

function Dock.SetSide(side)
    if not Dock.SIDES[side] then return false end
    ML.db.dock.side = side
    if Dock.button then Dock.Place() end
    return true
end

local function create(onOpen)
    local button = CreateFrame("Button", "MediaLabDock", UIParent, "BackdropTemplate")
    button:SetSize(Dock.SIZE, Dock.SIZE)
    button:SetFrameStrata("MEDIUM")
    button:SetClampedToScreen(true)
    button:SetBackdrop({bgFile = W.WHITE, edgeFile = W.WHITE, edgeSize = 1})
    button:SetBackdropColor(unpack(T.window))
    button:SetBackdropBorderColor(unpack(T.selected))
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 3, -3)
    icon:SetPoint("BOTTOMRIGHT", -3, 3)
    icon:SetTexture(Dock.ICON)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    button:SetHighlightTexture(W.WHITE)
    button:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.12)
    button:SetMovable(true)
    button:RegisterForDrag("LeftButton")
    button:SetScript("OnDragStart", function(self) self.dragging = true; self:StartMoving() end)
    button:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        self.dragging = nil
        local scale = self:GetEffectiveScale() / UIParent:GetEffectiveScale()
        local x = (self:GetLeft() + self:GetWidth() / 2) * scale
        local y = (self:GetTop() - self:GetHeight() / 2) * scale
        ML.db.dock.side, ML.db.dock.at = Dock.Nearest(x, y, UIParent:GetWidth(), UIParent:GetHeight())
        Dock.Place()
    end)
    button:SetScript("OnClick", function(self) if not self.dragging then Dock.onOpen() end end)
    W.Tip(button, ML.TITLE, "Click to open. Drag to move it along the edge, or to another edge.")
    return button
end

function Dock.Show(onOpen)
    Dock.onOpen = onOpen
    Dock.button = Dock.button or create()
    Dock.Place()
    Dock.button:Show()
end

function Dock.Hide()
    if Dock.button then Dock.button:Hide() end
end

function Dock.IsShown()
    return Dock.button ~= nil and Dock.button:IsShown() or false
end
