local _, ML = ...

-- The results area: renders a slice of entries as a thumbnail grid or a list,
-- reusing a small pool of cells. It reports clicks; it does not own state.
local W = ML.Widgets
local T = W.theme
local Browser = {}
Browser.__index = Browser
ML.Browser = Browser

local GAP, ROW = 6, 22
-- The scrollbar's width plus its gap from the cells.
local BAR, BAR_GAP, MIN_THUMB = 8, 6, 24

-- handlers: onSelect(entry, modifiers) ({ctrl, shift}), onMenu(entry, cell)
-- (right-click), onPlay(entry), onChanged(), isSelected(entry), onZoom(delta)
-- (Ctrl+wheel on a grid)
function Browser.New(parent, handlers)
    local self = setmetatable({handlers = handlers, offset = 0, results = {}, cells = {}, rows = {}}, Browser)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetClipsChildren(true)
    frame:EnableMouseWheel(true)
    -- Ctrl+wheel zooms a thumbnail grid; the wheel alone scrolls.
    frame:SetScript("OnMouseWheel", function(_, delta)
        if IsControlKeyDown() and self.layout and self.layout.mode == "grid" and self.handlers.onZoom then
            return self.handlers.onZoom(delta)
        end
        self:Scroll(-delta * self:Step())
    end)
    frame:SetScript("OnSizeChanged", function() self:Render() end)
    self.frame = frame
    self.empty = W.Label(frame, "", 12, T.muted)
    self.empty:SetPoint("CENTER")
    self.empty:SetJustifyH("CENTER")
    self.empty:SetWordWrap(true)
    self.empty:SetWidth(320)
    self:CreateScrollbar()
    return self
end

-- A thin track on the right: the thumb shows where the page is and how much of
-- the list it covers. Drag the thumb, or click the track to page.
function Browser:CreateScrollbar()
    local track = CreateFrame("Button", nil, self.frame)
    track:SetPoint("TOPRIGHT", 0, 0)
    track:SetPoint("BOTTOMRIGHT", 0, 0)
    track:SetWidth(BAR)
    track:RegisterForClicks("LeftButtonUp")
    W.Fill(track, {1, 1, 1, 0.04})
    track:SetScript("OnClick", function()
        local _, y = GetCursorPosition()
        local scale = track:GetEffectiveScale()
        local thumbTop = self.thumb:GetTop() or 0
        self:Page(y / scale > thumbTop and -1 or 1)
    end)
    local thumb = CreateFrame("Button", nil, track)
    thumb:SetWidth(BAR)
    thumb.fill = W.Fill(thumb, T.border)
    thumb:SetScript("OnEnter", function() thumb.fill:SetColorTexture(unpack(T.accent)) end)
    thumb:SetScript("OnLeave", function() if not self.dragging then thumb.fill:SetColorTexture(unpack(T.border)) end end)
    thumb:SetScript("OnMouseDown", function()
        local _, y = GetCursorPosition()
        self.dragging = {y = y / thumb:GetEffectiveScale(), row = self:FirstRow()}
        thumb:SetScript("OnUpdate", function() self:DragThumb() end)
    end)
    thumb:SetScript("OnMouseUp", function()
        self.dragging = nil
        thumb:SetScript("OnUpdate", nil)
        thumb.fill:SetColorTexture(unpack(T.border))
    end)
    self.track, self.thumb = track, thumb
end

function Browser:FirstRow()
    local columns = self:Geometry()
    return math.floor(self.offset / columns)
end

