local _, ML = ...

-- A sound's waveform: one bar per character of its loudness outline
-- ("0" quiet to "f" loud, from the codex), and a playhead. Bars left of the
-- playhead light up while it plays. Used by the sound rows and the preview.
local W = ML.Widgets
local T = W.theme
local Waveform = {}
Waveform.__index = Waveform
ML.Waveform = Waveform

local LEVELS = 15

function Waveform.New(parent)
    local self = setmetatable({bars = {}}, Waveform)
    local frame = CreateFrame("Button", nil, parent)
    frame:RegisterForClicks("LeftButtonUp")
    self.frame = frame
    self.empty = W.Label(frame, "no waveform", 9, T.muted)
    self.empty:SetPoint("LEFT")
    self.head = frame:CreateTexture(nil, "OVERLAY")
    self.head:SetColorTexture(1, 1, 1, 0.9)
    self.head:SetWidth(1)
    frame:SetScript("OnSizeChanged", function() self:Render() end)
    return self
end

function Waveform:Bar(index)
    local bar = self.bars[index]
    if bar then return bar end
    bar = self.frame:CreateTexture(nil, "ARTWORK")
    self.bars[index] = bar
    return bar
end

-- wave: the outline string, or nil; progress: 0 to 1 while playing, else nil.
function Waveform:Set(wave, progress)
    self.wave, self.progress = wave, progress
    self:Render()
end

function Waveform:Render()
    local wave = self.wave
    local width, height = self.frame:GetWidth() or 0, self.frame:GetHeight() or 0
    self.empty:SetShown(not wave)
    local count = wave and #wave or 0
    local slot = count > 0 and width / count or 0
    for index = 1, count do
        local level = tonumber(wave:sub(index, index), 16) or 0
        local bar = self:Bar(index)
        bar:ClearAllPoints()
        bar:SetPoint("LEFT", self.frame, "LEFT", (index - 1) * slot + 1, 0)
        bar:SetSize(math.max(1, slot - 2), math.max(2, height * level / LEVELS))
        local lit = self.progress and (index - 0.5) / count <= self.progress
        bar:SetColorTexture(unpack(lit and T.accent or T.muted))
        bar:SetAlpha(lit and 1 or 0.55)
        bar:Show()
    end
    for index = count + 1, #self.bars do self.bars[index]:Hide() end
    self.head:SetShown(self.progress ~= nil and count > 0)
    if self.progress then
        self.head:ClearAllPoints()
        self.head:SetPoint("TOP", self.frame, "TOPLEFT", width * self.progress, 0)
        self.head:SetHeight(math.max(1, height))
    end
end
