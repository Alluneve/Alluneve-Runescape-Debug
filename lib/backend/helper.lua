local Helper = {}

local database = require("lib/backend/db/Database")
local TICKS_PER_SECOND = 50

function Helper.FormatMessage(...)
    local values = {}

    for i = 1, select("#", ...) do
        values[i] = tostring(select(i, ...))
    end

    return table.concat(values, " ")
end

---@param addonIdentifier string
---@param logObject LogObject
---@param referenceTick integer?
---@return string
function Helper.LogObjectToString(addonIdentifier, logObject, referenceTick)
    local prefix

    if referenceTick then
        prefix = string.format(
            "[%+.3f] %-5s ",
            (logObject.tick - referenceTick) / TICKS_PER_SECOND,
            logObject.severity
        )
    else
        prefix = string.format(
            "[tick %d : %s - %s]: ",
            logObject.tick,
            addonIdentifier,
            logObject.severity
        )
    end

    return prefix .. logObject.message
end


---@param addonIdentifier string
---@param logObjects LogObject[]
---@param triggerTick integer?
---@return boolean
function Helper.SendToDB(addonIdentifier, logObjects, triggerTick)
    local flags = database.GetSettings().Severities

    ---@type LogObject[]
    local filteredObjects = {}

    local selectedSeverities = {}

    for _, severity in ipairs({ "DEBUG", "INFO", "WARN", "ERROR" }) do
        if flags[severity] then
            selectedSeverities[#selectedSeverities + 1] = severity
        end
    end

    for _, logObject in ipairs(logObjects) do
        if flags[logObject.severity] then
            filteredObjects[#filteredObjects + 1] = logObject
        end
    end

    if #filteredObjects == 0 then
        return false
    end

    -- For a triggered report, offsets are relative to the trigger.
    -- For a manual submission, use the first original log entry.
    local referenceTick = triggerTick or logObjects[1].tick

    local lines = {
        string.format("Alluneve-Debug Report: %s", addonIdentifier),
        string.format(
            "%s at tick: %d",
            triggerTick and "Triggered" or "Started",
            referenceTick
        ),
        string.format("Entries: %d", #filteredObjects),
        string.format("Severities: %s", table.concat(selectedSeverities, ", ")),
        ""
    }

    for _, logObject in ipairs(filteredObjects) do
        lines[#lines + 1] = Helper.LogObjectToString(
            addonIdentifier,
            logObject,
            referenceTick
        )
    end

    local report = database.CreateDbObject(
        addonIdentifier,
        table.concat(lines, "\n")
    )

    return not not database.SaveReport(report)
end

return Helper