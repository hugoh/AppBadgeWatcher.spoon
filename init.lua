-- vim: set ft=lua:

--- === AppBadgeWatcher ===
---
--- A Hammerspoon Spoon that monitors app dock badges and displays notification counts in your menu bar.
---
--- Download: https://github.com/hugoh/AppBadgeWatcher.spoon/releases/latest

local obj = {}
obj.__index = obj

obj.name = "AppBadgeWatcher"
obj.version = "dev"
obj.author = "Hugo Haas"
obj.license = "MIT"
obj.homepage = "https://github.com/hugoh/AppBadgeWatcher.spoon"

-- Configurable
--- AppBadgeWatcher.appsToWatch
--- Variable
--- List of application names (strings) to watch for dock badge counts.
obj.appsToWatch = {}
--- AppBadgeWatcher.refreshInterval
--- Variable
--- Seconds between badge refresh polls (default: 15).
obj.refreshInterval = 15
--- AppBadgeWatcher.nothingIndicator
--- Variable
--- Menu bar text shown when no badges are active (default: "・").
obj.nothingIndicator = "・"
--- AppBadgeWatcher.grayscaleIcon
--- Variable
--- Convert app icons to grayscale in the menu bar (default: false).
obj.grayscaleIcon = false
--- AppBadgeWatcher.infiniteThreshold
--- Variable
--- Badge counts above this value are shown as a plus sign ("⁺") instead of the number (default: 9).
obj.infiniteThreshold = 9

-- Internal
obj.timer = nil
obj.menu = nil
obj.appItems = {}
obj.iconCache = {}
obj.log = hs.logger.new("AppBadgeWatcher", "info")
obj.snoozedBadges = {}

local ax = require("hs.axuielement")

local AX_TIMEOUT_SECONDS = 1

local function getAppPath(appName)
	local app = hs.application.get(appName)
	if not app then return nil end
	return app:bundleID() and app:path()
end

function obj.getIconForApp(appName, iconDim)
	local cacheKey = appName .. "_" .. iconDim .. "_" .. tostring(obj.grayscaleIcon)
	if obj.iconCache[cacheKey] then return obj.iconCache[cacheKey] end

	local appPath = getAppPath(appName)
	if not appPath then return nil end

	local icon = hs.image.iconForFile(appPath)
	if not icon then return nil end

	local resized = icon:bitmapRepresentation({ w = iconDim, h = iconDim }, obj.grayscaleIcon)
	obj.iconCache[cacheKey] = resized
	return resized
end

