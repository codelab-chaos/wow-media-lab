local _, ML = ...

-- Puts an image entry on a texture region and reports its native size.
-- Shared by thumbnails and the zoomable preview so both render identically.
local Art = {}
ML.Art = Art

-- File textures expose no dimensions to addons, so non-atlas sizes are assumed.
local ASSUMED = {icon = 64, texture = 256}

function Art.Reset(texture)
    texture:Hide()
    texture:SetTexture(nil)
    texture:SetTexCoord(0, 1, 0, 1)
    texture:SetVertexColor(1, 1, 1)
    texture:SetAlpha(1)
end

-- Returns loaded, width, height, exact (true when the size came from the client).
function Art.Apply(texture, entry)
    Art.Reset(texture)
    if not entry then return false end
    if entry.kind == "atlas" then
        local info = ML.Sources.AtlasInfo(entry.value)
        if not info then return false end
        texture:SetAtlas(entry.value, false)
        texture:Show()
        return true, math.max(1, info.width or 64), math.max(1, info.height or 64), true, info
    end
    if not texture:SetTexture(entry.value) then return false end
    texture:Show()
    local size = ASSUMED[entry.kind] or 128
    return true, size, size, false
end

-- Fits an image into a box, keeping its aspect ratio. Returns the scale used.
function Art.Fit(texture, entry, width, height, upscale)
    local loaded, nativeWidth, nativeHeight = Art.Apply(texture, entry)
    if not loaded then return false end
    local scale = math.min(width / nativeWidth, height / nativeHeight)
    if not upscale then scale = math.min(1, scale) end
    texture:SetSize(math.max(1, nativeWidth * scale), math.max(1, nativeHeight * scale))
    return true, scale
end
