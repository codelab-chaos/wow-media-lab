local _, ML = ...

-- Plays one sound at a time and knows when it ends: from the game's
-- SOUNDKIT_FINISHED event, the sound's measured length, or C_Sound.IsPlaying.
-- Progress (0 to 1, when the length is known) drives the waveform playheads.
-- Listeners hear every change; onFinished(entry) runs when a sound ends by
-- itself (Play through uses it). No frames of its own beyond a ticker.
local Player = {listeners = {}}
ML.SoundPlayer = Player

local SETTLE = 0.25 -- seconds before IsPlaying is trusted to say a sound ended

local function now() return GetTime and GetTime() or 0 end

function Player:Listen(callback) self.listeners[#self.listeners + 1] = callback end

function Player:Notify()
    for _, callback in ipairs(self.listeners) do callback(self) end
end

function Player:IsPlaying(entry)
    return self.entry ~= nil and (entry == nil or self.entry.key == entry.key)
end

-- 0 to 1 while a sound of known length plays, else nil.
function Player:Progress()
    if not self.entry or not self.length or self.length <= 0 then return nil end
    return math.min(1, (now() - self.started) / self.length)
end

function Player:Elapsed() return self.entry and (now() - self.started) or 0 end

-- source: "click", "hover", "auto" or "next"; returns whether the game played it.
function Player:Play(entry, source)
    self:Stop(true)
    if not entry or type(PlaySound) ~= "function" then return false end
    local ok, willPlay, handle = pcall(PlaySound, entry.id, ML.db.view.channel or "Master", false, true)
    if not (ok and willPlay) then
        self.refused = entry
        self:Notify()
        return false
    end
    self.entry, self.handle, self.source, self.started, self.refused = entry, handle, source, now(), nil
    self.length = entry.duration
    local ticker = self:Ticker()
    ticker:SetScript("OnUpdate", function() self:Tick() end) -- only while something plays
    ticker:Show()
    self:Notify()
    return true
end

function Player:Stop(quiet)
    if self.handle and type(StopSound) == "function" then pcall(StopSound, self.handle) end
    self.entry, self.handle, self.source = nil, nil, nil
    if self.ticker then
        self.ticker:SetScript("OnUpdate", nil)
        self.ticker:Hide()
    end
    if not quiet then self:Notify() end
end

-- The sound ended by itself.
function Player:Finish()
    local finished = self.entry
    self:Stop()
    if finished and self.onFinished then self.onFinished(finished) end
end

function Player:Tick()
    if not self.entry then return end
    local elapsed = now() - self.started
    local ended = self.length and elapsed >= self.length + 0.05
    if not ended and not self.length and elapsed > SETTLE and C_Sound and C_Sound.IsPlaying then
        local ok, playing = pcall(C_Sound.IsPlaying, self.handle)
        ended = ok and playing == false
    end
    if ended then return self:Finish() end
    self:Notify()
end

-- A small frame that ticks while a sound plays, and hears the game say a
-- sound kit finished.
function Player:Ticker()
    if self.ticker then return self.ticker end
    local ticker = CreateFrame("Frame")
    ticker:Hide()
    ticker:RegisterEvent("SOUNDKIT_FINISHED")
    ticker:SetScript("OnEvent", function(_, _, handle)
        if self.handle and handle == self.handle then self:Finish() end
    end)
    self.ticker = ticker
    return ticker
end
