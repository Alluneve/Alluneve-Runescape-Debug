local Content = {}

local registeredAddons = {}

---@param addons table<string, AlluneveDebugAPI>
function Content.SetRegisteredAddons(addons)
    registeredAddons = addons
end

local Reports = require("lib/ui/Reports")

local EVENT_REFERENCE = "AlluneveDebugContent"
local contentView

local function OnContentLayerReady(event)
    if contentView then
        contentView:Destroy()
    end

    local parent = event.component

    contentView = prettyui.SimpleView.new(parent, {
        width = parent.width,
        height = parent.height
    })

    contentView:AddTitle("Alluneve-Debug")
    contentView:AddSimpleButton("Open saved reports", Reports.Open)

    contentView:AddTitle("Submit debug log")

    local identifiers = {}

    for addonIdentifier in pairs(registeredAddons) do
        identifiers[#identifiers + 1] = addonIdentifier
    end

    table.sort(identifiers)

    if #identifiers > 0 then
        local entries = {}

        for index, addonIdentifier in ipairs(identifiers) do
            entries[#entries + 1] = {
                id = index,
                label = addonIdentifier
            }
        end

        local selectedAddon = identifiers[1]

        contentView:AddComboBox({
            entries = entries,
            selectedID = 1,
            onChange = function(_, id)
                selectedAddon = identifiers[id]
            end
        })

        contentView:AddSimpleButton("Submit log", function()
            local addonAPI = registeredAddons[selectedAddon]

            if addonAPI then
                addonAPI.SubmitLog()
            end
        end)
    else
        contentView:AddText("No registered plugins.")
    end
end

function Content.Shutdown()
    Event.ContentLayerReady.Unsubscribe(EVENT_REFERENCE)

    if contentView then
        contentView:Destroy()
        contentView = nil
    end
end

Event.ContentLayerReady.Subscribe(
    EVENT_REFERENCE,
    OnContentLayerReady
)

return Content