local _, ML = ...

-- The entries picked in the results, like a file browser: a click picks one,
-- Ctrl+click adds or removes one, Shift+click picks the range from the last
-- click (Ctrl+Shift adds the range). Keeps the order things were picked in.
-- It knows nothing about frames.
local Selection = {entries = {}, set = {}}
ML.Selection = Selection

function Selection:Clear()
    self.entries, self.set, self.anchor = {}, {}, nil
end

function Selection:Has(entry) return entry ~= nil and self.set[entry.key] == true end
function Selection:Count() return #self.entries end
function Selection:Entries() return self.entries end

function Selection:Add(entry)
    if not self.set[entry.key] then
        self.set[entry.key] = true
        self.entries[#self.entries + 1] = entry
    end
end

function Selection:Remove(entry)
    if not self.set[entry.key] then return end
    self.set[entry.key] = nil
    for index, picked in ipairs(self.entries) do
        if picked.key == entry.key then table.remove(self.entries, index); break end
    end
end

-- One click on entry, with modifiers {ctrl, shift}, within the shown results.
-- Returns the entry to inspect: the one clicked, unless Ctrl took it out.
function Selection:Click(entry, modifiers, results)
    modifiers = modifiers or {}
    if modifiers.shift and self.anchor then
        local from, to
        for index, candidate in ipairs(results or {}) do
            if candidate.key == self.anchor.key then from = index end
            if candidate.key == entry.key then to = index end
        end
        if from and to then
            if not modifiers.ctrl then self.entries, self.set = {}, {} end
            for index = math.min(from, to), math.max(from, to) do self:Add(results[index]) end
            return entry
        end
    end
    self.anchor = entry
    if modifiers.ctrl then
        if self:Has(entry) then
            self:Remove(entry)
            return self.entries[#self.entries]
        end
        self:Add(entry)
        return entry
    end
    self:Clear()
    self.anchor = entry
    self:Add(entry)
    return entry
end

-- What a right-click acts on: the whole selection when the entry is part of
-- it, else just the entry (which becomes the selection).
function Selection:For(entry)
    if self:Has(entry) and #self.entries > 1 then return self.entries end
    self:Click(entry)
    return {entry}
end
