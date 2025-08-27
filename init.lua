local obj = {}
obj.__index = obj

obj.name = "AppBadgeWatcher"
obj.version = "1.0.1"
obj.author = "Hugo Haas"
obj.license = "MIT"
obj.homepage = "https://github.com/hugoh/AppBadgeWatcher.spoon"

-- Configurable
obj.appsToWatch = {}
obj.refreshInterval = 15
obj.nothingIndicator = "・"

-- Internal
obj.timer = nil
obj.menu = nil
obj.iconCache = {}
obj.log = hs.logger.new("AppBadgeWatcher", "info")

local ax = require("hs.axuielement")

local function getAppPath(appName)
	local app = hs.application.get(appName)
	if not app then
		return nil
	end
	return app:bundleID() and app:path()
end

function obj.getIconForApp(appName, iconDim)
	local cacheKey = appName .. "_" .. iconDim
	if obj.iconCache[cacheKey] then
		return obj.iconCache[cacheKey]
	end

	local appPath = getAppPath(appName)
	if not appPath then
		return nil
	end

	local icon = hs.image.iconForFile(appPath)
	if not icon then
		return nil
	end

	local resized = icon:setSize({ w = iconDim, h = iconDim })
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
						self.log.d(string.format("Badge for '%s': %s", title, badge))
						results[title] = tonumber(badge)
					else
						self.log.v(string.format("No badge for '%s'", title))
					end
				end
			end
		else
			self.log.v("Skipping non-AXList child with role:", container.AXRole)
		end
	end

	return results
end

local function tablesEqual(t1, t2)
	if not t2 then
		return false
	end
	for k, v in pairs(t1) do
		if t2[k] ~= v then
			return false
		end
	end
	for k in pairs(t2) do
		if t1[k] == nil then
			return false
		end
	end
	return true
end

function obj:updateMenuNoNotification()
	self.menu:setTitle(self.nothingIndicator)
	self.menu:setIcon(nil)
	self.log.d("No active badges, showing indicator:", self.nothingIndicator)
end

function obj:updateMenuWithBadges(badges)
	local menuItemDim = 22
	local iconDim = 19
	local itemWidth = 25
	local fontSize = 6

	local activeIcons = {}
	for _, appName in ipairs(self.appsToWatch) do
		local badge = badges[appName]
		if badge then
			if badge > 9 then
				badge = "∞"
			end
			local iconCanvas = hs.canvas.new({ x = 0, y = 0, h = menuItemDim, w = itemWidth }):alpha(0)
			iconCanvas[1] = {
				type = "image",
				image = obj.getIconForApp(appName, iconDim),
				imageScaling = "none",
				frame = { x = 0, y = 1, h = menuItemDim, w = menuItemDim },
			}
			iconCanvas[2] = {
				type = "text",
				text = badge,
				textSize = fontSize,
				textColor = { white = 1 },
				frame = { x = menuItemDim - 1, y = 1, h = fontSize + 2, w = fontSize + 2 },
			}
			table.insert(activeIcons, iconCanvas:imageFromCanvas())
		end
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
	self.log.d("Updated menubar icon with", #activeIcons, "icons")
end

function obj:updateMenu()
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

	if tablesEqual(filteredBadges, self.lastBadges) then
		self.log.d("No badge changes, skipping update")
		return
	end
	self.lastBadges = filteredBadges

	if not hasBadges then
		self:updateMenuNoNotification()
		return
	end

	self:updateMenuWithBadges(filteredBadges)
end

function obj:start()
	self.menu = hs.menubar.new()
	self:updateMenuNoNotification()
	self.log.i("AppBadgeWatcher started")
	self:updateMenu()
	self.timer = hs.timer.doEvery(self.refreshInterval, function()
		self:updateMenu()
	end)
end

function obj:stop()
	if self.timer then
		self.timer:stop()
	end
	if self.menu then
		self.menu:delete()
	end
	self.log.i("AppBadgeWatcher stopped")
end

return obj
