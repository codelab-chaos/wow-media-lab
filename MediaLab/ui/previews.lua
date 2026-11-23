local _, ML = ...

-- Inspector previews, one per ML.Kinds[].preview value. Each is built lazily
-- inside the inspector's preview area and exposes Show(entry), Hide(), Layout().
local W = ML.Widgets
local T = W.theme
local Previews = {}
ML.Previews = Previews

local function view() return ML.db.view end

local function findCanvas(id)
    for _, canvas in ipairs(ML.Canvases) do if canvas.id == id then return canvas end end
    return ML.Canvases[1]
end

local function nextIn(list, value, key)
    for index, item in ipairs(list) do
        if (key and item[key] or item) == value then
            local nextItem = list[index % #list + 1]
            return key and nextItem[key] or nextItem
        end
    end
    return key and list[1][key] or list[1]
end

local function baseFrame(parent)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints()
    frame:Hide()
    return frame
end

local function stageFrame(parent, bottomInset)
    local stage = CreateFrame("Frame", nil, parent)
    stage:SetPoint("TOPLEFT", 0, 0)
    stage:SetPoint("BOTTOMRIGHT", 0, bottomInset)
    stage:SetClipsChildren(true)
    stage.base = W.Fill(stage, findCanvas("Dark").color)
    stage.checkers = {}
    return stage
end

-- A bounded set of color squares makes transparency visible without shipping art.
local function paintCanvas(stage, id)
    local canvas = findCanvas(id)
    stage.base:SetColorTexture(unpack(canvas.color))
    local used, tile = 0, 16
    if canvas.checker then
        local width, height = stage:GetWidth(), stage:GetHeight()
        for row = 0, math.ceil(height / tile) - 1 do
            for column = 0, math.ceil(width / tile) - 1 do
                if (row + column) % 2 == 0 then
                    used = used + 1
                    local square = stage.checkers[used]
                    if not square then
                        square = stage:CreateTexture(nil, "BACKGROUND", nil, 1)
                        stage.checkers[used] = square
                    end
                    square:SetColorTexture(unpack(canvas.checker))
                    square:ClearAllPoints()
                    square:SetPoint("TOPLEFT", column * tile, -row * tile)
                    square:SetSize(math.min(tile, width - column * tile), math.min(tile, height - row * tile))
                    square:Show()
                end
            end
        end
    end
    for index = used + 1, #stage.checkers do stage.checkers[index]:Hide() end
end

-- Shared with previews kept in their own files (modelpreview.lua).
Previews.Parts = {baseFrame = baseFrame, stageFrame = stageFrame, paintCanvas = paintCanvas, nextIn = nextIn}

---------------------------------------------------------------------------
-- Zoom and pan, shared by previews with a stage. The owner provides
-- self.stage and Layout(); Layout sets self.fitZoom (and optionally
-- self.defaultZoom) and draws at CurrentZoom() offset by panX, panY.
---------------------------------------------------------------------------
local Zoomable = {}

function Zoomable.Attach(self)
    self.panX, self.panY = 0, 0
    local stage = self.stage
    stage:EnableMouse(true)
    stage:EnableMouseWheel(true)
    stage:SetScript("OnMouseWheel", function(_, delta)
        self:SetZoom(self:CurrentZoom() * (delta > 0 and ML.Zoom.step or 1 / ML.Zoom.step))
    end)
    stage:SetScript("OnMouseDown", function()
        local x, y = GetCursorPosition()
        self.drag = {x = x, y = y, panX = self.panX, panY = self.panY}
        stage:SetScript("OnUpdate", function() self:Drag() end)
    end)
    stage:SetScript("OnMouseUp", function()
        self.drag = nil
        stage:SetScript("OnUpdate", nil)
    end)
    stage:SetScript("OnSizeChanged", function() self:Layout() end)
end

-- -, +, 1:1 and Fit buttons on a bar; returns the last one for anchoring.
function Zoomable.Buttons(self, bar, actualTip)
    local previous
    local function tool(text, width, onClick, tipTitle, tipBody)
        local button = W.Button(bar, text, width, onClick, 22)
        if previous then button:SetPoint("LEFT", previous, "RIGHT", 4, 0) else button:SetPoint("LEFT") end
        if tipTitle then W.Tip(button, tipTitle, tipBody) end
        previous = button
        return button
    end
    tool("-", 24, function() self:SetZoom(self:CurrentZoom() / ML.Zoom.step) end, "Zoom out", "Or use the mouse wheel.")
    tool("+", 24, function() self:SetZoom(self:CurrentZoom() * ML.Zoom.step) end, "Zoom in", "Or use the mouse wheel.")
    tool("1:1", 34, function() self:SetZoom(1) end, "Actual size", actualTip)
    tool("Fit", 34, function() self:Fit() end, "Fit to the stage", "Drag the stage to pan.")
    self.zoomLabel = W.Label(bar, "", 11, T.muted)
    self.zoomLabel:SetPoint("RIGHT", -2, 0)
    return previous
end

-- Explicit zoom, else Fit when asked, else the owner's default, else fit.
function Zoomable:CurrentZoom()
    return self.zoom or (self.fitting and self.fitZoom) or self.defaultZoom or self.fitZoom or 1
end

function Zoomable:SetZoom(value)
    local before = self:CurrentZoom()
    self.zoom = W.Clamp(value, ML.Zoom.min, ML.Zoom.max)
    -- Keep the point under the stage center fixed while zooming.
    local ratio = self.zoom / before
    self.panX, self.panY = self.panX * ratio, self.panY * ratio
    self:Layout()
end

function Zoomable:Fit()
    self.zoom, self.fitting, self.panX, self.panY = nil, true, 0, 0
    self:Layout()
end

function Zoomable:ResetView()
    self.zoom, self.fitting, self.panX, self.panY = nil, false, 0, 0
end

function Zoomable:Drag()
    if not self.drag then return end
    local x, y = GetCursorPosition()
    local scale = self.stage:GetEffectiveScale()
    self.panX = self.drag.panX + (x - self.drag.x) / scale
    self.panY = self.drag.panY + (y - self.drag.y) / scale
    self:Layout()
end

function Zoomable:ZoomText()
    return string.format("%d%%%s", math.floor(self:CurrentZoom() * 100 + 0.5), self.zoom and "" or "  fit")
end

local function mixin(target)
    for name, fn in pairs(Zoomable) do
        if name ~= "Attach" and name ~= "Buttons" then target[name] = fn end
    end
end

---------------------------------------------------------------------------
-- Images: zoom with the wheel or buttons, drag to pan.
---------------------------------------------------------------------------
local Image = {}
Image.__index = Image
Previews.image = Image
mixin(Image)

function Image.New(parent)
    local self = setmetatable({}, Image)
    self.frame = baseFrame(parent)
    self.stage = stageFrame(self.frame, 54)
    self.art = self.stage:CreateTexture(nil, "ARTWORK")
    self.message = W.Label(self.stage, "", 11, T.muted)
    self.message:SetPoint("CENTER")
    Zoomable.Attach(self)
    local bar = CreateFrame("Frame", nil, self.frame)
    bar:SetPoint("BOTTOMLEFT", 0, 28)
    bar:SetPoint("BOTTOMRIGHT", 0, 28)
    bar:SetHeight(22)
    local fit = Zoomable.Buttons(self, bar, "One texture pixel per UI unit (assumed size for file textures).")
    self.canvasButton = W.Button(bar, "Dark", 62, function()
        view().canvas = nextIn(ML.Canvases, view().canvas or "Dark", "id")
        self:Layout()
    end, 22)
    self.canvasButton:SetPoint("LEFT", fit, "RIGHT", 4, 0)
    W.Tip(self.canvasButton, "Canvas", "Cycle the background to inspect transparency.")
    self.note = W.Label(self.frame, "", 10, T.muted)
    self.note:SetPoint("BOTTOMLEFT", 1, 10)
    self.note:SetPoint("BOTTOMRIGHT", -1, 10)
    return self
end

function Image:Show(entry)
    if not self.entry or self.entry.key ~= entry.key then self:ResetView() end
    self.entry = entry
    self.frame:Show()
    self:Layout()
end

function Image:Layout()
    if not self.entry then return end
    paintCanvas(self.stage, view().canvas or "Dark")
    self.canvasButton:SetLabel(view().canvas or "Dark")
    local loaded, width, height, exact, info = ML.Art.Apply(self.art, self.entry)
    self.message:SetShown(not loaded)
    self.message:SetText("This image did not load.\nIt may not exist in this client.")
    if not loaded then
        self.zoomLabel:SetText("")
        self.note:SetText("")
        return
    end
    local stageWidth, stageHeight = math.max(1, self.stage:GetWidth() - 16), math.max(1, self.stage:GetHeight() - 16)
    self.fitZoom = math.min(stageWidth / width, stageHeight / height)
    local zoom = self:CurrentZoom()
    self.art:SetSize(math.max(1, width * zoom), math.max(1, height * zoom))
    self.art:ClearAllPoints()
    self.art:SetPoint("CENTER", self.stage, "CENTER", self.panX, self.panY)
    self.zoomLabel:SetText(self:ZoomText())
    if exact then
        self.note:SetText(string.format("%d x %d native  /  file %s", width, height, tostring(info.file or info.filename or "?")))
    else
        self.note:SetText(string.format("Size unknown to addons; 1:1 assumes %d x %d. Wheel zooms, drag pans.", width, height))
    end
end

function Image:Hide() self.frame:Hide() end

---------------------------------------------------------------------------
-- Sounds: play, stop, channel, auto-play on select.
---------------------------------------------------------------------------
local Sound = {}
Sound.__index = Sound
Previews.sound = Sound

function Sound.New(parent)
    local self = setmetatable({}, Sound)
    self.frame = baseFrame(parent)
    local stage = stageFrame(self.frame, 0)
    self.title = W.Label(stage, "", 14, T.accent)
    self.title:SetPoint("TOPLEFT", 12, -14)
    self.title:SetPoint("TOPRIGHT", -12, -14)
    self.id = W.Label(stage, "", 11, T.muted)
    self.id:SetPoint("TOPLEFT", 12, -36)
    self.play = W.Button(stage, "Play", 70, function() self:Play() end, 26)
    self.play:SetPoint("TOPLEFT", 12, -64)
    self.stop = W.Button(stage, "Stop", 70, function() self:Stop() end, 26)
    self.stop:SetPoint("LEFT", self.play, "RIGHT", 6, 0)
    self.channel = W.Button(stage, "", 110, function()
        view().channel = nextIn(ML.SoundChannels, view().channel or "Master")
        self:Refresh()
        if self.onOptions then self.onOptions() end
    end, 26)
    self.channel:SetPoint("LEFT", self.stop, "RIGHT", 6, 0)
    W.Tip(self.channel, "Sound channel", "Which volume slider the sound obeys. A muted channel plays nothing.")
    self.auto = W.Button(stage, "", 140, function()
        view().autoplay = not view().autoplay or nil
        self:Refresh()
    end, 22)
    self.auto:SetPoint("TOPLEFT", 12, -100)
    W.Tip(self.auto, "Auto-play", "Play each sound as soon as you select it.")
    self.status = W.Label(stage, "", 11, T.muted)
    self.status:SetPoint("TOPLEFT", 12, -134)
    self.status:SetPoint("TOPRIGHT", -12, -134)
    self.status:SetWordWrap(true)
    return self
end

function Sound:Refresh()
    self.channel:SetLabel("Channel: " .. (view().channel or "Master"))
    self.auto:SetLabel(view().autoplay and "Auto-play: on" or "Auto-play: off")
    self.auto:SetActive(view().autoplay == true)
end

function Sound:Show(entry)
    self.entry = entry
    self.title:SetText(entry.name)
    self.id:SetText("Sound kit " .. tostring(entry.id))
    self.status:SetText(type(PlaySound) == "function" and "" or "PlaySound is unavailable in this client.")
    self:Refresh()
    self.frame:Show()
    if view().autoplay then self:Play() end
end

-- Returns whether the client accepted the sound.
function Sound:Play(entry)
    entry = entry or self.entry
    if not entry or type(PlaySound) ~= "function" then return false end
    self:Stop()
    local ok, willPlay, handle = pcall(PlaySound, entry.id, view().channel or "Master")
    if ok and willPlay then
        self.handle = handle
        self.status:SetText("Playing " .. entry.name .. ".")
        return true
    end
    self.status:SetText("The client did not play this sound. The channel may be muted, or the kit has no audio here.")
    return false
end

function Sound:Stop()
    if self.handle and type(StopSound) == "function" then pcall(StopSound, self.handle) end
    self.handle = nil
end

function Sound:Hide() self.frame:Hide() end

---------------------------------------------------------------------------
-- Controls: describe a template, and build a live instance on request.
---------------------------------------------------------------------------
local Control = {}
Control.__index = Control
Previews.control = Control
mixin(Control)

function Control.New(parent)
    local self = setmetatable({instances = {}}, Control)
    self.frame = baseFrame(parent)
    self.stage = stageFrame(self.frame, 120)
    -- Built instances live in the holder; zoom scales it, pan moves it.
    self.holder = CreateFrame("Frame", nil, self.stage)
    self.holder:SetSize(1, 1)
    self.holder:SetPoint("CENTER")
    Zoomable.Attach(self)
    local bar = CreateFrame("Frame", nil, self.frame)
    bar:SetPoint("BOTTOMLEFT", 0, 92)
    bar:SetPoint("BOTTOMRIGHT", 0, 92)
    bar:SetHeight(22)
    Zoomable.Buttons(self, bar, "The control at its own size.")
    self.message = W.Label(self.stage, "", 11, T.muted)
    self.message:SetPoint("CENTER")
    self.message:SetJustifyH("CENTER")
    self.message:SetWordWrap(true)
    self.message:SetWidth(260)
    self.build = W.Button(self.frame, "Build preview", 110, function() self:Build() end, 22)
    self.build:SetPoint("BOTTOMLEFT", 0, 64)
    W.Tip(self.build, "Build preview", "Creates one live instance of the template and runs its scripts. WoW cannot delete frames, so each template is built once per session and reused.")
    self.canvasButton = W.Button(self.frame, "Dark", 62, function()
        view().canvas = nextIn(ML.Canvases, view().canvas or "Dark", "id")
        paintCanvas(self.stage, view().canvas)
        self.canvasButton:SetLabel(view().canvas)
    end, 22)
    self.canvasButton:SetPoint("LEFT", self.build, "RIGHT", 4, 0)
    self.info = W.Label(self.frame, "", 10, T.muted)
    self.info:SetPoint("BOTTOMLEFT", 1, 4)
    self.info:SetPoint("BOTTOMRIGHT", -1, 4)
    self.info:SetHeight(54)
    self.info:SetJustifyV("TOP")
    self.info:SetWordWrap(true)
    return self
end

function Control:TemplateInfo(entry)
    if not (C_XMLUtil and C_XMLUtil.GetTemplateInfo) then return end
    local ok, info = pcall(C_XMLUtil.GetTemplateInfo, entry.value)
    if ok and type(info) == "table" then return info end
end

function Control:Show(entry)
    self.entry = entry
    for _, instance in pairs(self.instances) do instance:Hide() end
    paintCanvas(self.stage, view().canvas or "Dark")
    self.canvasButton:SetLabel(view().canvas or "Dark")
    local info = self:TemplateInfo(entry)
    local lines = {"Type: " .. (info and info.type or entry.tag or "?")}
    if info and (info.width or 0) > 0 then lines[1] = lines[1] .. string.format("   Size: %d x %d", info.width, info.height) end
    local inherits = info and info.inherits or entry.inherits
    if inherits and inherits ~= "" then lines[#lines + 1] = "Inherits: " .. inherits end
    local source = info and info.sourceLocation or entry.source
    if source then lines[#lines + 1] = "Source: " .. source end
    if info and info.keyValues and #info.keyValues > 0 then lines[#lines + 1] = #info.keyValues .. " key values" end
    self.info:SetText(table.concat(lines, "\n"))
    if not self.entry or self.shownKey ~= entry.key then self:ResetView() end
    self.shownKey = entry.key
    local existing = self.instances[entry.key]
    local buildable = not ML.UnbuildableTypes[entry.tag or "Frame"]
    self.build:SetEnabled(buildable and not existing)
    if existing then
        existing:Show()
        self.message:SetText("")
    else
        self.message:SetText(buildable and "Press Build preview to create a live instance." or "This template type has no visual preview.")
    end
    self.frame:Show()
    self:Layout()
end

-- Scales and positions the holder around the shown instance. Opens at actual
-- size, shrunk to fit when larger than the stage; Fit fills the stage.
function Control:Layout()
    local widget = self.entry and self.instances[self.entry.key]
    if not widget then
        self.holder:SetScale(1)
        self.fitZoom, self.defaultZoom = nil, nil
        self.zoomLabel:SetText("")
        return
    end
    local width, height = math.max(1, widget:GetWidth() or 1), math.max(1, widget:GetHeight() or 1)
    local stageWidth, stageHeight = math.max(1, self.stage:GetWidth() - 16), math.max(1, self.stage:GetHeight() - 16)
    self.fitZoom = W.Clamp(math.min(stageWidth / width, stageHeight / height), ML.Zoom.min, ML.Zoom.max)
    self.defaultZoom = math.min(1, self.fitZoom)
    local zoom = self:CurrentZoom()
    self.holder:SetScale(zoom)
    -- Offsets on a scaled frame are in its own units.
    self.holder:ClearAllPoints()
    self.holder:SetPoint("CENTER", self.stage, "CENTER", self.panX / zoom, self.panY / zoom)
    self.zoomLabel:SetText(self:ZoomText())
end

local samples = {
    Button = function(widget) if widget.SetText then widget:SetText("Button") end end,
    CheckButton = function(widget) if widget.SetChecked then widget:SetChecked(true) end end,
    EditBox = function(widget) widget:SetText("Sample text"); widget:SetAutoFocus(false); widget:ClearFocus() end,
    Slider = function(widget) widget:SetMinMaxValues(0, 100); widget:SetValue(50) end,
    StatusBar = function(widget) widget:SetMinMaxValues(0, 1); widget:SetValue(0.6) end,
    FontString = function(widget) widget:SetText("The quick brown fox") end,
}

-- Builds the selected template into the stage. Returns the instance or nil, reason.
function Control:Build()
    local entry = self.entry
    if not entry or self.instances[entry.key] then return self.instances[entry and entry.key] end
    if InCombatLockdown and InCombatLockdown() then
        self.message:SetText("Templates can't be built in combat. Try again afterwards.")
        return nil, "combat"
    end
    local tag = entry.tag or "Frame"
    local constructor = ML.RegionTypes[tag]
    local ok, widget
    if constructor then
        ok, widget = pcall(self.holder[constructor], self.holder, nil, "ARTWORK", entry.value)
    else
        ok, widget = pcall(CreateFrame, tag, nil, self.holder, entry.value)
    end
    if not ok or not widget then
        self.message:SetText("The client could not build this template:\n" .. tostring(widget))
        return nil, "failed"
    end
    pcall(function()
        widget:ClearAllPoints()
        widget:SetPoint("CENTER")
        if (widget:GetWidth() or 0) < 1 or (widget:GetHeight() or 0) < 1 then widget:SetSize(160, 26) end
        if samples[tag] then samples[tag](widget) end
        widget:Show()
    end)
    self.instances[entry.key] = widget
    self.build:SetEnabled(false)
    self.message:SetText("")
    self:Layout()
    return widget
end

function Control:Hide()
    for _, instance in pairs(self.instances) do instance:Hide() end
    self.frame:Hide()
end

---------------------------------------------------------------------------
-- Fonts: render editable sample text with the font object.
---------------------------------------------------------------------------
local Font = {}
Font.__index = Font
Previews.font = Font

-- The user's sample (or the default headline), then the glyph and lorem blocks.
function Font.Text(custom)
    local parts = {custom or ML.FontSamples.headline}
    for _, block in ipairs(ML.FontSamples.blocks) do parts[#parts + 1] = block end
    return table.concat(parts, "\n\n")
end

function Font.New(parent)
    local self = setmetatable({}, Font)
    self.frame = baseFrame(parent)
    self.stage = stageFrame(self.frame, 92)
    self.sample = self.stage:CreateFontString(nil, "OVERLAY")
    self.sample:SetPoint("TOPLEFT", 12, -12)
    self.sample:SetPoint("BOTTOMRIGHT", -12, 12)
    self.sample:SetJustifyH("LEFT")
    self.sample:SetJustifyV("TOP")
    self.sample:SetWordWrap(true)
    self.input = W.EditBox(self.frame, 24, "Sample text")
    self.input:SetPoint("BOTTOMLEFT", 0, 62)
    self.input:SetPoint("BOTTOMRIGHT", 0, 62)
    self.input.box:SetScript("OnTextChanged", function(box)
        local text = box:GetText()
        self.input.placeholder:SetShown(text == "")
        view().sample = text ~= "" and text or nil
        self.sample:SetText(Font.Text(view().sample))
    end)
    self.info = W.Label(self.frame, "", 10, T.muted)
    self.info:SetPoint("BOTTOMLEFT", 1, 4)
    self.info:SetPoint("BOTTOMRIGHT", -1, 4)
    self.info:SetHeight(50)
    self.info:SetJustifyV("TOP")
    self.info:SetWordWrap(true)
    return self
end

function Font:Show(entry)
    self.entry = entry
    paintCanvas(self.stage, "Dark")
    local object = ML.Sources.FontObject(entry.value)
    if object then
        self.sample:SetFontObject(object)
        local file, size, flags = object:GetFont()
        self.info:SetText(string.format("File: %s\nSize: %s   Flags: %s", tostring(file or "?"),
            size and string.format("%.1f", size) or "?", (flags and flags ~= "") and flags or "none"))
    else
        self.info:SetText("This font object is not loaded in this client.")
    end
    if self.input.box:GetText() ~= (view().sample or "") then self.input.box:SetText(view().sample or "") end
    self.sample:SetText(Font.Text(view().sample))
    self.frame:Show()
end

function Font:Hide() self.frame:Hide() end
