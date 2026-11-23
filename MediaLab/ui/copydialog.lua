local _, ML = ...

-- A small popup holding a set of entries as text, ready for Ctrl+C, in one of
-- the ML.CopyFormats (a Lua table or CSV). Built on first use; it only shows
-- text that ML.Export produced.
local W = ML.Widgets
local T = W.theme
local Dialog = {}
ML.CopyDialog = Dialog

local function create(parent)
    local frame = W.Panel(parent, T.window)
    frame:SetSize(560, 380)
    frame:SetPoint("CENTER")
    frame:SetFrameLevel(parent:GetFrameLevel() + 50)
    frame:EnableMouse(true)
    frame.title = W.Label(frame, "Copy", 13, T.accent)
    frame.title:SetPoint("TOPLEFT", 12, -10)
    frame.title:SetPoint("RIGHT", -150, 0)
    local close = W.Button(frame, "x", 24, function() frame:Hide() end, 22)
    close:SetPoint("TOPRIGHT", -6, -6)
    frame.formats = {}
    local previous = close
    for index = #ML.CopyFormats, 1, -1 do
        local format = ML.CopyFormats[index]
        local button = W.Button(frame, format.label, 44, function() Dialog.SetFormat(format.id) end, 22)
        button:SetPoint("RIGHT", previous, "LEFT", -6, 0)
        W.Tip(button, format.label, format.hint)
        button.format = format.id
        frame.formats[index] = button -- in ML.CopyFormats order
        previous = button
    end
    frame.note = W.Label(frame, "", 10, T.muted)
    frame.note:SetPoint("BOTTOMLEFT", 12, 10)
    frame.note:SetPoint("BOTTOMRIGHT", -12, 10)
    frame.field = W.CopyField(frame)
    frame.field:SetPoint("TOPLEFT", 12, -52)
    frame.field:SetPoint("TOPRIGHT", -12, -52)
    frame.field:SetClipsChildren(true)
    return frame
end

function Dialog.Render()
    local frame, request = Dialog.frame, Dialog.request
    local text, shown, total = ML.Export.Format(request.format, request.entries, request.name)
    frame.title:SetText("Copy " .. (request.name or "results"))
    frame.field:SetField(string.format("%d %s", shown, shown == 1 and "entry" or "entries"), text, 19)
    frame.note:SetText(shown < total
        and string.format("First %d of %d. Narrow the search to copy the rest.", shown, total)
        or "Click the text or Copy, then press Ctrl+C.")
    for _, button in ipairs(frame.formats) do button:SetActive(button.format == request.format) end
end

function Dialog.SetFormat(format)
    if not Dialog.request then return end
    Dialog.request.format = format
    ML.db.view.copyFormat = format
    Dialog.Render()
end

-- request: {entries, name (shown and used for the Lua table), format}
function Dialog.Show(parent, request)
    Dialog.frame = Dialog.frame or create(parent)
    request.format = request.format or ML.db.view.copyFormat or ML.CopyFormats[1].id
    Dialog.request = request
    Dialog.Render()
    Dialog.frame:Show()
    return Dialog.frame
end
