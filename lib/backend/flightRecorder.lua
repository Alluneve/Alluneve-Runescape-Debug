local FlightRecorder = {}

local RollingLog = require("lib/backend/db/RollingLog")
local Helper = require("lib/backend/Helper")
local database = require("lib/backend/db/Database")

-- Constants --

local TICKS_PER_SECOND = 50
local CLEANUP_OPERATIONS_PER_TICK = 128
local CLEANUP_WINDOW_FRACTION = 5 / 6
local EVENT_REFERENCE = "AlluneveDebugFlightRecorder"

-- Settings --

local db = database.GetSettings().FlightRecorder

local function EnsureSetting(key, default)
    local value = db[key]

    if type(value) ~= "number"
        or value ~= value
        or value <= 0
        or value >= math.huge then
        db[key] = default
    end
end

EnsureSetting("CaptureSeconds", 60)
EnsureSetting("PostTriggerSeconds", 10)
EnsureSetting("TickerTimer", 60)

-- Module Variables --

---@type table<string, RollingLog>
local currentFlightRecorders = {}

---@type table<string, { tick: integer, deadlineTick: integer }>
local activeTriggers = {}

-- Normalize client-wide logic ticks to plugin-local ticks. This allows
-- logging before the first Event.Logic callback (tick 0) without a jump.
local firstClientTick
local currentTick = 0
local nextCleanupTick
local cleanupWork

-- Utilities --

---@param seconds number
---@return integer
local function SecondsToTicks(seconds)
    return math.max(1, math.ceil(seconds * TICKS_PER_SECOND))
end

---@param seconds number
local function ValidateSeconds(seconds)
    if type(seconds) ~= "number"
        or seconds ~= seconds
        or seconds <= 0
        or seconds >= math.huge then
        error("Alluneve-Debug: Seconds must be a positive finite number", 3)
    end
end

local function ResetCleanupSchedule()
    cleanupWork = nil
    nextCleanupTick = nil
end

-- Event storage --

---@param addonIdentifier string
---@param severity Severity
---@param message string
---@param tick integer
local function RecordFlightEvent(addonIdentifier, severity, message, tick)
    local log = currentFlightRecorders[addonIdentifier]

    if not log then
        log = RollingLog.CreateRollingLog()
        currentFlightRecorders[addonIdentifier] = log
    end

    log.Append(RollingLog.CreateLogObject(severity, message, tick))
end

-- Global rolling cleanup --

---@param log RollingLog
---@param cutoffTick integer
---@param budget integer
---@return boolean, integer
local function CleanHistory(log, cutoffTick, budget)
    while budget > 0 do
        local maxTick = log.GetOldestPageMaxTick()

        if maxTick == nil then
            return true, budget
        end

        if maxTick < cutoffTick then
            log.EvictOldestPage()
        else
            local oldest = log.PeekOldest()

            if not oldest or oldest.tick >= cutoffTick then
                return true, budget
            end

            log.RemoveOldest()
        end

        budget = budget - 1
    end

    return false, budget
end