function obj:getDockBadges()
	local results = {}
	local watched = {}
	for _, appName in ipairs(self.appsToWatch) do
		watched[appName] = true
	end
	local dockApp = hs.application.find("Dock")
	if not dockApp then
		self.log.w("Dock not found")
		return nil
	end

	local dockAX = ax.applicationElement(dockApp)
	if not dockAX then
		self.log.w("Failed to get AXUIElement for Dock")
		return nil
	end

	local ok, err = pcall(function()
		dockAX:setTimeout(AX_TIMEOUT_SECONDS)
		local topChildren = dockAX.AXChildren or {}
		self.log.d("Found", #topChildren, "top-level Dock children")

		for _, container in ipairs(topChildren) do
			container:setTimeout(AX_TIMEOUT_SECONDS)
			if container.AXRole == "AXList" then
				local dockItems = container.AXChildren or {}
				self.log.d("Found", #dockItems, "Dock items in AXList")

				for _, item in ipairs(dockItems) do
					item:setTimeout(AX_TIMEOUT_SECONDS)
					local title = item.AXTitle
					if title and watched[title] then
						local badge = item.AXBadgeValue or item.AXStatusLabel
						if badge then
							local n = tonumber(badge)
							if n then
								self.log.d(string.format("Badge for '%s': %s", title, badge))
								results[title] = n
							else
								self.log.d(string.format("Non-numeric badge for '%s': %s", title, badge))
							end
						else
							self.log.v(string.format("No badge for '%s'", title))
						end
					end
				end
			else
				self.log.v("Skipping non-AXList child with role:", container.AXRole)
			end
		end
	end)

	if not ok then
		self.log.w("AX traversal failed (Dock may be relaunching or unresponsive):", tostring(err))
		return nil
	end

	return results
end

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

local SUPERSCRIPT = { digits = { "⁰", "¹", "²", "³", "⁴", "⁵", "⁶", "⁷", "⁸", "⁹" }, plus = "⁺" }
local SUBSCRIPT = { digits = { "₀", "₁", "₂", "₃", "₄", "₅", "₆", "₇", "₈", "₉" }, plus = "₊" }

local function scriptDigits(value, glyphs)
	if value > obj.infiniteThreshold then return glyphs.plus end
	return (tostring(value):gsub("%d", function(d) return glyphs.digits[tonumber(d) + 1] end))
end

local function badgeTitle(newBadge, snoozed)
	return (newBadge > 0 and scriptDigits(newBadge, SUPERSCRIPT) or "")
		.. (snoozed > 0 and scriptDigits(snoozed, SUBSCRIPT) or "")
end

local function deleteItem(item)
	if item then item:delete() end
end

function obj:appItem(appName)
	if not self.appItems[appName] then self.appItems[appName] = hs.menubar.new(true, "AppBadgeWatcher." .. appName) end
	return self.appItems[appName]
end

function obj:removeAppItem(appName)
	deleteItem(self.appItems[appName])
	self.appItems[appName] = nil
end

function obj:showIndicator()
	self.menu = self.menu or hs.menubar.new(true, "AppBadgeWatcher")
	if not self.menu then
		self.log.d("Failed to create menu bar item (menu bar may be full)")
		return
	end
	self.menu:setTitle(self.nothingIndicator)
end

function obj:hideIndicator()
	deleteItem(self.menu)
	self.menu = nil
end

function obj:updateMenuNoNotification()
	for appName in pairs(self.appItems) do
		self:removeAppItem(appName)
	end
	self:showIndicator()
	self.log.d("No active badges, showing indicator:", self.nothingIndicator)
	return self.menu ~= nil
end

function obj:updateMenuWithBadges(badges)
	local iconDim = 19

	local snoozeCallback = function()
		local copy = {}
		for k, v in pairs(self.lastBadges or {}) do
			copy[k] = v
		end
		self.snoozedBadges = copy
		hs.timer.doAfter(0, function() self:updateMenu(true) end)
	end

	local complete = true
	local shown = {}
	for _, appName in ipairs(self.appsToWatch) do
		if badges[appName] then
			if not self.snoozedBadges[appName] or self.snoozedBadges[appName] > badges[appName] then
				self.snoozedBadges[appName] = 0
			end
			local newBadge = badges[appName] - self.snoozedBadges[appName]
			local snoozed = self.snoozedBadges[appName]
			local appIcon = obj.getIconForApp(appName, iconDim)
			local wanted = (newBadge > 0 or snoozed > 0) and appIcon
			local item = wanted and self:appItem(appName)
			if item then
				item:setIcon(appIcon, false)
				item:setTitle(badgeTitle(newBadge, snoozed))
				item:setClickCallback(snoozeCallback)
				shown[appName] = true
			elseif wanted then
				complete = false
			end
		end
	end

	if next(shown) == nil then
		self.log.d("No icons to display despite active badges, falling back to nothingIndicator")
		local indicatorShown = self:updateMenuNoNotification()
		return complete and indicatorShown
	end

	for appName in pairs(self.appItems) do
		if not shown[appName] then self:removeAppItem(appName) end
	end
	self:hideIndicator()
	self.log.d("Updated menubar with badge items")
	return complete
end

function obj:updateMenu(forceUpdate)
	if not self.running then return end
	local dockBadges = self:getDockBadges()
	if not dockBadges then return end

	local hasBadges = false
	local filteredBadges = {}
	for _, appName in ipairs(self.appsToWatch) do
		local badge = dockBadges[appName]
		if badge and badge > 0 then
			filteredBadges[appName] = badge
			hasBadges = true
		end
	end

	for appName in pairs(self.snoozedBadges) do
		if not filteredBadges[appName] then self.snoozedBadges[appName] = nil end
	end

	if not forceUpdate and tablesEqual(filteredBadges, self.lastBadges) then
		self.log.d("No badge changes, skipping update")
		return
	end
	self.lastBadges = filteredBadges

	local rendered
	if hasBadges then
		rendered = self:updateMenuWithBadges(filteredBadges)
	else
		rendered = self:updateMenuNoNotification()
	end
	if not rendered then self.lastBadges = nil end
end

-- hs.timer stops a repeating timer whose callback throws, silently ending polling.
function obj:_poll()
	local ok, err = xpcall(self.updateMenu, debug.traceback, self)
	if not ok then self.log.e("Badge refresh failed: " .. tostring(err)) end
end

--- AppBadgeWatcher:configure(opts)
--- Method
--- Set one or more of AppBadgeWatcher's spoon-level variables from a table. Call before `:start()`.
---
--- Parameters:
---  * opts - a table with any of `appsToWatch`, `refreshInterval`, `nothingIndicator`,
---    `grayscaleIcon`, `infiniteThreshold`
function obj:configure(opts)
	for key, value in pairs(opts) do
		self[key] = value
	end
	self.lastBadges = nil
	return self
end

--- AppBadgeWatcher:init()
--- Method
--- Called automatically by `hs.loadSpoon()`. Logs the loaded version.
function obj:init()
	self.log.f("Loaded %s v%s", self.name, self.version)
	return self
end

-- Dock badge changes emit no accessibility notification (the Dock only supports
-- AXCreated, AXUIElementDestroyed and AXSelectedChildrenChanged), so the values
-- themselves must be polled. Launch and quit events at least confine that polling to
-- the time a watched app is actually running.
function obj:_watchedRunning(excluding)
	for _, appName in ipairs(self.appsToWatch) do
		if appName ~= excluding and hs.application.get(appName) then return true end
	end
	return false
end

function obj:_startPoll()
	if self.timer then return end
	self:updateMenu()
	self.timer = hs.timer.doEvery(self.refreshInterval, function() self:_poll() end)
end

function obj:_stopPoll()
	if self.timer then self.timer:stop() end
	self.timer = nil
end

local function contains(list, value)
	for _, v in ipairs(list) do
		if v == value then return true end
	end
	return false
end

function obj:_onAppEvent(appName, event)
	if not self.running or not contains(self.appsToWatch, appName) then return end
	if event == hs.application.watcher.launched then
		self:_startPoll()
	elseif event == hs.application.watcher.terminated and not self:_watchedRunning(appName) then
		self:_stopPoll()
		self.lastBadges = nil
		self.snoozedBadges = {}
		self:updateMenuNoNotification()
	end
end

--- AppBadgeWatcher:start()
--- Method
--- Start the badge watcher: create the menu bar item and poll at the configured interval
--- while any watched app is running.
function obj:start()
	if self.running then self:stop() end
	self.menu = hs.menubar.new(true, "AppBadgeWatcher")
	if not self.menu then
		self.log.w("Failed to create menu bar item (menu bar may be full); AppBadgeWatcher not started")
		return self
	end
	self.running = true
	self:showIndicator()
	self.log.i("AppBadgeWatcher started")
	self.appWatcher = hs.application.watcher.new(function(appName, event) self:_onAppEvent(appName, event) end)
	self.appWatcher:start()
	if self:_watchedRunning() then self:_startPoll() end
	return self
end

--- AppBadgeWatcher:stop()
--- Method
--- Stop the badge watcher and remove the menu bar item.
function obj:stop()
	self.log.f("Stopping %s v%s", self.name, self.version)
	self.running = false
	if self.appWatcher then self.appWatcher:stop() end
	self.appWatcher = nil
	self:_stopPoll()
	self:hideIndicator()
	for appName in pairs(self.appItems) do
		self:removeAppItem(appName)
	end
	self.lastBadges = nil
	self.snoozedBadges = {}
	self.iconCache = {}
	return self
end

return obj
