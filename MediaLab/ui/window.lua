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
local TITLE, FACET_WIDTH, FACET_ROW = 30, 150, 20
-- The inspector column: its default width, the narrowest it goes, and the
-- room it always leaves the results when dragged wider.
local INSPECTOR = {width = 330, min = 280, browserMin = 300, handle = 8}

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
        if self.tabId and not self.selected[self.tabId] and self.results[1] and self.tabId ~= ML.ListsTab then
            self:Select(self.results[1])
        end
    end
end

---------------------------------------------------------------------------
-- Tabs and facets
---------------------------------------------------------------------------
-- Tabs a player can see right now: developer-only ones need developer mode.
function UI:Available(id)
    local button = ML.TabButtonOf(id)
    return button ~= nil and (ML.db.developer or not button.developer)
end

function UI:SelectTab(id)
    if not self:Tab(id) or not self:Available(id) then return false end
    self.tabId = id
    view().tab = id
    local button = ML.TabButtonOf(id)
    view().views = type(view().views) == "table" and view().views or {}
    view().views[button.id] = id
    self.browser:ResetScroll()
    self:Refresh()
    local selected = self.selected[id]
    if not selected and self.results[1] and id ~= ML.ListsTab then selected = self.results[1] end
    self:Select(selected)
    return true
end

function UI:SelectTabByName(name)
    name = tostring(name or ""):lower()
    for _, tab in ipairs(ML.Tabs) do
        local match = tab.id == name or tab.label:lower() == name or tab.noun == name
        for _, alias in ipairs(tab.aliases or {}) do match = match or alias == name end
        if match then return self:SelectTab(tab.id) end
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
    local onLists = self.tabId == ML.ListsTab
    if onLists and active and not ML.Lists:FromFacet(active) then active = nil; view().facets[self.tabId] = nil end
    self.facetHeading:SetText(onLists and "LISTS" or "FILTER")
    self:RenderListActions(onLists and ML.Lists:FromFacet(active))
    local items = {{name = "All", label = onLists and "All saved" or "All", count = C:TabCount(self.tabId)}}
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
            item.name:SetText(data.label or data.name)
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
    if tab.id == ML.ListsTab then
        local list = ML.Lists:FromFacet(view().facets[tab.id])
        emptyText = self.query ~= "" and "Nothing saved matches."
            or (ML.Lists.IsBuiltIn(list) and "Right-click anything in another tab to favorite it.")
            or (list and (list.name .. " is empty. Use Add to list in the inspector to fill it."))
            or "Right-click anything to favorite it, or use Add to list in the inspector."
    elseif not C.indexed[tab.id] then
        emptyText = "Indexing " .. tab.noun .. "..."
    else
        emptyText = "No " .. tab.noun .. " match. Try fewer words or the All filter."
    end
    return {mode = tab.layout, cell = tab.cell, scale = thumb, caption = tab.caption, mixed = tab.id == ML.ListsTab,
        emptyText = emptyText}
end

function UI:Refresh()
    if not self.frame or ML.db.minimized then return end
    local facet = view().facets[self.tabId]
    self.results = C:Filter(self.tabId, facet, self.query)
    local tab = self:Tab(self.tabId)
    self.thumbButton:SetShown(tab.layout == "grid")
    self.copyButton:SetShown(ML.db.developer and true or false)
    self.thumbButton:SetLabel("Size: " .. math.floor((ML.ThumbScales[view().thumb or 2] or 1) * 100) .. "%")
    local current = ML.TabButtonOf(self.tabId)
    for _, button in ipairs(self.tabButtons) do
        local count = 0
        for _, kind in ipairs(button.tab.kinds) do count = count + C:TabCount(kind) end
        button:SetLabel(button.tab.label .. "  " .. count)
        button:SetActive(button.tab == current)
    end
    for _, button in ipairs(self.viewButtons) do
        button:SetShown(button.group == current)
        button:SetActive(button.kind == self.tabId)
    end
    self:LayoutToolbar()
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

-- Right-click and the star: in or out of Favorites.
function UI:ToggleFavorite(entry)
    ML.Lists:ToggleFavorite(entry.key)
    self:RefreshSaved()
