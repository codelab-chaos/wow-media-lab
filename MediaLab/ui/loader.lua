local _, ML = ...

-- The loading card: whenever a tab has to load a library (icons, models,
-- sounds), one row per library on its way in, with a
-- bar and a count ticking up, a check when it is done, a pulsing beaker and a
-- line of what the lab is doing. Totals come from the last session (ML.db.counts),
-- so bars show real progress from the second open; the first, a moving stripe.
-- It shows what the catalog reports; it does no indexing itself.
local W = ML.Widgets
local T = W.theme
local Loader = {}
ML.Loader = Loader

local ROW, BAR, WIDTH = 34, 6, 440
local FADE = 0.4 -- seconds to fade out once everything is in
local CHECK = "|TInterface\\Buttons\\UI-CheckBox-Check:14:14|t"

local function format(number)
    local text = tostring(math.floor(number))
    while true do
        local changed
        text, changed = text:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
        if changed == 0 then return text end
    end
end
Loader.Format = format

function Loader.Create(parent, onBrowse)
    local frame = W.Panel(parent, T.window)
    frame:SetFrameStrata("DIALOG")
    frame:SetWidth(WIDTH)
    frame:SetPoint("CENTER")
    frame:EnableMouse(true)
    frame.beaker = frame:CreateTexture(nil, "ARTWORK")
    frame.beaker:SetSize(40, 40)
    frame.beaker:SetPoint("TOPLEFT", 16, -16)
    frame.beaker:SetTexture(ML.ICON)
    frame.title = W.Label(frame, "Stocking the lab", 15, T.accent)
    frame.title:SetPoint("TOPLEFT", frame.beaker, "TOPRIGHT", 12, -2)
    frame.line = W.Label(frame, "", 11, T.muted)
    frame.line:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -6)
    frame.line:SetPoint("RIGHT", -16, 0)
    frame.rows = {}
    for index, kindId in ipairs(ML.IndexOrder) do
        local kind = ML.KindById[kindId]
        local row = CreateFrame("Frame", nil, frame)
        row:SetHeight(ROW)
        row.name = W.Label(row, kind.label, 12, T.text)
        row.name:SetPoint("TOPLEFT", 0, 0)
        row.count = W.Label(row, "", 11, T.muted)
        row.count:SetPoint("TOPRIGHT", 0, 0)
        row.count:SetJustifyH("RIGHT")
        row.source = W.Label(row, kind.holds or "", 9, T.muted)
        row.source:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -2)
        row.source:SetPoint("RIGHT", row.count, "LEFT", -8, 0)
        row.track = W.Fill(row, {1, 1, 1, 0.06}, "BORDER")
        row.track:ClearAllPoints()
        row.track:SetPoint("BOTTOMLEFT", 0, 2)
        row.track:SetPoint("BOTTOMRIGHT", 0, 2)
        row.track:SetHeight(BAR)
        row.bar = row:CreateTexture(nil, "ARTWORK")
        row.bar:SetColorTexture(unpack(T.accent))
        row.bar:SetPoint("BOTTOMLEFT", 0, 2)
        row.bar:SetHeight(BAR)
        row.kind = kindId
        frame.rows[index] = row
    end
    frame.kinds = {}
    frame.browse = W.Button(frame, "Browse now", 96, onBrowse, 22)
    frame.browse:SetPoint("BOTTOMRIGHT", -16, 14)
    W.Tip(frame.browse, "Browse now", "Hide this; tabs fill in as they finish.")
    frame.total = W.Label(frame, "", 10, T.muted)
    frame.total:SetPoint("BOTTOMLEFT", 16, 20)
    frame:Hide()
    Loader.frame, Loader.clock = frame, 0
    return frame
end

