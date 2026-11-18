-- Reads a MediaLab_Export saved variables file and prints it as JSON.
-- Usage: lua5.1 scripts/sv2json.lua <MediaLab_Export.lua>
local path = assert(arg[1], "usage: sv2json.lua <file>")
local chunk = assert(loadfile(path))
setfenv(chunk, {})
local env = getfenv(chunk)
chunk()
local data = assert(env.MediaLabExport, "no MediaLabExport in " .. path)

local encode
local function str(value)
    return '"' .. value:gsub('[%c"\\]', function(c)
        local named = {['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\t"] = "\\t", ["\r"] = "\\r"}
        return named[c] or string.format("\\u%04x", c:byte())
    end) .. '"'
end
local function num(value)
    if value == math.floor(value) and math.abs(value) < 2^53 then return string.format("%d", value) end
    return (string.format("%.6f", value):gsub("0+$", ""):gsub("%.$", ""))
end
function encode(value)
    local kind = type(value)
    if kind == "nil" then return "null" end
    if kind == "boolean" then return tostring(value) end
    if kind == "number" then return num(value) end
    if kind == "string" then return str(value) end
    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = key end
    if #keys == #value then
        local parts = {}
        for index = 1, #value do parts[index] = encode(value[index]) end
        return "[" .. table.concat(parts, ",") .. "]"
    end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local parts = {}
    for _, key in ipairs(keys) do parts[#parts + 1] = str(tostring(key)) .. ":" .. encode(value[key]) end
    return "{" .. table.concat(parts, ",") .. "}"
end

-- Rows can hold nils, so turn each one into an object over its kind's fields.
local out = {client = data.client, addonVersion = data.addonVersion, exported = data.exported, kinds = {}}
for kind, block in pairs(data.kinds or {}) do
    local items = {}
    for index, row in ipairs(block.rows or {}) do
        local item = {}
        for column, field in ipairs(block.fields) do item[field] = row[column] end
        items[index] = item
    end
    out.kinds[kind] = {fields = block.fields, items = items}
end
-- Empty item lists must stay arrays.
local text = encode(out):gsub('"items":{}', '"items":[]')
io.write(text, "\n")
