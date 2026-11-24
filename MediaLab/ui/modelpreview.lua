local _, ML = ...

-- The 3D preview for creature displays: drag (left or right button) to turn
-- it on any axis (across spins, up and down tilts, Shift+drag rolls),
-- middle-drag to pan, wheel to zoom, cycle
-- animations and the canvas, or load your current target. Registered as
-- ML.Previews.model; built lazily inside the inspector like the others.
local W = ML.Widgets
local T = W.theme
local P = ML.Previews.Parts
local Model = {}
Model.__index = Model
ML.Previews.model = Model

local function view() return ML.db.view end

local function animationById(id)
    for _, animation in ipairs(ML.ModelAnimations) do if animation.id == id then return animation end end
    return ML.ModelAnimations[1]
end

function Model.New(parent)
    local self = setmetatable({facing = 0, pitch = 0, roll = 0, distance = 1, panX = 0, panY = 0}, Model)
    self.frame = P.baseFrame(parent)
    self.stage = P.stageFrame(self.frame, 54)
    self.model = CreateFrame("PlayerModel", nil, self.stage)
    self.model:SetAllPoints()
    self.model:EnableMouse(true)
    self.model:EnableMouseWheel(true)
    self.model:SetScript("OnModelLoaded", function() self:Apply() end)
    self.model:SetScript("OnMouseWheel", function(_, delta)
        local step = delta > 0 and 1 / ML.ModelCamera.step or ML.ModelCamera.step
        self.distance = W.Clamp(self.distance * step, ML.ModelCamera.min, ML.ModelCamera.max)
        view().modelDistance = self.distance ~= 1 and self.distance or nil
        self:Apply()
    end)
    self.model:SetScript("OnMouseDown", function(_, button)
        local x, y = GetCursorPosition()
        self.drag = {x = x, y = y, facing = self.facing, pitch = self.pitch, roll = self.roll,
            panX = self.panX, panY = self.panY, pan = button == "MiddleButton", rolling = IsShiftKeyDown() and true or false}
        self.model:SetScript("OnUpdate", function() self:Drag() end)
    end)
    self.model:SetScript("OnMouseUp", function()
        self.drag = nil
        self.model:SetScript("OnUpdate", nil)
    end)
    self.stage:SetScript("OnSizeChanged", function() self:Layout() end)

    local bar = CreateFrame("Frame", nil, self.frame)
    bar:SetPoint("BOTTOMLEFT", 0, 28)
    bar:SetPoint("BOTTOMRIGHT", 0, 28)
    bar:SetHeight(22)
    self.animation = W.Button(bar, "", 92, function() self:NextAnimation() end, 22)
    self.animation:SetPoint("LEFT")
    W.Tip(self.animation, "Animation", "Cycle the animations this model has.")
    local reset = W.Button(bar, "Reset", 46, function() self:ResetView(); self:Apply() end, 22)
    reset:SetPoint("LEFT", self.animation, "RIGHT", 4, 0)
    W.Tip(reset, "Reset view", "Face forward, upright, centered, at the default distance. Drag turns, Shift+drag rolls, middle-drag moves, the wheel zooms.")
    self.canvasButton = W.Button(bar, "Dark", 62, function()
        view().canvas = P.nextIn(ML.Canvases, view().canvas or "Dark", "id")
        self:Layout()
    end, 22)
    self.canvasButton:SetPoint("LEFT", reset, "RIGHT", 4, 0)
    W.Tip(self.canvasButton, "Canvas", "Cycle the background behind the model.")
    self.target = W.Button(bar, "Target", 56, function() if self.onTarget then self.onTarget() end end, 22)
    self.target:SetPoint("RIGHT")
    W.Tip(self.target, "From target", "Find the model your current target uses and remember its name, so the Models tab can search by NPC name.")
    self.note = W.Label(self.frame, "", 10, T.muted)
    self.note:SetPoint("BOTTOMLEFT", 1, 10)
    self.note:SetPoint("BOTTOMRIGHT", -1, 10)
    self.note:SetWordWrap(false)
    return self
end

-- Reset faces the model forward at the default distance, and forgets the
-- remembered distance; a new model only turns to face forward.
function Model:ResetView()
    self.facing, self.pitch, self.roll, self.distance, self.panX, self.panY = 0, 0, 0, 1, 0, 0
    view().modelDistance = nil
