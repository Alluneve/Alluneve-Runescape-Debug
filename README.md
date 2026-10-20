# Alluneve-Debug

**Alluneve-Debug** is a shared debugging framework for RuneScape plugin developers. It provides a common API for structured, severity-based logging without having to build and maintain your own logging infrastructure.

Diagnostic messages are retained in independent, per-plugin rolling histories. When a registered plugin logs an error or manually triggers the flight recorder, Alluneve-Debug generates a report containing events from **60 seconds before and 10 seconds after the trigger** by default. This gives developers a timeline of what their plugin was doing around a problem.

Reports are stored locally and can be browsed through an in-game interface powered by **PrettyUI**.

## Features

- Shared debugging API with **DEBUG, INFO, WARN, and ERROR** severity levels.
- Independent per-plugin rolling session logs.
- Automatic flight-recorder triggers through the logging API, with configurable recording intervals.
- Manual recording triggers and session-log submission through the API.
- Independent severity filtering for console output and submitted reports.
- Efficient paged FIFO storage with tick-budgeted cleanup.
- Persistent reports with an in-game viewer for browsing and management.
- Support for both required and optional dependency integration.

Only diagnostic events explicitly supplied by participating plugins are recorded. Alluneve-Debug does not intercept global Lua errors.

For integration instructions and API documentation, see [INSTALLATION.md](INSTALLATION.md).