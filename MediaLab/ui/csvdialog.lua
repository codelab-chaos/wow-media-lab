local _, ML = ...

-- A small popup holding the current results as CSV, ready for Ctrl+C.
-- Built on first use; it only displays text that ML.Export produced.
local W = ML.Widgets
local T = W.theme
local Dialog = {}
ML.CsvDialog = Dialog

local function create(parent)
    local frame = W.Panel(parent, T.window)
    frame:SetSize(560, 360)
    frame:SetPoint("CENTER")
    frame:SetFrameLevel(parent:GetFrameLevel() + 50)
    frame:EnableMouse(true)
    frame.title = W.Label(frame, "Copy as CSV", 13, T.accent)
    frame.title:SetPoint("TOPLEFT", 12, -10)
    local close = W.Button(frame, "x", 24, function() frame:Hide() end, 22)
    close:SetPoint("TOPRIGHT", -6, -6)
    frame.note = W.Label(frame, "", 10, T.muted)
    frame.note:SetPoint("BOTTOMLEFT", 12, 10)
    frame.note:SetPoint("BOTTOMRIGHT", -12, 10)
    frame.field = W.CopyField(frame)
    frame.field:SetPoint("TOPLEFT", 12, -52)
    frame.field:SetPoint("TOPRIGHT", -12, -52)
    frame.field:SetClipsChildren(true)
    return frame
end

function Dialog.Show(parent, entries)
    Dialog.frame = Dialog.frame or create(parent)
    local text, shown, total = ML.Export.Csv(entries)
    local frame = Dialog.frame
    frame.field:SetField(string.format("%d rows", shown), text, 18)
    frame.note:SetText(shown < total
        and string.format("First %d of %d results. Narrow the search or use /mlab export for everything.", shown, total)
        or "Click the text or Copy, then press Ctrl+C.")
    frame:Show()
    return frame
end
