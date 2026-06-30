local mock_hs
local mock_ax
local AppBadgeWatcher

before_each(function()
	mock_hs = {
		logger = {
			new = function(_name, _level)
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
				elseif name == "Messages" then
					return {
						bundleID = function() return "com.apple.Messages" end,
						path = function() return "/Applications/Messages.app" end,
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
					bitmapRepresentation = function(_self, size, grayscale)
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

				canvas.alpha = function(self, _a) return self end
				canvas.imageFromCanvas = function(_self) return { elements = elements, frame = frame } end

				setmetatable(canvas, {
					__len = function(_self) return #elements end,
					__newindex = function(_self, key, value)
						if type(key) == "number" then elements[key] = value end
					end,
				})

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
					setIcon = function(self, icon, _flag)
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
			doEvery = function(_interval, _fn)
				return {
					stop = function(self) self._stopped = true end,
				}
			end,
		},
	}

	mock_ax = {
		applicationElement = function(app)
			if app and app.name == "Dock" then
				return {
					AXChildren = {
						{
							AXRole = "AXList",
							AXChildren = {
								{ AXTitle = "Mail", AXBadgeValue = "5" },
								{ AXTitle = "Slack", AXBadgeValue = "3" },
								{ AXTitle = "Messages", AXBadgeValue = "12" },
								{ AXTitle = "Finder" },
							},
						},
					},
				}
			end
			return nil
		end,
	}

	package.loaded["hs.axuielement"] = mock_ax
	package.loaded.hs = nil
	_G.hs = mock_hs

	AppBadgeWatcher = dofile("init.lua")
end)

after_each(function()
	if AppBadgeWatcher.timer then AppBadgeWatcher:stop() end
	AppBadgeWatcher.iconCache = {}
	AppBadgeWatcher.snoozedBadges = {}
	AppBadgeWatcher.lastBadges = nil
	AppBadgeWatcher.appsToWatch = {}
end)

local nothingIndicator = "・"

describe("AppBadgeWatcher", function()
	describe("module structure", function()
		it("returns a table", function() assert.is.table(AppBadgeWatcher) end)

		it("has name", function() assert.are.equal("AppBadgeWatcher", AppBadgeWatcher.name) end)
	end)

	describe("default configuration", function()
		it("has empty appsToWatch", function()
			assert.is.table(AppBadgeWatcher.appsToWatch)
			assert.are.equal(0, #AppBadgeWatcher.appsToWatch)
		end)

		it(
			"has default nothingIndicator",
			function() assert.are.equal(nothingIndicator, AppBadgeWatcher.nothingIndicator) end
		)
	end)

	describe("getIconForApp", function()
		it("returns icon for existing app", function()
			local icon = AppBadgeWatcher.getIconForApp("Mail", 32)
			assert.is_not_nil(icon)
		end)

		it("returns icon with correct path", function()
			local icon = AppBadgeWatcher.getIconForApp("Mail", 32)
			assert.are.equal("/Applications/Mail.app", icon.path)
		end)

		it("returns icon with correct dimensions", function()
			local icon = AppBadgeWatcher.getIconForApp("Mail", 32)
			assert.are.equal(32, icon.size.w)
			assert.are.equal(32, icon.size.h)
		end)

		it("caches icons by app name and size", function()
			local icon1 = AppBadgeWatcher.getIconForApp("Mail", 32)
			local icon2 = AppBadgeWatcher.getIconForApp("Mail", 32)
			assert.are.equal(icon1, icon2)
		end)

		it("creates different cache entries for different sizes", function()
			local icon1 = AppBadgeWatcher.getIconForApp("Mail", 16)
			local icon2 = AppBadgeWatcher.getIconForApp("Mail", 32)
			assert.are_not.equal(icon1, icon2)
		end)

		it("returns nil for non-existent app", function()
			local icon = AppBadgeWatcher.getIconForApp("NonExistentApp", 32)
			assert.is_nil(icon)
		end)

		it("passes grayscale flag to icon", function()
			AppBadgeWatcher.grayscaleIcon = true
			local icon = AppBadgeWatcher.getIconForApp("Mail", 32)
			assert.is_true(icon.grayscale)
		end)
	end)

	describe("getDockBadges", function()
		it("returns a table", function()
			local badges = AppBadgeWatcher:getDockBadges()
			assert.is.table(badges)
		end)

		it("extracts badge values from Dock", function()
			local badges = AppBadgeWatcher:getDockBadges()
			assert.are.equal(5, badges["Mail"])
			assert.are.equal(3, badges["Slack"])
		end)

		it("handles apps without badges", function()
			local badges = AppBadgeWatcher:getDockBadges()
			assert.is_nil(badges["Finder"])
		end)

		it("converts badge values to numbers", function()
			local badges = AppBadgeWatcher:getDockBadges()
			assert.is_number(badges["Mail"])
		end)

		it("returns empty table and does not throw when AX traversal errors", function()
			local originalApplicationElement = mock_ax.applicationElement
			mock_ax.applicationElement = function(app)
				if app and app.name == "Dock" then
					return {
						AXChildren = setmetatable({}, {
							__index = function() error("AX timeout") end,
						}),
					}
				end
				return nil
			end
			package.loaded["hs.axuielement"] = mock_ax
			AppBadgeWatcher = dofile("init.lua")

			local badges
			assert.has_no.errors(function() badges = AppBadgeWatcher:getDockBadges() end)
			assert.is.table(badges)
			assert.is_nil(next(badges))

			mock_ax.applicationElement = originalApplicationElement
		end)
	end)

	describe("start and stop", function()
		it("creates menu on start", function()
			AppBadgeWatcher:start()
			assert.is_not_nil(AppBadgeWatcher.menu)
		end)

		it("creates timer on start", function()
			AppBadgeWatcher:start()
			assert.is_not_nil(AppBadgeWatcher.timer)
		end)

		it("shows nothingIndicator initially", function()
			AppBadgeWatcher:start()
			assert.are.equal(nothingIndicator, AppBadgeWatcher.menu._title)
		end)

		it("stops timer on stop", function()
			AppBadgeWatcher:start()
			AppBadgeWatcher:stop()
			assert.is_true(AppBadgeWatcher.timer._stopped)
		end)

		it("deletes menu on stop", function()
			AppBadgeWatcher:start()
			AppBadgeWatcher:stop()
			assert.is_true(AppBadgeWatcher.menu._deleted)
		end)
	end)

	describe("updateMenu", function()
		before_each(function()
			AppBadgeWatcher.appsToWatch = { "Mail", "Slack" }
			AppBadgeWatcher:start()
		end)

		after_each(function() AppBadgeWatcher:stop() end)

		it("filters badges to watched apps only", function()
			AppBadgeWatcher:updateMenu(true)
			assert.is_not_nil(AppBadgeWatcher.lastBadges["Mail"])
			assert.is_not_nil(AppBadgeWatcher.lastBadges["Slack"])
			assert.is_nil(AppBadgeWatcher.lastBadges["Messages"])
		end)

		it("stores lastBadges after update", function()
			AppBadgeWatcher:updateMenu(true)
			assert.is_table(AppBadgeWatcher.lastBadges)
		end)

		it("skips update when badges unchanged", function()
			AppBadgeWatcher:updateMenu(true)
			local firstBadges = AppBadgeWatcher.lastBadges
			AppBadgeWatcher:updateMenu(false)
			assert.are.equal(firstBadges, AppBadgeWatcher.lastBadges)
		end)

		it("forces update when forceUpdate is true", function()
			AppBadgeWatcher:updateMenu(true)
			AppBadgeWatcher:updateMenu(true)
			assert.is.table(AppBadgeWatcher.lastBadges)
		end)

		it("clears snoozedBadges when no badges", function()
			AppBadgeWatcher.snoozedBadges["Mail"] = 2
			local originalGetDockBadges = AppBadgeWatcher.getDockBadges
			AppBadgeWatcher.getDockBadges = function(_self) return {} end
			AppBadgeWatcher:updateMenu(true)
			assert.is_nil(next(AppBadgeWatcher.snoozedBadges))
			AppBadgeWatcher.getDockBadges = originalGetDockBadges
		end)

		it("shows nothingIndicator when no badges", function()
			local originalGetDockBadges = AppBadgeWatcher.getDockBadges
			AppBadgeWatcher.getDockBadges = function(_self) return {} end
			AppBadgeWatcher:updateMenu(true)
			assert.are.equal(nothingIndicator, AppBadgeWatcher.menu._title)
			AppBadgeWatcher.getDockBadges = originalGetDockBadges
		end)
	end)

	describe("snoozedBadges", function()
		before_each(function()
			AppBadgeWatcher.appsToWatch = { "Mail" }
			AppBadgeWatcher:start()
		end)

		after_each(function() AppBadgeWatcher:stop() end)

		it("tracks snoozed badge values", function()
			AppBadgeWatcher:updateMenu(true)
			AppBadgeWatcher.snoozedBadges["Mail"] = 2
			AppBadgeWatcher:updateMenu(true)
			assert.are.equal(2, AppBadgeWatcher.snoozedBadges["Mail"])
		end)

		it("resets snooze when badge exceeds snoozed value", function()
			AppBadgeWatcher.snoozedBadges["Mail"] = 10
			AppBadgeWatcher:updateMenu(true)
			assert.are.equal(0, AppBadgeWatcher.snoozedBadges["Mail"])
		end)

		it("still shows icon when all badges are snoozed after click", function()
			AppBadgeWatcher:updateMenu(true)
			AppBadgeWatcher.menu._clickCb()
			assert.is_not_nil(AppBadgeWatcher.menu._icon)
			assert.are.equal("", AppBadgeWatcher.menu._title)
		end)

		it("keeps click callback after all badges are snoozed", function()
			AppBadgeWatcher:updateMenu(true)
			AppBadgeWatcher.menu._clickCb()
			assert.is_function(AppBadgeWatcher.menu._clickCb)
		end)

		it("second click after snooze is a no-op resnooze", function()
			AppBadgeWatcher:updateMenu(true)
			AppBadgeWatcher.menu._clickCb()
			AppBadgeWatcher.menu._clickCb()
			assert.is_not_nil(AppBadgeWatcher.menu._icon)
			assert.is_function(AppBadgeWatcher.menu._clickCb)
		end)

		it("snoozedBadges is a copy of lastBadges, not an alias", function()
			AppBadgeWatcher:updateMenu(true)
			AppBadgeWatcher.menu._clickCb()
			assert.are_not.equal(AppBadgeWatcher.lastBadges, AppBadgeWatcher.snoozedBadges)
			AppBadgeWatcher.lastBadges["Mail"] = 999
			assert.are_not.equal(999, AppBadgeWatcher.snoozedBadges["Mail"])
		end)
	end)

	describe("badge display edge cases", function()
		before_each(function()
			AppBadgeWatcher.appsToWatch = { "Messages" }
			AppBadgeWatcher:start()
		end)

		after_each(function() AppBadgeWatcher:stop() end)

		it("stores badges over 9", function()
			AppBadgeWatcher:updateMenu(true)
			assert.are.equal(12, AppBadgeWatcher.lastBadges["Messages"])
		end)
	end)

	describe("internal state", function()
		it("initializes with nil timer", function() assert.is_nil(AppBadgeWatcher.timer) end)

		it("initializes with nil menu", function() assert.is_nil(AppBadgeWatcher.menu) end)

		it("initializes with empty iconCache", function()
			assert.is_table(AppBadgeWatcher.iconCache)
			assert.are.equal(0, #AppBadgeWatcher.iconCache)
		end)

		it("initializes with empty snoozedBadges", function()
			assert.is_table(AppBadgeWatcher.snoozedBadges)
			assert.is_nil(next(AppBadgeWatcher.snoozedBadges))
		end)

		it("has logger instance", function() assert.is_table(AppBadgeWatcher.log) end)
	end)
end)
