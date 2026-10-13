-- Native macOS Spaces + Hammerspoon tiling. Mouse/clipboard bindings stay in init.lua.
local M = { hotkeys = {}, tasks = {}, actions = {}, enabled = true }
-- Reserve standard Cmd editing/navigation chords for macOS and applications.
local mod, shift = {"ctrl", "alt"}, {"ctrl", "alt", "shift"}
local launchMod, launchShift = {"cmd"}, {"cmd", "shift"}
local root = hs.configdir .. "/omarchy-assets"
local previousWindow
M.desktops = require("desktops")
M.tiler = require("tiler")

function M.reflow()
    M.tiler.reflow()
end
M.desktops.afterChange = function() M.tiler.schedule(0.15) end

local function task(bin, args)
    local t
    t = hs.task.new(bin, function(code, stdout, stderr)
        M.tasks[t] = nil
        if code ~= 0 then hs.alert.show("Command failed: " .. (stderr or stdout or "")) end
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

local function add(label, hint, fn, modifiers, key)
    local action = { text = label, subText = hint, run = fn }
    table.insert(M.actions, action)
    if modifiers and key then
        local hotkey = hs.hotkey.bind(modifiers, key, fn)
        table.insert(M.hotkeys, hotkey)
    end
end

function M.setTheme(dark)
    local ok = hs.osascript.applescript('tell application "System Events" to tell appearance preferences to set dark mode to ' .. tostring(dark))
    if not ok then hs.alert.show("macOS could not change the appearance; open System Settings → Appearance."); return end
    for _, screen in ipairs(hs.screen.allScreens()) do
        screen:desktopImageURL("file://" .. root .. (dark and "/mocha.png" or "/latte.png"))
    end
    hs.alert.show(dark and "Catppuccin Mocha" or "Catppuccin Latte")
end

for _, dir in ipairs({"left", "right", "up", "down"}) do
    add("Focus: " .. dir, "Ctrl + Option + " .. dir, function()
        local w = hs.window.focusedWindow()
        if w then
            local method = {left="focusWindowWest",right="focusWindowEast",up="focusWindowNorth",down="focusWindowSouth"}
            w[method[dir]](w, nil, false, true)
        end
    end, mod, dir)
end

add("Ghostty — terminal", "Cmd + Return · F12: quick terminal", app("Ghostty"), launchMod, "return")
add("Finder — files", "Cmd + E", app("Finder"), launchMod, "e")
add("Browser — Google Chrome", "Cmd + Shift + Return", app("Google Chrome"), launchShift, "return")
add("Zed — editor", "Existing editor", app("Zed"))
add("VS Code — editor", "Existing editor", app("Visual Studio Code"))
add("Reminders", "Native macOS", app("Reminders"))
add("Calendar", "Native macOS", app("Calendar"))
add("System Settings — Focus and system", "Native macOS settings", app("System Settings"))
add("Mission Control — Spaces overview", "Cmd + middle click", function() hs.spaces.toggleMissionControl() end)
add("Clipboard history", "Cmd + Ctrl + V · existing history", function() hs.eventtap.keyStroke({"cmd", "ctrl"}, "v", 0) end)
add("Screenshot — select area", "Native Screenshot app", app("Screenshot"))
add("Screenshot and screen recording", "Native Screenshot app", app("Screenshot"))
add("Lock screen", "Native macOS", function() hs.caffeinate.lockScreen() end)
add("Theme — Catppuccin Mocha", "Dark system, terminal, editors and wallpaper", function() M.setTheme(true) end)
add("Theme — Catppuccin Latte", "Light system, terminal, editors and wallpaper", function() M.setTheme(false) end)

local commands = {
    {"Layout — next", "l", mod}, {"Layout — previous", "l", shift},
    {"Layout — Tall", "a", mod},
    {"Layout — Wide", "w", mod}, {"Layout — single window", "f", mod},
    {"Layout — Floating / manual arrangement", "f", shift},
    {"Window — toggle floating", "t", mod}, {"Tiling — enable / disable", "t", shift},
    {"Layout — show current", "i", mod}, {"Layout — reflow", "r", mod},
    {"Window — swap with previous", "left", shift},
    {"Window — swap with next", "right", shift},
    {"Window — previous monitor", "up", shift},
    {"Window — next monitor", "down", shift},
    {"Window — swap with main", "m", mod},
    {"Tall/Wide — shrink main pane", "-", mod},
    {"Tall/Wide — expand main pane", "=", mod},
}
for _, c in ipairs(commands) do
    add(c[1], "Ctrl + Option + " .. (c[3] == shift and "Shift + " or "") .. c[2], keys(c[3], c[2]),c[3],c[2])
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
end, mod, "x")
add("Tiling — manage excluded apps", "Add or remove apps that stay floating", function() M.manageExcludes() end)
for i = 1, 9 do
    add("Desktop — " .. i .. " on the current display", "Cmd + " .. i,
        function() M.desktops.goToNumber(i) end, launchMod, tostring(i))
    add("Window — move to Desktop " .. i .. " on this display", "Cmd + Shift + " .. i .. " · create if missing, then follow the window",
        function() M.desktops.moveWindow(i) end, launchShift, tostring(i))
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
end):start()
M.screenWatcher = hs.screen.watcher.new(function() M.tiler.schedule() end):start()

-- Native Shortcuts run after automatic tiling is put into Floating layout.
for n = 2, 4 do
    add("Manual arrangement — last " .. n .. " windows", "Floating layout, then the existing native Shortcut", function()
        keys(shift, "f")()
        hs.timer.doAfter(0.3, function() task("/usr/bin/shortcuts", {"run", "Tile Last " .. n .. " Windows"}) end)
    end)
end
add("Tiling — automatic arrangement", "Hammerspoon · Tall", function() M.tiler.enabled=true;M.tiler.setLayout("tall") end)
add("Reload Hammerspoon", "Load configuration changes", function() hs.reload() end)

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
        table.insert(choices, {text=action.text, subText=action.subText, actionIndex=i})
    end
    M.chooser:choices(choices):query(query or ""):show()
end
table.insert(M.hotkeys, hs.hotkey.bind(mod, "space", function() M.show() end))
table.insert(M.hotkeys, hs.hotkey.bind(mod, "k", function() M.show() end))

M.bar = hs.menubar.new()
M.bar:setTooltip("macOS Omarchy — commands and native Spaces")
M.bar:setMenu(function()
    return {
        {title="Commands — Ctrl + Option + Space", fn=function() M.show() end},
        {title="Current layout — Ctrl + Option + I", fn=keys(mod,"i")},
        {title="Next layout — Ctrl + Option + L", fn=keys(mod,"l")},
        {title="Floating window — Ctrl + Option + T", fn=keys(mod,"t")},
        {title="Exclude focused app — Ctrl + Option + X", fn=function() M.tiler.toggleFocused() end},
        {title="Excluded apps…", fn=function() M.manageExcludes() end},
        {title="Enable / disable tiling", fn=keys(shift,"t")},
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
M.timer = hs.timer.doEvery(2, M.updateStatus)
M.updateStatus()
return M