end

-- After any list change: counts, the Lists tab, the inspector's button.
function UI:RefreshSaved()
    self.facetCache[ML.ListsTab] = nil
    self.inspector:RefreshLists()
    if ML.ListMenu.frame and ML.ListMenu.frame:IsShown() then ML.ListMenu.Render() end
    self:Refresh()
end

-- The Target button and /mlab target: find the target's creature display,
-- remember the NPC's name on it, and select it on the Models tab. When only
-- the model file can be read, search for it so the skins can be compared.
function UI:FromTarget()
    ML.Npcs:CaptureTarget(function(npc, detail)
        local function report(text)
            ML.Print(text)
            local preview = self.inspector.previews.model
            if preview and self.tabId == "model" then preview:SetStatus(text) end
        end
        if not npc then return report(detail) end
        if not C.indexed.model then return report("Models are still indexing. Try again when the lab says Ready.") end
        local label = npc.name .. " (creature " .. detail .. ")"
        local entry = npc.display and C.byKey[C:Key("model", npc.display)]
        view().facets.model = nil
        self.facetCache.model = nil
        if entry then
            C:Touch(ML.Sources.ApplyNpcs(entry))
            self:SelectTab("model")
            self:Search("")
            self:Select(entry)
            self.browser:Reveal(entry)
            return report(label .. " uses display " .. npc.display .. ".")
        end
        self:SelectTab("model")
        if npc.model then
            self:Search(tostring(npc.model))
            return report(label .. " uses model file " .. npc.model .. "; its display is not readable, so pick the matching skin.")
        end
        report(label .. " uses display " .. tostring(npc.display) .. ", which this catalog does not list.")
    end)
end

function UI:Search(text)
    self.search.box:SetText(text or "")
    self.query = text or ""
    self.browser:ResetScroll()
    self:Refresh()
end

function UI:OnIndexed(kind)
    if kind then self.facetCache[kind] = nil end
    self.facetCache[ML.ListsTab] = nil
    if not self.frame then return end
    self:Refresh()
    if (kind == self.tabId or kind == nil) and not self.selected[self.tabId] and self.results[1] and self.tabId ~= ML.ListsTab then
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
    local title = W.Label(bar, ML.TITLE, 13, T.accent)
    title:SetPoint("LEFT", 10, 0)
    self.status = W.Label(bar, "", 10, T.muted)
    self.status:SetPoint("LEFT", title, "RIGHT", 12, 0)
    local close = W.Button(bar, "x", 22, function() frame:Hide() end, 20)
    close:SetPoint("RIGHT", -4, 0)
    W.Tip(close, "Close", "/mlab opens it again.")
    self.minimize = W.Button(bar, "_", 22, function() self:SetMinimized(not ML.db.minimized) end, 20)
    self.minimize:SetPoint("RIGHT", close, "LEFT", -4, 0)
    W.Tip(self.minimize, "Minimize", "Collapse to the title bar. Click again to restore.")
    self.helpButton = W.Button(bar, "?", 22, function() self:ToggleHelp() end, 20)
    self.helpButton:SetPoint("RIGHT", self.minimize, "LEFT", -4, 0)
    W.Tip(self.helpButton, "Help", "Tips for the tab you are on.")
    self.devButton = W.Button(bar, "Dev", 40, function() self:SetDeveloper(not ML.db.developer) end, 20)
    self.devButton:SetPoint("RIGHT", self.helpButton, "LEFT", -4, 0)
    W.Tip(self.devButton, "Developer mode", "Show the code behind each entry, the Fonts tab and Copy. For addon makers.")
end

---------------------------------------------------------------------------
-- Developer mode and help
---------------------------------------------------------------------------
function UI:SetDeveloper(on)
    ML.db.developer = on and true or nil
    self.devButton:SetActive(on and true or false)
    if not self:Available(self.tabId) then self:SelectTab(ML.TabBar[1].kinds[1]) end
    self:LayoutTabs()
    self.inspector:RefreshFields()
    self:Refresh()
    if ML.HelpPanel.IsShown() then ML.HelpPanel.Render(self.tabId, ML.db.developer) end
