
# Installation & Integration

Alluneve-Debug provides a shared logging API for RuneScape plugins. Integration is opt-in and supports both required and optional dependencies.

## 1. Installation

Install **Alluneve-Debug** through the RuneScape Plugin Hub and enable it in-game.

**PrettyUI** is required for the settings and report viewer.

For local development, the plugin's folder identifier is `Alluneve-Runescape-Debug`.

## 2. Declare the Dependency

Add Alluneve-Debug to your plugin's `plugin.json`.

**Required dependency:**

```json
"requiredDependencies": {
    "AlluneveDebug": "Alluneve-Runescape-Debug"
}
```

**Optional dependency (recommended):**

```json
"optionalDependencies": {
    "AlluneveDebug": "Alluneve-Runescape-Debug"
}
```

The identifier `AlluneveDebug` becomes the Lua variable through which your plugin accesses the exported API.

An optional dependency allows your plugin to continue functioning without Alluneve-Debug installed or enabled.

## 3. Register Your Plugin

Once the dependency is available, register using a unique identifier for your plugin:

```lua
local debugAPI = AlluneveDebug.RegisterYourself("MyPlugin")
```

Registration returns a logging API bound to your plugin identifier. You do not need to pass the identifier again when logging.

Use **dot notation** when calling these functions.

## 4. Logging API

```lua
debugAPI.Debug("Detailed diagnostic information")
debugAPI.Info("Plugin initialized")
debugAPI.Warn("Unexpected value:", value)
debugAPI.Error("Something went wrong:", reason)
```

Multiple arguments are supported and converted to strings.

| Method | Purpose |
|---|---|
| `Debug(...)` | Detailed diagnostic messages |
| `Info(...)` | General informational messages |
| `Warn(...)` | Unexpected or potentially problematic behavior |
| `Error(...)` | Error messages; automatically triggers the flight recorder |
| `SubmitLog()` | Submits the current session log as a saved report |
| `TriggerRecorder()` | Manually triggers the flight recorder |

For example:

```lua
-- Save a report of the current session.
debugAPI.SubmitLog()

-- Capture events surrounding unexpected behavior.
debugAPI.TriggerRecorder()
```

By default, the flight recorder captures **60 seconds before and 10 seconds after** its trigger. These durations can be configured in Alluneve-Debug's settings.

Logging an error through `Error()` automatically triggers the recorder. Alluneve-Debug does not intercept global Lua errors.

## 5. Optional Dependency Integration

When using an optional dependency, provide a no-op fallback so logging calls remain safe even when Alluneve-Debug is unavailable.

```lua
local function NoOp(...) end

local FALLBACK = {
    Debug = NoOp,
    Info = NoOp,
    Warn = NoOp,
    Error = NoOp,
    SubmitLog = NoOp,
    TriggerRecorder = NoOp
}

local debugAPI = FALLBACK
local dependencyEnabled = true

local function BindDebug()
    if not dependencyEnabled
        or not AlluneveDebug
        or not AlluneveDebug.RegisterYourself then
        debugAPI = FALLBACK
        return
    end

    debugAPI = AlluneveDebug.RegisterYourself("MyPlugin")
        or FALLBACK
end

BindDebug()

-- Handle enabling/disabling the optional dependency.
Event.OptionalDependencyChanged.Subscribe(
    "MyPluginDebugDependency",
    function(event)
        if event.pluginIdentifier ~= "AlluneveDebug" then
            return
        end

        dependencyEnabled = event.enabled
        debugAPI = FALLBACK

        if dependencyEnabled then
            BindDebug()
        end
    end
)

-- Retry registration if the dependency export
-- is not immediately available after enabling it.
Event.Logic.Subscribe("MyPluginDebugRetry", function()
    if dependencyEnabled and debugAPI == FALLBACK then
        BindDebug()
    end
end)
```

Your plugin can now call `debugAPI.Info(...)` and the other methods without checking whether Alluneve-Debug is enabled each time.

If you subscribe to events yourself, remember to unsubscribe during your plugin's shutdown.

## 6. Settings & Reports

Alluneve-Debug provides an in-game interface for managing diagnostics.

- **Settings:** Independently enable or disable DEBUG, INFO, WARN, and ERROR output.
- **Console:** Enabled severity levels are printed to the developer console.
- **Reports:** Severity settings also determine which entries are included in submitted reports.
- **Session history:** Messages are recorded independently of severity filtering.
- **Manual submission:** Select a registered plugin and submit its session log through the Plugins interface.
- **Report viewer:** Browse, inspect, and delete saved reports.

Reports are stored locally and persisted during normal plugin shutdown. An unexpected client termination may result in the loss of reports not yet saved.

Direct clipboard export is awaiting support from the RuneScape Plugin API.

## Additional Information

- [Alluneve-Debug on GitHub](https://github.com/Alluneve/Alluneve-Runescape-Debug)
- [RuneScape Plugin API Documentation](https://developer.runescape.com/rs/getting-started.html)
- [RuneScape Plugin Dependencies](https://developer.runescape.com/rs/structure.html#dependencies)