local EVENT_REFERENCE = "AlluneveDebugTestSequence"
local DEPENDENCY_REFERENCE = "AlluneveDebugTestDependency"
local ADDON_IDENTIFIER = "AlluneveDebugTest"

-- No-op fallback --

local function NoOp() end

---@type AlluneveDebugAPI
local NOOP_DEBUG_API = {
    Info = NoOp,
    Debug = NoOp,
    Warn = NoOp,
    Error = NoOp,
    SubmitLog = NoOp,
    TriggerRecorder = NoOp
}

---@type AlluneveDebugAPI
local debugAPI = NOOP_DEBUG_API

-- State --

local boundDependency
local disabledDependency
local firstTick
local step = 1
local running = false

-- Test sequence --

local steps = {
    {
        tick = 100,
        run = function()
            debugAPI.Info("Delayed INFO test")
            debugAPI.Debug("Delayed DEBUG test")
            debugAPI.Warn("Delayed WARN test")
            print("[Alluneve-Debug Test] Three messages logged")
        end
    },
    {
        tick = 200,
        run = function()
            debugAPI.SubmitLog()
            print("[Alluneve-Debug Test] Requested settings-filtered report")
        end
    },
    {
        tick = 300,
        run = function()
            debugAPI.Error("Triggered flight recorder test")
            print("[Alluneve-Debug Test] Triggered flight recorder")
        end
    },
    {
        tick = 350,
        run = function()
            debugAPI.Info("Post-trigger entry")
        end
    },
    {
        tick = 850,
        run = function()
            print("[Alluneve-Debug Test] Flight recorder deadline should have passed")
        end
    },
    {
        tick = 900,
        run = function()
            debugAPI.SubmitLog()
            print("[Alluneve-Debug Test] Requested final report")
        end
    },
    {
        tick = 950, -- ~19 seconds
        run = function()
            local lines = {}

            for i = 1, 200 do
                lines[#lines + 1] = string.format(
                    "Large report test - Line %03d | %s",
                    i,
                    string.rep("0123456789 ", 7)
                )
            end

            debugAPI.Warn(table.concat(lines, "\n"))
            debugAPI.SubmitLog()

            print("[Alluneve-Debug Test] Requested large multiline report (200 lines)")
        end
    }
}

-- Dependency management --

local function StopTest()
    running = false
    firstTick = nil
    step = 1
end

local function UnbindDebug()
    StopTest()
    debugAPI = NOOP_DEBUG_API
    boundDependency = nil
end

local function TryRegister()
    local dependency = AlluneveDebug

    if type(dependency) ~= "table"
        or type(dependency.RegisterYourself) ~= "function"
        or dependency == disabledDependency then
        if boundDependency then
            UnbindDebug()
            print("[Alluneve-Debug Test] Dependency unavailable; using no-op API")
        end

        return
    end

    -- Already registered against this dependency instance.
    if dependency == boundDependency then
        return
    end

    local success, result = pcall(
        dependency.RegisterYourself,
        ADDON_IDENTIFIER
    )

    if not success then
        print("[Alluneve-Debug Test] Registration failed:", result)
        return
    end

    if type(result) ~= "table" then
        print("[Alluneve-Debug Test] Registration returned no API")
        return
    end

    debugAPI = result
    boundDependency = dependency

    firstTick = nil
    step = 1
    running = true

    print("[Alluneve-Debug Test] Registered; test sequence scheduled")
end

-- Logic scheduler --

local function OnLogic(event)
    -- Also detects availability if a dependency event is missed.
    TryRegister()

    if not running then
        return
    end

    firstTick = firstTick or event.logicTick
    local elapsed = event.logicTick - firstTick

    while running and steps[step] and elapsed >= steps[step].tick do
        steps[step].run()
        step = step + 1
    end

    if running and not steps[step] then
        running = false
        print("[Alluneve-Debug Test] Sequence complete")
    end
end

-- Optional dependency events --

local function OnDependencyChanged(event)
    print(
        "[Alluneve-Debug Test] Dependency event:",
        event.pluginIdentifier,
        event.enabled
    )

    if event.pluginIdentifier ~= "AlluneveDebug"
        and event.pluginIdentifier ~= "Alluneve-Runescape-Debug" then
        return
    end

    if event.enabled then
        disabledDependency = nil
        -- Retry registration on the next logic tick.
    else
        disabledDependency = AlluneveDebug
        UnbindDebug()
        print("[Alluneve-Debug Test] Switched to no-op API")
    end
end

-- Lifecycle --

Event.OptionalDependencyChanged.Subscribe(
    DEPENDENCY_REFERENCE,
    OnDependencyChanged
)

Event.Logic.Subscribe(EVENT_REFERENCE, OnLogic)

function PluginShutdown()
    Event.Logic.Unsubscribe(EVENT_REFERENCE)
    Event.OptionalDependencyChanged.Unsubscribe(DEPENDENCY_REFERENCE)
    UnbindDebug()
end

-- Initial registration attempt.
TryRegister()

if not boundDependency then
    print("[Alluneve-Debug Test] Waiting for Alluneve-Debug")
end
