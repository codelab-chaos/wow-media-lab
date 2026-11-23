local _, ML = ...

-- Named lists of catalog entries. An entry can be in any number of lists; a
-- list holds entry keys, so it survives reloads and client updates. Saved in
-- ML.db.lists as {id, name, keys = {[entry key] = true}} in the order made.
-- Favorites is built in: always the first list, never renamed or deleted, and
-- what right-click and the star toggle. It knows nothing about frames.
local Lists = {}
ML.Lists = Lists

Lists.FAVORITES = 1 -- the built-in list's id
Lists.FAVORITES_NAME = "Favorites"
Lists.MAX_NAME = 40

local function db() return ML.db end

local function cleanName(name)
    name = tostring(name or ""):gsub("[%c]", ""):match("^%s*(.-)%s*$")
    if name == "" then return nil end
    return name:sub(1, Lists.MAX_NAME)
end

-- Saved-variable cleanup, called once from ML.Initialize. Favorites is put
-- first (made if missing); the old favorites set fills it.
function Lists.Sanitize(saved)
    local lists, seen = {}, {}
    for _, list in ipairs(type(saved.lists) == "table" and saved.lists or {}) do
        local id, name = tonumber(type(list) == "table" and list.id), type(list) == "table" and cleanName(list.name)
        if id and name and not seen[id] then
            seen[id] = true
            local keys = {}
            for key, value in pairs(type(list.keys) == "table" and list.keys or {}) do
                if type(key) == "string" and value == true then keys[key] = true end
            end
            lists[#lists + 1] = {id = id, name = name, keys = keys}
        end
    end
    local favorites
    for index, list in ipairs(lists) do
        if list.id == Lists.FAVORITES then favorites = table.remove(lists, index); break end
    end
    favorites = favorites or {id = Lists.FAVORITES, keys = {}}
    favorites.name = Lists.FAVORITES_NAME
    table.insert(lists, 1, favorites)
    if type(saved.favorites) == "table" then
        for key, value in pairs(saved.favorites) do
            if type(key) == "string" and value == true then favorites.keys[key] = true end
        end
    end
    saved.favorites = nil
    local nextId = 1
    for _, list in ipairs(lists) do nextId = math.max(nextId, list.id + 1) end
    saved.lists = lists
    saved.nextListId = math.max(tonumber(saved.nextListId) or 1, nextId)
    return saved
end

function Lists:All() return db().lists end

function Lists:Get(id)
    for _, list in ipairs(db().lists) do if list.id == id then return list end end
end

function Lists:Named(name)
    name = cleanName(name)
    if not name then return end
    for _, list in ipairs(db().lists) do if list.name:lower() == name:lower() then return list end end
end

-- Returns the new list, or nil and a reason.
function Lists:Create(name)
    name = cleanName(name)
    if not name then return nil, "Give the list a name." end
    if self:Named(name) then return nil, "A list called " .. name .. " already exists." end
    local list = {id = db().nextListId, name = name, keys = {}}
    db().nextListId = list.id + 1
    db().lists[#db().lists + 1] = list
    return list
end

function Lists:Favorites() return self:Get(Lists.FAVORITES) end

function Lists.IsBuiltIn(list) return list ~= nil and list.id == Lists.FAVORITES end

function Lists:IsFavorite(key) return self:Has(self:Favorites(), key) end

function Lists:ToggleFavorite(key) return self:Toggle(self:Favorites(), key) end

function Lists:Rename(id, name)
    local list = self:Get(id)
    name = cleanName(name)
    if not list then return nil, "That list is gone." end
    if Lists.IsBuiltIn(list) then return nil, "Favorites keeps its name." end
    if not name then return nil, "Give the list a name." end
    local other = self:Named(name)
    if other and other ~= list then return nil, "A list called " .. name .. " already exists." end
    list.name = name
    return list
end

function Lists:Delete(id)
    if id == Lists.FAVORITES then return false end
    for index, list in ipairs(db().lists) do
        if list.id == id then
            table.remove(db().lists, index)
            return true
        end
    end
    return false
end

function Lists:Has(list, key) return list ~= nil and list.keys[key] == true end

function Lists:Set(list, key, member) list.keys[key] = member and true or nil end

-- Returns whether the key is in the list afterwards.
function Lists:Toggle(list, key)
    self:Set(list, key, not list.keys[key])
    return list.keys[key] == true
end

-- The lists holding a key, in list order.
function Lists:Of(key)
    local result = {}
    for _, list in ipairs(db().lists) do if list.keys[key] then result[#result + 1] = list end end
    return result
end

function Lists:InAny(key)
    for _, list in ipairs(db().lists) do if list.keys[key] then return true end end
    return false
end

-- Facet names used for lists on the Lists tab ("list:3"), so the filter
-- column can show them like any other facet.
function Lists.Facet(list) return "list:" .. list.id end
function Lists:FromFacet(facet)
    local id = tonumber(tostring(facet or ""):match("^list:(%d+)$"))
    return id and self:Get(id)
end