end

function UI:ShowHelp()
    ML.HelpPanel.Show(self.tabId, ML.db.developer)
    self.helpButton:SetActive(true)
end

function UI:HideHelp()
    ML.HelpPanel.Hide()
    self.helpButton:SetActive(false)
    ML.db.welcomed = true
end

function UI:ToggleHelp()
    if ML.HelpPanel.IsShown() then self:HideHelp() else self:ShowHelp() end
end

-- The tab buttons in order, skipping the ones developer mode hides.
function UI:LayoutTabs()
    local previous
    for _, button in ipairs(self.tabButtons) do
        local shown = not button.tab.developer or ML.db.developer
        button:SetShown(shown and true or false)
        if shown then
            button:ClearAllPoints()
            if previous then button:SetPoint("LEFT", previous, "RIGHT", 4, 0) else button:SetPoint("TOPLEFT", 12, -(TITLE + 8)) end
            previous = button
        end
    end
end

-- The second row, left to right: search, Clear, then whichever tools apply.
function UI:LayoutToolbar()
    local previous = self.clearButton
    for _, item in ipairs(self.toolbarItems) do
        if item:IsShown() then
            item:ClearAllPoints()
            item:SetPoint("LEFT", previous, "RIGHT", 4, 0)
            previous = item
        end
    end
end

