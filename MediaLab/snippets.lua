local _, ML = ...

-- Copyable fields for each kind: the reference itself first, then ready-to-paste
-- Lua. Pure functions of an entry; the inspector only displays what these return.
local Snippets = {}
ML.Snippets = Snippets

local function literal(value)
    if type(value) == "number" then return tostring(value) end
    return string.format("%q", value)
end

local function textureFields(entry)
    local ref = literal(entry.value)
    local fields = {}
    if type(entry.value) == "number" then
        fields[#fields + 1] = {label = "File ID", text = tostring(entry.value)}
    else
        fields[#fields + 1] = {label = "Name", text = entry.name}
        fields[#fields + 1] = {label = "Path", text = entry.value}
    end
    fields[#fields + 1] = {label = "Lua", text = "texture:SetTexture(" .. ref .. ")"}
    fields[#fields + 1] = {label = "Inline text", text = "CreateSimpleTextureMarkup(" .. ref .. ", 16, 16)"}
    if entry.tags then fields[#fields + 1] = {label = "Tags", text = entry.tags} end
    return fields
end

Snippets.icon = textureFields
Snippets.texture = textureFields

Snippets.atlas = function(entry)
    local ref = literal(entry.value)
    return {
        {label = "Atlas", text = entry.value},
        {label = "Lua", text = "texture:SetAtlas(" .. ref .. ", true)"},
        {label = "Inline text", text = "CreateAtlasMarkup(" .. ref .. ", 16, 16)"},
    }
end

local function soundKitExpression(entry)
    if type(entry.value) == "string" and entry.value:match("^[%a_][%w_]*$") then return "SOUNDKIT." .. entry.value end
    return tostring(entry.id)
end

Snippets.sound = function(entry, options)
    local channel = options and options.channel or "Master"
    return {
        {label = "Name", text = entry.value},
        {label = "Sound kit ID", text = tostring(entry.id)},
        {label = "Lua", text = "PlaySound(" .. soundKitExpression(entry) .. ", " .. literal(channel) .. ")"},
    }
end

-- How a template is instantiated depends on whether it is a frame or a region.
function Snippets.ControlCode(entry)
    local ref = literal(entry.value)
    local tag = entry.tag or "Frame"
    local constructor = ML.RegionTypes[tag]
    if constructor == "CreateTexture" then
        return "local texture = parent:CreateTexture(nil, \"ARTWORK\", " .. ref .. ")"
    elseif constructor == "CreateFontString" then
        return "local text = parent:CreateFontString(nil, \"OVERLAY\", " .. ref .. ")"
    elseif constructor == "CreateLine" then
        return "local line = parent:CreateLine(nil, \"ARTWORK\", " .. ref .. ")"
    elseif ML.UnbuildableTypes[tag] then
        return "local group = region:CreateAnimationGroup(nil, " .. ref .. ")"
    end
    local code = "local widget = CreateFrame(" .. literal(tag) .. ", nil, UIParent, " .. ref .. ")"
    if tag == "Button" or tag == "CheckButton" then code = code .. "\nwidget:SetText(\"Click me\")" end
    return code .. "\nwidget:SetPoint(\"CENTER\")"
end

Snippets.control = function(entry)
    local fields = {
        {label = "Template", text = entry.value},
        {label = "Lua", text = Snippets.ControlCode(entry), lines = 3},
    }
    if entry.inherits then fields[#fields + 1] = {label = "Inherits", text = entry.inherits} end
    return fields
end

Snippets.font = function(entry)
    local ref = literal(entry.value)
    return {
        {label = "Font object", text = entry.value},
        {label = "Lua", text = "fontString:SetFontObject(" .. ref .. ")"},
        {label = "New text", text = "parent:CreateFontString(nil, \"OVERLAY\", " .. ref .. ")"},
    }
end

function Snippets.For(entry, options)
    local build = Snippets[entry.kind]
    return build and build(entry, options) or {{label = "Reference", text = tostring(entry.value)}}
end
