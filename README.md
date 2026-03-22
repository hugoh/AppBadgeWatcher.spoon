# AppBadgeWatcher Spoon

[![MIT License](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![Hammerspoon Spoon](https://img.shields.io/badge/Hammerspoon-Spoon-FFA500.svg)](https://www.hammerspoon.org/docs/index.html)

A Hammerspoon Spoon that monitors app dock badges and displays notification counts in your menu bar.

**Repository**: [https://github.com/hugoh/AppBadgeWatcher.spoon](https://github.com/hugoh/AppBadgeWatcher.spoon)

## Features

- Monitors dock badge values of specified applications
- Displays clean menu bar indicators with app icons
- Configurable refresh interval
- "Snooze" badge counts by clicking menu bar item

## Alternatives

If you're looking for other solutions in this space, consider:

- [Doll](https://github.com/xiaogdgenuine/Doll) - Native macOS app with similar functionality
- [Badgeify](https://apps.apple.com/us/app/badgeify/id1527212219) - Commercial alternative on Mac App Store

AppBadgeWatcher aims to provide a Hammerspoon-powered, configurable, lightweight option.

## Installation

1. Ensure you have [Hammerspoon](https://www.hammerspoon.org) installed
2. Clone this repository to your Spoons directory:
```bash
cd ~/.hammerspoon/Spoons
git clone https://github.com/hugoh/AppBadgeWatcher.spoon.git
```

## Configuration

Below is a sample configuration to add this to your `.hammerspoon/init.lua`:

```lua
-- Load the Spoon
hs.loadSpoon("AppBadgeWatcher")

-- Configure watched apps and settings
spoon.AppBadgeWatcher.appsToWatch = {
    "Slack",
    "Microsoft Teams",
}
-- Optional: default configuration showed below
spoon.AppBadgeWatcher.refreshInterval = 15  -- Update every 15 seconds
spoon.AppBadgeWatcher.nothingIndicator = "・"  -- Shown when no notifications
spoon.AppBadgeWatcher.grayscaleIcon = false  -- Convert app icons to grayscale?
spoon.AppBadgeWatcher.fontSize = 6  -- Badge font size
spoon.AppBadgeWatcher.textOffset = { x = 2, y = 0 } -- Text offset on icon

-- Start the watcher
spoon.AppBadgeWatcher:start()
```

## How It Works

The Spoon periodically checks the Dock's accessibility elements for badge values on specified applications. Key features:

- **Smart Polling**: Checks at configured intervals (default 15s)
- **Icon Cache**: App icons are cached for better performance
- **Compact Display**: Shows ∞ symbol for counts over 9
- **Low Profile**: Displays subtle dot when no notifications exist

## Security & Permissions

This Spoon requires Accessibility API access to:
- Monitor dock badge values
- Update menu bar indicators

Enable access in:
1. System Settings → Privacy & Security → Accessibility
2. Add Hammerspoon to the allowed apps list
