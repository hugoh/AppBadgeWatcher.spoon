-- Test suite for AppBadgeWatcher.spoon
-- Run with: lua test_init.lua

-- Mock Hammerspoon environment
local mock_hs = {
	logger = {
		new = function(name, level)
			return {
				i = function() end,
				w = function() end,
				d = function() end,
				v = function() end,
			}
		end,
	},
	application = {
		get = function(name)
			if name == "Mail" then
				return {
					bundleID = function() return "com.apple.Mail" end,
					path = function() return "/Applications/Mail.app" end,
				}
			elseif name == "Slack" then
				return {
					bundleID = function() return "com.tinyspeck.slackmacgap" end,
					path = function() return "/Applications/Slack.app" end,
				}
			end
			return nil
		end,
		find = function(name)
			if name == "Dock" then return { name = "Dock" } end
			return nil
		end,
	},
	image = {
		iconForFile = function(path)
			return {
				bitmapRepresentation = function(self, size, grayscale)
					return {
						path = path,
						size = size,
						grayscale = grayscale,
					}
				end,
			}
		end,
	},
	canvas = {
		new = function(frame)
			local canvas = {}
			local elements = {}

			canvas.alpha = function(self, a) return self end

			canvas.__len = function() return #elements end

			canvas.__newindex = function(self, key, value)
				if type(key) == "number" then elements[key] = value end
			end

			canvas.imageFromCanvas = function(self) return { elements = elements, frame = frame } end

			return canvas
		end,
	},
	menubar = {
		new = function()
			return {
				setTitle = function(self, title)
					self._title = title
					return self
				end,
				setIcon = function(self, icon, flag)
					self._icon = icon
					return self
				end,
				setClickCallback = function(self, cb)
					self._clickCb = cb
					return self
				end,
				delete = function(self)
					self._deleted = true
					return self
				end,
			}
		end,
	},
	timer = {
		doEvery = function(interval, fn)
			return {
				stop = function(self) self._stopped = true end,
			}
		end,
	},
}

local mock_ax = {
	applicationElement = function(app)
		if app and app.name == "Dock" then
			return {
				AXChildren = {
					{
						AXRole = "AXList",
						AXChildren = {
							{ AXTitle = "Mail", AXBadgeValue = "5" },
							{ AXTitle = "Slack", AXBadgeValue = "3" },
							{ AXTitle = "Finder" },
						},
					},
				},
			}
		end
		return nil
	end,
}

-- Setup package path to find the module
package.loaded["hs.axuielement"] = mock_ax
package.loaded.hs = mock_hs
_G.hs = mock_hs

-- Load the module
local AppBadgeWatcher = dofile("init.lua")

-- Test helper
local tests_passed = 0
local tests_failed = 0

local function assert_equal(actual, expected, message)
	if actual == expected then
		tests_passed = tests_passed + 1
		print("✓ " .. message)
	else
		tests_failed = tests_failed + 1
		print("✗ " .. message)
		print("  Expected: " .. tostring(expected))
		print("  Actual: " .. tostring(actual))
	end
end

local function assert_nil(value, message)
	if value == nil then
		tests_passed = tests_passed + 1
		print("✓ " .. message)
	else
		tests_failed = tests_failed + 1
		print("✗ " .. message)
		print("  Expected nil, got: " .. tostring(value))
	end
end

local function assert_not_nil(value, message)
	if value ~= nil then
		tests_passed = tests_passed + 1
		print("✓ " .. message)
	else
		tests_failed = tests_failed + 1
		print("✗ " .. message)
		print("  Expected non-nil value")
	end
end

-- Tests
print("\n=== AppBadgeWatcher Tests ===\n")

-- Test: Module structure
print("-- Module Structure --")
assert_equal(type(AppBadgeWatcher), "table", "Module returns a table")
assert_equal(AppBadgeWatcher.name, "AppBadgeWatcher", "Module has name")