-- Rows in the list, rows that fit, and the furthest first row.
function Browser:RowSpan()
    local columns, rows = self:Geometry()
    local total = math.ceil(#self.results / columns)
    return total, rows, math.max(0, total - rows)
end

function Browser:DragThumb()
    if not self.dragging then return end
    local _, y = GetCursorPosition()
    local total, _, maxRow = self:RowSpan()
    local travel = self.track:GetHeight() - self.thumb:GetHeight()
    if travel <= 0 or maxRow == 0 then return end
    local moved = self.dragging.y - y / self.thumb:GetEffectiveScale()
    local row = W.Clamp(math.floor(self.dragging.row + moved / travel * maxRow + 0.5), 0, maxRow)
    local columns = self:Geometry()
    if row * columns ~= self.offset then
        self.offset = row * columns
        self:Render()
    end
end

function Browser:UpdateScrollbar()
    local total, rows, maxRow = self:RowSpan()
    local show = total > rows
    self.track:SetShown(show)
    if not show then return end
    local height = self.track:GetHeight()
    local thumbHeight = math.max(MIN_THUMB, height * rows / total)
    local y = maxRow > 0 and (height - thumbHeight) * self:FirstRow() / maxRow or 0
    self.thumb:SetHeight(thumbHeight)
    self.thumb:ClearAllPoints()
    self.thumb:SetPoint("TOPLEFT", self.track, "TOPLEFT", 0, -y)
end

function Browser:SetData(results, layout, selectedKey)
    self.results, self.layout, self.selectedKey = results, layout, selectedKey
    self:Render()
end

function Browser:SetSelected(key)
    self.selectedKey = key
    self:Render()
end

function Browser:ResetScroll() self.offset = 0 end

-- A new thumbnail scale that keeps the first visible entry on screen.
function Browser:SetScale(scale)
    if not self.layout then return end
    local first = self.offset
    self.layout.scale = scale
    local columns = self:Geometry()
    self.offset = math.floor(first / columns) * columns
    self:Render()
end

function Browser:Geometry()
    -- The scrollbar's lane is always reserved so the layout never jumps.
    local width, height = self.frame:GetWidth() - BAR - BAR_GAP, self.frame:GetHeight()
    local layout = self.layout or {mode = "rows"}
    if layout.mode == "grid" then
        local cell = math.floor(layout.cell * (layout.scale or 1))
        local cellHeight = cell + (layout.caption and 16 or 0)
        local columns = math.max(1, math.floor((width + GAP) / (cell + GAP)))
        local rows = math.max(1, math.floor((height + GAP) / (cellHeight + GAP)))
        return columns, rows, cell, cellHeight
    end
    return 1, math.max(1, math.floor(height / ROW)), width, ROW
end

function Browser:PageSize()
    local columns, rows = self:Geometry()
    return columns * rows
end

function Browser:Step()
    local columns = self:Geometry()
    return self.layout and self.layout.mode == "grid" and columns or 3
end

function Browser:Scroll(amount)
    local size, count = self:PageSize(), #self.results
    local columns = self:Geometry()
    local maxOffset = math.max(0, math.ceil((count - size) / columns) * columns)
    self.offset = W.Clamp(self.offset + amount, 0, maxOffset)
    self:Render()
end

function Browser:Page(direction) self:Scroll(direction * self:PageSize()) end

local function onCellClick(cell, mouse)
    local self, entry = cell.browser, cell.entry
    if not entry then return end
    if mouse == "RightButton" then return self.handlers.onMenu(entry, cell) end
    self.handlers.onSelect(entry, {ctrl = IsControlKeyDown() and true or false, shift = IsShiftKeyDown() and true or false})
end

local function onCellEnter(cell)
    local entry = cell.entry
    if not entry then return end
    GameTooltip:SetOwner(cell, "ANCHOR_RIGHT")
    GameTooltip:SetText(entry.name, unpack(T.accent))
    if tostring(entry.value) ~= entry.name then GameTooltip:AddLine(tostring(entry.value), 0.85, 0.88, 0.93, true) end
    if entry.id and entry.id ~= entry.value then GameTooltip:AddLine("ID " .. entry.id, 0.85, 0.88, 0.93) end
    if entry.description then GameTooltip:AddLine(entry.description, 1, 1, 1, true) end
    if entry.tags then GameTooltip:AddLine(entry.tags, 0.62, 0.78, 0.91, true) end
    GameTooltip:AddLine(ML.Catalog.FacetLabels(entry.facets), unpack(T.muted))
    GameTooltip:AddLine("Click to inspect  /  Ctrl or Shift+click to pick more  /  Right-click for lists", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

function Browser:Cell(index)
    local cell = self.cells[index]
    if cell then return cell end
    cell = CreateFrame("Button", nil, self.frame, "BackdropTemplate")
    cell.browser = self
    cell:SetBackdrop({bgFile = W.WHITE, edgeFile = W.WHITE, edgeSize = 1})
    cell:SetBackdropColor(unpack(T.field))
    cell:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    cell:SetHighlightTexture(W.WHITE)
    cell:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.06)
    cell.picked = W.Fill(cell, {T.accent[1], T.accent[2], T.accent[3], 0.16}, "BORDER")
    cell.art = cell:CreateTexture(nil, "ARTWORK")
    cell.art:SetPoint("CENTER", cell, "TOP", 0, 0)
    cell.caption = W.Label(cell, "", 10, T.muted)
    cell.caption:SetPoint("BOTTOMLEFT", 4, 3)
    cell.caption:SetPoint("BOTTOMRIGHT", -4, 3)
    cell.star = W.Label(cell, "*", 14, T.accent)
    cell.star:SetPoint("TOPRIGHT", -3, -1)
    cell.missing = W.Label(cell, "?", 14, T.muted)
    cell.missing:SetPoint("CENTER")
    cell:SetScript("OnClick", onCellClick)
    cell:SetScript("OnEnter", onCellEnter)
    cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self.cells[index] = cell
    return cell
end

function Browser:Row(index)
    local row = self.rows[index]
    if row then return row end
    row = CreateFrame("Button", nil, self.frame)
    row.browser = self
    row:SetHeight(ROW)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row.base = W.Fill(row, {1, 1, 1, 0.025})
    row.picked = W.Fill(row, {T.accent[1], T.accent[2], T.accent[3], 0.14}, "BORDER")
    row:SetHighlightTexture(W.WHITE)
    row:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.05)
    row.play = W.Button(row, "Play", 36, function() if row.entry then self.handlers.onPlay(row.entry) end end, 18)
    row.play:SetPoint("LEFT", 2, 0)
    row.art = row:CreateTexture(nil, "ARTWORK")
    row.art:SetSize(18, 18)
    row.name = W.Label(row, "", 11)
    row.detail = W.Label(row, "", 10, T.muted)
    row.detail:SetPoint("RIGHT", -18, 0)
    row.detail:SetJustifyH("RIGHT")
    row.detail:SetWidth(170)
    row.name:SetPoint("RIGHT", row.detail, "LEFT", -8, 0)
    row.star = W.Label(row, "*", 13, T.accent)
    row.star:SetPoint("RIGHT", -5, 0)
    row:SetScript("OnClick", onCellClick)
    row:SetScript("OnEnter", onCellEnter)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self.rows[index] = row
    return row