-- The line under the title: what the lab is busy with, from ML.LoaderLines.
function Loader.Line(kindId)
    local lines = ML.LoaderLines[kindId] or ML.LoaderLines.default
    return lines[math.floor(Loader.clock / 2.2) % #lines + 1]
end

-- counts: {kind = entries so far}; current: the kind being indexed (nil when done).
function Loader.Render(counts, current, done)
    local frame = Loader.frame
    if not frame then return end
    local width, total = frame.rows[1]:GetWidth() or 0, 0
    for _, row in ipairs(frame.rows) do
        local count, expected = counts[row.kind] or 0, ML.db.counts and ML.db.counts[row.kind]
        total = total + count
        local finished = done[row.kind]
        local fraction = finished and 1 or (expected and expected > 0 and math.min(0.98, count / expected)) or nil
        row.fraction = fraction
        row.count:SetText(finished and (CHECK .. " " .. format(count))
            or expected and (format(count) .. " / " .. format(expected)) or format(count))
        row.name:SetTextColor(unpack((finished or row.kind == current) and T.accent or T.text))
        if fraction then
            row.bar:SetWidth(math.max(1, width * fraction))
            row.bar:SetAlpha(1)
        elseif row.kind ~= current then
            row.bar:SetWidth(1)
            row.bar:SetAlpha(0)
        end
    end
    frame.total:SetText(format(total) .. " entries so far")
    frame.current = current
    frame.line:SetText(current and Loader.Line(current) or "All in. Enjoy the lab.")
end

-- The beaker pulses; a library of unknown size gets a moving stripe; once
-- everything is in, the card fades out.
function Loader.Animate(elapsed)
    local frame = Loader.frame
    Loader.clock = Loader.clock + (elapsed or 0)
    frame.beaker:SetAlpha(0.65 + 0.35 * math.abs(math.sin(Loader.clock * 2.4)))
    for _, row in ipairs(frame.rows) do
        if row.kind == frame.current and not row.fraction then
            local width = row:GetWidth() or 0
            local phase = (Loader.clock * 0.7) % 1
            row.bar:SetAlpha(1)
            row.bar:SetWidth(math.max(1, width * 0.25))
            row.bar:ClearAllPoints()
            row.bar:SetPoint("BOTTOMLEFT", width * 0.75 * phase, 2)
        elseif row.fraction then
            row.bar:ClearAllPoints()
            row.bar:SetPoint("BOTTOMLEFT", 0, 2)
        end
    end
    if frame.fading then
        frame.fading = frame.fading - (elapsed or 0)
        frame:SetAlpha(math.max(0, frame.fading / FADE))
        if frame.fading <= 0 then Loader.Hide() end
    end
end

-- The kinds on the card, in ML.IndexOrder.
function Loader.Kinds() return Loader.frame and Loader.frame.kinds or {} end

-- Stacks the rows of the kinds on the card and sizes the card to fit.
function Loader.Layout()
    local frame, shown = Loader.frame, {}
    for _, kind in ipairs(frame.kinds) do shown[kind] = true end
    local index = 0
    for _, row in ipairs(frame.rows) do
        row:SetShown(shown[row.kind] == true)
        if shown[row.kind] then
            local y = -72 - index * ROW
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 16, y)
            row:SetPoint("TOPRIGHT", -16, y)
            index = index + 1
        end
    end
    frame:SetHeight(72 + index * ROW + 52)
end

-- Shows the card for these kinds (every kind when none are given). While it
-- is up, more kinds join it; once it has faded, it starts over with the new ones.
-- The animation runs only while the card is up.
function Loader.Show(kinds)
    local frame = Loader.frame
    local fresh = not frame:IsShown() or frame.fading
    if fresh then frame.kinds = {} end
    local wanted = {}
    for _, kind in ipairs(frame.kinds) do wanted[kind] = true end
    for _, kind in ipairs(kinds or ML.IndexOrder) do wanted[kind] = true end
    frame.kinds = {}
    for _, kind in ipairs(ML.IndexOrder) do if wanted[kind] then frame.kinds[#frame.kinds + 1] = kind end end
    Loader.Layout()
    frame.fading = nil
    frame:SetAlpha(1)
    frame:Show()
    frame:SetScript("OnUpdate", function(_, elapsed) Loader.Animate(elapsed) end)
end

function Loader.Finish() if Loader.frame and Loader.frame:IsShown() then Loader.frame.fading = FADE end end
function Loader.Hide()
    local frame = Loader.frame
    if not frame then return end
    frame.fading = nil
    frame:SetScript("OnUpdate", nil)
    frame:Hide()
end
function Loader.IsShown() return Loader.frame ~= nil and Loader.frame:IsShown() end
