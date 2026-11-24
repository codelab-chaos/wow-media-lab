local _, ML = ...

-- Plain, flat building blocks shared by every panel. No layout decisions here.
local W = {}
ML.Widgets = W

local WHITE = [[Interface\Buttons\WHITE8X8]]
W.WHITE = WHITE
W.theme = {
    text = {0.86, 0.89, 0.92},
    muted = {0.55, 0.60, 0.66},
    accent = {0.62, 0.78, 0.91},
    window = {0.06, 0.07, 0.085, 0.97},
    panel = {0.085, 0.10, 0.12, 1},
    field = {0.035, 0.042, 0.052, 1},
    border = {0.22, 0.25, 0.29, 1},
    button = {0.13, 0.15, 0.18, 1},
    selected = {0.62, 0.78, 0.91, 1},
    active = {0.80, 0.92, 1.00, 1}, -- something in effect: a search, a filter
}
local T = W.theme

function W.Label(parent, text, size, color)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(STANDARD_TEXT_FONT, size or 12, "")
    fs:SetTextColor(unpack(color or T.text))
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    fs:SetText(text or "")
    return fs
end

function W.Fill(parent, color, layer)
    local texture = parent:CreateTexture(nil, layer or "BACKGROUND")
    texture:SetAllPoints()
    texture:SetColorTexture(unpack(color))
    return texture
end

function W.Panel(parent, color, name)
    local frame = CreateFrame("Frame", name, parent, "BackdropTemplate")
    frame:SetBackdrop({bgFile = WHITE, edgeFile = WHITE, edgeSize = 1})
    frame:SetBackdropColor(unpack(color or T.panel))
    frame:SetBackdropBorderColor(unpack(T.border))
    return frame
end

function W.Tip(frame, title, body)
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(title, unpack(T.accent))
        if body then GameTooltip:AddLine(body, 0.85, 0.87, 0.9, true) end
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

function W.Button(parent, text, width, onClick, height)
    local frame = CreateFrame("Button", nil, parent, "BackdropTemplate")
    frame:SetSize(width or 80, height or 22)
    frame:SetBackdrop({bgFile = WHITE, edgeFile = WHITE, edgeSize = 1})
    frame:SetBackdropColor(unpack(T.button))
    frame:SetBackdropBorderColor(unpack(T.border))
    frame.text = W.Label(frame, text, 11)
    frame.text:SetPoint("CENTER")
    frame:SetHighlightTexture(WHITE)
    frame:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.06)
    frame:SetScript("OnClick", onClick)
    frame:SetScript("OnEnable", function(self) self:SetAlpha(1) end)
    frame:SetScript("OnDisable", function(self) self:SetAlpha(0.35) end)
    function frame:SetLabel(value) self.text:SetText(value) end
    function frame:SetActive(active)
        self.active = active and true or false
        self:SetBackdropBorderColor(unpack(active and T.selected or T.border))
        self.text:SetTextColor(unpack(active and T.accent or T.text))
    end
    return frame
end

function W.EditBox(parent, height, placeholder)
    local holder = W.Panel(parent, T.field)
    holder:SetHeight(height or 24)
    local box = CreateFrame("EditBox", nil, holder)
    box:SetPoint("TOPLEFT", 7, -3)
    box:SetPoint("BOTTOMRIGHT", -7, 3)
    box:SetFont(STANDARD_TEXT_FONT, 12, "")
    box:SetTextColor(unpack(T.text))
    box:SetAutoFocus(false)
    box:SetMaxLetters(512)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    holder.box = box
    if placeholder then
        holder.placeholder = W.Label(holder, placeholder, 11, T.muted)
        holder.placeholder:SetPoint("LEFT", 8, 0)
    end
    return holder
end

-- A soft outline just outside a frame that pulses while on: says "this is
-- in effect". The pulse is an animation group, so it costs no Lua per frame.
function W.Glow(frame, color)
    local glow = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    glow:SetPoint("TOPLEFT", -2, 2)
    glow:SetPoint("BOTTOMRIGHT", 2, -2)
    glow:SetBackdrop({edgeFile = WHITE, edgeSize = 2})
    glow:SetBackdropBorderColor(unpack(color or T.active))
    glow:EnableMouse(false)
    local pulse = glow:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    local fade = pulse:CreateAnimation("Alpha")
    fade:SetFromAlpha(0.9)
    fade:SetToAlpha(0.25)
    fade:SetDuration(0.9)
    fade:SetSmoothing("IN_OUT")
    glow.pulse = pulse
    function glow:SetOn(on)
        self:SetShown(on)
        if on and not self.pulse:IsPlaying() then self.pulse:Play() elseif not on then self.pulse:Stop() end
    end
    glow:Hide()
    return glow
end

-- A read-only, selectable text field. Clicking selects everything so Ctrl+C
-- copies it; typing is undone. WoW gives addons no clipboard API of their own.
function W.CopyField(parent, onCopy)
    local holder = W.Panel(parent, T.field)
    holder:SetHeight(24)
    holder.caption = W.Label(parent, "", 10, T.muted)
    holder.caption:SetPoint("BOTTOMLEFT", holder, "TOPLEFT", 1, 2)
    local box = CreateFrame("EditBox", nil, holder)
    box:SetPoint("TOPLEFT", 7, -4)
    box:SetPoint("BOTTOMRIGHT", -44, 4)
    box:SetFont(STANDARD_TEXT_FONT, 11, "")
    box:SetTextColor(unpack(T.text))
    box:SetAutoFocus(false)
    box:SetMaxLetters(0)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEditFocusGained", function(self)
        self:HighlightText()
        if onCopy then onCopy(holder) end
    end)
    box:SetScript("OnEditFocusLost", function(self) self:HighlightText(0, 0) end)
    box:SetScript("OnTextChanged", function(self, userInput)
        if userInput then self:SetText(holder.value or ""); self:HighlightText() end
    end)
    box:SetScript("OnMouseUp", function(self) self:HighlightText() end)
    holder.box = box
    holder.copy = W.Button(holder, "Copy", 38, function() box:SetFocus() end, 18)
    holder.copy:SetPoint("RIGHT", -3, 0)
    W.Tip(holder.copy, "Copy", "Selects the text. Press Ctrl+C to copy it.")
    function holder:SetField(caption, value, lines)
        self.value = value or ""
        self.caption:SetText(caption or "")
        local multi = (lines or 1) > 1
        box:SetMultiLine(multi)
        self:SetHeight(multi and (10 + 14 * lines) or 24)
        box:SetText(self.value)
        box:SetCursorPosition(0)
    end
    return holder
end

function W.Clamp(value, low, high) return math.max(low, math.min(high, value)) end
