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
local MAXIMIZED_MARGIN = 8 -- room left around a maximized window
local TRAY, TRAY_NAMES = 22, 12 -- the selection strip's height, and names it lists
local BOUNDS = {minWidth = 860, minHeight = 560, maxWidth = 1900, maxHeight = 1300}
local TITLE, FACET_ROW = 30, 20
-- The two side columns, as data: default and narrowest width (and widest, for
-- the filters), which edge drags, and where the width is saved. The results
-- in the middle always keep BROWSER_MIN.
local COLUMNS = {
    facets = {default = 190, min = 140, max = 400, edge = "right", saved = "facetWidth",
        title = "Filter width", hint = "Drag to widen or narrow the filters. Double-click to reset."},
    inspector = {default = 330, min = 280, edge = "left", saved = "inspectorWidth",
        title = "Preview width", hint = "Drag to widen or narrow the preview. Double-click to reset."},
}
local BROWSER_MIN, HANDLE = 300, 8
local GUTTERS = 12 + 10 + 10 + 12 -- window edge, column gap, column gap, window edge

local function view() return ML.db.view end

function UI:Tab(id)
    for _, tab in ipairs(ML.Tabs) do if tab.id == id then return tab end end
end

---------------------------------------------------------------------------
-- Window placement, maximizing and minimizing to the dock
---------------------------------------------------------------------------
-- The restore size and place; a maximized window keeps the one it had.
function UI:SaveWindow()
    if ML.db.maximized then return end
    local frame = self.frame
    local point, _, relativePoint, x, y = frame:GetPoint()
    local saved = ML.db.window or {}
    saved.point, saved.relativePoint, saved.x, saved.y = point, relativePoint, x, y
    saved.width, saved.height = frame:GetWidth(), frame:GetHeight()
    ML.db.window = saved
end

function UI:RestoreWindow()
    local frame, saved = self.frame, ML.db.window
    frame:ClearAllPoints()
    if ML.db.maximized then
        frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", MAXIMIZED_MARGIN, -MAXIMIZED_MARGIN)
        frame:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -MAXIMIZED_MARGIN, MAXIMIZED_MARGIN)
        return
    end
    frame:SetSize(W.Clamp(saved and tonumber(saved.width) or DEFAULT.width, BOUNDS.minWidth, BOUNDS.maxWidth),
        W.Clamp(saved and tonumber(saved.height) or DEFAULT.height, BOUNDS.minHeight, BOUNDS.maxHeight))
    if saved and type(saved.point) == "string" and type(saved.relativePoint) == "string" then
        frame:SetPoint(saved.point, UIParent, saved.relativePoint, tonumber(saved.x) or 0, tonumber(saved.y) or 0)
    else
        frame:SetPoint("CENTER")
    end
end

function UI:ResetWindow()
    ML.db.window, ML.db.maximized = nil, nil
    self:Show()
    self:RestoreWindow()
    self:UpdateMaximize()
    self:SaveWindow()
end

-- Maximized fills the screen; again restores the size and place it had.
function UI:SetMaximized(maximized)
    if maximized and not ML.db.maximized then self:SaveWindow() end
    ML.db.maximized = maximized and true or nil
    self:RestoreWindow()
    self:UpdateMaximize()
    self:FitColumns()
    self:Refresh()
end

function UI:UpdateMaximize()
    local maximized = ML.db.maximized == true
    self.maximize.back:SetShown(maximized)
    self.resizeGrip:SetShown(not maximized)
end

