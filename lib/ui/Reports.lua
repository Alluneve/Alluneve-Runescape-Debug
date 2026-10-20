local Reports = {}

local database = require("lib/backend/db/Database")

local window
local clearDialog
local parent

local reportLabel
local readablePanel
local readableView

local olderButton
local newerButton
local deleteButton
local clearButton
local copyButton

local reports = {}
local selectedIndex = 0

-- Format for multiline display.
local function ReadableReportValue(content)
    return content
        :gsub("\r\n", "\n")
        :gsub("\r", "\n")
        :gsub("\n", "<br>")
end

-- Rebuild the readable content so PrettyUI can measure
-- the complete text when adding it to the layout.
local function SetReadableReport(content)
    if readableView then
        readableView:Destroy()
        readableView = nil
    end

    readableView = prettyui.SimpleView.new(
        readablePanel.content,
        {
            x = 0,
            y = 0,
            width = readablePanel.content.width,
            height = readablePanel.content.height,
            scrollable = true,
            scrollStep = 32
        }
    )

    readableView:AddText({
        text = ReadableReportValue(content),
        maxLines = 0,
        marginTop = 0,
        marginBottom = 0
    })

    readableView:SetScrollPosition(0)
end

-- Reports arrive in descending ID order.
-- Deleted IDs are intentionally skipped.
local function RefreshDisplay()
    local report = reports[selectedIndex]

    if report then
        reportLabel.content = string.format(
            "Report %d/%d  |  %s",
            #reports - selectedIndex + 1,
            #reports,
            report.addon
        )

        SetReadableReport(report.content)
    else
        reportLabel.content = "No saved reports."
        SetReadableReport("")
    end

    olderButton:SetDisabled(selectedIndex >= #reports)
    newerButton:SetDisabled(selectedIndex <= 1)
    deleteButton:SetDisabled(report == nil)
    clearButton:SetDisabled(#reports == 0)
    copyButton:SetDisabled(report == nil or true)
end

local function RefreshReports(keepSelection, direction)
    local oldReport = reports[selectedIndex]
    local oldId = oldReport and oldReport.id
    local oldIndex = selectedIndex

    -- Always retrieve the current database contents.
    reports = database.GetReports()

    selectedIndex = #reports > 0 and 1 or 0

    if #reports > 0 then
        if keepSelection then
            local found = false

            for index, report in ipairs(reports) do
                if report.id == oldId then
                    selectedIndex = index
                    found = true
                    break
                end
            end

            -- Handle reports deleted since the last refresh.
            if not found then
                selectedIndex = math.min(
                    math.max(oldIndex, 1),
                    #reports
                )
            end
        end

        if direction then
            selectedIndex = math.max(
                1,
                math.min(#reports, selectedIndex + direction)
            )
        end
    end

    RefreshDisplay()
end

local function DeleteSelectedReport()
    local report = reports[selectedIndex]

    if not report then
        return
    end

    database.DeleteReport(report.id)
    RefreshReports(true)
end

local function ConfirmClearReports()
    if clearDialog or #reports == 0 then
        return
    end

    clearDialog = prettyui.Confirm.new(parent, {
        title = "Clear all reports?",
        body = "Delete every saved Alluneve-Debug report? This cannot be undone.",
        confirmLabel = "Clear reports",
        confirmVariant = "negative",

        onConfirm = function()
            database.ClearReports()
            clearDialog = nil
            RefreshReports()
            return true
        end,

        onCancel = function()
            clearDialog = nil
            return true
        end
    })
end

-- Clipboard integration --
-- TODO: Implement once RuneScape exposes clipboard access.
local function CopySelectedReport()
    local report = reports[selectedIndex]

    if not report then
        return
    end

    -- Complete original report, including real newlines.
    local content = report.content

    -- TODO: Write content to the clipboard using the
    -- future RuneScape clipboard API.

    print(string.format(
        "Alluneve-Debug: Clipboard API unavailable. Report ready (%d bytes).",
        #content
    ))
end

function Reports.Open()
    if window then
        RefreshReports()
        window:Show()
        return
    end

    parent = ui.Interfaces:GetComponent(
        id.Component.TOPLEVEL_V2__GAME_AREA
    )

    if not parent then
        print(
            "Alluneve-Debug: Cannot open report viewer; game UI is unavailable."
        )
        return
    end

    reports = database.GetReports()
    selectedIndex = #reports > 0 and 1 or 0

    window = prettyui.Window.new(parent, {
        title = "Alluneve-Debug - Saved Reports",
        x = -310,
        y = -260,
        xAnchor = 0.5,
        yAnchor = 0.5,
        width = 620,
        height = 520,
        minWidth = 400,
        minHeight = 340,
        resizable = true
    })

    -- Report navigation --

    reportLabel = window:AddText("No saved reports.")

    olderButton = window:AddSimpleButton(
        "Older",
        function()
            RefreshReports(true, 1)
        end
    )

    newerButton = window:AddSimpleButton(
        "Newer",
        function()
            RefreshReports(true, -1)
        end,
        { inline = true }
    )

    window:AddSimpleButton(
        "Refresh",
        RefreshReports,
        { inline = true }
    )

    -- Readable report --

    readablePanel = window:AddPanel({
        height = 300,
        scrollable = false
    })

    -- Report management --

    deleteButton = window:AddSimpleButton(
        "Delete report",
        DeleteSelectedReport
    )

    clearButton = window:AddSimpleButton(
        "Clear all reports",
        ConfirmClearReports,
        { inline = true }
    )

    -- Clipboard button --

    copyButton = window:AddSimpleButton(
        "Copy to clipboard",
        CopySelectedReport
    )
    window:AddText("Clipboard API not available yet, awaiting updated API functionality")

    RefreshDisplay()
    window:Show()
end

function Reports.Shutdown()
    if clearDialog then
        clearDialog:Destroy()
        clearDialog = nil
    end

    if window then
        window:Destroy()
        window = nil
    end

    parent = nil
    reportLabel = nil
    readablePanel = nil
    readableView = nil
    olderButton = nil
    newerButton = nil
    deleteButton = nil
    clearButton = nil
    copyButton = nil
    reports = {}
    selectedIndex = 0
end

return Reports
