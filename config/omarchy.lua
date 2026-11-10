-- Native macOS Spaces + Hammerspoon tiling. Mouse gestures stay in init.lua.
local M = { hotkeys = {}, tasks = {}, actions = {}, shortcutEntries = {}, enabled = true }
local S = require("settings")
-- Reserve standard Cmd editing/navigation chords for macOS and applications.
local mod, shift = {"ctrl", "alt"}, {"ctrl", "alt", "shift"}
local launchMod, launchShift = {"cmd"}, {"cmd", "shift"}
local root = hs.configdir .. "/omarchy-assets"
local previousWindow
M.desktops = require("desktops")
M.tiler = require("tiler")
local focus = require("focus")

function M.reflow()
    M.tiler.reflow()
end
M.desktops.afterChange = function() M.tiler.schedule(0.15) end

local function task(bin, args)
    local t
    t = hs.task.new(bin, function(code, stdout, stderr)
        M.tasks[t] = nil
        if code ~= 0 then S.alert("Command failed: " .. (stderr or stdout or "")) end
    end, args or {})
    if t then M.tasks[t] = true; t:start() end
end

local function app(name) return function() hs.application.launchOrFocus(name) end end
local function keys(modifiers, key)
    return function()
        local command = (modifiers==shift and "shift:" or "") .. key
        if M.tiler.commands[command] then M.tiler.commands[command]() end
    end
end

local function bindShortcut(entry)
    if entry.hotkey then
        pcall(function() entry.hotkey:delete() end)
        entry.hotkey = nil
    end
    local combo = S.get("shortcuts." .. entry.id, entry.default)
    entry.combo = combo or entry.default
    if S.isShortcutDisabled(entry.combo) then return end
    local modifiers, key = S.parseShortcut(entry.combo)
    if not modifiers or not key then return end
    local ok, hotkey = pcall(hs.hotkey.bind, modifiers, key, entry.fn)
    if ok and hotkey then
        entry.hotkey = hotkey
        table.insert(M.hotkeys, hotkey)
    end
end