end

-- Drag turns the model; middle-drag moves it, the way the game's dressing
-- room does (SetPosition, in model units: ML.ModelCamera.pan per UI unit at
-- the default distance, more when zoomed out).
function Model:Drag()
    local drag = self.drag
    if not drag then return end
    local x, y = GetCursorPosition()
    local scale = self.stage:GetEffectiveScale()
    if drag.pan then
        local units = ML.ModelCamera.pan * self.distance / scale
        self.panX = drag.panX + (x - drag.x) * units
        self.panY = drag.panY + (y - drag.y) * units
        self:ApplyPan()
    elseif drag.rolling then
        self.roll = drag.roll + (x - drag.x) / scale * ML.ModelCamera.turn
        self:ApplyTilt()
    else
        self.facing = drag.facing + (x - drag.x) / scale * ML.ModelCamera.turn
        self.pitch = drag.pitch - (y - drag.y) / scale * ML.ModelCamera.turn
        self.model:SetFacing(self.facing)
        self:ApplyTilt()
    end
end

-- Pitch and roll, only once the model has been tilted: an upright model is
-- left to the game's own framing.
function Model:ApplyTilt()
    if self.pitch == 0 and self.roll == 0 and not self.tilted then return end
    self.tilted = self.pitch ~= 0 or self.roll ~= 0
    self.model:SetPitch(self.pitch)
    self.model:SetRoll(self.roll)
end

-- Only once something has been panned: an untouched model keeps the game's
-- own framing, and turning and zooming work as they always did.
function Model:ApplyPan()
    if self.panX == 0 and self.panY == 0 and not self.panned then return end
    self.panned = self.panX ~= 0 or self.panY ~= 0
    self.model:SetPosition(0, self.panX, self.panY)
end

-- Animations this model has; every listed one when the client cannot say.
function Model:Animations()
    local result = {}
    for _, animation in ipairs(ML.ModelAnimations) do
        local ok, has = pcall(self.model.HasAnimation, self.model, animation.id)
        if not ok or has then result[#result + 1] = animation end
    end
    return #result > 0 and result or {ML.ModelAnimations[1]}
end

function Model:NextAnimation()
    local current = view().modelAnimation or 0
    local available = self:Animations()
    local nextOne = available[1]
    for index, animation in ipairs(available) do
        if animation.id == current then nextOne = available[index % #available + 1] end
    end
    view().modelAnimation = nextOne.id
    self:Apply()
end

-- Camera, facing and animation; again whenever the model finishes loading.
function Model:Apply()
    local wanted = view().modelAnimation or 0
    local animation = animationById(0)
    for _, candidate in ipairs(self:Animations()) do
        if candidate.id == wanted then animation = candidate end
    end
    self.model:SetCamDistanceScale(self.distance)
    self.model:SetFacing(self.facing)
    self:ApplyTilt()
    self:ApplyPan()
    self.model:SetAnimation(animation.id)
    self.animation:SetLabel(animation.label)
end

function Model:Show(entry)
    if not self.entry or self.entry.key ~= entry.key then
        self.facing, self.pitch, self.roll, self.panX, self.panY, self.status = 0, 0, 0, 0, 0, nil
        self.distance = W.Clamp(tonumber(view().modelDistance) or 1, ML.ModelCamera.min, ML.ModelCamera.max)
    end
    self.entry = entry
    self.frame:Show()
    self.model:SetDisplayInfo(entry.id)
    self:Apply()
    self:Layout()
end

function Model:Layout()
    if not self.entry then return end
    P.paintCanvas(self.stage, view().canvas or "Dark")
    self.canvasButton:SetLabel(view().canvas or "Dark")
    local parts = {"Display " .. self.entry.id}
    if self.entry.model then parts[#parts + 1] = "model file " .. self.entry.model end
    if self.status then parts[#parts + 1] = self.status end
    self.note:SetText(table.concat(parts, "  /  "))
end

-- A one-line result from the Target button, shown until the next selection.
function Model:SetStatus(text)
    self.status = text
    self:Layout()
end

function Model:Hide()
    self.drag = nil
    self.model:SetScript("OnUpdate", nil)
    self.frame:Hide()
end
