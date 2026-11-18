local _, ML = ...

-- Turns catalog entries into plain rows: a full snapshot for the load-on-demand
-- MediaLab_Export addon (written to disk on /reload) and small CSV listings for
-- copying. It reads the catalog and client APIs; it knows nothing about frames.
local Export = {}
ML.Export = Export

Export.ADDON = "MediaLab_Export"
Export.CSV_LIMIT = 500

local function facets(entry) return table.concat(entry.facets, ";") end

local function atlas(entry)
    local info = ML.Sources.AtlasInfo(entry.value) or {}
    return {entry.name, info.width, info.height, info.file or info.filename,
        info.leftTexCoord, info.rightTexCoord, info.topTexCoord, info.bottomTexCoord, facets(entry)}
end

local function template(entry)
    local ok, info = pcall(C_XMLUtil and C_XMLUtil.GetTemplateInfo or error, entry.value)
    info = ok and type(info) == "table" and info or {}
    return {entry.name, entry.tag or info.type, entry.inherits, entry.source, info.width, info.height, facets(entry)}
end

local function font(entry)
    local object = ML.Sources.FontObject(entry.value)
    local file, size, flags
    if object then file, size, flags = object:GetFont() end
    return {entry.name, file, size, flags, facets(entry)}
end

-- One row shape per kind: column names, then how to fill them from an entry.
Export.Shapes = {
    icon = {fields = {"value", "facets"}, row = function(e) return {e.value, facets(e)} end},
    texture = {fields = {"path", "facets"}, row = function(e) return {e.value, facets(e)} end},
    atlas = {fields = {"name", "width", "height", "file", "left", "right", "top", "bottom", "facets"}, row = atlas},
    sound = {fields = {"name", "id", "facets"}, row = function(e) return {e.name, e.id, facets(e)} end},
    control = {fields = {"name", "type", "inherits", "source", "width", "height", "facets"}, row = template},
    font = {fields = {"name", "file", "size", "flags", "facets"}, row = font},
}

function Export.Rows(kind, entries)
    local shape = Export.Shapes[kind]
    local rows = {}
    for index, entry in ipairs(entries) do rows[index] = shape.row(entry) end
    return {fields = shape.fields, rows = rows}
end

-- Everything the catalog holds, with the client build it came from.
function Export.Snapshot()
    local version, build, date, interface = GetBuildInfo()
    local snapshot = {
        addonVersion = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ML.name, "Version"),
        client = {version = version, build = build, date = date, interface = interface},
        exported = time and time() or nil,
        kinds = {},
    }
    local total = 0
    for _, kind in ipairs(ML.Kinds) do
        local entries = ML.Catalog.byKind[kind.id] or {}
        snapshot.kinds[kind.id] = Export.Rows(kind.id, entries)
        total = total + #entries
    end
    return snapshot, total
end

local function loadHolder()
    local load = C_AddOns and C_AddOns.LoadAddOn or LoadAddOn
    if not load then return false, "no LoadAddOn" end
    local loaded, reason = load(Export.ADDON)
    return loaded, reason
end

-- Fills MediaLabExport; the game writes it to SavedVariables on /reload or logout.
function Export.Save()
    if not ML.Catalog.ready then return false, "The catalog is still indexing. Try again when the lab says Ready." end
    local loaded, reason = loadHolder()
    if not loaded then
        return false, "Enable the MediaLab_Export addon to export (" .. tostring(reason or "not loaded") .. ")."
    end
    local snapshot, total = Export.Snapshot()
    MediaLabExport = snapshot
    return true, total
end

local function csvCell(value)
    if value == nil then return "" end
    value = tostring(value)
    if value:find('[,"\n]') then value = '"' .. value:gsub('"', '""') .. '"' end
    return value
end

-- A CSV listing of the given entries, capped so the text box stays responsive.
-- Mixed kinds (Favorites) share a simple kind,name,value,id shape.
function Export.Csv(entries)
    local kinds = {}
    for _, entry in ipairs(entries) do kinds[entry.kind] = true end
    local single = next(kinds) and next(kinds, next(kinds)) == nil and next(kinds)
    local fields = single and Export.Shapes[single].fields or {"kind", "name", "value", "id"}
    local lines = {table.concat(fields, ",")}
    local count = math.min(#entries, Export.CSV_LIMIT)
    for index = 1, count do
        local entry = entries[index]
        local row = single and Export.Shapes[single].row(entry) or {entry.kind, entry.name, entry.value, entry.id}
        local cells = {}
        for column = 1, #fields do cells[column] = csvCell(row[column]) end
        lines[#lines + 1] = table.concat(cells, ",")
    end
    return table.concat(lines, "\n"), count, #entries
end