local function registerShortcut(id, label, hint, fn, modifiers, key)
    local default = S.formatShortcut(modifiers, key)
    local entry = {
        id = id, label = label, hint = hint, default = default, fn = fn,
        hintSuffix = type(hint) == "string" and hint:match("·%s*(.*)$") or nil,
    }
    M.shortcutEntries[#M.shortcutEntries + 1] = entry
    bindShortcut(entry)
    return entry
end

function M.shortcutHint(entry)
    if not entry then return nil end
    local label = S.shortcutLabel(entry.combo or entry.default)
    if entry.hintSuffix then return label .. " · " .. entry.hintSuffix end
    return label
end

local function unbindShortcuts()
    for _, entry in ipairs(M.shortcutEntries) do
        if entry.hotkey then
            pcall(function() entry.hotkey:delete() end)
            entry.hotkey = nil
        end
    end
    M.hotkeys = {}
end

function M.rebindShortcuts()
    M.shortcutsSuspended = false
    unbindShortcuts()
    for _, entry in ipairs(M.shortcutEntries) do bindShortcut(entry) end
    return #M.hotkeys
end

-- While the settings window records a combination, its own hotkeys must be out
-- of the way or the event never reaches the webview.
function M.setShortcutCapture(active)
    active = active == true
    if M.captureTimer then
        pcall(function() M.captureTimer:stop() end)
        M.captureTimer = nil
    end
    if active then
        if M.shortcutsSuspended then
            M.captureTimer = hs.timer.doAfter(30, function()
                M.captureTimer = nil
                M.setShortcutCapture(false)
            end)
            return
        end
        M.shortcutsSuspended = true
        unbindShortcuts()
        local clipboard = package.loaded.clipboard
        if clipboard and clipboard.suspendHotkey then pcall(clipboard.suspendHotkey) end
        M.captureTimer = hs.timer.doAfter(30, function()
            M.captureTimer = nil
            M.setShortcutCapture(false)
        end)
        return
    end
    if not M.shortcutsSuspended then return end
    M.rebindShortcuts()
    local clipboard = package.loaded.clipboard
    if clipboard and clipboard.resumeHotkey then pcall(clipboard.resumeHotkey) end
end

local function add(label, hint, fn, modifiers, key, id)
    local action = { text = label, subText = hint, run = fn }
    table.insert(M.actions, action)
    if modifiers and key then
        if id then
            local entry = registerShortcut(id, label, hint, fn, modifiers, key)
            action.shortcut = entry
        else
            local hotkey = hs.hotkey.bind(modifiers, key, fn)
            table.insert(M.hotkeys, hotkey)
        end
    end
    return action
end

-- Off by default. Turning it on or off keeps the choice for the next reload.
function M.toggleFocusFollow()
    local enabled, saved = focus.toggle()
    local settingsSaved = S.set("focus.enabled", enabled)
    local message = enabled and "Focus follows the pointer enabled"
        or "Focus follows the pointer disabled"
    S.alert(saved and settingsSaved and message or (message .. " · not saved"))
    return enabled
end

function M.setTheme(dark)
    local ok = hs.osascript.applescript('tell application "System Events" to tell appearance preferences to set dark mode to ' .. tostring(dark))
    if not ok then S.alert("macOS could not change the appearance; open System Settings → Appearance."); return end
    for _, screen in ipairs(hs.screen.allScreens()) do
        screen:desktopImageURL("file://" .. root .. (dark and "/mocha.png" or "/latte.png"))
    end
    S.alert(dark and "Catppuccin Mocha" or "Catppuccin Latte")
end

local focusDirection = {
    left = "focusWindowWest", right = "focusWindowEast",
    up = "focusWindowNorth", down = "focusWindowSouth",
}
-- Hammerspoon searches every visible window when candidates are omitted, which
-- crosses displays. Pass only windows on the focused window's display.
local function focusNeighbour(direction)
    local current = hs.window.focusedWindow()
    local screen = current and current:screen()
    if not screen then return end
    local candidates = {}
    local ok, windows = pcall(function() return M.windowFilter:getWindows() end)
    if ok and type(windows) == "table" then
        for _, window in ipairs(windows) do
            if window:id() ~= current:id() and window:isVisible()
                and window:screen() and window:screen():id() == screen:id() then
                candidates[#candidates + 1] = window
            end
        end
    end
    current[focusDirection[direction]](current, candidates, true, true)
end

for _, dir in ipairs({"left", "right", "up", "down"}) do
    add("Focus: " .. dir, "Ctrl + Option + " .. dir, function() focusNeighbour(dir) end,
        mod, dir, "focus_" .. dir)
end
M.focusNeighbour = focusNeighbour

local focusAction = add("Focus — follow the pointer", "Ctrl + Option + P · off by default",
    function() M.toggleFocusFollow() end, mod, "p", "focus_toggle")

add("Ghostty — terminal", "Cmd + Return · F12: quick terminal", app("Ghostty"), launchMod, "return", "launch_ghostty")
add("Finder — files", "Cmd + E", app("Finder"), launchMod, "e", "launch_finder")
add("Browser — Google Chrome", "Cmd + Shift + Return", app("Google Chrome"), launchShift, "return", "launch_browser")
add("Zed — editor", "Existing editor", app("Zed"))
add("VS Code — editor", "Existing editor", app("Visual Studio Code"))
add("Reminders", "Native macOS", app("Reminders"))
add("Calendar", "Native macOS", app("Calendar"))
add("System Settings — Focus and system", "Native macOS settings", app("System Settings"))
add("Mission Control — Spaces overview", "Cmd + middle click", function() hs.spaces.toggleMissionControl() end)
local clipboardAction = add("Clipboard history", "Ctrl + V · text and images", function()
    local clipboard = package.loaded.clipboard
    if clipboard and clipboard.openChooser then
        clipboard.openChooser()
    else
        hs.eventtap.keyStroke({"ctrl"}, "v", 0)
    end
end)
clipboardAction.shortcutId = "clipboard_history"
clipboardAction.shortcutSuffix = "text and images"
add("Screenshot — select area", "Native Screenshot app", app("Screenshot"))
add("Screenshot and screen recording", "Native Screenshot app", app("Screenshot"))
add("Lock screen", "Native macOS", function() hs.caffeinate.lockScreen() end)
add("Theme — Catppuccin Mocha", "Dark system, terminal, editors and wallpaper", function() M.setTheme(true) end)
add("Theme — Catppuccin Latte", "Light system, terminal, editors and wallpaper", function() M.setTheme(false) end)

local commands = {
    {"Layout — next", "l", mod, "layout_next"},
    {"Layout — previous", "l", shift, "layout_previous"},
    {"Layout — Tall", "a", mod, "layout_tall"},
    {"Layout — Wide", "w", mod, "layout_wide"},
    {"Layout — single window", "f", mod, "layout_single"},
    {"Layout — Floating / manual arrangement", "f", shift, "layout_floating"},
    {"Window — toggle floating", "t", mod, "window_toggle_floating"},
    {"Tiling — enable / disable", "t", shift, "tiling_toggle"},
    {"Layout — show current", "i", mod, "layout_show"},
    {"Layout — reflow", "r", mod, "layout_reflow"},
    {"Window — swap with previous", "left", shift, "window_swap_previous"},
    {"Window — swap with next", "right", shift, "window_swap_next"},
    {"Window — previous monitor", "up", shift, "window_previous_monitor"},
    {"Window — next monitor", "down", shift, "window_next_monitor"},
    {"Window — swap with main", "m", mod, "window_swap_main"},
    {"Tall/Wide — shrink main pane", "-", mod, "tiler_shrink_main"},
    {"Tall/Wide — expand main pane", "=", mod, "tiler_expand_main"},
}
for _, c in ipairs(commands) do
    add(c[1], "Ctrl + Option + " .. (c[3] == shift and "Shift + " or "") .. c[2],
        keys(c[3], c[2]), c[3], c[2], c[4])
end

local function frontApp()
    local w = hs.window.focusedWindow and hs.window.focusedWindow() or nil
    if not w then w = previousWindow end
    if not w or not w.application then return end
    local ok, app = pcall(function() return w:application() end)
    if not ok or not app or not app.bundleID then return end
    local id = app:bundleID()
    if not id or id == "" then return end
    return id, (app.name and app:name()) or id
end

-- Searchable list: the focused app, remembered excludes, then other running apps.
function M.manageExcludes(query)
    if not M.excludeChooser then
        M.excludeChooser = hs.chooser.new(function(choice)
            if not choice or not choice.bundleID then return end
            local keep = ""
            pcall(function() keep = M.excludeChooser:query() or "" end)
            M.tiler.toggleApp(choice.bundleID, choice.name)
            hs.timer.doAfter(0.05, function() M.manageExcludes(keep) end)
        end)
        M.excludeChooser:searchSubText(true):rows(14):width(60):placeholderText("Exclude or include an app")
    end
    local choices, seen = {}, {}
    local function row(id, display, name, sub)
        if not id or seen[id] then return end
        seen[id] = true
        choices[#choices+1] = {text=display, subText=sub .. " · " .. id, bundleID=id, name=name}
    end
    local function describe(id)
        if M.tiler.isBuiltin(id) then return "Always excluded" end
        if M.tiler.isExcluded(id) then return "Excluded · select to tile again" end
        return "Select to exclude from tiling"
    end
    local fid, fname = frontApp()
    if fid and fname then row(fid, fname .. " — focused", fname, describe(fid)) end
    for _, item in ipairs(M.tiler.excludedApps()) do
        row(item.bundleID, item.name, item.name, describe(item.bundleID))
    end
    local running = {}
    if hs.application and hs.application.runningApplications then
        local ok, apps = pcall(hs.application.runningApplications)
        if ok and apps then
            for _, app in ipairs(apps) do
                local id, name, kind
                local readOk = pcall(function()
                    id = app:bundleID()
                    name = app:name()
                    kind = app.kind and app:kind() or 1
                end)
                if readOk and id and id ~= "" and name and name ~= "" and not seen[id] and kind ~= 0 then
                    running[#running+1] = {id=id, name=name}
                end
            end
        end
    end
    table.sort(running, function(a, b) return a.name:lower() < b.name:lower() end)
    for _, app in ipairs(running) do
        row(app.id, app.name, app.name, "Select to exclude from tiling")
    end
    M.excludeChooser:choices(choices):query(query or ""):show()
end

add("App — exclude from tiling", "Ctrl + Option + X · this app stays floating", function()
    if M.fromMenu and M.menuApp then
        M.tiler.toggleApp(M.menuApp.bundleID, M.menuApp.name)
    else
        M.tiler.toggleFocused()
    end
end, mod, "x", "app_exclude")
add("Tiling — manage excluded apps", "Add or remove apps that stay floating", function() M.manageExcludes() end)
for i = 1, S.get("desktops.maxNumber") do
    add("Desktop — " .. i .. " on the display under the pointer", "Cmd + " .. i,
        function() M.desktops.goToNumber(i) end, launchMod, tostring(i), "desktop_" .. i)
    add("Window — move to Desktop " .. i .. " on this display", "Cmd + Shift + " .. i .. " · create if missing, then follow the window",
        function() M.desktops.moveWindow(i) end, launchShift, tostring(i), "window_move_" .. i)
end

-- Keep a cached window inventory and react to lifecycle/geometry changes.
M.windowFilter = hs.window.filter.new():setCurrentSpace(true)
M.tiler.cachedWindowSource=function() return M.windowFilter:getWindows() end
M.tiler.windowSource=M.tiler.cachedWindowSource
M.windowFilter:subscribe({hs.window.filter.windowCreated,
    hs.window.filter.windowVisible,hs.window.filter.windowNotVisible,
    hs.window.filter.windowMinimized,hs.window.filter.windowUnminimized},function()
    M.tiler.schedule()
end)
M.windowFilter:subscribe(hs.window.filter.windowDestroyed,function(window)
    M.tiler.forget(window:id())
end)
M.windowFilter:subscribe(hs.window.filter.windowMoved,M.tiler.windowMoved)
M.spaceWatcher = hs.spaces.watcher.new(function()
    M.desktops.settle()
    M.tiler.schedule(0.15)
    if M.updateStatus then M.updateStatus() end
end):start()
M.screenWatcher = hs.screen.watcher.new(function()
    M.tiler.schedule()
    if M.updateStatus then M.updateStatus() end
end):start()

-- Native Shortcuts run after automatic tiling is put into Floating layout.
for n = 2, 4 do
    add("Manual arrangement — last " .. n .. " windows", "Floating layout, then the existing native Shortcut", function()
        keys(shift, "f")()
        hs.timer.doAfter(0.3, function() task("/usr/bin/shortcuts", {"run", "Tile Last " .. n .. " Windows"}) end)
    end)
end
add("Tiling — automatic arrangement", "Hammerspoon · Tall", function() M.tiler.enabled=true;S.set("tiler.enabled",true);M.tiler.setLayout("tall") end)
add("Settings — MacOmarchy", "Ctrl + Option + , · all settings", function() M.showSettings() end, mod, ",", "settings_open")
add("Reload Hammerspoon", "Load configuration changes", function() hs.reload() end)

-- ---------------------------------------------------------------------------
-- Settings: one file, one schema and, when available, one window.
-- ---------------------------------------------------------------------------
local settingsWindowPayload

function M.pushSettings(payload, action)
    if not M.settingsWindow then return end
    if action then payload.action = action end
    local ok, encoded = pcall(S.encode, payload)
    if not ok then return end
    encoded = encoded:gsub("</", "<\\/")
    pcall(function()
        M.settingsWindow:evaluateJavaScript(
            "window.macomarchy && window.macomarchy.onResult(" .. encoded .. ")")
    end)
end

function M.applySettings()
    local ok, errors = S.reload()
    if not ok then return false, errors end
    local shortcutsChanged = false
    local currentShortcuts = S.values.shortcuts or {}
    for _, entry in ipairs(M.shortcutEntries) do
        if entry.combo ~= currentShortcuts[entry.id] then
            shortcutsChanged = true
            break
        end
    end

    local focusEnabled = S.get("focus.enabled", false) == true
    if focus.isEnabled() ~= focusEnabled then focus.setEnabled(focusEnabled, true) end
    if shortcutsChanged and not M.shortcutsSuspended then M.rebindShortcuts() end
    if M.tiler and M.tiler.applySettings then M.tiler.applySettings() end
    if M.desktops and M.desktops.applySettings then M.desktops.applySettings() end
    local clipboard = package.loaded.clipboard
    if clipboard and clipboard.applySettings then pcall(clipboard.applySettings) end
    M.updateStatus()
    return true
end

-- Watch the settings directory so CLI and hand edits apply without a reload.
function M.watchSettings()
    if not S.userPath or not hs.pathwatcher then return false end
    local dir = S.userPath:match("^(.*)/")
    if not dir or dir == "" then return false end
    if hs.fs and hs.fs.mkdir then pcall(hs.fs.mkdir, dir) end
    if M.settingsWatcher then pcall(function() M.settingsWatcher:stop() end) end
    local watcher = hs.pathwatcher.new(dir, function(paths)
        local relevant = false
        for _, changed in ipairs(paths or {}) do
            if changed == S.userPath then relevant = true end
        end
        if not relevant then return end
        if M.settingsDebounce then M.settingsDebounce:stop() end
        M.settingsDebounce = hs.timer.doAfter(0.2, function()
            M.settingsDebounce = nil
            M.applySettings()
            if M.settingsWindow and settingsWindowPayload then
                M.pushSettings(settingsWindowPayload(), "reload")
            end
        end)
    end)
    if not watcher then return false end
    watcher:start()
    M.settingsWatcher = watcher
    return true
end

local function excludedAppsForSettings()
    if M.tiler and M.tiler.excludedApps then
        local ok, list = pcall(M.tiler.excludedApps)
        if ok then return list end
    end
    return {}
end

settingsWindowPayload = function()
    return {
        schema = S.schema,
        values = S.values,
        defaults = S.defaults,
        userPath = S.userPath or "",
        errors = S.errors or {},
        excludedApps = excludedAppsForSettings(),
    }
end

function M.showSettings()
    local loaded, loadErrors = S.reload()
    if not loaded and loadErrors and loadErrors[1] then
        S.alert("Settings: " .. tostring(loadErrors[1]))
    end
    if M.settingsWindow then
        local reused = pcall(function()
            M.settingsWindow:show()
            M.settingsWindow:bringToFront()
        end)
        if reused then
            M.pushSettings(settingsWindowPayload(), "reload")
            return
        end
        M.settingsWindow = nil
    end
    if M.shortcutsSuspended then M.setShortcutCapture(false) end
    if not hs.webview or not hs.webview.usercontent then
        S.alert("This Hammerspoon build does not provide hs.webview")
        return
    end
    local path = hs.configdir .. "/settings-ui.html"
    local file = io.open(path, "r")
    if not file then
        S.alert("Settings UI is missing: " .. path)
        return
    end
    local template = file:read("*a")
    file:close()
    local encodedOk, encoded = pcall(S.encode, settingsWindowPayload())
    if not encodedOk then
        S.alert("Settings: could not encode the configuration")
        return
    end
    encoded = encoded:gsub("</", "<\\/")
    local html = template:gsub("__BOOT_JSON__", function() return encoded end)

    local usercontent = hs.webview.usercontent.new("macomarchySettings")
    usercontent:setCallback(function(message)
        local body = type(message) == "table" and message.body or nil
        if type(body) ~= "table" then return end
        local kind, changed, errors = body.type, nil, nil
        if kind == "set" then
            changed, errors = S.set(body.path, body.value)
        elseif kind == "unset" then
            changed, errors = S.unset(body.path)
        elseif kind == "reset" then
            changed, errors = S.reset()
        elseif kind == "reload" then
            changed, errors = M.applySettings()
        elseif kind == "capture" then
            M.setShortcutCapture(body.active == true)
            return
        elseif kind == "close" then
            M.setShortcutCapture(false)
            if M.settingsWindow then
                pcall(function() M.settingsWindow:delete() end)
                M.settingsWindow = nil
            end
            return
        elseif kind == "includeApp" then
            local callOk, result = false, "missing"
            if body.bundleID and M.tiler and M.tiler.includeApp then
                callOk, result = pcall(M.tiler.includeApp, body.bundleID)
            end
            local payload = settingsWindowPayload()
            payload.ok = callOk and result == "tiled"
            payload.errors = payload.ok and {}
                or {"Could not include this app in tiling again"}
            payload.action = kind
            payload.path = body.bundleID or ""
            M.pushSettings(payload)
            return
        elseif kind == "refreshExclusions" then
            local payload = settingsWindowPayload()
            payload.ok = true
            payload.action = "exclusions"
            M.pushSettings(payload)
            return
        else
            return
        end
        if changed and kind ~= "reload" then changed, errors = M.applySettings() end
        local payload = settingsWindowPayload()
        payload.ok = changed == true
        payload.errors = errors or {}
        payload.action = kind
        payload.path = body.path or ""
        M.pushSettings(payload)
    end)

    local frame = hs.screen.mainScreen():frame()
    local width, height = 760, 620
    local rect = {
        x = frame.x + math.floor((frame.w - width) / 2),
        y = frame.y + math.floor((frame.h - height) / 2),
        w = width, h = height,
    }
    local created, webview = pcall(function()
        return hs.webview.newBrowser(rect, {
            developerExtrasEnabled = false,
            javaScriptCanOpenWindowsAutomatically = false,
        }, usercontent)
    end)
    if not created or not webview then
        S.alert("Could not open the settings window")
        return
    end
    M.settingsWindow = webview
    webview:windowTitle("MacOmarchy Settings")
    -- fullSizeContentView keeps the native title bar opaque; without it the
    -- title bar is transparent and shows the desktop behind it.
    webview:windowStyle(32783)
    webview:deleteOnClose(true)
    webview:windowCallback(function(action)
        if action == "closing" then
            M.setShortcutCapture(false)
            M.settingsWindow = nil
        end
    end)
    webview:html(html)
    webview:show()
    webview:bringToFront()
end

M.chooser = hs.chooser.new(function(choice)
    if not choice then M.menuApp = nil; return end
    if previousWindow then pcall(function() previousWindow:focus() end) end
    hs.timer.doAfter(0.15, function()
        -- The menu took focus, so exclude uses the app captured when it opened.
        M.fromMenu = true
        M.actions[choice.actionIndex].run()
        M.fromMenu = false
        M.menuApp = nil
    end)
end)
M.chooser:searchSubText(true):rows(12):width(55):placeholderText("Commands, apps, layouts, themes…")
function M.show(query)
    previousWindow = hs.window.focusedWindow and hs.window.focusedWindow() or nil
    M.menuApp = nil
    if previousWindow and previousWindow.application then
        local ok, app = pcall(function() return previousWindow:application() end)
        if ok and app and app.bundleID and app:bundleID() then
            M.menuApp = {bundleID=app:bundleID(), name=(app.name and app:name()) or app:bundleID()}
        end
    end
    local choices = {}
    for i, action in ipairs(M.actions) do
        local hint = action.subText
        if action == focusAction then
            hint = (M.shortcutHint(action.shortcut) or "Focus")
                .. " · currently " .. (focus.isEnabled() and "enabled" or "disabled")
        elseif action.shortcut then
            hint = M.shortcutHint(action.shortcut)
        elseif action.shortcutId then
            hint = S.shortcutLabel(S.get("shortcuts." .. action.shortcutId))
            if action.shortcutSuffix then hint = hint .. " · " .. action.shortcutSuffix end
        end
        table.insert(choices, {text=action.text, subText=hint, actionIndex=i})
    end
    M.chooser:choices(choices):query(query or ""):show()
end
registerShortcut("menu_commands", "Commands — menu", "Open the command palette",
    function() M.show() end, mod, "space")
registerShortcut("menu_commands_alt", "Commands — menu (alternate)", "Alternate key for the command palette",
    function() M.show() end, mod, "k")

local function shortcutSuffix(id)
    local label = S.shortcutLabel(S.get("shortcuts." .. id))
    return label ~= "None" and (" — " .. label) or ""
end

M.bar = hs.menubar.new()
M.bar:setTooltip("macOS Omarchy — commands and native Spaces")
M.bar:setMenu(function()
    return {
        {title="Commands" .. shortcutSuffix("menu_commands"), fn=function() M.show() end},
        {title="Settings…" .. shortcutSuffix("settings_open"), fn=function() M.showSettings() end},
        {title="-"},
        {title="Current layout" .. shortcutSuffix("layout_show"), fn=keys(mod,"i")},
        {title="Next layout" .. shortcutSuffix("layout_next"), fn=keys(mod,"l")},
        {title="Floating window" .. shortcutSuffix("window_toggle_floating"), fn=keys(mod,"t")},
        {title="Exclude focused app" .. shortcutSuffix("app_exclude"), fn=function() M.tiler.toggleFocused() end},
        {title="Excluded apps…", fn=function() M.manageExcludes() end},
        {title="Enable / disable tiling" .. shortcutSuffix("tiling_toggle"), fn=keys(shift,"t")},
        {title=(focus.isEnabled() and "✓ " or "") .. "Focus follows the pointer" .. shortcutSuffix("focus_toggle"),
            fn=function() M.toggleFocusFollow() end},
        {title="-"},
        {title="Catppuccin Mocha", fn=function() M.setTheme(true) end},
        {title="Catppuccin Latte", fn=function() M.setTheme(false) end},
    }
end)
function M.updateStatus()
    local screen = hs.screen.mainScreen()
    local index = "?"
    if screen then
        local current = hs.spaces.activeSpaceOnScreen(screen)
        local all = M.desktops.userSpaces(screen)
        for i, id in ipairs(all) do if id == current then index = tostring(i); break end end
    end
    M.bar:setTitle("⌘ " .. index)
end
-- Space/screen watchers refresh the title on change; this is only a fallback.
M.timer = hs.timer.doEvery(10, M.updateStatus)
M.updateStatus()
return M
