local _, ML = ...

-- The 3D preview for creature displays: drag to turn, wheel to zoom, cycle
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
    local self = setmetatable({facing = 0, distance = 1}, Model)
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
    self.model:SetScript("OnMouseDown", function()
        self.drag = {x = GetCursorPosition(), facing = self.facing}
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
    W.Tip(reset, "Reset view", "Face forward at the default distance. Drag turns, the wheel zooms.")
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
    self.facing, self.distance = 0, 1
    view().modelDistance = nil
end

function Model:Drag()
    if not self.drag then return end
    local x = GetCursorPosition()
    self.facing = self.drag.facing + (x - self.drag.x) / self.stage:GetEffectiveScale() * ML.ModelCamera.turn
    self.model:SetFacing(self.facing)
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
    self.model:SetAnimation(animation.id)
    self.animation:SetLabel(animation.label)
end

function Model:Show(entry)
    if not self.entry or self.entry.key ~= entry.key then
        self.facing, self.status = 0, nil
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
