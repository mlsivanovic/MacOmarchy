-- macOS Spaces + Amethyst. Existing mouse/clipboard bindings stay in init.lua.
local M = { hotkeys = {}, tasks = {}, actions = {}, enabled = true }
local mod, shift = {"ctrl", "alt"}, {"ctrl", "alt", "shift"}
local root = hs.configdir .. "/omarchy-assets"
local previousWindow

local function task(bin, args)
    local t
    t = hs.task.new(bin, function(code, stdout, stderr)
        M.tasks[t] = nil
        if code ~= 0 then hs.alert.show("Komanda nije uspela: " .. (stderr or stdout or "")) end
    end, args or {})
    if t then M.tasks[t] = true; t:start() end
end

local function app(name) return function() hs.application.launchOrFocus(name) end end
local function keys(modifiers, key)
    return function()
        if not hs.application.get("Amethyst") then
            hs.alert.show("Pokreni Amethyst i uključi Accessibility dozvolu.")
            return
        end
        hs.eventtap.keyStroke(modifiers, key, 0)
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
    if not ok then hs.alert.show("macOS nije dozvolio promenu izgleda; otvori System Settings → Appearance."); return end
    for _, screen in ipairs(hs.screen.allScreens()) do
        screen:desktopImageURL("file://" .. root .. (dark and "/mocha.png" or "/latte.png"))
    end
    hs.alert.show(dark and "Catppuccin Mocha" or "Catppuccin Latte")
end

for _, dir in ipairs({"left", "right", "up", "down"}) do
    add("Fokus: " .. dir, "Ctrl + Option + " .. dir, function()
        local w = hs.window.focusedWindow()
        if w then
            local method = {left="focusWindowWest",right="focusWindowEast",up="focusWindowNorth",down="focusWindowSouth"}
            w[method[dir]](w, nil, false, true)
        end
    end, mod, dir)
end

add("Ghostty — terminal", "Ctrl + Option + Return · F12: quick terminal", app("Ghostty"), mod, "return")
add("Browser — Google Chrome", "Ctrl + Option + Shift + Return", app("Google Chrome"), shift, "return")
add("Zed — editor", "Postojeći editor", app("Zed"))
add("VS Code — editor", "Postojeći editor", app("Visual Studio Code"))
add("Reminders — podsetnici", "Native macOS", app("Reminders"))
add("Calendar — kalendar", "Native macOS", app("Calendar"))
add("System Settings — Focus i sistem", "Native macOS podešavanja", app("System Settings"))
add("Mission Control — pregled Spaces", "Cmd + middle click", function() hs.spaces.toggleMissionControl() end)
add("Clipboard istorija", "Cmd + Ctrl + V · postojeća istorija", function() hs.eventtap.keyStroke({"cmd", "ctrl"}, "v", 0) end)
add("Screenshot — izbor oblasti", "Native Cmd + Shift + 4", function() hs.eventtap.keyStroke({"cmd", "shift"}, "4", 0) end)
add("Screenshot i snimanje ekrana", "Native Cmd + Shift + 5", function() hs.eventtap.keyStroke({"cmd", "shift"}, "5", 0) end)
add("Zaključaj ekran", "Native macOS", function() hs.caffeinate.lockScreen() end)
add("Tema — Catppuccin Mocha", "Tamni sistem, terminal, editori i wallpaper", function() M.setTheme(true) end)
add("Tema — Catppuccin Latte", "Svetli sistem, terminal, editori i wallpaper", function() M.setTheme(false) end)

local commands = {
    {"Layout — sledeći", "l", mod}, {"Layout — prethodni", "l", shift},
    {"Layout — BSP", "b", mod}, {"Layout — Tall", "a", mod},
    {"Layout — Wide", "w", mod}, {"Layout — jedan prozor", "f", mod},
    {"Layout — Floating / ručni raspored", "f", shift},
    {"Prozor — floating toggle", "t", mod}, {"Tiling — uključi / isključi", "t", shift},
    {"Layout — prikaži trenutni", "i", mod}, {"Layout — ponovo rasporedi", "r", mod},
    {"Prozor — zameni sa prethodnim", "left", shift},
    {"Prozor — zameni sa sledećim", "right", shift},
    {"Prozor — prethodni monitor", "up", shift},
    {"Prozor — sledeći monitor", "down", shift},
    {"Prozor — zameni sa glavnim", "m", mod},
    {"Tall/Wide — smanji glavni panel", "-", mod},
    {"Tall/Wide — povećaj glavni panel", "=", mod},
}
for _, c in ipairs(commands) do
    add(c[1], "Ctrl + Option + " .. (#c[3] == 3 and "Shift + " or "") .. c[2], keys(c[3], c[2]))
end
for i = 1, 9 do
    add("Prozor — prebaci na Space " .. i, "Ctrl + Option + Shift + " .. i, keys(shift, tostring(i)))
end

-- Native Shortcuts are only run after Amethyst is put into Floating layout.
for n = 2, 4 do
    add("Ručni raspored — poslednja " .. n .. " prozora", "Floating layout, pa postojeći native Shortcut", function()
        keys(shift, "f")()
        hs.timer.doAfter(0.3, function() task("/usr/bin/shortcuts", {"run", "Tile Last " .. n .. " Windows"}) end)
    end)
end
add("Pokreni Amethyst", "Automatski tiling", app("Amethyst"))
add("Ponovo učitaj Hammerspoon", "Učitaj izmene konfiguracije", function() hs.reload() end)

M.chooser = hs.chooser.new(function(choice)
    if not choice then return end
    if previousWindow then pcall(function() previousWindow:focus() end) end
    hs.timer.doAfter(0.15, function() M.actions[choice.actionIndex].run() end)
end)
M.chooser:searchSubText(true):rows(12):width(55):placeholderText("Komande, aplikacije, layouti, teme…")
function M.show(query)
    previousWindow = hs.window.focusedWindow()
    local choices = {}
    for i, action in ipairs(M.actions) do
        table.insert(choices, {text=action.text, subText=action.subText, actionIndex=i})
    end
    M.chooser:choices(choices):query(query or ""):show()
end
table.insert(M.hotkeys, hs.hotkey.bind(mod, "space", function() M.show() end))
table.insert(M.hotkeys, hs.hotkey.bind(mod, "k", function() M.show() end))

M.bar = hs.menubar.new()
M.bar:setTooltip("macOS Omarchy — komande i native Space")
M.bar:setMenu(function()
    return {
        {title="Komande — Ctrl + Option + Space", fn=function() M.show() end},
        {title="Trenutni layout — Ctrl + Option + I", fn=keys(mod,"i")},
        {title="Sledeći layout — Ctrl + Option + L", fn=keys(mod,"l")},
        {title="Floating prozor — Ctrl + Option + T", fn=keys(mod,"t")},
        {title="Tiling uključi / isključi", fn=keys(shift,"t")},
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
        local all = hs.spaces.spacesForScreen(screen) or {}
        for i, id in ipairs(all) do if id == current then index = tostring(i); break end end
    end
    M.bar:setTitle("⌘ " .. index)
end
M.timer = hs.timer.doEvery(2, M.updateStatus)
M.updateStatus()
return M