end

local function detailText(entry, mixed)
    if mixed then return ML.KindById[entry.kind].label end
    if ML.KindById[entry.kind].detail == "id" then return "ID " .. tostring(entry.id) end
    if entry.kind == "control" then return entry.tag or "" end
    return entry.facets[1] and ML.Catalog.FacetLabel(entry.facets[1]) or ""
end

function Browser:RenderGrid(first, size)
    local columns, _, cell, cellHeight = self:Geometry()
    for index = 1, size do
        local entry = self.results[first + index]
        local frame = self:Cell(index)
        frame.entry = entry
        frame:SetShown(entry ~= nil)
        if entry then
            local column, line = (index - 1) % columns, math.floor((index - 1) / columns)
            frame:ClearAllPoints()
            frame:SetPoint("TOPLEFT", column * (cell + GAP), -line * (cellHeight + GAP))
            frame:SetSize(cell, cellHeight)
            local picked = self.handlers.isSelected and self.handlers.isSelected(entry)
            frame:SetBackdropBorderColor(unpack((entry.key == self.selectedKey or picked) and T.selected or T.border))
            frame.picked:SetShown(picked and true or false)
            frame.art:ClearAllPoints()
            frame.art:SetPoint("CENTER", frame, "TOP", 0, -cell / 2)
            local loaded = ML.Art.Fit(frame.art, entry, cell - 8, cell - 8, true)
            frame.missing:SetShown(not loaded)
            frame.caption:SetShown(self.layout.caption == true)
            frame.caption:SetText(entry.name)
            frame.star:SetShown(ML.Catalog:IsFavorite(entry))
        end
    end
    for index = size + 1, #self.cells do self.cells[index]:Hide() end
    for _, row in ipairs(self.rows) do row:Hide() end
end

function Browser:RenderRows(first, size)
    local mixed = self.layout.mixed
    for index = 1, size do
        local entry = self.results[first + index]
        local row = self:Row(index)
        row.entry = entry
        row:SetShown(entry ~= nil)
        if entry then
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW)
            row:SetPoint("TOPRIGHT", -(BAR + BAR_GAP), -(index - 1) * ROW)
            row.base:SetShown(index % 2 == 0)
            local visual = ML.KindById[entry.kind].visual
            local playable = entry.kind == "sound"
            row.play:SetShown(playable)
            row.art:ClearAllPoints()
            row.art:SetPoint("LEFT", playable and 42 or 4, 0)
            if visual then
                row.art:SetShown(ML.Art.Fit(row.art, entry, 18, 18, true))
            else
                ML.Art.Reset(row.art)
            end
            row.name:ClearAllPoints()
            row.name:SetPoint("LEFT", (playable and 42 or 6) + (visual and 24 or 0), 0)
            row.name:SetPoint("RIGHT", row.detail, "LEFT", -8, 0)
            row.name:SetText(entry.name)
            local picked = self.handlers.isSelected and self.handlers.isSelected(entry)
            row.picked:SetShown(picked and true or false)
            row.name:SetTextColor(unpack((entry.key == self.selectedKey or picked) and T.accent or T.text))
            row.detail:SetText(detailText(entry, mixed))
            row.star:SetShown(ML.Catalog:IsFavorite(entry))
        end
    end
    for index = size + 1, #self.rows do self.rows[index]:Hide() end
    for _, cell in ipairs(self.cells) do cell:Hide() end
end

function Browser:Render()
    if not self.layout or self.frame:GetWidth() < 10 then return end
    local size, count = self:PageSize(), #self.results
    local columns = self:Geometry()
    self.offset = W.Clamp(self.offset, 0, math.max(0, math.ceil((count - size) / columns) * columns))
    if self.layout.mode == "grid" then self:RenderGrid(self.offset, size) else self:RenderRows(self.offset, size) end
    self:UpdateScrollbar()
    self.empty:SetShown(count == 0)
    self.empty:SetText(self.layout.emptyText or "Nothing matches.")
    if self.handlers.onChanged then self.handlers.onChanged() end
end

function Browser:Range()
    local count = #self.results
    if count == 0 then return 0, 0, 0 end
    return self.offset + 1, math.min(count, self.offset + self:PageSize()), count
end

-- Moves the view so the given entry is visible (used after jumping to a result).
function Browser:Reveal(entry)
    for index, candidate in ipairs(self.results) do
        if candidate == entry then
            local size, columns = self:PageSize(), self:Geometry()
            if index <= self.offset or index > self.offset + size then
                self.offset = math.floor((index - 1) / columns) * columns
            end
            break
        end
    end
    self:Render()
end
