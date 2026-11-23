local _, ML = ...

-- One provider per kind. A provider gathers references from the running client
-- (preferred) or the generated catalog (fallback) and hands each one to add().
-- step() lets the indexer yield between batches. Providers never touch the UI.
local Sources = {}
ML.Sources = Sources

local function token(value, pattern)
    local first = tostring(value):match(pattern)
    return first and first ~= "" and first or "Other"
end

local function lowerFirst(value) return (value:gsub("^%l", string.upper)) end

local function isIconPath(path)
    return tostring(path):lower():find("^interface\\icons\\") ~= nil
end

function Sources.Normalize(path)
    return (tostring(path):gsub("/", "\\"):gsub("\\+", "\\"):gsub("%.[bB][lL][pP]$", ""):gsub("%.[tT][gG][aA]$", ""))
end

local function commonSet(kind)
    local set = {}
    for _, name in ipairs(ML.Common[kind] or {}) do set[name] = true end
    return set
end

local function safe(fn, ...)
    if type(fn) ~= "function" then return end
    local ok, result = pcall(fn, ...)
    if ok then return result end
end

-- Optional icon metadata from the load-on-demand MediaLab_Icons addon, built
-- offline by scripts/icon-metadata.py: [fileID] = "name\tcolors\tsubject\ttags\tdescription".
-- Loaded once, when icons are indexed, and released from the global table.
function Sources.IconMeta(step)
    if Sources.iconMeta ~= nil then return Sources.iconMeta or nil, Sources.iconIds end
    local load = C_AddOns and C_AddOns.LoadAddOn or LoadAddOn
    if load and type(MediaLabIconMeta) ~= "table" then pcall(load, "MediaLab_Icons") end
    local meta = type(MediaLabIconMeta) == "table" and MediaLabIconMeta or false
    MediaLabIconMeta = nil
    Sources.iconMeta, Sources.iconIds = meta, {}
    if meta then
        for id, raw in pairs(meta) do
            Sources.iconIds[raw:match("^[^\t]*")] = id
            if step then step() end
        end
    end
    return meta or nil, Sources.iconIds
end

local function capital(value) return (value:gsub("^%l", string.upper)) end

