local _, ML = ...

-- The right-hand panel: what the selection is, a preview, and copyable fields.
local W = ML.Widgets
local T = W.theme
local Inspector = {}
Inspector.__index = Inspector
ML.Inspector = Inspector

local MAX_FIELDS = 4

-- handlers: onFavorite(entry), onLists(entry, button) opens the list menu for
-- the entry, onTarget() loads the player's target (the model preview's button)
function Inspector.New(parent, handlers)
    local self = setmetatable({handlers = handlers, previews = {}, fields = {}}, Inspector)
    local frame = W.Panel(parent)
    self.frame = frame
    self.title = W.Label(frame, "Nothing selected", 14, T.accent)
    self.title:SetPoint("TOPLEFT", 12, -12)
    self.title:SetPoint("TOPRIGHT", -126, -12)
    self.subtitle = W.Label(frame, "Pick something from the list.", 10, T.muted)
    self.subtitle:SetPoint("TOPLEFT", 12, -32)
    self.subtitle:SetPoint("TOPRIGHT", -12, -32)
    self.subtitle:SetWordWrap(false)
    self.lists = W.Button(frame, "Add to list", 84, function(button)
        if self.entry then handlers.onLists(self.entry, button) end
    end, 20)
    self.lists:SetPoint("TOPRIGHT", -10, -10)
    W.Tip(self.lists, "Lists", "Add this to any of your lists, or start a new one.")
    self.lists:Disable()
    self.favorite = W.Button(frame, "*", 22, function()
        if self.entry then handlers.onFavorite(self.entry) end
    end, 20)
    self.favorite:SetPoint("RIGHT", self.lists, "LEFT", -4, 0)
    W.Tip(self.favorite, "Favorite", "Add to or remove from Favorites. Right-click in the results does the same.")
    self.favorite:Disable()
    self.previewArea = CreateFrame("Frame", nil, frame)
    self.previewArea:SetPoint("TOPLEFT", 12, -52)
    self.previewArea:SetPoint("BOTTOMRIGHT", -12, 200)
    self.previewArea:SetScript("OnSizeChanged", function() self:Layout() end)
    self.hint = W.Label(frame, "Click a field, then press Ctrl+C.", 10, T.muted)
    self.hint:SetPoint("BOTTOMLEFT", 12, 10)
    for index = 1, MAX_FIELDS do
        local field = W.CopyField(frame, function() self.hint:SetText("Selected. Press Ctrl+C to copy.") end)
        field:Hide()
        field.caption:Hide()
        self.fields[index] = field
    end
    return self
end

function Inspector:Preview(name)
    if not name or not ML.Previews[name] then return end
    if not self.previews[name] then self.previews[name] = ML.Previews[name].New(self.previewArea) end
    return self.previews[name]
end

-- Fields stack upwards from the hint; the preview takes the remaining height.
function Inspector:LayoutFields()
    local y = 28
    for index = #self.fields, 1, -1 do
        local field = self.fields[index]
        if field:IsShown() then
            field:ClearAllPoints()
            field:SetPoint("BOTTOMLEFT", self.frame, "BOTTOMLEFT", 12, y)
            field:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", -12, y)
            y = y + field:GetHeight() + 18
        end
    end
    self.previewArea:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", -12, y + 6)
end

function Inspector:RefreshFields()
    if not self.entry then return end
    local options = {channel = ML.db.view.channel}
    local values = {}
    for _, value in ipairs(ML.Snippets.For(self.entry, options)) do
        if ML.db.developer or not value.developer then values[#values + 1] = value end
    end
    for index, field in ipairs(self.fields) do
        local value = values[index]
        field:SetShown(value ~= nil)
        field.caption:SetShown(value ~= nil)
        if value then field:SetField(value.label, value.text, value.lines) end
    end
    self:LayoutFields()
end

function Inspector:Show(entry)
    self.entry = entry
    local kind = entry and ML.KindById[entry.kind]
    for name, preview in pairs(self.previews) do
        if not kind or name ~= kind.preview then preview:Hide() end
    end
    if not entry then
        self.title:SetText("Nothing selected")
        self.subtitle:SetText("Pick something from the list.")
        self.lists:Disable()
        self.favorite:Disable()
        for _, field in ipairs(self.fields) do field:Hide(); field.caption:Hide() end
        return
    end
    self.title:SetText(entry.name)
    self.subtitle:SetText(entry.description
        or (kind.label .. "  /  " .. table.concat(entry.facets, ", ") .. "  /  " .. (entry.origin or "")))
    self.lists:Enable()
    self.favorite:Enable()
    self:RefreshLists()
    local preview = self:Preview(kind.preview)
    if preview then
        preview.onOptions = function() self:RefreshFields() end
        preview.onTarget = self.handlers.onTarget
        preview:Show(entry)
    end
    self:RefreshFields()
end

function Inspector:RefreshLists()
    if not self.entry then return end
    local count = #ML.Lists:Of(self.entry.key)
    self.lists:SetLabel(count == 0 and "Add to list" or count == 1 and "In 1 list" or ("In " .. count .. " lists"))
    self.lists:SetActive(count > 0)
    self.favorite:SetActive(ML.Lists:IsFavorite(self.entry.key))
end

function Inspector:Layout()
    local preview = self.entry and self.previews[ML.KindById[self.entry.kind].preview]
    if preview and preview.Layout then preview:Layout() end
end