-- Minimized hides the window and docks an icon at a screen edge; the icon,
-- /mlab or the addon menu bring it back.
function UI:SetMinimized(minimized)
    if minimized then
        ML.db.minimized = true
        self.frame:Hide()
        ML.Dock.Show(function() self:Show() end)
    else
        self:Show()
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
    -- The full name, for names the column is too narrow to show.
    item:SetScript("OnEnter", function(button)
        if not button.tip then return end
        GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
        GameTooltip:SetText(button.tip, unpack(T.accent))
        GameTooltip:AddLine(button.count:GetText() .. " entries", unpack(T.muted))
        GameTooltip:Show()
    end)
    item:SetScript("OnLeave", function() GameTooltip:Hide() end)
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
    local group
    for _, facet in ipairs(facets) do
        local nextGroup = not onLists and C.FacetGroup(facet.name) or nil
        if nextGroup and nextGroup ~= group then items[#items + 1] = {heading = nextGroup:upper()} end
        group = nextGroup or group
        items[#items + 1] = {name = facet.name, label = onLists and facet.label or C.FacetLabel(facet.name),
            count = facet.count}
    end
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
            local selected = not data.heading and item.facet == active
            item:EnableMouse(not data.heading)
            item.name:SetText(data.heading or data.label or data.name)
            item.tip = not data.heading and (data.label or data.name) or nil
            item.name:SetTextColor(unpack(data.heading and T.muted or selected and T.accent or T.text))
            item.count:SetText(data.heading and "" or tostring(data.count))
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
    if not self.frame or not self.frame:IsShown() then return end
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
        if button.tab.id == ML.ListsTab then count = C:ListsBadge() end
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

-- A click in the results (with modifiers {ctrl, shift}), or the lab choosing
-- an entry itself. The inspector shows the entry clicked; the selection
-- (selection.lua) can hold many.
function UI:Select(entry, modifiers)
    ML.ListMenu.Hide()
    if entry then entry = ML.Selection:Click(entry, modifiers, self.results) else ML.Selection:Clear() end
    self.selected[self.tabId] = entry
    self.inspector:Show(entry)
    self.browser:SetSelected(entry and entry.key)
    self:RenderTray()
end

-- What the lists menu and Copy act on: the selection when it holds several.
function UI:Picked(entry)
    if ML.Selection:Count() > 1 and (not entry or ML.Selection:Has(entry)) then return ML.Selection:Entries() end
    return entry and {entry} or {}
end

function UI:OpenListMenu(entries, anchor)
    if #entries == 0 then return end
    ML.ListMenu.Open(self.frame, {entries = entries, anchor = anchor,
        onChanged = function() self:RefreshSaved() end,
        onManage = function() self:SelectTab(ML.ListsTab) end})
end

-- Right-click: the menu for the selection when the entry is part of it, else
-- for the entry alone, which becomes the selection.
function UI:ContextMenu(entry)
    local entries = ML.Selection:For(entry)
    if #entries == 1 then
        self.selected[self.tabId] = entry
        self.inspector:Show(entry)
        self.browser:SetSelected(entry.key)
    end
    self:RenderTray()
    self.browser:Render()
    self:OpenListMenu(entries)
end

-- A thin strip under the results while several entries are selected.
function UI:CreateTray(body)
    local tray = CreateFrame("Frame", nil, body)
    tray:SetHeight(TRAY)
    tray.clear = W.Button(tray, "Clear", 48, function() self:Select(self.selected[self.tabId]) end, 20)
    tray.clear:SetPoint("RIGHT")
    W.Tip(tray.clear, "Clear selection", "Keep only the entry you are inspecting.")
    tray.lists = W.Button(tray, "Lists", 48, function(button) self:OpenListMenu(ML.Selection:Entries(), button) end, 20)
    tray.lists:SetPoint("RIGHT", tray.clear, "LEFT", -4, 0)
    W.Tip(tray.lists, "Lists", "Add the selection to Favorites or any list, or start a new one.")
    tray.label = W.Label(tray, "", 10, T.muted)
    tray.label:SetPoint("LEFT", 2, 0)
    tray.label:SetPoint("RIGHT", tray.lists, "LEFT", -8, 0)
    tray:Hide()
    self.tray = tray
end

function UI:RenderTray()
    if not self.tray then return end
    local entries = ML.Selection:Entries()
    local shown = #entries > 1
    self.tray:SetShown(shown)
    self.browser.frame:SetPoint("BOTTOMRIGHT", self.inspector.frame, "BOTTOMLEFT", -10, shown and (TRAY + 6) or 0)
    if not shown then return end
    local names = {}
    for index = 1, math.min(#entries, TRAY_NAMES) do names[index] = entries[index].name end
    self.tray.label:SetText(#entries .. " selected:  " .. table.concat(names, ", ")
        .. (#entries > TRAY_NAMES and ", ..." or ""))
end

-- The star: in or out of Favorites.
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
    local bar = CreateFrame("Button", nil, frame)
    bar:SetPoint("TOPLEFT", 1, -1)
    bar:SetPoint("TOPRIGHT", -1, -1)
    bar:SetHeight(TITLE - 2)
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function() if not ML.db.maximized then frame:StartMoving() end end)
    bar:SetScript("OnDragStop", function() frame:StopMovingOrSizing(); self:SaveWindow() end)
    bar:SetScript("OnDoubleClick", function() self:SetMaximized(not ML.db.maximized) end)
    W.Fill(bar, {0.09, 0.105, 0.125, 1})
    local title = W.Label(bar, ML.TITLE, 13, T.accent)
    title:SetPoint("LEFT", 10, 0)
    self.status = W.Label(bar, "", 10, T.muted)
    self.status:SetPoint("LEFT", title, "RIGHT", 12, 0)
    local close = W.Button(bar, "x", 22, function() frame:Hide() end, 20)
    close:SetPoint("RIGHT", -4, 0)
    W.Tip(close, "Close", "/mlab opens it again.")
    self.maximize = W.Button(bar, "", 22, function() self:SetMaximized(not ML.db.maximized) end, 20)
    self.maximize:SetPoint("RIGHT", close, "LEFT", -4, 0)
    W.Tip(self.maximize, "Maximize", "Fill the screen. Click again, or double-click the title bar, to restore.")
    -- A drawn window icon: one square, or two overlapping when maximized.
    local function square(x, y)
        local box = CreateFrame("Frame", nil, self.maximize, "BackdropTemplate")
        box:SetSize(9, 8)
        box:SetPoint("CENTER", x, y)
        box:SetBackdrop({edgeFile = W.WHITE, edgeSize = 1})
        box:SetBackdropBorderColor(unpack(T.text))
        return box
    end
    self.maximize.front = square(-1, -1)
    self.maximize.back = square(2, 2)
    self.minimize = W.Button(bar, "_", 22, function() self:SetMinimized(true) end, 20)
    self.minimize:SetPoint("RIGHT", self.maximize, "LEFT", -4, 0)
    W.Tip(self.minimize, "Minimize", "Dock to an icon at the edge of the screen. Click the icon to bring it back.")
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
    self.search:SetWidth(300)
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
    if ML.Selection:Count() > 1 then return "Selected media" end
    local facet = view().facets[self.tabId]
    if self.tabId == ML.ListsTab then
        local list = ML.Lists:FromFacet(facet)
        return list and list.name or "Saved media"
    end
    local label = self:Tab(self.tabId).label
    return facet and (label .. " " .. facet:gsub("^[^:]+: ", "")) or label
end

function UI:CopyResults(format)
    local entries = ML.Selection:Count() > 1 and ML.Selection:Entries() or self.results
    return ML.CopyDialog.Show(self.frame, {entries = entries, name = self:ResultsName(), format = format})
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
    local function button(label, onClick, title, body)
        local item = W.Button(bar, label, 40, onClick, 20)
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

-- New, Rename and Delete share the column's width.
function UI:LayoutListActions(columnWidth)
    local width = math.floor((columnWidth - 16) / 3)
    for _, key in ipairs({"new", "rename", "delete"}) do self.listActions[key]:SetWidth(width) end
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
    self.facetColumn = column
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
-- Column widths: drag a side column's inner edge; double-click resets it
---------------------------------------------------------------------------
function UI:ColumnFrame(name)
    return name == "facets" and self.facetColumn or self.inspector.frame
end

-- The widest a side column can be in a window this size, leaving the
-- results their minimum beside the other column.
function UI:ColumnMax(name)
    local spec, other = COLUMNS[name], name == "facets" and "inspector" or "facets"
    local otherWidth = self:ColumnFrame(other) and self:ColumnFrame(other):GetWidth() or COLUMNS[other].default
    local room = (self.frame:GetWidth() or 0) - GUTTERS - otherWidth - BROWSER_MIN
    return math.max(spec.min, math.min(spec.max or room, room))
end

function UI:SetColumnWidth(name, width, save)
    local spec = COLUMNS[name]
    width = W.Clamp(tonumber(width) or spec.default, spec.min, self:ColumnMax(name))
    self:ColumnFrame(name):SetWidth(width)
    if name == "facets" then self:LayoutListActions(width) end
    if save then view()[spec.saved] = width ~= spec.default and width or nil end
    return width
end

function UI:FitColumns()
    for _, name in ipairs({"facets", "inspector"}) do self:SetColumnWidth(name, view()[COLUMNS[name].saved]) end
end

function UI:CreateSplitter(body, name)
    local spec, column = COLUMNS[name], self:ColumnFrame(name)
    local leftEdge = spec.edge == "left"
    local handle = CreateFrame("Button", nil, body)
    handle:SetWidth(HANDLE)
    if leftEdge then
        handle:SetPoint("TOPRIGHT", column, "TOPLEFT", -1, 0)
        handle:SetPoint("BOTTOMRIGHT", column, "BOTTOMLEFT", -1, 0)
    else
        handle:SetPoint("TOPLEFT", column, "TOPRIGHT", 1, 0)
        handle:SetPoint("BOTTOMLEFT", column, "BOTTOMRIGHT", 1, 0)
    end
    handle:EnableMouse(true)
    local line = handle:CreateTexture(nil, "OVERLAY")
    line:SetPoint("TOP")
    line:SetPoint("BOTTOM")
    line:SetWidth(2)
    line:SetColorTexture(unpack(T.accent))
    line:SetAlpha(0)
    handle.line = line
    W.Tip(handle, spec.title, spec.hint)
    local showTip = handle:GetScript("OnEnter")
    local hideTip = handle:GetScript("OnLeave")
    handle:SetScript("OnEnter", function(frame) line:SetAlpha(0.6); showTip(frame) end)
    handle:SetScript("OnLeave", function(frame) if not handle.drag then line:SetAlpha(0) end; hideTip(frame) end)
    handle:SetScript("OnMouseDown", function()
        handle.drag = {x = GetCursorPosition(), width = column:GetWidth()}
        handle:SetScript("OnUpdate", function()
            local moved = (GetCursorPosition() - handle.drag.x) / handle:GetEffectiveScale()
            self:SetColumnWidth(name, handle.drag.width + (leftEdge and -moved or moved))
        end)
    end)
    handle:SetScript("OnMouseUp", function()
        handle:SetScript("OnUpdate", nil)
        handle.drag = nil
        line:SetAlpha(0)
        self:SetColumnWidth(name, column:GetWidth(), true)
    end)
    handle:SetScript("OnDoubleClick", function() self:SetColumnWidth(name, spec.default, true) end)
    self.splitters[name] = handle
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
    -- A smaller window keeps the results usable by narrowing the side columns.
    frame:SetScript("OnSizeChanged", function()
        if self.splitters then self:FitColumns() end
    end)

    local body = CreateFrame("Frame", nil, frame)
    body:SetAllPoints()
    self.body = body
    self:CreateToolbar(body)
    local facets = self:CreateFacetColumn(body)

    self.inspector = ML.Inspector.New(body, {
        onFavorite = function(entry) self:ToggleFavorite(entry) end,
        onLists = function(entry, button) self:OpenListMenu(self:Picked(entry), button) end,
        onTarget = function() self:FromTarget() end,
    })
    self.inspector.frame:SetPoint("TOPRIGHT", -12, -(TITLE + 40))
    self.inspector.frame:SetPoint("BOTTOMRIGHT", -12, 12)
    self.splitters = {}
    self:CreateSplitter(body, "facets")
    self:CreateSplitter(body, "inspector")
    self:FitColumns()

    local prev = W.Button(body, "<", 26, function() self.browser:Page(-1) end, 24)
    local nextPage = W.Button(body, ">", 26, function() self.browser:Page(1) end, 24)
    nextPage:SetPoint("TOPRIGHT", self.inspector.frame, "TOPLEFT", -10, 0)
    prev:SetPoint("RIGHT", nextPage, "LEFT", -4, 0)
    self.range = W.Label(body, "", 11, T.muted)
    self.range:SetPoint("RIGHT", prev, "LEFT", -8, 0)
    self.range:SetJustifyH("RIGHT")

    self.browser = ML.Browser.New(body, {
        onSelect = function(entry, modifiers) self:Select(entry, modifiers) end,
        onMenu = function(entry) self:ContextMenu(entry) end,
        isSelected = function(entry) return ML.Selection:Count() > 1 and ML.Selection:Has(entry) end,
        onPlay = function(entry)
            self:Select(entry)
            local preview = self.inspector:Preview("sound")
            if not ML.db.view.autoplay then preview:Play(entry) end
        end,
        onChanged = function() self:UpdatePager() end,
    })
    self.browser.frame:SetPoint("TOPLEFT", facets, "TOPRIGHT", 10, 0)
    self.browser.frame:SetPoint("BOTTOMRIGHT", self.inspector.frame, "BOTTOMLEFT", -10, 0)
    self:CreateTray(body)
    self.tray:SetPoint("BOTTOMLEFT", facets, "BOTTOMRIGHT", 10, 0)
    self.tray:SetPoint("BOTTOMRIGHT", self.inspector.frame, "BOTTOMLEFT", -10, 0)

    local resize = CreateFrame("Button", nil, body)
    self.resizeGrip = resize
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
    self:UpdateMaximize()
    C:Start(function(kind) self:OnIndexed(kind) end)
    self:SelectTab(self.tabId)
    if not ML.db.welcomed then self:ShowHelp() end
end

function UI:Show()
    ML.db.minimized = nil
    ML.Dock.Hide()
    if not self.frame then self:Create() end
    self.frame:Show()
    self:Refresh()
    if self.tabId and not self.selected[self.tabId] and self.results[1] and self.tabId ~= ML.ListsTab then
        self:Select(self.results[1])
    end
end

function UI:Toggle()
    if self.frame and self.frame:IsShown() then self.frame:Hide() else self:Show() end
end