-- Fills name, tags, description and Subject/Color facets for a known file ID.
local function describeIcon(data, meta, id)
    local raw = meta and meta[id]
    if not raw then return data end
    local name, colors, subject, tags, description = raw:match("^([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t(.*)$")
    if not name then return data end
    data.value, data.id, data.name = id, id, name
    data.path = "Interface\\Icons\\" .. name
    data.tags = tags ~= "" and tags:gsub(",", ", ") or nil
    data.subject = subject ~= "" and subject or nil
    data.description = description ~= "" and description or nil
    local facets = data.facets
    if data.subject then facets[#facets + 1] = "Subject: " .. capital(subject) end
    for color in colors:gmatch("[^,]+") do facets[#facets + 1] = "Color: " .. capital(color) end
    return data
end

Sources.icon = function(add, step)
    local meta, ids = Sources.IconMeta(step)
    local function addIcon(data)
        local id = data.id
        if not id and meta then id = ids[tostring(data.value):match("[^\\]+$"):lower()] end
        add(describeIcon(data, meta, id))
    end
    local lists = {
        {api = "GetMacroIcons", facet = "Spell icons"},
        {api = "GetMacroItemIcons", facet = "Item icons"},
        {api = "GetLooseMacroIcons", facet = "Loose spell icons"},
        {api = "GetLooseMacroItemIcons", facet = "Loose item icons"},
    }
    for _, list in ipairs(lists) do
        local icons = {}
        if type(_G[list.api]) == "function" and pcall(_G[list.api], icons) then
            for _, value in ipairs(icons) do
                local numeric = tonumber(value)
                if numeric then
                    addIcon({value = numeric, id = numeric, name = "File " .. numeric, facets = {list.facet}, origin = list.api})
                elseif type(value) == "string" and value ~= "" then
                    local path = value:find("[\\/]") and Sources.Normalize(value) or "Interface\\Icons\\" .. value
                    addIcon({value = path, name = path:match("[^\\]+$"), facets = {list.facet}, origin = list.api})
                end
                step()
            end
        end
    end
    for _, path in ipairs(ML.TexturePaths or {}) do
        if isIconPath(path) then
            addIcon({value = path, name = path:match("[^\\]+$"), facets = {"UI source"}, origin = "Blizzard UI source"})
        end
    end
end

Sources.texture = function(add, step)
    -- Folder filters: one spelling per folder, whatever casing the source used.
    local spelling = {}
    for _, path in ipairs(ML.TexturePaths or {}) do
        if not isIconPath(path) then
            local folder = token(path, "^[^\\]+\\([^\\]+)\\")
            spelling[folder:lower()] = spelling[folder:lower()] or lowerFirst(folder)
            add({value = path, name = path:match("[^\\]+$"), facets = {spelling[folder:lower()]},
                origin = "Blizzard UI source"})
        end
        step()
    end
end

function Sources.AtlasInfo(name)
    if not (C_Texture and C_Texture.GetAtlasInfo) then return end
    local ok, info = pcall(C_Texture.GetAtlasInfo, name)
    if ok and type(info) == "table" then return info end
end

Sources.atlas = function(add, step)
    local names = C_Texture and safe(C_Texture.GetAtlasElements)
    local native = type(names) == "table"
    Sources.nativeAtlases = native
    for _, name in pairs(native and names or ML.AtlasFallback or {}) do
        if type(name) == "string" and name ~= "" and (native or Sources.AtlasInfo(name)) then
            add({value = name, name = name, facets = {lowerFirst(token(name, "^([%w]+)"))},
                origin = native and "Client atlas list" or "UI source (validated)"})
        end
        step()
    end
end

Sources.sound = function(add, step)
    local common, seen = commonSet("sound"), {}
    local function sound(name, id, origin)
        if type(name) ~= "string" or type(id) ~= "number" or seen[name] then return end
        seen[name] = true
        local facets = {token(name, "^([%u%d]+)_")}
        if common[name] then facets[#facets + 1] = "Common" end
        add({value = name, id = id, name = name, facets = facets, origin = origin})
        step()
    end
    if type(SOUNDKIT) == "table" then
        for name, id in pairs(SOUNDKIT) do sound(name, id, "Client SOUNDKIT") end
    end
    for _, row in ipairs(ML.SoundKits or {}) do sound(row[1], row[2], "UI source") end
end

Sources.control = function(add, step)
    local common, known = commonSet("control"), {}
    for _, row in ipairs(ML.Templates or {}) do known[row[1]] = row end
    local function control(name, tag)
        -- Font objects have their own tab.
        if type(name) ~= "string" or tag == "Font" or tag == "FontFamily" then return end
        local row = known[name]
        local facets = {tag or (row and row[2]) or "Frame"}
        if common[name] then facets[#facets + 1] = "Common" end
        add({value = name, name = name, facets = facets, tag = facets[1],
            inherits = row and row[3] ~= "" and row[3] or nil, source = row and row[4] or nil,
            origin = row and "UI source" or "Client template list"})
        step()
    end
    local templates = C_XMLUtil and safe(C_XMLUtil.GetTemplates)
    Sources.nativeTemplates = type(templates) == "table"
    if Sources.nativeTemplates then
        for _, info in ipairs(templates) do
            if type(info) == "table" then control(info.name, info.type) end
        end
    else
        for _, row in ipairs(ML.Templates or {}) do control(row[1], row[2]) end
    end
end

function Sources.FontObject(name)
    local object = type(name) == "string" and _G[name]
    if type(object) == "table" and type(object.GetFont) == "function" then return object end
end

Sources.font = function(add, step)
    local common, seen = commonSet("font"), {}
    local function font(name, origin)
        if seen[name] or not Sources.FontObject(name) then return end
        seen[name] = true
        local facets = {token(name, "^(%u%l+)")}
        if common[name] then facets[#facets + 1] = "Common" end
        add({value = name, name = name, facets = facets, origin = origin})
        step()
    end
    local names = safe(GetFonts)
    if type(names) == "table" then
        for _, name in ipairs(names) do font(name, "Client font list") end
    end
    for _, row in ipairs(ML.FontTemplates or {}) do font(row[1], "UI source") end
end

-- Creature displays from the load-on-demand MediaLab_Models addon, built
-- offline by scripts/creature-models.py from the client's DB2 tables:
-- [displayID] = "name\ttype\tfamily\tmodel file ID\tskins". Loaded once, when
-- models are indexed, and released from the global table.
function Sources.ModelData()
    if Sources.modelData ~= nil then return Sources.modelData or nil end
    local load = C_AddOns and C_AddOns.LoadAddOn or LoadAddOn
    if load and type(MediaLabModels) ~= "table" then pcall(load, "MediaLab_Models") end
    Sources.modelData = type(MediaLabModels) == "table" and MediaLabModels or false
    MediaLabModels = nil
    return Sources.modelData or nil
end

Sources.SEEN = "Seen in game"

-- NPC names learned from targets (npcs.lua) join a display's description,
-- search words and facets. Safe to call again after a new capture; the
-- catalog's Touch then refreshes its search text.
function Sources.ApplyNpcs(entry)
    local names = ML.Npcs:ForDisplay(entry.id)
    entry.npcs = #names > 0 and names or nil
    entry.description = entry.npcs and ("Seen as " .. table.concat(names, ", ")) or nil
    entry.keywords = table.concat({tostring(entry.model or ""), table.concat(names, " ")}, " ")
    if entry.npcs then
        local seen = false
        for _, facet in ipairs(entry.facets) do seen = seen or facet == Sources.SEEN end
        if not seen then entry.facets[#entry.facets + 1] = Sources.SEEN end
    end
    return entry
end

Sources.model = function(add, step)
    for id, raw in pairs(Sources.ModelData() or {}) do
        local name, kind, family, model, skins = raw:match("^([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t(.*)$")
        if name then
            add(Sources.ApplyNpcs({value = id, id = id, name = name, model = tonumber(model), family = family,
                tags = skins ~= "" and skins:gsub(",", ", ") or nil,
                facets = {kind, "Family: " .. capital(family)}, origin = "Client creature tables"}))
        end
        step()
    end
end
