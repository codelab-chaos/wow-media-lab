local _, ML = ...

-- The main window: title bar (drag, minimize, close), tabs, search, the facet
-- filter column, the browser and the inspector. It owns view state and wires
-- the other parts together; rendering lives in browser.lua and inspector.lua.
local W = ML.Widgets
local T = W.theme
local C = ML.Catalog
local UI = {}
ML.UI = UI

local DEFAULT = {width = 1120, height = 700}
local BOUNDS = {minWidth = 860, minHeight = 560, maxWidth = 1900, maxHeight = 1300}
local TITLE, FACET_WIDTH, INSPECTOR_WIDTH, FACET_ROW = 30, 150, 330, 20

local function view() return ML.db.view end

function UI:Tab(id)
    for _, tab in ipairs(ML.Tabs) do if tab.id == id then return tab end end
end

---------------------------------------------------------------------------
-- Window placement and minimizing
---------------------------------------------------------------------------
function UI:SaveWindow()
    local frame = self.frame
    local point, _, relativePoint, x, y = frame:GetPoint()
    local saved = ML.db.window or {}
    saved.point, saved.relativePoint, saved.x, saved.y = point, relativePoint, x, y
    saved.width = frame:GetWidth()
    if not ML.db.minimized then saved.height = frame:GetHeight() end
    ML.db.window = saved
end

function UI:RestoreWindow()
    local frame, saved = self.frame, ML.db.window
    frame:ClearAllPoints()
    frame:SetSize(W.Clamp(saved and tonumber(saved.width) or DEFAULT.width, BOUNDS.minWidth, BOUNDS.maxWidth),
        W.Clamp(saved and tonumber(saved.height) or DEFAULT.height, BOUNDS.minHeight, BOUNDS.maxHeight))
    if saved and type(saved.point) == "string" and type(saved.relativePoint) == "string" then
        frame:SetPoint(saved.point, UIParent, saved.relativePoint, tonumber(saved.x) or 0, tonumber(saved.y) or 0)
    else
        frame:SetPoint("CENTER")
    end
end

function UI:ResetWindow()
    self:Show()
    ML.db.window = nil
    self:SetMinimized(false)
    self:RestoreWindow()
    self:SaveWindow()
end

-- Anchors by the top-left corner so height changes keep the title bar in place.
function UI:PinTopLeft()
    local frame = self.frame
    local left, top = frame:GetLeft(), frame:GetTop()
    if not left or not top then return end
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
end

-- Minimized keeps only the title bar; the window keeps its place and width.
function UI:SetMinimized(minimized)
    local frame = self.frame
    self:PinTopLeft()
    ML.db.minimized = minimized or nil
    self.body:SetShown(not minimized)
    self.minimize:SetLabel(minimized and "+" or "_")
    if minimized then
        frame:SetResizeBounds(BOUNDS.minWidth, TITLE, BOUNDS.maxWidth, TITLE)
        frame:SetHeight(TITLE)
    else
        frame:SetResizeBounds(BOUNDS.minWidth, BOUNDS.minHeight, BOUNDS.maxWidth, BOUNDS.maxHeight)
        local saved = ML.db.window
        frame:SetHeight(W.Clamp(saved and tonumber(saved.height) or DEFAULT.height, BOUNDS.minHeight, BOUNDS.maxHeight))
        self:Refresh()
        if self.tabId and not self.selected[self.tabId] and self.results[1] and self.tabId ~= "favorites" then
            self:Select(self.results[1])
        end
    end
end

---------------------------------------------------------------------------
-- Tabs and facets
---------------------------------------------------------------------------
function UI:SelectTab(id)
    if not self:Tab(id) then return false end
    self.tabId = id
    view().tab = id
    self.browser:ResetScroll()
    self:Refresh()
    local selected = self.selected[id]
    if not selected and self.results[1] and id ~= "favorites" then selected = self.results[1] end
    self:Select(selected)
    return true
end

function UI:SelectTabByName(name)
    name = tostring(name or ""):lower()
    for _, tab in ipairs(ML.Tabs) do
        if tab.id == name or tab.label:lower() == name or tab.noun == name then return self:SelectTab(tab.id) end
    end
    return false
end

