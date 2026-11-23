local _, ML = ...

-- Copyable fields for each kind: the reference itself first, then ready-to-paste
-- Lua. Pure functions of an entry; the inspector only displays what these return.
-- Fields marked developer = true (code) show only in developer mode.
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
    fields[#fields + 1] = {label = "Lua", developer = true, text = "texture:SetTexture(" .. ref .. ")"}
    fields[#fields + 1] = {label = "Inline text", developer = true, text = "CreateSimpleTextureMarkup(" .. ref .. ", 16, 16)"}
    if entry.tags then fields[#fields + 1] = {label = "Tags", text = entry.tags} end
    return fields
end

Snippets.icon = textureFields
Snippets.texture = textureFields

Snippets.atlas = function(entry)
    local ref = literal(entry.value)
    return {
        {label = "Atlas", text = entry.value},
        {label = "Lua", developer = true, text = "texture:SetAtlas(" .. ref .. ", true)"},
        {label = "Inline text", developer = true, text = "CreateAtlasMarkup(" .. ref .. ", 16, 16)"},
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
        {label = "Lua", developer = true, text = "PlaySound(" .. soundKitExpression(entry) .. ", " .. literal(channel) .. ")"},
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
        {label = "Lua", developer = true, text = Snippets.ControlCode(entry), lines = 3},
    }
    if entry.inherits then fields[#fields + 1] = {label = "Inherits", developer = true, text = entry.inherits} end
    return fields
end

Snippets.font = function(entry)
    local ref = literal(entry.value)
    return {
        {label = "Font object", text = entry.value},
        {label = "Lua", developer = true, text = "fontString:SetFontObject(" .. ref .. ")"},
        {label = "New text", developer = true, text = "parent:CreateFontString(nil, \"OVERLAY\", " .. ref .. ")"},
    }
end

-- A creature display: PlayerModel takes the display ID, a ModelScene actor
-- too. The bare model file renders without the display's skin.
Snippets.model = function(entry)
    local id = tostring(entry.id)
    local fields = {
        {label = "Display ID", text = id},
        {label = "Lua", developer = true, text = "local model = CreateFrame(\"PlayerModel\", nil, parent)\nmodel:SetDisplayInfo(" .. id .. ")", lines = 2},
        {label = "Model scene", developer = true, text = "actor:SetModelByCreatureDisplayID(" .. id .. ")"},
    }
    if entry.model then fields[#fields + 1] = {label = "Model file (no skin)", developer = true, text = tostring(entry.model)} end
    return fields
end

-- The Lua expression that refers to an entry, as a value in a table: an icon
-- file ID or path, an atlas, template or font object name, a sound kit.
function Snippets.Value(entry)
    if entry.kind == "sound" then return soundKitExpression(entry) end
    return literal(entry.value)
end

function Snippets.For(entry, options)
    local build = Snippets[entry.kind]
    return build and build(entry, options) or {{label = "Reference", text = tostring(entry.value)}}
end
