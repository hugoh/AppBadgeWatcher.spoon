local mock_hs
local mock_ax
local AppBadgeWatcher
local created_items
local warnings
local deferred

local function axElement(t)
	function t:setTimeout(seconds)
		self._timeout = seconds
		return self
	end
	return t
end

local function runDeferred()
	local pending = deferred
	deferred = {}
	for _, fn in ipairs(pending) do
		fn()
	end
end

local function appItem(name)
	for i = #created_items, 1, -1 do
		if created_items[i]._autosaveName == "AppBadgeWatcher." .. name then return created_items[i] end
	end
end

before_each(function()
	created_items = {}
	warnings = {}
	deferred = {}
	mock_hs = {
		logger = {
			new = function(_name, _level)
				return {
					i = function() end,
					f = function() end,
					w = function(...) table.insert(warnings, table.concat({ ... }, " ")) end,
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
		menubar = {
			new = function(_inMenuBar, autosaveName)
				local item = { _autosaveName = autosaveName }
				function item:setTitle(title)
					self._title = title
					return self
				end
				function item:setIcon(icon, _flag)
					self._icon = icon
					return self
				end
				function item:setClickCallback(cb)
					self._clickCb = cb
					return self
				end
				function item:delete()
					self._deleted = true
					return self
				end
				table.insert(created_items, item)
				return item
			end,
		},
		timer = {
			doEvery = function(_interval, _fn)
				return {
					stop = function(self) self._stopped = true end,
				}
			end,
			doAfter = function(_delay, fn) table.insert(deferred, fn) end,
		},
	}

	mock_ax = {
		applicationElement = function(app)
			if app and app.name == "Dock" then
				return axElement({
					AXChildren = {
						axElement({
							AXRole = "AXList",
							AXChildren = {
								axElement({ AXTitle = "Mail", AXBadgeValue = "5" }),
								axElement({ AXTitle = "Slack", AXBadgeValue = "3" }),
								axElement({ AXTitle = "Messages", AXBadgeValue = "12" }),
								axElement({ AXTitle = "Notes", AXBadgeValue = "•" }),
								axElement({ AXTitle = "Finder" }),
							},
						}),
					},
				})
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

		it("returns nil and does not throw when AX traversal errors", function()
			local originalApplicationElement = mock_ax.applicationElement
			mock_ax.applicationElement = function(app)
				if app and app.name == "Dock" then
					return {
						setTimeout = function(self) return self end,
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
			assert.is_nil(badges)

			mock_ax.applicationElement = originalApplicationElement
		end)
	end)

	describe("getDockBadges robustness", function()
		it("bounds AX calls with a timeout so a hung Dock cannot stall Hammerspoon", function()
			local dockAX = mock_ax.applicationElement({ name = "Dock" })
			mock_ax.applicationElement = function() return dockAX end
			AppBadgeWatcher:getDockBadges()
			assert.are.equal(1, dockAX._timeout)
		end)

		it("bounds AX calls on every Dock element, since child elements do not inherit the timeout", function()
			local dockAX = mock_ax.applicationElement({ name = "Dock" })
			mock_ax.applicationElement = function() return dockAX end
			AppBadgeWatcher:getDockBadges()
			local list = dockAX.AXChildren[1]
			assert.are.equal(1, list._timeout)
			for _, item in ipairs(list.AXChildren) do
				assert.are.equal(1, item._timeout)
			end
		end)

		it("does not warn about non-numeric badges on every poll", function()
			AppBadgeWatcher:getDockBadges()
			assert.are.equal(0, #warnings)
		end)
	end)

	describe("getDockBadges when the Dock is unavailable", function()
		it("returns nil so callers can tell failure from no badges", function()
			mock_hs.application.find = function() return nil end
			assert.is_nil(AppBadgeWatcher:getDockBadges())
		end)
	end)

	describe("start and stop", function()
		it("creates menu on start", function()
			AppBadgeWatcher:start()
			assert.is_not_nil(AppBadgeWatcher.menu)
		end)

		it("gives the nothing indicator a stable autosave name", function()
			AppBadgeWatcher:start()
			assert.are.equal("AppBadgeWatcher", AppBadgeWatcher.menu._autosaveName)
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
			local timer = AppBadgeWatcher.timer
			AppBadgeWatcher:stop()
			assert.is_true(timer._stopped)
			assert.is_nil(AppBadgeWatcher.timer)
		end)

		it("deletes menu on stop", function()
			AppBadgeWatcher:start()
			local menu = AppBadgeWatcher.menu
			AppBadgeWatcher:stop()
			assert.is_true(menu._deleted)
			assert.is_nil(AppBadgeWatcher.menu)
		end)

		it("start twice replaces the first timer and menu instead of leaking them", function()
			AppBadgeWatcher:start()
			local timer, menu = AppBadgeWatcher.timer, AppBadgeWatcher.menu
			AppBadgeWatcher:start()
			assert.is_true(timer._stopped)
			assert.is_true(menu._deleted)
			assert.is_not_nil(AppBadgeWatcher.menu)
		end)

		it("updateMenu after stop is a no-op", function()
			AppBadgeWatcher.appsToWatch = { "Mail" }
			AppBadgeWatcher:start()
			AppBadgeWatcher:stop()
			local count = #created_items
			assert.has_no.errors(function() AppBadgeWatcher:updateMenu(true) end)
			assert.are.equal(count, #created_items)
		end)

		it("clears lastBadges, snoozedBadges and iconCache on stop", function()
			AppBadgeWatcher.appsToWatch = { "Mail" }
			AppBadgeWatcher:start()
			AppBadgeWatcher:updateMenu(true)
			AppBadgeWatcher.snoozedBadges["Mail"] = 2
			AppBadgeWatcher.getIconForApp("Mail", 19)
			assert.is_not_nil(AppBadgeWatcher.lastBadges)
			assert.is_not_nil(next(AppBadgeWatcher.snoozedBadges))
			assert.is_not_nil(next(AppBadgeWatcher.iconCache))

			AppBadgeWatcher:stop()

			assert.is_nil(AppBadgeWatcher.lastBadges)
			assert.is_nil(next(AppBadgeWatcher.snoozedBadges))
			assert.is_nil(next(AppBadgeWatcher.iconCache))
		end)

		it("does not crash when menubar.new() returns nil", function()
			mock_hs.menubar.new = function() return nil end
			assert.has_no.errors(function() AppBadgeWatcher:start() end)
			assert.is_nil(AppBadgeWatcher.menu)
			assert.is_nil(AppBadgeWatcher.timer)
		end)

		it("does not crash calling updateMenu when menu failed to create", function()
			mock_hs.menubar.new = function() return nil end
			AppBadgeWatcher.appsToWatch = { "Mail" }
			AppBadgeWatcher:start()
			assert.has_no.errors(function() AppBadgeWatcher:updateMenu(true) end)
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

		it("keeps snoozes and items when the Dock read fails", function()
			AppBadgeWatcher:updateMenu(true)
			AppBadgeWatcher.snoozedBadges["Mail"] = 2
			local mail = appItem("Mail")
			AppBadgeWatcher.getDockBadges = function(_self) return nil end
			AppBadgeWatcher:updateMenu(true)
			assert.are.equal(2, AppBadgeWatcher.snoozedBadges["Mail"])
			assert.is_nil(mail._deleted)
			assert.is_nil(AppBadgeWatcher.menu)
		end)

		it("forgets the snooze of an app whose badge cleared while others remain", function()
			AppBadgeWatcher:updateMenu(true)
			AppBadgeWatcher.snoozedBadges["Mail"] = 5
			AppBadgeWatcher.getDockBadges = function(_self) return { Slack = 3 } end
			AppBadgeWatcher:updateMenu(true)
			assert.is_nil(AppBadgeWatcher.snoozedBadges["Mail"])
			AppBadgeWatcher.getDockBadges = function(_self) return { Mail = 6, Slack = 3 } end
			AppBadgeWatcher:updateMenu(true)
			assert.are.equal("⁶", appItem("Mail")._title)
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

		it("still shows icon with subscript count when all badges are snoozed after click", function()
			AppBadgeWatcher:updateMenu(true)
			appItem("Mail")._clickCb()
			runDeferred()
			assert.is_not_nil(appItem("Mail")._icon)
			assert.are.equal("₅", appItem("Mail")._title)
		end)

		it("keeps click callback after all badges are snoozed", function()
			AppBadgeWatcher:updateMenu(true)
			appItem("Mail")._clickCb()
			runDeferred()
			assert.is_function(appItem("Mail")._clickCb)
		end)

		it("second click after snooze is a no-op resnooze", function()
			AppBadgeWatcher:updateMenu(true)
			appItem("Mail")._clickCb()
			runDeferred()
			appItem("Mail")._clickCb()
			runDeferred()
			assert.is_not_nil(appItem("Mail")._icon)
			assert.is_function(appItem("Mail")._clickCb)
		end)

		it("defers the snooze refresh so an item is never deleted inside its own click callback", function()
			AppBadgeWatcher:updateMenu(true)
			local item = appItem("Mail")
			AppBadgeWatcher.getDockBadges = function() return {} end
			item._clickCb()
			assert.is_nil(item._deleted)
			runDeferred()
			assert.is_true(item._deleted)
		end)

		it("snoozedBadges is a copy of lastBadges, not an alias", function()
			AppBadgeWatcher:updateMenu(true)
			appItem("Mail")._clickCb()
			runDeferred()
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

		it("has default infiniteThreshold of 9", function() assert.are.equal(9, AppBadgeWatcher.infiniteThreshold) end)

		it("shows a superscript plus for counts over infiniteThreshold", function()
			AppBadgeWatcher:updateMenu(true)
			assert.are.equal("⁺", appItem("Messages")._title)
		end)

		it("shows the number when count is within a raised infiniteThreshold", function()
			AppBadgeWatcher.infiniteThreshold = 20
			AppBadgeWatcher:updateMenu(true)
			assert.are.equal("¹²", appItem("Messages")._title)
		end)

		it("falls back to nothingIndicator when no icons resolve", function()
			AppBadgeWatcher.getIconForApp = function(_appName, _iconDim) return nil end
			AppBadgeWatcher:updateMenu(true)
			assert.are.equal(nothingIndicator, AppBadgeWatcher.menu._title)
			assert.is_nil(next(AppBadgeWatcher.appItems))
		end)
	end)

	describe("per-app menubar items", function()
		before_each(function()
			AppBadgeWatcher.appsToWatch = { "Mail", "Slack", "Messages" }
			AppBadgeWatcher:start()
		end)

		after_each(function() AppBadgeWatcher:stop() end)

		it("creates one live item per badged app with a stable autosave name and icon", function()
			AppBadgeWatcher:updateMenu(true)
			for _, name in ipairs({ "Mail", "Slack", "Messages" }) do
				assert.is_nil(appItem(name)._deleted)
				assert.is_not_nil(appItem(name)._icon)
				assert.is_function(appItem(name)._clickCb)
			end
		end)

		it("shows superscript counts, and a plus over the threshold", function()
			AppBadgeWatcher:updateMenu(true)
			assert.are.equal("⁵", appItem("Mail")._title)
			assert.are.equal("³", appItem("Slack")._title)
			assert.are.equal("⁺", appItem("Messages")._title)
		end)

		it("shows the new count as superscript and the snoozed count as subscript", function()
			AppBadgeWatcher:updateMenu(true)
			AppBadgeWatcher.snoozedBadges["Mail"] = 2
			AppBadgeWatcher:updateMenu(true)
			assert.are.equal("³₂", appItem("Mail")._title)
		end)

		it("uses a subscript plus for a snoozed count over the threshold", function()
			AppBadgeWatcher:updateMenu(true)
			AppBadgeWatcher.snoozedBadges["Messages"] = 11
			AppBadgeWatcher:updateMenu(true)
			assert.are.equal("¹₊", appItem("Messages")._title)
		end)

		it("removes the nothing indicator while badge items are shown", function()
			local indicator = AppBadgeWatcher.menu
			AppBadgeWatcher:updateMenu(true)
			assert.is_nil(AppBadgeWatcher.menu)
			if indicator then assert.is_true(indicator._deleted) end
		end)

		it("deletes app items and recreates the indicator when badges clear", function()
			AppBadgeWatcher:updateMenu(true)
			local mail = appItem("Mail")
			AppBadgeWatcher.getDockBadges = function(_self) return {} end
			AppBadgeWatcher:updateMenu(true)
			assert.is_true(mail._deleted)
			assert.are.equal("AppBadgeWatcher", AppBadgeWatcher.menu._autosaveName)
			assert.are.equal(nothingIndicator, AppBadgeWatcher.menu._title)
		end)

		it("deletes only the item whose badge went away", function()
			AppBadgeWatcher:updateMenu(true)
			local slack = appItem("Slack")
			AppBadgeWatcher.getDockBadges = function(_self) return { Mail = 5 } end
			AppBadgeWatcher:updateMenu(true)
			assert.is_true(slack._deleted)
			assert.is_nil(appItem("Mail")._deleted)
		end)

		it("recreates a cleared app item under the same autosave name", function()
			AppBadgeWatcher:updateMenu(true)
			local first = appItem("Mail")
			AppBadgeWatcher.getDockBadges = function(_self) return {} end
			AppBadgeWatcher:updateMenu(true)
			AppBadgeWatcher.getDockBadges = function(_self) return { Mail = 5 } end
			AppBadgeWatcher:updateMenu(true)
			local second = appItem("Mail")
			assert.are_not.equal(first, second)
			assert.are.equal("AppBadgeWatcher.Mail", second._autosaveName)
			assert.is_nil(second._deleted)
		end)

		it("reuses a shown item across updates", function()
			AppBadgeWatcher:updateMenu(true)
			local count = #created_items
			AppBadgeWatcher:updateMenu(true)
			assert.are.equal(count, #created_items)
		end)

		it("deletes app items on stop", function()
			AppBadgeWatcher:updateMenu(true)
			AppBadgeWatcher:stop()
			assert.is_true(appItem("Mail")._deleted)
		end)
	end)

	describe("when the menubar is full", function()
		it("retries creating an item that failed, without waiting for a badge change", function()
			local full = true
			local newItem = mock_hs.menubar.new
			mock_hs.menubar.new = function(inMenuBar, name)
				if full and name == "AppBadgeWatcher.Mail" then return nil end
				return newItem(inMenuBar, name)
			end
			AppBadgeWatcher.appsToWatch = { "Mail", "Slack" }
			AppBadgeWatcher:start()
			assert.is_nil(appItem("Mail"))
			assert.is_not_nil(appItem("Slack"))

			full = false
			AppBadgeWatcher:updateMenu()
			assert.is_not_nil(appItem("Mail"))
			AppBadgeWatcher:stop()
		end)
	end)

	describe("configure", function()
		it("sets provided fields and leaves others untouched", function()
			local result = AppBadgeWatcher:configure({ refreshInterval = 30, infiniteThreshold = 99 })
			assert.are.equal(30, AppBadgeWatcher.refreshInterval)
			assert.are.equal(99, AppBadgeWatcher.infiniteThreshold)
			assert.are.equal(nothingIndicator, AppBadgeWatcher.nothingIndicator)
			assert.are.equal(AppBadgeWatcher, result)
		end)

		it("drops items of apps removed from appsToWatch on the next update", function()
			AppBadgeWatcher.appsToWatch = { "Mail", "Slack" }
			AppBadgeWatcher:start()
			local slack = appItem("Slack")
			AppBadgeWatcher:configure({ appsToWatch = { "Mail" } })
			AppBadgeWatcher:updateMenu()
			assert.is_true(slack._deleted)
			assert.is_nil(AppBadgeWatcher.appItems["Slack"])
			AppBadgeWatcher:stop()
		end)

		it("applies display settings on the next update even when badges are unchanged", function()
			AppBadgeWatcher.appsToWatch = { "Messages" }
			AppBadgeWatcher:start()
			assert.are.equal("⁺", appItem("Messages")._title)
			AppBadgeWatcher:configure({ infiniteThreshold = 20 })
			AppBadgeWatcher:updateMenu()
			assert.are.equal("¹²", appItem("Messages")._title)
			AppBadgeWatcher:stop()
		end)

		it("chains with start", function()
			local result = AppBadgeWatcher:configure({ appsToWatch = { "Mail" } }):start()
			assert.are.equal(AppBadgeWatcher, result)
			assert.same({ "Mail" }, AppBadgeWatcher.appsToWatch)
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