function UI:FacetButton(index)
    local item = self.facetButtons[index]
    if item then return item end
    item = CreateFrame("Button", nil, self.facetList)
    item:SetHeight(FACET_ROW)
    item.name = W.Label(item, "", 11, T.muted)
    item.name:SetPoint("LEFT", 8, 0)
    item.name:SetPoint("RIGHT", -44, 0)
    item.count = W.Label(item, "", 10, T.muted)
    item.count:SetPoint("RIGHT", -4, 0)
    item.count:SetJustifyH("RIGHT")
    item.marker = item:CreateTexture(nil, "ARTWORK")
    item.marker:SetColorTexture(unpack(T.accent))
    item.marker:SetSize(2, 14)
    item.marker:SetPoint("LEFT")
    item:SetHighlightTexture(W.WHITE)
    item:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.05)
    item:SetScript("OnClick", function(button) self:SetFacet(button.facet) end)
    self.facetButtons[index] = item
    return item
end

function UI:SetFacet(facet)
    view().facets[self.tabId] = facet
    self.browser:ResetScroll()
    self:Refresh()
end

function UI:RenderFacets()
    local facets = self.facetCache[self.tabId]
    if not facets then
        facets = C:Facets(self.tabId)
        self.facetCache[self.tabId] = facets
    end
    local active = view().facets[self.tabId]
    local items = {{name = "All", count = C:TabCount(self.tabId)}}
    for _, facet in ipairs(facets) do items[#items + 1] = facet end
    local visible = math.max(1, math.floor(self.facetList:GetHeight() / FACET_ROW))
    self.facetOffset = W.Clamp(self.facetOffset or 0, 0, math.max(0, #items - visible))
    for index = 1, visible do
        local item, data = self:FacetButton(index), items[self.facetOffset + index]
        item:SetShown(data ~= nil)
        if data then
            item:ClearAllPoints()
            item:SetPoint("TOPLEFT", 0, -(index - 1) * FACET_ROW)
            item:SetPoint("TOPRIGHT", 0, -(index - 1) * FACET_ROW)
            item.facet = data.name ~= "All" and data.name or nil
            local selected = item.facet == active
            item.name:SetText(data.name)
            item.name:SetTextColor(unpack(selected and T.accent or T.text))
            item.count:SetText(tostring(data.count))
            item.marker:SetShown(selected)
        end
    end
    for index = visible + 1, #self.facetButtons do self.facetButtons[index]:Hide() end
    self.facetMore:SetText(#items > visible and string.format("%d-%d of %d  (wheel)", self.facetOffset + 1,
        math.min(#items, self.facetOffset + visible), #items) or "")
end

---------------------------------------------------------------------------
-- Results, selection, search
---------------------------------------------------------------------------
function UI:Layout()
    local tab = self:Tab(self.tabId)
    local thumb = ML.ThumbScales[view().thumb or 2] or 1
    local emptyText
    if tab.id == "favorites" then
        emptyText = (self.query ~= "" or view().facets.favorites) and "No favorites match."
            or "Right-click anything in another tab to save it here."
    elseif not C.indexed[tab.id] then
        emptyText = "Indexing " .. tab.noun .. "..."
    else
        emptyText = "No " .. tab.noun .. " match. Try fewer words or the All filter."
    end
    return {mode = tab.layout, cell = tab.cell, scale = thumb, caption = tab.caption, mixed = tab.id == "favorites",
        emptyText = emptyText}
end

function UI:Refresh()
    if not self.frame or ML.db.minimized then return end
    local facet = view().facets[self.tabId]
    self.results = C:Filter(self.tabId, facet, self.query)
    local tab = self:Tab(self.tabId)
    self.thumbButton:SetShown(tab.layout == "grid")
    self.thumbButton:SetLabel("Size: " .. math.floor((ML.ThumbScales[view().thumb or 2] or 1) * 100) .. "%")
    for _, button in ipairs(self.tabButtons) do
        button:SetLabel(button.tab.label .. "  " .. C:TabCount(button.tab.id))
        button:SetActive(button.tab.id == self.tabId)
    end
    local selected = self.selected[self.tabId]
    self.browser:SetData(self.results, self:Layout(), selected and selected.key)
    self:RenderFacets()
end

function UI:UpdatePager()
    local first, last, count = self.browser:Range()
    self.range:SetText(count == 0 and "0 results" or string.format("%d-%d of %d", first, last, count))
    self.status:SetText(C.error and "Indexing stopped; see chat." or (C.ready and "Ready" or "Indexing..."))
end

function UI:Select(entry)
    self.selected[self.tabId] = entry
    self.inspector:Show(entry)
    self.browser:SetSelected(entry and entry.key)
end

function UI:ToggleFavorite(entry)
    C:ToggleFavorite(entry)
    self.facetCache.favorites = nil
    self.inspector:RefreshFavorite()
    self:Refresh()
end

function UI:Search(text)
    self.search.box:SetText(text or "")
    self.query = text or ""
    self.browser:ResetScroll()
    self:Refresh()
end

function UI:OnIndexed(kind)
    if kind then self.facetCache[kind] = nil end
    self.facetCache.favorites = nil
    if not self.frame then return end
    self:Refresh()
    if (kind == self.tabId or kind == nil) and not self.selected[self.tabId] and self.results[1] and self.tabId ~= "favorites" then
        self:Select(self.results[1])
    end
    self:UpdatePager()
end

---------------------------------------------------------------------------
-- Construction
---------------------------------------------------------------------------
function UI:CreateTitleBar(frame)
    local bar = CreateFrame("Frame", nil, frame)
    bar:SetPoint("TOPLEFT", 1, -1)
    bar:SetPoint("TOPRIGHT", -1, -1)
    bar:SetHeight(TITLE - 2)
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function() frame:StartMoving() end)
    bar:SetScript("OnDragStop", function() frame:StopMovingOrSizing(); self:SaveWindow() end)
    W.Fill(bar, {0.09, 0.105, 0.125, 1})
    local title = W.Label(bar, "MediaLab", 13, T.accent)
    title:SetPoint("LEFT", 10, 0)
    self.status = W.Label(bar, "", 10, T.muted)
    self.status:SetPoint("LEFT", title, "RIGHT", 12, 0)
    local close = W.Button(bar, "x", 22, function() frame:Hide() end, 20)
    close:SetPoint("RIGHT", -4, 0)
    W.Tip(close, "Close", "/mlab opens it again.")
    self.minimize = W.Button(bar, "_", 22, function() self:SetMinimized(not ML.db.minimized) end, 20)
    self.minimize:SetPoint("RIGHT", close, "LEFT", -4, 0)
    W.Tip(self.minimize, "Minimize", "Collapse to the title bar. Click again to restore.")
end

function UI:CreateToolbar(body)
    self.tabButtons = {}
    local previous
    for _, tab in ipairs(ML.Tabs) do
        local button = W.Button(body, tab.label, 104, function() self:SelectTab(tab.id) end, 24)
        button.tab = tab
        if previous then button:SetPoint("LEFT", previous, "RIGHT", 4, 0) else button:SetPoint("TOPLEFT", 12, -(TITLE + 8)) end
        self.tabButtons[#self.tabButtons + 1] = button
        previous = button
    end
    self.search = W.EditBox(body, 24, "Search names, paths, IDs...")
    self.search:SetPoint("TOPLEFT", 12, -(TITLE + 40))
    self.search:SetWidth(FACET_WIDTH + 200)
    self.search.box:SetScript("OnTextChanged", function(box)
        local text = box:GetText()
        self.search.placeholder:SetShown(text == "")
        if text == self.query then return end
        self.query = text
        if self.searchTimer then self.searchTimer:Cancel() end
        self.searchTimer = C_Timer.NewTimer(0.2, function()
            self.browser:ResetScroll()
            self:Refresh()
        end)
    end)
    local clear = W.Button(body, "Clear", 48, function() self:Search("") end, 24)
    clear:SetPoint("LEFT", self.search, "RIGHT", 4, 0)
    self.thumbButton = W.Button(body, "Size", 86, function()
        view().thumb = (view().thumb or 2) % #ML.ThumbScales + 1
        self:Refresh()
    end, 24)
    self.thumbButton:SetPoint("LEFT", clear, "RIGHT", 4, 0)
    W.Tip(self.thumbButton, "Thumbnail size", "Cycle the grid's thumbnail zoom.")
end

function UI:CreateFacetColumn(body)
    local column = W.Panel(body)
    column:SetPoint("TOPLEFT", 12, -(TITLE + 72))
    column:SetPoint("BOTTOMLEFT", 12, 12)
    column:SetWidth(FACET_WIDTH)
    local heading = W.Label(column, "FILTER", 10, T.muted)
    heading:SetPoint("TOPLEFT", 8, -8)
    self.facetList = CreateFrame("Frame", nil, column)
    self.facetList:SetPoint("TOPLEFT", 2, -24)
    self.facetList:SetPoint("BOTTOMRIGHT", -2, 22)
    self.facetList:EnableMouseWheel(true)
    self.facetList:SetScript("OnMouseWheel", function(_, delta)
        self.facetOffset = (self.facetOffset or 0) - delta * 3
        self:RenderFacets()
    end)
    self.facetList:SetScript("OnSizeChanged", function() if self.tabId then self:RenderFacets() end end)
    self.facetMore = W.Label(column, "", 9, T.muted)
    self.facetMore:SetPoint("BOTTOMLEFT", 8, 7)
    self.facetButtons = {}
    return column
end

function UI:Create()
    local frame = W.Panel(UIParent, T.window, "MediaLabFrame")
    self.frame, self.selected, self.facetCache, self.query, self.results = frame, {}, {}, "", {}
    view().facets = type(view().facets) == "table" and view().facets or {}
    frame:SetFrameStrata("HIGH")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:SetResizable(true)
    frame:EnableMouse(true)
    frame:SetResizeBounds(BOUNDS.minWidth, BOUNDS.minHeight, BOUNDS.maxWidth, BOUNDS.maxHeight)
    frame:SetScale(math.min(1, UIParent:GetWidth() * 0.96 / DEFAULT.width, UIParent:GetHeight() * 0.94 / DEFAULT.height))
    tinsert(UISpecialFrames, "MediaLabFrame")
    self:RestoreWindow()
    self:CreateTitleBar(frame)

    local body = CreateFrame("Frame", nil, frame)
    body:SetAllPoints()
    self.body = body
    self:CreateToolbar(body)
    local facets = self:CreateFacetColumn(body)

    self.inspector = ML.Inspector.New(body, {onFavorite = function(entry) self:ToggleFavorite(entry) end})
    self.inspector.frame:SetPoint("TOPRIGHT", -12, -(TITLE + 40))
    self.inspector.frame:SetPoint("BOTTOMRIGHT", -12, 12)
    self.inspector.frame:SetWidth(INSPECTOR_WIDTH)

    local prev = W.Button(body, "<", 26, function() self.browser:Page(-1) end, 24)
    local nextPage = W.Button(body, ">", 26, function() self.browser:Page(1) end, 24)
    nextPage:SetPoint("TOPRIGHT", self.inspector.frame, "TOPLEFT", -10, 0)
    prev:SetPoint("RIGHT", nextPage, "LEFT", -4, 0)
    self.range = W.Label(body, "", 11, T.muted)
    self.range:SetPoint("RIGHT", prev, "LEFT", -8, 0)
    self.range:SetJustifyH("RIGHT")

    self.browser = ML.Browser.New(body, {
        onSelect = function(entry) self:Select(entry) end,
        onFavorite = function(entry) self:ToggleFavorite(entry) end,
        onPlay = function(entry)
            self:Select(entry)
            local preview = self.inspector:Preview("sound")
            if not ML.db.view.autoplay then preview:Play(entry) end
        end,
        onChanged = function() self:UpdatePager() end,
    })
    self.browser.frame:SetPoint("TOPLEFT", facets, "TOPRIGHT", 10, 0)
    self.browser.frame:SetPoint("BOTTOMRIGHT", self.inspector.frame, "BOTTOMLEFT", -10, 0)

    local resize = CreateFrame("Button", nil, body)
    resize:SetSize(16, 16)
    resize:SetPoint("BOTTOMRIGHT", -1, 1)
    resize:SetNormalTexture([[Interface\ChatFrame\UI-ChatIM-SizeGrabber-Up]])
    resize:SetHighlightTexture([[Interface\ChatFrame\UI-ChatIM-SizeGrabber-Highlight]])
    resize:SetScript("OnMouseDown", function() frame:StartSizing("BOTTOMRIGHT") end)
    resize:SetScript("OnMouseUp", function() frame:StopMovingOrSizing(); self:SaveWindow() end)

    frame:SetScript("OnHide", function()
        self.search.box:ClearFocus()
        local sound = self.inspector.previews.sound
        if sound then sound:Stop() end
        GameTooltip:Hide()
    end)

    self.tabId = self:Tab(view().tab) and view().tab or ML.Tabs[1].id
    self:SetMinimized(ML.db.minimized == true)
    C:Start(function(kind) self:OnIndexed(kind) end)
    self:SelectTab(self.tabId)
end

function UI:Show()
    if not self.frame then self:Create() end
    self.frame:Show()
    self:Refresh()
end

function UI:Toggle()
    if self.frame and self.frame:IsShown() then self.frame:Hide() else self:Show() end
end
