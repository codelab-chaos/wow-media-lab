local _, ML = ...

-- NPCs seen in game. The client's files name models, not NPCs (the server
-- sends names), so MediaLab learns them from your target: creature ID, name,
-- and the creature display it uses. Saved in ML.db.npcs as
-- [creatureID] = {name, display, model}. It knows nothing about the window.
local Npcs = {}
ML.Npcs = Npcs

Npcs.WAIT = 1.5 -- seconds to wait for the target's model to load
Npcs.POLL = 0.1

-- Saved-variable cleanup, called once from ML.Initialize.
function Npcs.Sanitize(saved)
    local npcs = {}
    for id, npc in pairs(type(saved.npcs) == "table" and saved.npcs or {}) do
        id = tonumber(id)
        if id and type(npc) == "table" and type(npc.name) == "string" and npc.name ~= "" then
            npcs[id] = {name = npc.name, display = tonumber(npc.display), model = tonumber(npc.model)}
        end
    end
    saved.npcs = npcs
    return saved
end

function Npcs:All() return ML.db.npcs end

-- Names of the NPCs seen using a display, sorted.
function Npcs:ForDisplay(display)
    local names = {}
    for _, npc in pairs(ML.db.npcs) do
        if npc.display == display then names[#names + 1] = npc.name end
    end
    table.sort(names)
    return names
end

function Npcs:Remember(id, name, display, model)
    ML.db.npcs[id] = {name = name, display = display, model = model}
    return ML.db.npcs[id]
end

local function creatureId(guid)
    if C_CreatureInfo and C_CreatureInfo.GetCreatureID then
        local ok, id = pcall(C_CreatureInfo.GetCreatureID, guid)
        if ok and type(id) == "number" then return id end
    end
    local unitType, _, _, _, _, id = strsplit("-", guid or "")
    if unitType == "Creature" or unitType == "Vehicle" or unitType == "Pet" then return tonumber(id) end
end

local function number(fn, object)
    if type(fn) ~= "function" then return end
    local ok, value = pcall(fn, object)
    if ok and type(value) == "number" and value > 0 then return value end
end

-- Reads the target with a hidden model frame, which loads asynchronously, so
-- the answer comes to done(npc, creatureID) or done(nil, reason) a moment later.
function Npcs:CaptureTarget(done)
    if not UnitExists("target") then return done(nil, "Target an NPC first.") end
    if UnitIsPlayer("target") then return done(nil, "That is a player; target an NPC.") end
    local id = creatureId(UnitGUID("target"))
    if not id then return done(nil, "That target has no creature ID.") end
    local name = UnitName("target") or ("Creature " .. id)
    if not self.probe then
        self.probe = CreateFrame("PlayerModel", nil, UIParent)
        self.probe:SetSize(1, 1)
        self.probe:SetPoint("TOPLEFT", UIParent, "BOTTOMRIGHT", 10, -10) -- off screen
    end
    local probe = self.probe
    probe:Show()
    probe:SetUnit("target")
    local waited = 0
    local function check()
        local display = number(probe.GetDisplayInfo, probe)
        local model = number(probe.GetModelFileID, probe)
        if display or waited >= Npcs.WAIT then
            probe:ClearModel()
            probe:Hide()
            if not (display or model) then return done(nil, "The target's model did not load. Try again.") end
            return done(self:Remember(id, name, display, model), id)
        end
        waited = waited + Npcs.POLL
        C_Timer.After(Npcs.POLL, check)
    end
    C_Timer.After(Npcs.POLL, check)
end
