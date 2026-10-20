local Settings = {}

local database = require("lib/backend/db/Database")
local Reports = require("lib/ui/Reports")

local EVENT_REFERENCE = "AlluneveDebugSettings"
local settingsView

local function OnSettingsLayerReady(event)
    if settingsView then
        settingsView:Destroy()
        settingsView = nil
    end

    local parent = event.component
    settingsView = prettyui.SimpleView.new(parent, {
        width = parent.width,
        height = parent.height
    })

    settingsView:AddTitle("Alluneve-Debug")

    settingsView:AddTitle("Console and report output")
    settingsView:AddText(
        "Choose which severities appear in the console and submitted reports. All messages are still recorded."
    )

    local flags = database.GetSettings().Severities
    settingsView:AddCheckboxButton({
        { text = "DEBUG", value = "DEBUG", selected = flags.DEBUG },
        { text = "INFO",  value = "INFO",  selected = flags.INFO },
        { text = "WARN",  value = "WARN",  selected = flags.WARN },
        { text = "ERROR", value = "ERROR", selected = flags.ERROR }
    }, {
        onChange = function(_, _, changedValue, selected)
            if flags[changedValue] ~= nil then
                flags[changedValue] = selected
            end
        end
    })
end

function Settings.Shutdown()
    Event.SettingsLayerReady.Unsubscribe(EVENT_REFERENCE)
    if settingsView then
        settingsView:Destroy()
        settingsView = nil
    end
    Reports.Shutdown()
end

Event.SettingsLayerReady.Subscribe(EVENT_REFERENCE, OnSettingsLayerReady)

return Settings