local _, ML = ...

-- A small popup that asks for one line of text (a list name). Enter or OK
-- accepts, Escape or x cancels. onAccept(text) returns nil on success, or a
-- message to show and keep the prompt open.
local W = ML.Widgets
local T = W.theme
local Prompt = {}
ML.Prompt = Prompt

local function create(parent)
    local frame = W.Panel(parent, T.window)
    frame:SetSize(300, 116)
    frame:SetPoint("CENTER")
    frame:SetFrameLevel(parent:GetFrameLevel() + 60)
    frame:EnableMouse(true)
    frame.title = W.Label(frame, "", 13, T.accent)
    frame.title:SetPoint("TOPLEFT", 12, -10)
    local close = W.Button(frame, "x", 24, function() frame:Hide() end, 22)
    close:SetPoint("TOPRIGHT", -6, -6)
    frame.input = W.EditBox(frame, 24)
    frame.input:SetPoint("TOPLEFT", 12, -40)
    frame.input:SetPoint("TOPRIGHT", -12, -40)
    frame.input.box:SetMaxLetters(ML.Lists.MAX_NAME)
    frame.input.box:SetScript("OnEnterPressed", function() Prompt.Accept() end)
    frame.input.box:SetScript("OnEscapePressed", function() frame:Hide() end)
    frame.message = W.Label(frame, "", 10, T.muted)
    frame.message:SetPoint("BOTTOMLEFT", 12, 14)
    frame.message:SetPoint("RIGHT", -84, 0)
    frame.accept = W.Button(frame, "OK", 64, function() Prompt.Accept() end, 22)
    frame.accept:SetPoint("BOTTOMRIGHT", -12, 10)
    frame:SetScript("OnHide", function() frame.input.box:ClearFocus() end)
    return frame
end

function Prompt.Accept()
    local frame, request = Prompt.frame, Prompt.request
    if not request then return end
    local problem = request.onAccept(frame.input.box:GetText())
    if problem then
        frame.message:SetText(problem)
        return
    end
    Prompt.request = nil
    frame:Hide()
end

-- request: {title, text (starting value), button, hint, onAccept(text)}
function Prompt.Show(parent, request)
    Prompt.frame = Prompt.frame or create(parent)
    local frame = Prompt.frame
    Prompt.request = request
    frame.title:SetText(request.title)
    frame.accept:SetLabel(request.button or "OK")
    frame.message:SetText(request.hint or "")
    frame.input.box:SetText(request.text or "")
    frame:Show()
    frame.input.box:SetFocus()
    frame.input.box:HighlightText()
    return frame
end
