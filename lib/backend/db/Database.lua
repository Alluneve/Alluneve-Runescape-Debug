local database = {}

local PRIMARY_KEY = "pk"
local BLOB_KEY = "blob"
local SETTINGS_KEY = "settings"

local pk = 0

---@class dbObject
---@field id integer?
---@field addon string
---@field content string

---@type table<integer, dbObject>
local blob = {}

---@class FlightRecorderSettings
---@field CaptureSeconds number
---@field PostTriggerSeconds number
---@field TickerTimer number

---@class SeveritiesSettings
---@field DEBUG boolean
---@field INFO boolean
---@field WARN boolean
---@field ERROR boolean

---@class DatabaseSettings
---@field FlightRecorder FlightRecorderSettings
---@field Severities SeveritiesSettings

---@return DatabaseSettings
local function CreateDefaultSettings()
    return {
        FlightRecorder = {
            CaptureSeconds = 60,
            PostTriggerSeconds = 10,
            TickerTimer = 60
        },
        Severities = {
            DEBUG = false,
            INFO = true,
            WARN = true,
            ERROR = true
        }
    }
end

---@type DatabaseSettings
local settings = CreateDefaultSettings()

---@param addon string
---@param content string
---@return dbObject
function database.CreateDbObject(addon, content)
    return {
        addon = addon,
        content = content
    }
end

---Load the database into memory before importing the backend modules.
function database.Load()
    pk = PersistentDB:GetInt(PRIMARY_KEY) or 0
    blob = PersistentDB:GetStructuredData(BLOB_KEY) or {}

    local storedSettings = PersistentDB:GetStructuredData(SETTINGS_KEY)

    if type(storedSettings) == "table" then
        settings = storedSettings
    else
        settings = CreateDefaultSettings()
    end

    if type(settings.FlightRecorder) ~= "table" then
        settings.FlightRecorder = CreateDefaultSettings().FlightRecorder
    end


    -- Migrate previous console preferences.
    if type(settings.Severities) ~= "table" then
        settings.Severities =
            type(settings.ConsolePrint) == "table"
            and settings.ConsolePrint
            or CreateDefaultSettings().Severities

        settings.ConsolePrint = nil
    end

    local defaults = CreateDefaultSettings().Severities

    for severity, enabled in pairs(defaults) do
        if type(settings.Severities[severity]) ~= "boolean" then
            settings.Severities[severity] = enabled
        end
    end
end

---Persist the in-memory database at shutdown.
---@return boolean
function database.Save()
    if not PersistentDB:SetStructuredData(BLOB_KEY, blob) then
        return false
    end

    if not PersistentDB:SetInt(PRIMARY_KEY, pk) then
        return false
    end

    return PersistentDB:SetStructuredData(SETTINGS_KEY, settings)
end

---@return DatabaseSettings
function database.GetSettings()
    return settings
end

---@param report dbObject
---@return integer?
function database.SaveReport(report)
    if type(report) ~= "table"
        or type(report.addon) ~= "string"
        or type(report.content) ~= "string" then
        return nil
    end

    pk = pk + 1

    local storedReport = {
        id = pk,
        addon = report.addon,
        content = report.content
    }

    blob[pk] = storedReport
    report.id = pk

    return pk
end

---@param id integer
---@return dbObject?
function database.GetReport(id)
    return blob[id]
end

---@return dbObject[]
function database.GetReports()
    ---@type dbObject[]
    local reports = {}

    for _, report in pairs(blob) do
        reports[#reports + 1] = report
    end

    table.sort(reports, function(a, b)
        return a.id > b.id
    end)

    return reports
end

---@param id integer
---@return boolean
function database.DeleteReport(id)
    if not blob[id] then
        return false
    end

    blob[id] = nil
    return true
end

---Clear reports in O(1), preserving settings.
function database.ClearReports()
    blob = {}
    pk = 0
end

return database
