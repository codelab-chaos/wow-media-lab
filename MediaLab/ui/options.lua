local _, ML = ...

-- The Options card: a checkbox per kind, in tab order, for what loads when
-- the lab opens (ML.db.disabled holds the ones turned off). Everything is on
-- by default. It only records the choice and reports it through onChange(kind,
-- on); the window decides what loading that means. Done calls onDismiss().
local W = ML.Widgets
local T = W.theme
local Options = {}
ML.Options = Options

local WIDTH, PAD, ROW = 360, 16, 24
local CHECK = [[Interface\Buttons\UI-CheckBox-Check]]

-- Whether a kind is on, and turning it on or off.
function Options.IsOn(kind) return ML.IsEnabled(kind) end

function Options.Set(kind, on)
    ML.db.disabled[kind] = (not on) or nil
end

local function checkbox(frame, kind, index, onChange)
    local row = CreateFrame("Button", nil, frame)
    row:SetHeight(ROW)
    row:SetPoint("TOPLEFT", PAD, -(60 + (index - 1) * ROW))
    row:SetPoint("TOPRIGHT", -PAD, -(60 + (index - 1) * ROW))
    row.box = W.Panel(row, T.field)
    row.box:SetSize(16, 16)
    row.box:SetPoint("LEFT")
    row.check = row.box:CreateTexture(nil, "OVERLAY")
    row.check:SetTexture(CHECK)
    row.check:SetSize(20, 20)
    row.check:SetPoint("CENTER")
    row.name = W.Label(row, kind.label, 12, T.text)
    row.name:SetPoint("LEFT", row.box, "RIGHT", 8, 0)
    row.note = W.Label(row, kind.holds or "", 10, T.muted)
    row.note:SetPoint("LEFT", row.box, "RIGHT", 96, 0)
    row.note:SetPoint("RIGHT")
    row:SetHighlightTexture(W.WHITE)
    row:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.04)
    row.kind = kind.id
    row:SetScript("OnClick", function()
        local on = not Options.IsOn(kind.id)
        Options.Set(kind.id, on)
        Options.Render()
        onChange(kind.id, on)
    end)
    return row
end

function Options.Create(parent, onChange, onDismiss)
    local frame = W.Panel(parent, T.window)
    frame:SetFrameStrata("DIALOG")
    frame:SetWidth(WIDTH)
    frame:SetPoint("CENTER")
    frame:EnableMouse(true)
    frame.title = W.Label(frame, "Options", 15, T.accent)
    frame.title:SetPoint("TOPLEFT", PAD, -PAD)
    frame.hint = W.Label(frame, "Load when the lab opens. Fewer means a faster start.", 11, T.muted)
    frame.hint:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -6)
    frame.rows = {}
    for index, kind in ipairs(ML.Kinds) do frame.rows[index] = checkbox(frame, kind, index, onChange) end
    local bottom = 60 + #ML.Kinds * ROW
    frame.footer = W.Label(frame, "", 10, T.muted)
    frame.footer:SetPoint("TOPLEFT", PAD, -(bottom + 8))
    frame.footer:SetPoint("RIGHT", -PAD, 0)
    frame.footer:SetWordWrap(true)
    frame.close = W.Button(frame, "Done", 72, onDismiss, 22)
    frame.close:SetPoint("BOTTOMRIGHT", -PAD, PAD)
    frame:SetHeight(bottom + 8 + 28 + 22 + PAD + 8)
    frame:Hide()
    Options.frame = frame
    return frame
end

function Options.Render()
    local frame = Options.frame
    if not frame then return end
    local waiting = false
    for _, row in ipairs(frame.rows) do
        local on = Options.IsOn(row.kind)
        row.check:SetShown(on)
        row.name:SetTextColor(unpack(on and T.text or T.muted))
        -- Turned off, but already loaded this session: gone after a reload.
        if not on and ML.Catalog.indexed[row.kind] then waiting = true end
    end
    frame.footer:SetText(waiting and "Turning one off takes effect after /reload: the game cannot unload it."
        or "Turning one on loads it now.")
end

function Options.Show()
    Options.Render()
    Options.frame:Show()
end

function Options.Hide() if Options.frame then Options.frame:Hide() end end
function Options.IsShown() return Options.frame ~= nil and Options.frame:IsShown() end
