local _, ML = ...

-- Turns catalog entries into text to copy: a Lua table grouped by kind, or a
-- CSV listing. It reads the catalog and client APIs; it knows nothing about frames.
local Export = {}
ML.Export = Export

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
    model = {fields = {"display", "name", "model", "skins", "npcs", "facets"},
        row = function(e) return {e.id, e.name, e.model, e.tags, e.npcs and table.concat(e.npcs, ";"), facets(e)} end},
}

function Export.Rows(kind, entries)
    local shape = Export.Shapes[kind]
    local rows = {}
    for index, entry in ipairs(entries) do rows[index] = shape.row(entry) end
    return {fields = shape.fields, rows = rows}
end

local function csvCell(value)
    if value == nil then return "" end
    value = tostring(value)
    if value:find('[,"\n]') then value = '"' .. value:gsub('"', '""') .. '"' end
    return value
end

-- A CSV listing of the given entries, capped so the text box stays responsive.
-- Mixed kinds (a list) share a simple kind,name,value,id shape.
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

-- A Lua identifier from a list name: "Raid frame kit" -> "RaidFrameKit".
function Export.Identifier(name)
    local words = {}
    for word in tostring(name or ""):gmatch("%w+") do words[#words + 1] = word:sub(1, 1):upper() .. word:sub(2) end
    local identifier = table.concat(words)
    if identifier == "" then return "media" end
    if identifier:match("^%d") then identifier = "_" .. identifier end
    return identifier
end

-- The given entries as one Lua table, a field per kind in ML.Kinds order
-- (icons, textures, ...), each value ready to pass to the matching API. A
-- comment names entries whose value is not their name (icon file IDs).
-- Capped like the CSV listing.
function Export.Lua(entries, name)
    local count = math.min(#entries, Export.CSV_LIMIT)
    local byKind = {}
    for index = 1, count do
        local entry = entries[index]
        byKind[entry.kind] = byKind[entry.kind] or {}
        table.insert(byKind[entry.kind], entry)
    end
    local lines = {"local " .. Export.Identifier(name) .. " = {"}
    for _, kind in ipairs(ML.Kinds) do
        local group = byKind[kind.id]
        if group then
            lines[#lines + 1] = "    " .. kind.noun .. " = {"
            for _, entry in ipairs(group) do
                local value = ML.Snippets.Value(entry)
                local note = tostring(entry.value) ~= entry.name and (" -- " .. entry.name:gsub("[\r\n]", " ")) or ""
                lines[#lines + 1] = "        " .. value .. "," .. note
            end
            lines[#lines + 1] = "    },"
        end
    end
    lines[#lines + 1] = "}"
    return table.concat(lines, "\n"), count, #entries
end

-- One format from ML.CopyFormats.
function Export.Format(format, entries, name)
    if format == "lua" then return Export.Lua(entries, name) end
    return Export.Csv(entries)
end
