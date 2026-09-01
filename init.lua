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
--- AppBadgeWatcher.fontSize
--- Variable
--- Font size for badge count labels (default: 6).
obj.fontSize = 6
--- AppBadgeWatcher.textOffset
--- Variable
--- Pixel offset {x, y} applied to badge text on the icon (default: { x = 2, y = 0 }).
obj.textOffset = { x = 2, y = 0 }
--- AppBadgeWatcher.infiniteThreshold
--- Variable
--- Badge counts above this value are shown as "∞" instead of the number (default: 9).
obj.infiniteThreshold = 9

-- Internal
obj.timer = nil
obj.menu = nil
obj.iconCache = {}
obj.log = hs.logger.new("AppBadgeWatcher", "info")
obj.snoozedBadges = {}

local ax = require("hs.axuielement")

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
	local dockApp = hs.application.find("Dock")
	if not dockApp then
		self.log.w("Dock not found")
		return results
	end

	local dockAX = ax.applicationElement(dockApp)
	if not dockAX then
		self.log.w("Failed to get AXUIElement for Dock")
		return results
	end

	local ok, err = pcall(function()
		local topChildren = dockAX.AXChildren or {}
		self.log.d("Found", #topChildren, "top-level Dock children")

		for _, container in ipairs(topChildren) do
			if container.AXRole == "AXList" then
				local dockItems = container.AXChildren or {}
				self.log.d("Found", #dockItems, "Dock items in AXList")

				for _, item in ipairs(dockItems) do
					local title = item.AXTitle
					local badge = item.AXBadgeValue or item.AXStatusLabel
					if title then
						if badge then
							local n = tonumber(badge)
							if n then
								self.log.d(string.format("Badge for '%s': %s", title, badge))
								results[title] = n
							else
								self.log.w(string.format("Non-numeric badge for '%s': %s", title, badge))
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
		return {}
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

function obj:updateMenuNoNotification()
	if not self.menu then return end
	self.menu:setTitle(self.nothingIndicator)
	self.menu:setIcon(nil)
	self.log.d("No active badges, showing indicator:", self.nothingIndicator)
end

function obj:updateMenuWithBadges(badges)
	if not self.menu then return end
	local menuItemDim = 22
	local iconDim = 19
	local itemWidth = 25
	local fontSize = obj.fontSize

	local activeIcons = {}
	for _, appName in ipairs(self.appsToWatch) do
		if badges[appName] then
			if not self.snoozedBadges[appName] or self.snoozedBadges[appName] > badges[appName] then
				self.snoozedBadges[appName] = 0
			end
			local newBadge = badges[appName] - self.snoozedBadges[appName]
			local snoozed = self.snoozedBadges[appName]
			local appIcon = obj.getIconForApp(appName, iconDim)
			if (newBadge > 0 or snoozed > 0) and appIcon then
				local iconCanvas = hs.canvas.new({ x = 0, y = 0, h = menuItemDim, w = itemWidth }):alpha(0)
				local idx = 1
				iconCanvas[idx] = {
					type = "image",
					image = appIcon,
					imageScaling = "none",
					frame = { x = 0, y = 1, h = menuItemDim, w = menuItemDim },
				}
				if newBadge > 0 then
					if newBadge > obj.infiniteThreshold then newBadge = "∞" end
					idx = idx + 1
					iconCanvas[idx] = {
						type = "text",
						text = newBadge,
						textSize = fontSize,
						textColor = { white = 1 },
						frame = {
							x = itemWidth - fontSize + obj.textOffset.x,
							y = 1 + obj.textOffset.y,
							h = fontSize + 2,
							w = fontSize + 2,
						},
					}
				end
				if snoozed > 0 then
					if snoozed > obj.infiniteThreshold then snoozed = "∞" end
					idx = idx + 1
					iconCanvas[idx] = {
						type = "text",
						text = snoozed,
						textSize = fontSize,
						textColor = { white = 1 },
						frame = {
							x = itemWidth - fontSize + obj.textOffset.x,
							y = menuItemDim - fontSize + obj.textOffset.y,
							h = fontSize + 2,
							w = fontSize + 2,
						},
					}
				end
				table.insert(activeIcons, iconCanvas:imageFromCanvas())
			end
		end
	end

	if #activeIcons == 0 then
		self.log.d("No icons to display despite active badges, falling back to nothingIndicator")
		self:updateMenuNoNotification()
		return
	end

	local snoozeCallback = function()
		local copy = {}
		for k, v in pairs(self.lastBadges or {}) do
			copy[k] = v
		end
		self.snoozedBadges = copy
		self:updateMenu(true)
	end

	local totalWidth = itemWidth * #activeIcons
	local canvas = hs.canvas.new({ x = 0, y = 0, h = itemWidth, w = totalWidth }):alpha(0)
	for i, icon in ipairs(activeIcons) do
		canvas[#canvas + 1] = {
			type = "image",
			image = icon,
			frame = { x = (i - 1) * itemWidth, y = 0, h = menuItemDim, w = itemWidth },
		}
	end
	self.menu:setIcon(canvas:imageFromCanvas(), false)
	self.menu:setTitle("")
	self.menu:setClickCallback(snoozeCallback)
	self.log.d("Updated menubar icon with", #activeIcons, "icons")
end

function obj:updateMenu(forceUpdate)
	local dockBadges = self:getDockBadges()

	local hasBadges = false
	local filteredBadges = {}
	for _, appName in ipairs(self.appsToWatch) do
		local badge = dockBadges[appName]
		if badge and badge > 0 then
			filteredBadges[appName] = badge
			hasBadges = true
		end
	end

	if not forceUpdate and tablesEqual(filteredBadges, self.lastBadges) then
		self.log.d("No badge changes, skipping update")
		return
	end
	self.lastBadges = filteredBadges

	if not hasBadges then
		self:updateMenuNoNotification()
		self.snoozedBadges = {}
		return
	end

	self:updateMenuWithBadges(filteredBadges)
end

--- AppBadgeWatcher:configure(opts)
--- Method
--- Set one or more of AppBadgeWatcher's spoon-level variables from a table. Call before `:start()`.
---
--- Parameters:
---  * opts - a table with any of `appsToWatch`, `refreshInterval`, `nothingIndicator`,
---    `grayscaleIcon`, `fontSize`, `textOffset`, `infiniteThreshold`
function obj:configure(opts)
	for _, key in ipairs({
		"appsToWatch",
		"refreshInterval",
		"nothingIndicator",
		"grayscaleIcon",
		"fontSize",
		"textOffset",
		"infiniteThreshold",
	}) do
		if opts[key] ~= nil then self[key] = opts[key] end
	end
	return self
end

--- AppBadgeWatcher:init()
--- Method
--- Called automatically by `hs.loadSpoon()`. Logs the loaded version.
function obj:init()
	self.log.f("Loaded %s v%s", self.name, self.version)
	return self
end

--- AppBadgeWatcher:start()
--- Method
--- Start the badge watcher: create the menu bar item and begin polling at the configured interval.
function obj:start()
	self.menu = hs.menubar.new()
	if not self.menu then
		self.log.w("Failed to create menu bar item (menu bar may be full); AppBadgeWatcher not started")
		return self
	end
	self:updateMenuNoNotification()
	self.log.i("AppBadgeWatcher started")
	self:updateMenu()
	self.timer = hs.timer.doEvery(self.refreshInterval, function() self:updateMenu() end)
	return self
end

--- AppBadgeWatcher:stop()
--- Method
--- Stop the badge watcher and remove the menu bar item.
function obj:stop()
	self.log.f("Stopping %s v%s", self.name, self.version)
	if self.timer then self.timer:stop() end
	if self.menu then self.menu:delete() end
	self.lastBadges = nil
	self.snoozedBadges = {}
	self.iconCache = {}
	return self
end

return obj
