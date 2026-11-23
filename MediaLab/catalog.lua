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

-- Builds every kind in ML.IndexOrder inside one coroutine, yielding every
-- BATCH references. onKind(kind) fires as each kind finishes.
function Catalog:Start(onKind)
    if self.started then return end
    self.started = true
    local count = 0
    local function step()
        count = count + 1
        if count % BATCH == 0 then coroutine.yield() end
    end
    local thread = coroutine.create(function()
        for _, kind in ipairs(ML.IndexOrder) do
            local source = ML.Sources[kind]
            if source then source(function(data) return self:Add(kind, data) end, step) end
            table.sort(self.byKind[kind] or {}, byName)
            self.indexed[kind] = true
            if onKind then onKind(kind) end
            coroutine.yield()
        end
        self.ready = true
    end)
    self.worker = CreateFrame("Frame")
    self.worker:SetScript("OnUpdate", function(frame)
        local ok, err = coroutine.resume(thread)
        if ok and coroutine.status(thread) ~= "dead" then return end
        frame:SetScript("OnUpdate", nil)
        frame:Hide()
        if not ok then
            self.error = tostring(err)
            ML.Print("Indexing stopped: " .. self.error)
        end
        if onKind then onKind(nil) end
    end)
end

function Catalog:Count(kind) return #(self.byKind[kind] or {}) end

-- Saved entries that exist in this client, without scanning every entry.
-- With a list, only that list's; without, those in any list.
function Catalog:SavedCount(list)
    local count = 0
    if list then
        for key in pairs(list.keys) do if self.byKey[key] then count = count + 1 end end
        return count
    end
    local seen = {}
    for _, saved in ipairs(ML.Lists:All()) do
        for key in pairs(saved.keys) do
            if not seen[key] and self.byKey[key] then seen[key] = true; count = count + 1 end
        end
    end
    return count
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
    local function rank(facet) return groups[facet:match("^([^:]+): ") or ""] or 0 end
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
function Catalog:Filter(tabId, facet, query)
    local terms = {}
    for term in tostring(query or ""):lower():gmatch("%S+") do terms[#terms + 1] = term end
    local result = {}
    for _, entry in ipairs(self:List(tabId)) do
        local include = not facet
            or (tabId == ML.ListsTab and ML.Lists:Has(ML.Lists:FromFacet(facet), entry.key))
            or (tabId ~= ML.ListsTab and entry.facetSet[facet])
        if include then
            for _, term in ipairs(terms) do
                if not entry.search:find(term, 1, true) then include = false; break end
            end
            if include then result[#result + 1] = entry end
        end
    end
    return result
end