---@param tick integer
local function BeginCleanupPass(tick)
    if cleanupWork then
        return
    end

    local identifiers = {}

    for addonIdentifier in pairs(currentFlightRecorders) do
        identifiers[#identifiers + 1] = addonIdentifier
    end

    if #identifiers == 0 then
        return
    end

    cleanupWork = {
        identifiers = identifiers,
        index = 1,
        cutoffTick = tick - SecondsToTicks(db.CaptureSeconds),
        deadlineTick = tick + math.max(
            1,
            math.floor(SecondsToTicks(db.TickerTimer) * CLEANUP_WINDOW_FRACTION)
        )
    }
end

local function ProcessCleanupSlice()
    local work = cleanupWork

    if not work then
        return
    end

    local budget = CLEANUP_OPERATIONS_PER_TICK

    while work.index <= #work.identifiers and budget > 0 do
        local addonIdentifier = work.identifiers[work.index]
        local log = currentFlightRecorders[addonIdentifier]

        budget = budget - 1

        -- Keep the full history during the post-trigger window.
        if log and not activeTriggers[addonIdentifier] then
            local completed
            completed, budget = CleanHistory(log, work.cutoffTick, budget)

            if not completed then
                return
            end

            if not log.PeekOldest() then
                currentFlightRecorders[addonIdentifier] = nil
            end
        end

        work.index = work.index + 1
    end

    if work.index > #work.identifiers then
        cleanupWork = nil
    end
end

-- Report submission --

---@param addonIdentifier string
---@param triggerTick integer?
local function SubmitFlightRecorder(addonIdentifier, triggerTick)
    local log = currentFlightRecorders[addonIdentifier]

    if not log then
        return
    end

    ---@type LogObject[]
    local logObjects = {}

    for logObject in log.Iterator() do
        logObjects[#logObjects + 1] = logObject
    end

    if Helper.SendToDB(addonIdentifier, logObjects, triggerTick) then
        log.Clear()
    end
end

-- Trigger management --

---@param addonIdentifier string
local function TriggerFlightRecorder(addonIdentifier)
    local trigger = activeTriggers[addonIdentifier]

    if not trigger then
        trigger = {}
        activeTriggers[addonIdentifier] = trigger
    end

    -- Repeated triggers refresh the reference tick and extend the window.
    trigger.tick = currentTick
    trigger.deadlineTick = currentTick + SecondsToTicks(db.PostTriggerSeconds)
end

---@param tick integer
local function ProcessTriggers(tick)
    for addonIdentifier, trigger in pairs(activeTriggers) do
        if tick >= trigger.deadlineTick then
            SubmitFlightRecorder(addonIdentifier, trigger.tick)

            currentFlightRecorders[addonIdentifier] = nil
            activeTriggers[addonIdentifier] = nil
        end
    end
end

---@param addonIdentifier string
local function ClearFlightRecorder(addonIdentifier)
    if activeTriggers[addonIdentifier] then
        return
    end

    currentFlightRecorders[addonIdentifier] = nil
end

-- Logic tick scheduler --

---@param event table
local function OnLogic(event)
    local clientTick = event.logicTick

    if firstClientTick == nil then
        firstClientTick = clientTick
    end

    currentTick = clientTick - firstClientTick

    ProcessTriggers(currentTick)

    if not nextCleanupTick then
        BeginCleanupPass(currentTick)
        nextCleanupTick = currentTick + SecondsToTicks(db.TickerTimer)
    elseif currentTick >= nextCleanupTick then
        -- Abandon unfinished cleanup work from the previous cycle.
        cleanupWork = nil
        BeginCleanupPass(currentTick)
        nextCleanupTick = currentTick + SecondsToTicks(db.TickerTimer)
    end

    if cleanupWork then
        if currentTick >= cleanupWork.deadlineTick then
            cleanupWork = nil
        else
            ProcessCleanupSlice()
        end
    end
end

-- Interfaces --

---@return integer
function FlightRecorder.GetTick()
    return currentTick
end

---@param addonIdentifier string
---@param severity Severity
---@param message string
---@param tick integer
function FlightRecorder.Record(addonIdentifier, severity, message, tick)
    RecordFlightEvent(addonIdentifier, severity, message, tick)
end

---@param addonIdentifier string
function FlightRecorder.Trigger(addonIdentifier)
    TriggerFlightRecorder(addonIdentifier)
end

---@param addonIdentifier string
function FlightRecorder.Clear(addonIdentifier)
    ClearFlightRecorder(addonIdentifier)
end

---@return number
function FlightRecorder.GetTickerTimer()
    return db.TickerTimer
end

---@return number
function FlightRecorder.GetPostTriggerSeconds()
    return db.PostTriggerSeconds
end

---@return number
function FlightRecorder.GetCaptureSeconds()
    return db.CaptureSeconds
end

---@param seconds number
function FlightRecorder.SetTickerTimer(seconds)
    ValidateSeconds(seconds)
    db.TickerTimer = seconds
    ResetCleanupSchedule()
end

---@param seconds number
function FlightRecorder.SetPostTriggerSeconds(seconds)
    ValidateSeconds(seconds)
    db.PostTriggerSeconds = seconds
end

---@param seconds number
function FlightRecorder.SetCaptureSeconds(seconds)
    ValidateSeconds(seconds)
    db.CaptureSeconds = seconds
    ResetCleanupSchedule()
end

function FlightRecorder.Shutdown()
    Event.Logic.Unsubscribe(EVENT_REFERENCE)

    currentFlightRecorders = {}
    activeTriggers = {}
    firstClientTick = nil
    currentTick = 0
    ResetCleanupSchedule()
end

-- Subscribe on module load; no Initialize() needed.
Event.Logic.Subscribe(EVENT_REFERENCE, OnLogic)

return FlightRecorder