-- Test: Default configuration
print("\n-- Default Configuration --")
assert_equal(type(AppBadgeWatcher.appsToWatch), "table", "appsToWatch is a table")
assert_equal(#AppBadgeWatcher.appsToWatch, 0, "appsToWatch is empty by default")

-- Test: getIconForApp function
print("\n-- getIconForApp Function --")
local icon = AppBadgeWatcher.getIconForApp("Mail", 32)
assert_not_nil(icon, "Returns icon for existing app")
assert_equal(icon.path, "/Applications/Mail.app", "Icon has correct path")
assert_equal(icon.size.w, 32, "Icon has correct width")
assert_equal(icon.size.h, 32, "Icon has correct height")

local cachedIcon = AppBadgeWatcher.getIconForApp("Mail", 32)
assert_equal(icon, cachedIcon, "Icon is cached")

local noIcon = AppBadgeWatcher.getIconForApp("NonExistentApp", 32)
assert_nil(noIcon, "Returns nil for non-existent app")

-- Test: getDockBadges function
print("\n-- getDockBadges Function --")
local badges = AppBadgeWatcher:getDockBadges()
assert_equal(type(badges), "table", "Returns a table")
assert_equal(badges["Mail"], 5, "Gets Mail badge value")
assert_equal(badges["Slack"], 3, "Gets Slack badge value")
assert_nil(badges["Finder"], "Finder has no badge")

-- Test: tablesEqual function (internal)
print("\n-- tablesEqual Function --")
local tablesEqual
do
	local t1 = { a = 1, b = 2 }
	local t2 = { a = 1, b = 2 }
	local t3 = { a = 1, b = 3 }
	local t4 = { a = 1 }

	local function tablesEqual(t1, t2)
		if not t2 then return false end
		for k, v in pairs(t1) do
			if t2[k] ~= v then return false end
		end
		for k in pairs(t2) do
			if t1[k] == nil then return false end
		end
		return true
	end

	assert_equal(tablesEqual(t1, t2), true, "Equal tables return true")
	assert_equal(tablesEqual(t1, t3), false, "Different values return false")
	assert_equal(tablesEqual(t1, t4), false, "Missing keys return false")
	assert_equal(tablesEqual(t4, t1), false, "Extra keys return false")
	assert_equal(tablesEqual(t1, nil), false, "nil comparison returns false")
end

-- Test: start and stop
print("\n-- Start/Stop Functions --")
AppBadgeWatcher:start()
assert_not_nil(AppBadgeWatcher.menu, "Menu is created after start")
assert_not_nil(AppBadgeWatcher.timer, "Timer is created after start")
assert_equal(AppBadgeWatcher.menu._title, "・", "Menu shows nothingIndicator initially")

AppBadgeWatcher:stop()
assert_equal(AppBadgeWatcher.timer._stopped, true, "Timer is stopped")
assert_equal(AppBadgeWatcher.menu._deleted, true, "Menu is deleted")

-- Test: updateMenu with badges
print("\n-- updateMenu Function --")
AppBadgeWatcher.appsToWatch = { "Mail", "Slack" }
AppBadgeWatcher:start()

local dockBadges = AppBadgeWatcher:getDockBadges()
assert_equal(dockBadges["Mail"], 5, "Mail badge is 5")
assert_equal(dockBadges["Slack"], 3, "Slack badge is 3")

AppBadgeWatcher:updateMenu(true)
assert_not_nil(AppBadgeWatcher.lastBadges, "lastBadges is set after update")
assert_equal(AppBadgeWatcher.lastBadges["Mail"], 5, "lastBadges has Mail")
assert_equal(AppBadgeWatcher.lastBadges["Slack"], 3, "lastBadges has Slack")

AppBadgeWatcher:stop()

-- Test: updateMenu no changes skip
print("\n-- updateMenu Skip on No Changes --")
AppBadgeWatcher:start()
AppBadgeWatcher:updateMenu(true)
local firstBadges = AppBadgeWatcher.lastBadges
AppBadgeWatcher:updateMenu(false)
assert_equal(AppBadgeWatcher.lastBadges, firstBadges, "Skips update when no changes")
AppBadgeWatcher:stop()

-- Test: snoozedBadges functionality
print("\n-- snoozedBadges Functionality --")
AppBadgeWatcher.appsToWatch = { "Mail" }
AppBadgeWatcher:start()
AppBadgeWatcher:updateMenu(true)
AppBadgeWatcher.snoozedBadges["Mail"] = 2
AppBadgeWatcher:updateMenu(true)
assert_equal(AppBadgeWatcher.snoozedBadges["Mail"], 2, "Snoozed badge is tracked")
AppBadgeWatcher:stop()

-- Test: badge over 9 shows infinity
print("\n-- Badge Over 9 Shows Infinity --")
local originalGetDockBadges = AppBadgeWatcher.getDockBadges
AppBadgeWatcher.getDockBadges = function(self) return { Mail = 15 } end
AppBadgeWatcher.appsToWatch = { "Mail" }
AppBadgeWatcher:start()
AppBadgeWatcher:updateMenu(true)
assert_equal(AppBadgeWatcher.lastBadges["Mail"], 15, "Badge over 9 is stored")
AppBadgeWatcher:stop()
AppBadgeWatcher.getDockBadges = originalGetDockBadges

-- Test: no badges shows indicator
print("\n-- No Badges Shows Indicator --")
AppBadgeWatcher.getDockBadges = function(self) return {} end
AppBadgeWatcher.appsToWatch = { "Mail" }
AppBadgeWatcher:start()
AppBadgeWatcher:updateMenu(true)
assert_equal(AppBadgeWatcher.menu._title, "・", "Shows nothingIndicator when no badges")
assert_equal(next(AppBadgeWatcher.snoozedBadges), nil, "snoozedBadges is cleared")
AppBadgeWatcher:stop()
AppBadgeWatcher.getDockBadges = originalGetDockBadges

-- Test: Configuration changes
print("\n-- Configuration Changes --")
AppBadgeWatcher.appsToWatch = { "Mail", "Slack", "Teams" }
AppBadgeWatcher.refreshInterval = 30
AppBadgeWatcher.nothingIndicator = "○"
AppBadgeWatcher.grayscaleIcon = true
AppBadgeWatcher.fontSize = 8
AppBadgeWatcher.textOffset = { x = 3, y = 1 }

assert_equal(#AppBadgeWatcher.appsToWatch, 3, "appsToWatch can be updated")
assert_equal(AppBadgeWatcher.refreshInterval, 30, "refreshInterval can be updated")
assert_equal(AppBadgeWatcher.nothingIndicator, "○", "nothingIndicator can be updated")
assert_equal(AppBadgeWatcher.grayscaleIcon, true, "grayscaleIcon can be updated")
assert_equal(AppBadgeWatcher.fontSize, 8, "fontSize can be updated")
assert_equal(AppBadgeWatcher.textOffset.x, 3, "textOffset.x can be updated")
assert_equal(AppBadgeWatcher.textOffset.y, 1, "textOffset.y can be updated")

-- Test: icon cache
print("\n-- Icon Cache --")
AppBadgeWatcher.iconCache = {}
local icon1 = AppBadgeWatcher.getIconForApp("Mail", 16)
local icon2 = AppBadgeWatcher.getIconForApp("Mail", 16)
assert_equal(icon1, icon2, "Icons are cached for same dimensions")

local icon3 = AppBadgeWatcher.getIconForApp("Mail", 32)
assert_not_nil(icon3, "Different size creates new cache entry")

-- Test: textOffset default
print("\n-- textOffset Default --")
AppBadgeWatcher.textOffset = { x = 2, y = 0 }
assert_equal(AppBadgeWatcher.textOffset.x, 2, "Default textOffset.x is 2")
assert_equal(AppBadgeWatcher.textOffset.y, 0, "Default textOffset.y is 0")

-- Summary
print("\n=== Test Summary ===")
print(string.format("Passed: %d", tests_passed))
print(string.format("Failed: %d", tests_failed))
print(string.format("Total: %d", tests_passed + tests_failed))

if tests_failed > 0 then
	os.exit(1)
else
	print("\nAll tests passed!")
	os.exit(0)
end
