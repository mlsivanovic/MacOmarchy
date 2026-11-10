-- The settings window injects the boot payload and round-trips bridge messages.
package.path = "config/?.lua;" .. package.path

local function check(condition, message)
    if not condition then error(message or "assertion failed", 2) end
end

local root = "/tmp/mac-omarchy-window-test-" .. tostring(os.time())
os.execute('rm -rf "' .. root .. '" && mkdir -p "' .. root .. '"')
local S = dofile("config/settings.lua")
check(S.configure({userPath = root .. "/settings.json"}), "settings configure")
package.loaded.settings = S

local function chain()
    return setmetatable({}, {__index = function(self) return function() return self end end})
end

local messageCallback, webview, htmlText, evaluated = nil, nil, nil, {}
local watcherStarted = false
local alerts = {}

local view = {
    windowTitle = function(self) return self end,
    windowStyle = function(self) return self end,
    titleVisibility = function(self) return self end,
    deleteOnClose = function(self) return self end,
    windowCallback = function(self, fn) self.callback = fn; return self end,
    html = function(self, text) htmlText = text; return self end,
    show = function(self) return self end,
    bringToFront = function(self) return self end,
    delete = function(self) return self end,
    evaluateJavaScript = function(self, script) evaluated[#evaluated + 1] = script; return self end,
}

hs = {
    configdir = "config",
    window = {filter = {new = chain}},
    hotkey = {bind = function() return {} end},
    chooser = {new = chain},
    menubar = {new = chain},
    timer = {doEvery = function() return {stop = function() end} end,
        doAfter = function() return {stop = function() end} end},
    screen = {mainScreen = function()
            return {frame = function() return {x = 0, y = 0, w = 1200, h = 800} end}
        end,
        watcher = {new = function(fn) return {start = function() return true end, fn = fn} end}},
    spaces = {
        watcher = {new = function(fn) return {start = function() return true end, fn = fn} end},
        activeSpaceOnScreen = function() return 1 end,
    },
    mouse = {getCurrentScreen = function() return nil end},
    alert = {show = function(message) alerts[#alerts + 1] = message end},
    application = {launchOrFocus = function() end},
    osascript = {applescript = function() return true end},
    fs = {mkdir = function() return true end},
    pathwatcher = {new = function(dir, fn)
        return {start = function() watcherStarted = true end, stop = function() end, fn = fn, dir = dir}
    end},
    webview = {
        usercontent = {new = function(name)
            return {setCallback = function(self, fn) messageCallback = fn; return self end}
        end},
        newBrowser = function(rect, preferences, usercontent)
            webview = view
            return webview
        end,
    },
}
for _, name in ipairs({"windowCreated", "windowVisible", "windowNotVisible", "windowMinimized",
    "windowUnminimized", "windowDestroyed", "windowMoved"}) do
    hs.window.filter[name] = name
end
package.loaded.desktops = {
    settle = function() end,
    userSpaces = function() return {1} end,
}
local includedApp
package.loaded.tiler = {
    commands = {}, schedule = function() end, forget = function() end,
    windowMoved = function() end, reflow = function() end,
    applySettings = function() end,
    excludedApps = function()
        return {
            {bundleID = "com.example.App", name = "Example", builtin = false},
            {bundleID = "org.keepassxc.keepassxc", name = "KeePassXC", builtin = true},
        }
    end,
    includeApp = function(bundleID) includedApp = bundleID; return "tiled" end,
}
package.loaded.focus = {
    isEnabled = function() return false end, toggle = function() return true, true end,
    setEnabled = function() end, loadEnabled = function() return false end,
    configure = function() end,
}

local M = dofile("config/omarchy.lua")

check(M.watchSettings() == true and watcherStarted, "settings watcher starts")
M.showSettings()
check(type(htmlText) == "string", "the window receives HTML")
check(htmlText:find("window.MACOMARCHY_BOOT =", 1, true) ~= nil, "the boot payload is injected")
check(htmlText:find("__BOOT_JSON__", 1, true) == nil, "the placeholder is replaced")
check(htmlText:find('"tiler"', 1, true) ~= nil, "the payload contains sections")
check(htmlText:find("info-button", 1, true) ~= nil, "descriptions use hover information buttons")
check(htmlText:find('class="desc"', 1, true) == nil, "descriptions are not rendered inline")
check(htmlText:find('"excludedApps"', 1, true) ~= nil, "the payload contains tiling exclusions")
check(type(messageCallback) == "function", "the bridge callback is registered")

messageCallback({body = {type = "set", path = "tiler.gap", value = 6}})
check(S.get("tiler.gap") == 6, "a bridge set writes the value")
check(evaluated[#evaluated]:find('"action":"set"', 1, true) ~= nil, "the result carries the action")
check(evaluated[#evaluated]:find('"gap":6', 1, true) ~= nil, "the result carries new values")

messageCallback({body = {type = "set", path = "tiler.gap", value = 999}})
check(S.get("tiler.gap") == 6, "an invalid bridge set is refused")
check(evaluated[#evaluated]:find('"ok":false', 1, true) ~= nil, "the result reports the rejection")

messageCallback({body = {type = "unset", path = "tiler.gap"}})
check(S.get("tiler.gap") == 4, "a bridge unset restores the default")
check(evaluated[#evaluated]:find('"action":"unset"', 1, true) ~= nil, "unset is reported to the UI")

local nextEntry
for _, entry in ipairs(M.shortcutEntries) do
    if entry.id == "layout_next" then nextEntry = entry end
end
messageCallback({body = {type = "set", path = "shortcuts.layout_next", value = "ctrl+alt+j"}})
check(nextEntry.combo == "ctrl+alt+j", "a shortcut set rebinds the live entry")
check(evaluated[#evaluated]:find('"ok":true', 1, true) ~= nil, "a shortcut set is reported to the UI")

messageCallback({body = {type = "capture", active = true}})
check(M.shortcutsSuspended == true, "recording suspends shortcuts")
messageCallback({body = {type = "capture", active = false}})
check(M.shortcutsSuspended == false, "finishing recording resumes shortcuts")

messageCallback({body = {type = "includeApp", bundleID = "com.example.App"}})
check(includedApp == "com.example.App", "a bridge include tiles the app again")
check(evaluated[#evaluated]:find('"action":"includeApp"', 1, true) ~= nil,
    "the include result is reported to the UI")
check(evaluated[#evaluated]:find('"excludedApps"', 1, true) ~= nil,
    "the include result refreshes the exclusion list")
messageCallback({body = {type = "refreshExclusions"}})
check(evaluated[#evaluated]:find('"action":"exclusions"', 1, true) ~= nil,
    "the exclusion list can be refreshed")
messageCallback({body = {type = "close"}})

os.execute('rm -rf "' .. root .. '"')
print("PASS: settings window boot payload and bridge")
