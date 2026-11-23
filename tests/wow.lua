-- Strict, small UI/API stand-in. It checks Lua integration, not WoW rendering:
-- only methods listed here exist, so a misspelled API call fails loudly.
local Mock = {}
local methods = {}

local function object(kind, name, parent, template)
    local obj = setmetatable({kind = kind, name = name, parent = parent, template = template, scripts = {},
        points = {}, shown = true, text = ""}, {__index = methods})
    Mock.frames[#Mock.frames + 1] = obj
    if name then _G[name] = obj end
    return obj
end
Mock.object = object

local anchors = {
    TOPLEFT = {0, 1}, TOP = {0.5, 1}, TOPRIGHT = {1, 1}, LEFT = {0, 0.5}, CENTER = {0.5, 0.5},
    RIGHT = {1, 0.5}, BOTTOMLEFT = {0, 0}, BOTTOM = {0.5, 0}, BOTTOMRIGHT = {1, 0},
}

function methods:SetPoint(point, relative, relativePoint, x, y)
    if type(relative) == "number" then x, y, relative, relativePoint = relative, relativePoint, self.parent, point
    elseif relative == nil then relative, relativePoint = self.parent, point end
    if type(relative) == "string" then relative = _G[relative] end
    relativePoint = relativePoint or point
    assert(anchors[point] and anchors[relativePoint], "invalid anchor " .. tostring(point))
    self.points[point] = {relative or UIParent, relativePoint, x or 0, y or 0}
    self.firstPoint = self.firstPoint or point
end

-- Resolves one axis from anchors (enough for two-point stretching).
local function axis(self, index, depth)
    assert((depth or 0) < 60, "anchor loop")
    local size = index == 1 and self.width or self.height
    local firstFactor, firstTarget
    for point, data in pairs(self.points) do
        local factor = anchors[point][index]
        local position, relativeSize = axis(data[1], index, (depth or 0) + 1)
        local target = position + anchors[data[2]][index] * relativeSize + data[index + 2]
        if firstFactor and firstFactor ~= factor then
            local resolved = (target - firstTarget) / (factor - firstFactor)
            return firstTarget - firstFactor * resolved, resolved
        end
        firstFactor, firstTarget = factor, target
    end
    size = size or (self.kind == "FontString" and (index == 1 and #self.text * 6 or 14) or 0)
    return firstTarget and firstTarget - firstFactor * size or 0, size
end

function methods:GetWidth() local _, size = axis(self, 1); return size end
function methods:GetHeight() local _, size = axis(self, 2); return size end
function methods:GetLeft() return (axis(self, 1)) end
function methods:GetTop() local bottom, size = axis(self, 2); return bottom + size end
function methods:GetSize() return self:GetWidth(), self:GetHeight() end
local function sized(self)
    if self.scripts.OnSizeChanged then self.scripts.OnSizeChanged(self, self.width, self.height) end
end
function methods:SetWidth(value) self.width = value; sized(self) end
function methods:SetHeight(value) self.height = value; sized(self) end
function methods:SetSize(width, height) self.width, self.height = width, height; sized(self) end
function methods:GetPoint()
    local point = self.firstPoint
    if point then return point, unpack(self.points[point]) end
end
function methods:ClearAllPoints() self.points, self.firstPoint = {}, nil end
function methods:SetAllPoints(relative)
    self:ClearAllPoints()
    self:SetPoint("TOPLEFT", relative or self.parent, "TOPLEFT", 0, 0)
    self:SetPoint("BOTTOMRIGHT", relative or self.parent, "BOTTOMRIGHT", 0, 0)
end
function methods:SetScript(name, callback) self.scripts[name] = callback end
function methods:GetScript(name) return self.scripts[name] end
function methods:RegisterEvent(name) self.events = self.events or {}; self.events[name] = true end
function methods:UnregisterEvent(name) self.events[name] = nil end
function methods:Show() self.shown = true end
function methods:Hide()
    if not self.shown then return end
    self.shown = false
    if self.scripts.OnHide then self.scripts.OnHide(self) end
end
function methods:IsShown() return self.shown and (not self.parent or self.parent:IsShown()) end
function methods:SetShown(value) if value then self:Show() else self:Hide() end end
function methods:SetEnabled(value) self.enabled = value and true or false end
function methods:IsEnabled() return self.enabled ~= false end
function methods:Enable() self:SetEnabled(true) end
function methods:Disable() self:SetEnabled(false) end
function methods:CreateTexture(name, _, template) return object("Texture", name, self, template) end
function methods:CreateFontString(name, _, template) return object("FontString", name, self, template) end
function methods:CreateLine(name, _, template) return object("Line", name, self, template) end
function methods:SetText(value)
    self.text = tostring(value or "")
    if self.scripts.OnTextChanged then self.scripts.OnTextChanged(self, false) end
end
function methods:Type(value)
    self.text = value
    if self.scripts.OnTextChanged then self.scripts.OnTextChanged(self, true) end
end
function methods:GetText() return self.text end
function methods:GetStringHeight()
    local _, lines = tostring(self.text or ""):gsub("\n", "")
    return (lines + 1) * 14
end
function methods:SetFocus() self.focus = true; if self.scripts.OnEditFocusGained then self.scripts.OnEditFocusGained(self) end end
function methods:ClearFocus()
    if not self.focus then return end
    self.focus = false
    if self.scripts.OnEditFocusLost then self.scripts.OnEditFocusLost(self) end
end
function methods:SetTexture(value)
    self.texture, self.atlas = value, nil
    return value ~= nil and not tostring(value):find("missing", 1, true)
end
function methods:SetAtlas(value)
    assert(C_Texture.GetAtlasInfo(value), "SetAtlas with an unknown atlas")
    self.atlas, self.texture = value, nil
end
function methods:SetColorTexture(...) self.color = {...} end
function methods:SetFontObject(value) self.fontObject = value end
function methods:SetMultiLine(value) self.multiLine = value end
function methods:SetMinMaxValues(low, high) self.minValue, self.maxValue = low, high end
function methods:SetValue(value) self.value = value end
function methods:SetChecked(value) self.checked = value end
function methods:SetBackdrop(value) self.backdrop = value end
function methods:SetResizeBounds(...) self.bounds = {...} end
function methods:SetHighlightTexture(value) self.highlight = object("Texture", nil, self); self.highlight:SetTexture(value) end
function methods:GetHighlightTexture() return self.highlight end
function methods:GetEffectiveScale() return 1 end
function methods:SetFrameLevel(value) self.frameLevel = value end
function methods:SetScale(value) self.scale = value end
function methods:GetFrameLevel() return self.frameLevel or 1 end
function methods:AddMessage(value) Mock.messages[#Mock.messages + 1] = value end
-- PlayerModel: SetUnit loads Mock.target's display and model file.
function methods:SetDisplayInfo(id) self.displayInfo = id end
function methods:GetDisplayInfo() return self.displayInfo end
function methods:SetUnit(unit)
    local target = unit == "target" and Mock.target
    self.displayInfo, self.modelFile = target and target.display, target and target.model
end
function methods:GetModelFileID() return self.modelFile end
function methods:ClearModel() self.displayInfo, self.modelFile = nil, nil end
function methods:SetFacing(value) self.facing = value end
function methods:SetCamDistanceScale(value) self.camDistance = value end
function methods:SetAnimation(value) self.animationId = value end
function methods:HasAnimation(id) return id == 0 or id == 4 or id == 1 end
function methods:EnableMouse(value) self.mouse = value and true or false end

for _, name in ipairs({
    "SetFont", "SetTextColor", "SetJustifyH", "SetJustifyV", "SetWordWrap", "SetBackdropColor",
    "SetBackdropBorderColor", "SetAutoFocus", "SetMaxLetters", "HighlightText", "SetCursorPosition",
    "EnableMouse", "EnableMouseWheel", "RegisterForClicks", "RegisterForDrag", "SetClipsChildren",
    "SetFrameStrata", "SetClampedToScreen", "SetMovable", "SetResizable", "SetScale", "StartMoving",
    "StartSizing", "StopMovingOrSizing", "SetNormalTexture", "SetOwner", "AddLine", "SetTexCoord",
    "SetVertexColor", "SetAlpha",
}) do methods[name] = methods[name] or function() end end

local function font(name, size)
    _G[name] = {GetFont = function() return "Fonts\\FRIZQT__.TTF", size, "" end}
end

function Mock.install()
    Mock.frames, Mock.timers, Mock.messages, Mock.sounds, Mock.stopped = {}, {}, {}, {}, {}
    Mock.combat = false
    UIParent = object("Frame", "UIParent")
    UIParent:SetSize(1920, 1080)
    STANDARD_TEXT_FONT = "test-font"
    UISpecialFrames, SlashCmdList = {}, {}
    DEFAULT_CHAT_FRAME = object("Frame")
    GameTooltip = object("Frame")
    tinsert = table.insert
    CreateFrame = function(kind, name, parent, template)
        if template == "BrokenTemplate" then error("template failed") end
        return object(kind, name, parent, template)
    end
    C_Timer = {NewTimer = function(_, callback)
        local timer = {callback = callback, Cancel = function(self) self.cancelled = true end}
        Mock.timers[#Mock.timers + 1] = timer
        return timer
    end}
    C_Timer.After = function(delay, callback) C_Timer.NewTimer(delay, callback) end
    strsplit = function(separator, text)
        local parts = {}
        for part in (text .. separator):gmatch("(.-)" .. separator:gsub("%p", "%%%0")) do parts[#parts + 1] = part end
        return unpack(parts)
    end
    -- Mock.target = {name, guid, display, model, player}
    Mock.target = nil
    UnitExists = function(unit) return unit == "target" and Mock.target ~= nil end
    UnitIsPlayer = function(unit) return unit == "target" and Mock.target and Mock.target.player or false end
    UnitGUID = function(unit) return unit == "target" and Mock.target and Mock.target.guid or nil end
    UnitName = function(unit) return unit == "target" and Mock.target and Mock.target.name or nil end
    GetCursorPosition = function() return Mock.cursorX or 0, Mock.cursorY or 0 end
    IsShiftKeyDown = function() return Mock.shift == true end
    IsControlKeyDown = function() return Mock.ctrl == true end
    InCombatLockdown = function() return Mock.combat end
    C_Texture = {
        GetAtlasElements = function() return {"test-background", "test-glow", "common-icon-checkmark"} end,
        GetAtlasInfo = function(name)
            if name == "test-background" or name == "test-glow" or name == "common-icon-checkmark" then
                return {width = 256, height = 128, file = 12345}
            end
        end,
    }
    C_XMLUtil = {
        GetTemplates = function()
            return {
                {name = "UIPanelButtonTemplate", type = "Button"},
                {name = "UICheckButtonTemplate", type = "CheckButton"},
                {name = "InputBoxTemplate", type = "EditBox"},
                {name = "GameFontNormalTemplate", type = "FontString"},
                {name = "TestAnimTemplate", type = "AnimationGroup"},
                {name = "BrokenTemplate", type = "Frame"},
                {name = "GameFontNormal", type = "Font"},
            }
        end,
        GetTemplateInfo = function(name)
            if name == "UIPanelButtonTemplate" then
                return {type = "Button", width = 120, height = 22, keyValues = {}, sourceLocation = "SharedUIPanelTemplates.xml:10"}
            end
        end,
    }
    SOUNDKIT = {IG_MAINMENU_OPEN = 850, IG_MAINMENU_CLOSE = 851, UI_TEST_ONLY_RUNTIME = 99999}
    PlaySound = function(id, channel)
        Mock.sounds[#Mock.sounds + 1] = {id = id, channel = channel}
        return id ~= 404, #Mock.sounds
    end
    StopSound = function(handle) Mock.stopped[#Mock.stopped + 1] = handle end
    GetMacroIcons = function(values) values[#values + 1] = 134400; values[#values + 1] = "INV_Misc_Map_01" end
    GetMacroItemIcons = function(values) values[#values + 1] = "134400"; values[#values + 1] = "Interface\\Icons\\INV_Sword_04" end
    GetLooseMacroIcons, GetLooseMacroItemIcons = nil, nil
    font("GameFontNormal", 12); font("GameFontHighlight", 12); font("SystemFont_Large", 16)
    GetFonts = function() return {"GameFontNormal", "SystemFont_Large", "NotLoadedFont"} end
    GetBuildInfo = function() return "1.60.1", "70888", "Nov 1 2026", 16001 end
    time = os.time
    Mock.loaded = {}
    Mock.iconMeta = {
        [134400] = "inv_misc_questionmark\tred,gray\tsymbol\tquestion mark,unknown,help\tA red question mark.",
        [135274] = "inv_sword_04\tgray\tweapon\tsword,blade,melee\tA steel longsword.",
    }
    Mock.soundKits = {
        [850] = "uescapescreenopen\tInterface\t\tIG_MAINMENU_OPEN\t1",
        [417] = "mmurlocattack\tCreature\tmurloc\t\t3",
        [418] = "mmurlocwound\tCreature\tmurloc\t\t3",
        [20000] = "elwynn day_forest\tMusic\telwynn\t\t4",
    }
    Mock.models = {
        [1693] = "murloc blue\tCreature\tmurloc\t123456\tmurlocskinblue",
        [1694] = "murloc green\tCreature\tmurloc\t123456\tmurlocskingreen",
        [4611] = "orc male\tHumanoid NPC\torc\t1968587\t",
    }
    C_AddOns = {
        LoadAddOn = function(name)
            Mock.loaded[name] = true
            if name == "MediaLab_Icons" then MediaLabIconMeta = Mock.iconMeta end
            if name == "MediaLab_Models" then MediaLabModels = Mock.models end
            if name == "MediaLab_Sounds" then MediaLabSounds = Mock.soundKits end
            return true
        end,
        GetAddOnMetadata = function(_, field) return field == "Version" and "0.1.0" or nil end,
    }
    MediaLabDB = nil
end

function Mock.load(saved)
    Mock.install()
    MediaLabDB = saved
    local ML = {}
    for line in io.lines("MediaLab/MediaLab.toc") do
        if line ~= "" and not line:match("^#") then
            assert(loadfile("MediaLab/" .. line:gsub("\\", "/")))("MediaLab", ML)
        end
    end
    for _, frame in ipairs(Mock.frames) do
        if frame.events and frame.events.ADDON_LOADED then frame.scripts.OnEvent(frame, "ADDON_LOADED", "MediaLab") end
    end
    return ML
end

function Mock.flush()
    for _ = 1, 5000 do
        local pending = false
        for _, frame in ipairs(Mock.frames) do
            if frame.scripts.OnUpdate and frame ~= Mock.skipUpdate then frame.scripts.OnUpdate(frame, 1 / 60); pending = true end
        end
        for _, timer in ipairs(Mock.timers) do
            if not timer.cancelled and not timer.done then timer.done = true; timer.callback(); pending = true end
        end
        if not pending then return end
    end
    error("work did not settle")
end

return Mock
