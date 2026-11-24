local _, ML = ...

-- The catalog stores entries per kind, indexes them in small batches, and
-- answers filter and facet queries. It knows nothing about frames.
local Catalog = {byKind = {}, byKey = {}, ready = false, started = false, indexed = {}}
ML.Catalog = Catalog

local BATCH = 200

function Catalog:Key(kind, value)
    if type(value) == "number" then return kind .. ":" .. value end
    local canonical = tostring(value)
    if kind == "icon" or kind == "texture" then canonical = ML.Sources.Normalize(canonical):lower() end
    return kind .. ":" .. canonical
end

local function searchText(entry)
    local parts = {entry.name, tostring(entry.value), entry.id and tostring(entry.id) or "", entry.tag or "",
        entry.inherits or "", entry.tags or "", entry.subject or "", entry.keywords or "", table.concat(entry.facets, " ")}
    return table.concat(parts, " "):lower()
end

-- After a provider changes an entry's facets or words (a new NPC name).
function Catalog:Touch(entry)
    entry.facetSet = {}
    for _, facet in ipairs(entry.facets) do entry.facetSet[facet] = true end
    entry.search = searchText(entry)
    return entry
end

function Catalog:Add(kind, data)
    if data.value == nil or data.value == "" then return end
    local key = self:Key(kind, data.value)
    local entry = self.byKey[key]
    if entry then
        -- The same reference from another source keeps one entry with every facet.
        for _, facet in ipairs(data.facets or {}) do
            if not entry.facetSet[facet] then
                entry.facetSet[facet] = true
                entry.facets[#entry.facets + 1] = facet
            end
        end
        entry.search = searchText(entry)
        return entry
    end
    entry = data
    entry.kind, entry.key = kind, key
    entry.name = entry.name or tostring(entry.value)
    entry.facets = entry.facets or {}
    entry.facetSet = {}
    for _, facet in ipairs(entry.facets) do entry.facetSet[facet] = true end
    entry.search = searchText(entry)
    self.byKey[key] = entry
    local list = self.byKind[kind]
    if not list then list = {}; self.byKind[kind] = list end
    list[#list + 1] = entry
    return entry
end

local function byName(a, b)
    local left, right = a.name:lower(), b.name:lower()
    if left == right then return a.key < b.key end
    return left < right
end

-- Kinds are indexed on demand: Load(kinds) queues the ones not yet indexed,
-- and one worker builds them, in ML.IndexOrder, inside a coroutine that yields
-- every BATCH references. Start(onKind, onProgress) sets the listeners:
-- onKind(kind) as each kind finishes and onKind(nil) when the queue is empty;
-- onProgress(kind) after every batch, for the loading card. `ready` is true
-- while nothing is queued; `current` is the kind being built.
function Catalog:Start(onKind, onProgress)
    self.started = true
    self.onKind, self.onProgress = onKind, onProgress
    self.queue, self.waiting = self.queue or {}, self.waiting or {}
    self.ready = #self.queue == 0 and not self.current
end

function Catalog:IsQueued(kind)
    if self.current == kind then return true end
    for _, queued in ipairs(self.queue or {}) do if queued == kind then return true end end
    return false
end

-- Queues the kinds not yet indexed; done() runs once they all are (at once
-- when they already are). `first` puts them ahead of the queue (what you are
-- looking at goes before background work). Returns the kinds still to build.
function Catalog:Load(kinds, done, first)
    self.queue, self.waiting = self.queue or {}, self.waiting or {}
    local pending = {}
    for _, kind in ipairs(kinds) do
        if not self.indexed[kind] then pending[#pending + 1] = kind end
    end
    for index, kind in ipairs(pending) do
        if first then
            for at = #self.queue, 1, -1 do if self.queue[at] == kind then table.remove(self.queue, at) end end
            if self.current ~= kind then table.insert(self.queue, index, kind) end
        elseif not self:IsQueued(kind) then
            self.queue[#self.queue + 1] = kind
        end
    end
    if #pending == 0 then
        if done then done() end
        return pending
    end
    if done then self.waiting[#self.waiting + 1] = {kinds = pending, done = done} end
    self.ready = false
    self:Run()
    return pending
end

function Catalog:Notify(kind)
    if self.onKind then self.onKind(kind) end
    local still = {}
    for _, wait in ipairs(self.waiting) do
        local all = true
        for _, wanted in ipairs(wait.kinds) do all = all and self.indexed[wanted] == true end
        if all then wait.done() else still[#still + 1] = wait end
    end
    self.waiting = still
end

function Catalog:Run()
    if self.thread then return end
    local count = 0
    local function step()
        count = count + 1
        if count % BATCH == 0 then
            if self.onProgress then self.onProgress(self.current) end
            coroutine.yield()
        end
    end
    self.thread = coroutine.create(function()
        while #self.queue > 0 do
            local kind = table.remove(self.queue, 1)
            self.current = kind
            if self.onProgress then self.onProgress(kind) end
            local source = ML.Sources[kind]
            if source then source(function(data) return self:Add(kind, data) end, step) end
            table.sort(self.byKind[kind] or {}, byName)
            self.indexed[kind] = true
            self.current = nil
            self:Notify(kind)
            coroutine.yield()
        end
        self.ready = true
    end)
    -- The worker's OnUpdate is attached only while there is work.
    self.worker = self.worker or CreateFrame("Frame")
    self.worker:Show()
    self.worker:SetScript("OnUpdate", function(frame)
        local ok, err = coroutine.resume(self.thread)
        if ok and coroutine.status(self.thread) ~= "dead" then return end
        self.thread = nil
        frame:SetScript("OnUpdate", nil)
        frame:Hide()
        if not ok then
            self.error = tostring(err)
            self.current, self.queue, self.ready = nil, {}, true
            ML.Print("Indexing stopped: " .. self.error)
        end
        if #self.queue > 0 then return self:Run() end
        self:Notify(nil)
    end)
end

function Catalog:Count(kind) return #(self.byKind[kind] or {}) end

-- A saved key's kind: "sound:417" is a sound.
function Catalog.KindOf(key) return tostring(key):match("^([^:]+):") end

-- A saved entry exists in this client, or its kind is not indexed yet (and
-- it is taken on trust until it is).
function Catalog:Known(key)
    if self.byKey[key] then return true end
    local kind = Catalog.KindOf(key)
    return kind ~= nil and ML.KindById[kind] ~= nil and not self.indexed[kind]
end

-- The kinds the saved lists hold entries of, to index for the Lists tab.
function Catalog:SavedKinds()
    local seen, kinds = {}, {}
    for _, list in ipairs(ML.Lists:All()) do
        for key in pairs(list.keys) do
            local kind = Catalog.KindOf(key)
            if kind and ML.KindById[kind] and not seen[kind] then seen[kind] = true; kinds[#kinds + 1] = kind end
        end
    end
    return kinds
end

-- Saved entries that exist in this client, without scanning every entry.
-- With a list, only that list's; without, those in any list.
function Catalog:SavedCount(list)
    local count = 0
    if list then
        for key in pairs(list.keys) do if self:Known(key) then count = count + 1 end end
        return count
    end
    local seen = {}
    for _, saved in ipairs(ML.Lists:All()) do
        for key in pairs(saved.keys) do
            if not seen[key] and self:Known(key) then seen[key] = true; count = count + 1 end
        end
    end
    return count
end

-- The Lists tab's badge: how many lists, and how many entries across them
-- (an entry counts once in every list that holds it). "2:8" is two lists of four.
function Catalog:ListsBadge()
    local lists, entries = ML.Lists:All(), 0
    for _, list in ipairs(lists) do entries = entries + self:SavedCount(list) end
    return #lists .. ":" .. entries
end

function Catalog:TabCount(tabId)
    return tabId == ML.ListsTab and self:SavedCount() or self:Count(tabId)
end

function Catalog:IsFavorite(entry) return ML.Lists:IsFavorite(entry.key) end

-- The entries a tab shows before search and facet filtering.
function Catalog:List(tabId)
    if tabId ~= ML.ListsTab then return self.byKind[tabId] or {} end
    local result = {}
    for _, kind in ipairs(ML.Kinds) do
        for _, entry in ipairs(self.byKind[kind.id] or {}) do
            if ML.Lists:InAny(entry.key) then result[#result + 1] = entry end
        end
    end
    return result
end

-- On the Lists tab the facets are the lists themselves, in the order made,
-- including empty ones so they can be picked and filled.
function Catalog:ListFacets()
    local result = {}
    for _, list in ipairs(ML.Lists:All()) do
        result[#result + 1] = {name = ML.Lists.Facet(list), label = list.name, count = self:SavedCount(list)}
    end
    return result
end

-- Facet counts for a tab, most common first; "Common" always leads when present.
-- Grouped facets are stored as "Group: Value" so groups sort and never clash
-- (a type and a family can share a name); people see only the value, under a
-- group heading.
function Catalog.FacetGroup(facet) return facet:match("^([^:]+): ") end
function Catalog.FacetLabel(facet) return facet:match("^[^:]+: (.+)$") or facet end
function Catalog.FacetLabels(facets)
    local labels = {}
    for index, facet in ipairs(facets) do labels[index] = Catalog.FacetLabel(facet) end
    return table.concat(labels, ", ")
end

function Catalog:Facets(tabId)
    if tabId == ML.ListsTab then return self:ListFacets() end
    local counts, order = {}, {}
    for _, entry in ipairs(self:List(tabId)) do
        local facets = entry.facets
        for _, facet in ipairs(facets) do
            if not counts[facet] then counts[facet] = 0; order[#order + 1] = facet end
            counts[facet] = counts[facet] + 1
        end
    end
    -- Grouped facets ("Color: Green") follow the kind's facetGroups order, after plain ones.
    local groups = {}
    for index, group in ipairs((ML.KindById[tabId] or {}).facetGroups or {}) do groups[group] = index end
    local first = (ML.KindById[tabId] or {}).groupsFirst
    local function rank(facet)
        local group = groups[facet:match("^([^:]+): ") or ""]
        if not group then return 0 end
        return first and group - 100 or group
    end
    table.sort(order, function(a, b)
        if (a == "Common") ~= (b == "Common") then return a == "Common" end
        if rank(a) ~= rank(b) then return rank(a) < rank(b) end
        if counts[a] ~= counts[b] then return counts[a] > counts[b] end
        return a < b
    end)
    local result = {}
    for _, facet in ipairs(order) do result[#result + 1] = {name = facet, count = counts[facet]} end
    return result
end

-- Every search word must appear (literally) in the entry's name, reference, ID or facets.
-- size, when given, is {min, max} on the longer side; entries of unknown size drop out.
function Catalog:Filter(tabId, facet, query, size)
    local terms = {}
    for term in tostring(query or ""):lower():gmatch("%S+") do terms[#terms + 1] = term end
    local result = {}
    for _, entry in ipairs(self:List(tabId)) do
        local include = not facet
            or (tabId == ML.ListsTab and ML.Lists:Has(ML.Lists:FromFacet(facet), entry.key))
            or (tabId ~= ML.ListsTab and entry.facetSet[facet])
        if include and size then
            local longer = entry.width and math.max(entry.width, entry.height)
            include = longer ~= nil and longer >= size[1] and longer <= size[2]
        end
        if include then
            for _, term in ipairs(terms) do
                if not entry.search:find(term, 1, true) then include = false; break end
            end
            if include then result[#result + 1] = entry end
        end
    end
    return result
end
