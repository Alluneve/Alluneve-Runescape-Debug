local Debug = {}

local Helper = require("lib/backend/Helper")
local RollingLog = require("lib/backend/db/RollingLog")
local FlightRecorder = require("lib/backend/FlightRecorder")
local database = require("lib/backend/db/Database")

local MAX_LOG_BYTES = 1024 * 1024

---@type table<string, RollingLog>
local debugLogs = {}

---@param addonIdentifier string
---@param severity Severity
---@param message string
---@param tick integer
---@return LogObject
local function Append(addonIdentifier, severity, message, tick)
    local log = debugLogs[addonIdentifier]

    if not log then
        log = RollingLog.CreateRollingLog()
        debugLogs[addonIdentifier] = log
    end

    local logObject = RollingLog.CreateLogObject(severity, message, tick)
    log.Append(logObject)

    -- Enforce the 1 MiB per-plugin session log limit on insertion.
    while log.GetAproximateByteSize() > MAX_LOG_BYTES do
        log.RemoveOldest()
    end

    return logObject
end

---@param addonIdentifier string
---@param severity Severity
---@param ... any
local function Log(addonIdentifier, severity, ...)
    local message = Helper.FormatMessage(...)
    local tick = FlightRecorder.GetTick()

    FlightRecorder.Record(addonIdentifier, severity, message, tick)

    local logObject = Append(addonIdentifier, severity, message, tick)

    -- Console visibility is independent of logging and reporting.
    if database.GetSettings().Severities[severity] then
        print(Helper.LogObjectToString(addonIdentifier, logObject))
    end
end

---@param addonIdentifier string
local function SubmitLog(addonIdentifier)
    local log = debugLogs[addonIdentifier]

    if not log then
        return
    end

    ---@type LogObject[]
    local logObjects = {}

    for logObject in log.Iterator() do
        logObjects[#logObjects + 1] = logObject
    end

    local submitted = Helper.SendToDB(addonIdentifier, logObjects)
    local flags = database.GetSettings().Severities

    -- Only clear when every severity was included.
    if submitted and flags.DEBUG and flags.INFO
        and flags.WARN and flags.ERROR then
        log.Clear()
    end
end

---@param addonIdentifier string
local function ClearLog(addonIdentifier)
    local log = debugLogs[addonIdentifier]

    if log then
        log.Clear()
        debugLogs[addonIdentifier] = nil
    end
end

---@param addonIdentifier string
---@param severity Severity
---@param ... any
function Debug.Log(addonIdentifier, severity, ...)
    Log(addonIdentifier, severity, ...)
end

---@param addonIdentifier string
function Debug.SubmitLog(addonIdentifier)
    SubmitLog(addonIdentifier)
end

---@param addonIdentifier string
function Debug.Clear(addonIdentifier)
    ClearLog(addonIdentifier)
end

return Debug