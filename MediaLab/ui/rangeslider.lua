local _, ML = ...

-- A two-handle slider over fixed stops (the popular sizes 8, 16, ... 4096):
-- the handles snap to the stops like grooves, and the range between them is
-- the filter. The value reads "Any" when the handles are at the ends; click
-- it to go back there. onChange(low, high) gets stop values, or nil, nil for Any.
local W = ML.Widgets
local T = W.theme
local Range = {}
Range.__index = Range
ML.RangeSlider = Range

local INSET, HANDLE = 10, 10

function Range.New(parent, title, stops, onChange)
    local self = setmetatable({stops = stops, onChange = onChange, low = 1, high = #stops, ticks = {}}, Range)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetHeight(46)
    self.frame = frame
    self.title = W.Label(frame, title, 10, T.muted)
    self.title:SetPoint("TOPLEFT", 4, 0)
    self.value = W.Button(frame, "Any", 86, function() self:Set(1, #stops, true) end, 16)
    self.value:SetPoint("TOPRIGHT", -2, 2)
    W.Tip(self.value, title, "Drag the handles to the sizes you want (the longer side). Click here for any size.")
    local track = CreateFrame("Button", nil, frame)
    track:SetPoint("TOPLEFT", INSET, -24)
    track:SetPoint("TOPRIGHT", -INSET, -24)
    track:SetHeight(4)
    W.Fill(track, T.border)
    track:SetScript("OnClick", function() self:Nearest():Grab() end)
    track:SetScript("OnSizeChanged", function() self:Render() end)
    self.track = track
    self.fill = track:CreateTexture(nil, "ARTWORK")
    self.fill:SetColorTexture(unpack(T.accent))
    self.fill:SetHeight(4)
    for index, stop in ipairs(stops) do
        local tick = track:CreateTexture(nil, "BORDER")
        tick:SetColorTexture(unpack(T.muted))
        tick:SetSize(1, 8)
        tick.label = index % 2 == 0 and W.Label(frame, tostring(stop), 8, T.muted) or nil
        self.ticks[index] = tick
    end
    self.handles = {self:Handle("low"), self:Handle("high")}
    return self
end

function Range:Handle(side)
    local handle = CreateFrame("Button", nil, self.frame)
    handle:SetSize(HANDLE, 14)
    W.Fill(handle, T.accent)
    handle.side = side
    handle:SetScript("OnMouseDown", function() handle:Grab() end)
    handle:SetScript("OnMouseUp", function() handle:SetScript("OnUpdate", nil) end)
    local slider = self
    function handle:Grab()
        slider:Follow(self.side)
        self:SetScript("OnUpdate", function() slider:Follow(self.side) end)
    end
    return handle
end

-- The stop under the cursor.
function Range:StopAt()
    local x = GetCursorPosition() / self.track:GetEffectiveScale()
    local fraction = W.Clamp((x - (self.track:GetLeft() or 0)) / math.max(1, self.track:GetWidth()), 0, 1)
    return math.floor(fraction * (#self.stops - 1) + 0.5) + 1
end

-- The handle nearer the cursor, for clicks on the track.
function Range:Nearest()
    local stop = self:StopAt()
    return math.abs(stop - self.low) <= math.abs(stop - self.high) and self.handles[1] or self.handles[2]
end

function Range:Follow(side)
    local stop = self:StopAt()
    if side == "low" then self:Set(math.min(stop, self.high), self.high, true)
    else self:Set(self.low, math.max(stop, self.low), true) end
end

function Range:IsAny() return self.low == 1 and self.high == #self.stops end

-- Moves the handles to stop indexes; notify reports the change.
function Range:Set(low, high, notify)
    low = W.Clamp(math.floor(tonumber(low) or 1), 1, #self.stops)
    high = W.Clamp(math.floor(tonumber(high) or #self.stops), low, #self.stops)
    local changed = low ~= self.low or high ~= self.high
    self.low, self.high = low, high
    self:Render()
    if notify and changed then
        if self:IsAny() then self.onChange(nil, nil) else self.onChange(self.stops[low], self.stops[high]) end
    end
end

-- Moves the handles to the stops nearest two sizes (nil, nil for Any).
function Range:SetValues(low, high)
    local function index(value, fallback)
        if not value then return fallback end
        for position, stop in ipairs(self.stops) do if stop >= value then return position end end
        return #self.stops
    end
    self:Set(index(low, 1), index(high, #self.stops))
end

function Range:Render()
    local width = self.track:GetWidth() or 0
    local function x(index) return (index - 1) / (#self.stops - 1) * width end
    for index, tick in ipairs(self.ticks) do
        tick:ClearAllPoints()
        tick:SetPoint("CENTER", self.track, "LEFT", x(index), 0)
        if tick.label then
            tick.label:ClearAllPoints()
            tick.label:SetPoint("TOP", self.track, "BOTTOMLEFT", x(index), -6)
        end
    end
    for _, handle in ipairs(self.handles) do
        handle:ClearAllPoints()
        handle:SetPoint("CENTER", self.track, "LEFT", x(handle.side == "low" and self.low or self.high), 0)
    end
    self.fill:ClearAllPoints()
    self.fill:SetPoint("LEFT", self.track, "LEFT", x(self.low), 0)
    self.fill:SetWidth(math.max(1, x(self.high) - x(self.low)))
    local any = self:IsAny()
    self.value:SetLabel(any and "Any" or (self.stops[self.low] .. " to " .. self.stops[self.high] .. " px"))
    self.value:SetActive(not any)
end