function UI:CreateToolbar(body)
    self.tabButtons, self.viewButtons, self.toolbarItems = {}, {}, {}
    for _, tab in ipairs(ML.TabBar) do
        local button = W.Button(body, tab.label, 96, function()
            local remembered = type(view().views) == "table" and view().views[tab.id]
            self:SelectTab(remembered or tab.kinds[1])
        end, 24)
        button.tab = tab
        self.tabButtons[#self.tabButtons + 1] = button
    end
    self:LayoutTabs()
    self.search = W.EditBox(body, 24, "Search names, paths, IDs...")
    self.search:SetPoint("TOPLEFT", 12, -(TITLE + 40))
    self.search:SetWidth(FACET_WIDTH + 150)
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
    self.clearButton = W.Button(body, "Clear", 48, function() self:Search("") end, 24)
    self.clearButton:SetPoint("LEFT", self.search, "RIGHT", 4, 0)
    -- A tab holding several kinds (Textures: Files, Atlases) gets a switch.
    for _, tab in ipairs(ML.TabBar) do
        if #tab.kinds > 1 then
            for _, kind in ipairs(tab.kinds) do
                local label = ML.KindById[kind].view or ML.KindById[kind].label
                local button = W.Button(body, label, 58, function() self:SelectTab(kind) end, 24)
                button.group, button.kind = tab, kind
                W.Tip(button, label, "Show the " .. ML.KindById[kind].noun .. " in this tab.")
                self.viewButtons[#self.viewButtons + 1] = button
                self.toolbarItems[#self.toolbarItems + 1] = button
            end
        end
    end
    self.thumbButton = W.Button(body, "Size", 86, function()
        view().thumb = (view().thumb or 2) % #ML.ThumbScales + 1
        self:Refresh()
    end, 24)
    W.Tip(self.thumbButton, "Thumbnail size", "Cycle the grid's thumbnail zoom.")
    self.toolbarItems[#self.toolbarItems + 1] = self.thumbButton
    self.copyButton = W.Button(body, "Copy", 48, function() self:CopyResults() end, 24)
    W.Tip(self.copyButton, "Copy results", "The current results (a list, on the Lists tab) as a Lua table or CSV, first "
        .. ML.Export.CSV_LIMIT .. ".")
    self.toolbarItems[#self.toolbarItems + 1] = self.copyButton
end

-- What the results are called in the Copy dialog and its Lua table: the
-- picked list, else the tab and its filter.
function UI:ResultsName()
    local facet = view().facets[self.tabId]
    if self.tabId == ML.ListsTab then
        local list = ML.Lists:FromFacet(facet)
        return list and list.name or "Saved media"
    end
    local label = self:Tab(self.tabId).label
    return facet and (label .. " " .. facet:gsub("^[^:]+: ", "")) or label
end

function UI:CopyResults(format)
    return ML.CopyDialog.Show(self.frame, {entries = self.results, name = self:ResultsName(), format = format})
end

---------------------------------------------------------------------------
-- List actions, under the Lists tab's filter column
---------------------------------------------------------------------------
function UI:NewList()
    ML.Prompt.Show(self.frame, {title = "New list", button = "Create",
        hint = "Right-click media to add it.", onAccept = function(name)
            local list, problem = ML.Lists:Create(name)
            if not list then return problem end
            self:SelectTab(ML.ListsTab)
            self:SetFacet(ML.Lists.Facet(list))
            self:RefreshSaved()
        end})
end

function UI:RenameList(list)
    ML.Prompt.Show(self.frame, {title = "Rename list", button = "Rename", text = list.name,
        onAccept = function(name)
            local renamed, problem = ML.Lists:Rename(list.id, name)
            if not renamed then return problem end
            self:RefreshSaved()
        end})
end

-- Deleting asks twice: the first click arms the button for a few seconds.
function UI:DeleteList(list)
    local button = self.listActions.delete
    if button.armed ~= list.id then
        button.armed = list.id
        button:SetLabel("Sure?")
        if button.timer then button.timer:Cancel() end
        button.timer = C_Timer.NewTimer(3, function()
            button.armed = nil
            button:SetLabel("Delete")
        end)
        return
    end
    if button.timer then button.timer:Cancel() end
    button.armed = nil
    button:SetLabel("Delete")
    ML.Lists:Delete(list.id)
    view().facets[ML.ListsTab] = nil
    self:RefreshSaved()
end

function UI:CreateListActions(column)
    local bar = CreateFrame("Frame", nil, column)
    bar:SetPoint("BOTTOMLEFT", 4, 20)
    bar:SetPoint("BOTTOMRIGHT", -4, 20)
    bar:SetHeight(22)
    local width = math.floor((FACET_WIDTH - 16) / 3)
    local function button(label, onClick, title, body)
        local item = W.Button(bar, label, width, onClick, 20)
        W.Tip(item, title, body)
        return item
    end
    bar.new = button("New", function() self:NewList() end, "New list", "Make a list and pick it.")
    bar.new:SetPoint("LEFT")
    bar.rename = button("Rename", function() if bar.list then self:RenameList(bar.list) end end,
        "Rename list", "Rename the picked list.")
    bar.rename:SetPoint("LEFT", bar.new, "RIGHT", 4, 0)
    bar.delete = button("Delete", function() if bar.list then self:DeleteList(bar.list) end end,
        "Delete list", "Click twice. The media stays in your other lists.")
    bar.delete:SetPoint("LEFT", bar.rename, "RIGHT", 4, 0)
    self.listActions = bar
end

-- Shown on the Lists tab only; Rename and Delete act on the picked list.
function UI:RenderListActions(list)
    local bar = self.listActions
    local shown = self.tabId == ML.ListsTab
    bar:SetShown(shown)
    bar.list = list or nil
    local editable = list and not ML.Lists.IsBuiltIn(list)
    bar.rename:SetEnabled(editable and true or false)
    bar.delete:SetEnabled(editable and true or false)
    self.facetList:SetPoint("BOTTOMRIGHT", -2, shown and 46 or 22)
end

function UI:CreateFacetColumn(body)
    local column = W.Panel(body)
    column:SetPoint("TOPLEFT", 12, -(TITLE + 72))
    column:SetPoint("BOTTOMLEFT", 12, 12)
    column:SetWidth(FACET_WIDTH)
    self.facetHeading = W.Label(column, "FILTER", 10, T.muted)
    self.facetHeading:SetPoint("TOPLEFT", 8, -8)
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
    self:CreateListActions(column)
    return column
end

---------------------------------------------------------------------------
-- The splitter between the results and the inspector
---------------------------------------------------------------------------
-- The widest the inspector can be in a window this size.
function UI:InspectorMax()
    local width = self.frame:GetWidth() or 0
    return math.max(INSPECTOR.min, width - 12 - FACET_WIDTH - 10 - INSPECTOR.browserMin - 10 - 12)
end

function UI:SetInspectorWidth(width, save)
    width = W.Clamp(tonumber(width) or INSPECTOR.width, INSPECTOR.min, self:InspectorMax())
    self.inspector.frame:SetWidth(width)
    if save then view().inspectorWidth = width ~= INSPECTOR.width and width or nil end
    return width
end

-- Drag the inspector's left edge to widen the preview; double-click resets it.
function UI:CreateSplitter(body)
    local handle = CreateFrame("Button", nil, body)
    handle:SetWidth(INSPECTOR.handle)
    handle:SetPoint("TOPRIGHT", self.inspector.frame, "TOPLEFT", -1, 0)
    handle:SetPoint("BOTTOMRIGHT", self.inspector.frame, "BOTTOMLEFT", -1, 0)
    handle:EnableMouse(true)
    local line = handle:CreateTexture(nil, "OVERLAY")
    line:SetPoint("TOP")
    line:SetPoint("BOTTOM")
    line:SetWidth(2)
    line:SetColorTexture(unpack(T.accent))
    line:SetAlpha(0)
    handle.line = line
    handle:SetScript("OnEnter", function() line:SetAlpha(0.6) end)
    handle:SetScript("OnLeave", function() if not handle.drag then line:SetAlpha(0) end end)
    handle:SetScript("OnMouseDown", function()
        handle.drag = {x = GetCursorPosition(), width = self.inspector.frame:GetWidth()}
        handle:SetScript("OnUpdate", function()
            local x = GetCursorPosition()
            self:SetInspectorWidth(handle.drag.width + (handle.drag.x - x) / handle:GetEffectiveScale())
        end)
    end)
    handle:SetScript("OnMouseUp", function()
        handle:SetScript("OnUpdate", nil)
        handle.drag = nil
        line:SetAlpha(0)
        self:SetInspectorWidth(self.inspector.frame:GetWidth(), true)
    end)
    handle:SetScript("OnDoubleClick", function() self:SetInspectorWidth(INSPECTOR.width, true) end)
    W.Tip(handle, "Preview width", "Drag to widen or narrow the preview. Double-click to reset.")
    self.splitter = handle
    self:SetInspectorWidth(view().inspectorWidth)
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
    -- A smaller window keeps the results usable by narrowing the inspector.
    frame:SetScript("OnSizeChanged", function()
        if self.inspector then self:SetInspectorWidth(view().inspectorWidth) end
    end)

    local body = CreateFrame("Frame", nil, frame)
    body:SetAllPoints()
    self.body = body
    self:CreateToolbar(body)
    local facets = self:CreateFacetColumn(body)

    self.inspector = ML.Inspector.New(body, {
        onFavorite = function(entry) self:ToggleFavorite(entry) end,
        onLists = function(entry, button)
            ML.ListMenu.Toggle(self.frame, button, entry, function() self:RefreshSaved() end)
        end,
        onTarget = function() self:FromTarget() end,
    })
    self.inspector.frame:SetPoint("TOPRIGHT", -12, -(TITLE + 40))
    self.inspector.frame:SetPoint("BOTTOMRIGHT", -12, 12)
    self:CreateSplitter(body)

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

    ML.HelpPanel.Create(body, function() self:HideHelp() end)

    frame:SetScript("OnHide", function()
        self.search.box:ClearFocus()
        ML.ListMenu.Hide()
        local sound = self.inspector.previews.sound
        if sound then sound:Stop() end
        GameTooltip:Hide()
    end)

    local saved = view().tab
    self.tabId = self:Tab(saved) and self:Available(saved) and saved or ML.Tabs[1].id
    self.devButton:SetActive(ML.db.developer and true or false)
    self:SetMinimized(ML.db.minimized == true)
    C:Start(function(kind) self:OnIndexed(kind) end)
    self:SelectTab(self.tabId)
    if not ML.db.welcomed then self:ShowHelp() end
end

function UI:Show()
    if not self.frame then self:Create() end
    self.frame:Show()
    self:Refresh()
end

function UI:Toggle()
    if self.frame and self.frame:IsShown() then self.frame:Hide() else self:Show() end
end
