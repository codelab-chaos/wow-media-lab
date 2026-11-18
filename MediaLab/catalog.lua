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
        entry.inherits or "", table.concat(entry.facets, " ")}
    return table.concat(parts, " "):lower()
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

-- Saved favorites that exist in this client, without scanning every entry.
function Catalog:FavoriteCount()
    local count = 0
    for key in pairs(ML.db.favorites) do
        if self.byKey[key] then count = count + 1 end
    end
    return count
end

function Catalog:TabCount(tabId)
    return tabId == "favorites" and self:FavoriteCount() or self:Count(tabId)
end

function Catalog:IsFavorite(entry) return ML.db.favorites[entry.key] == true end

function Catalog:ToggleFavorite(entry)
    ML.db.favorites[entry.key] = not ML.db.favorites[entry.key] or nil
end

-- The entries a tab shows before search and facet filtering.
function Catalog:List(tabId)
    if tabId ~= "favorites" then return self.byKind[tabId] or {} end
    local result = {}
    for _, kind in ipairs(ML.Kinds) do
        for _, entry in ipairs(self.byKind[kind.id] or {}) do
            if ML.db.favorites[entry.key] then result[#result + 1] = entry end
        end
    end
    return result
end

function Catalog:FacetOf(tabId, entry)
    return tabId == "favorites" and ML.KindById[entry.kind].label or nil
end

-- Facet counts for a tab, most common first; "Common" always leads when present.
function Catalog:Facets(tabId)
    local counts, order = {}, {}
    for _, entry in ipairs(self:List(tabId)) do
        local facets = tabId == "favorites" and {self:FacetOf(tabId, entry)} or entry.facets
        for _, facet in ipairs(facets) do
            if not counts[facet] then counts[facet] = 0; order[#order + 1] = facet end
            counts[facet] = counts[facet] + 1
        end
    end
    table.sort(order, function(a, b)
        if (a == "Common") ~= (b == "Common") then return a == "Common" end
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
            or (tabId == "favorites" and self:FacetOf(tabId, entry) == facet)
            or (tabId ~= "favorites" and entry.facetSet[facet])
        if include then
            for _, term in ipairs(terms) do
                if not entry.search:find(term, 1, true) then include = false; break end
            end
            if include then result[#result + 1] = entry end
        end
    end
    return result
end
