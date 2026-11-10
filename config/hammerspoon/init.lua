-- ============================================================================
-- ~/.hammerspoon/init.lua
-- 1. Workspace Switcher: Cmd + Scroll (switch Spaces on the current display)
-- 2. Workspace Overview: Cmd + Middle Click (open Mission Control overview)
-- 3. Window Cycler:      Cmd + Ctrl + Scroll (cycle windows on the display)
-- 4. Clipboard Manager:  Ctrl + V (searchable 100-item text and image history)
-- 5. Focus follows the pointer, after a short hover, on every display
--    (off by default; toggle with Ctrl + Option + P)
-- ============================================================================

local spaces = require("hs.spaces")

-- Load the user settings before any module captures a default. Injecting the
-- module keeps every require("settings") on the same instance even when the
-- Hammerspoon package path differs from the repository checkout.
local settings = dofile(hs.configdir .. "/settings.lua")
package.loaded.settings = settings
local settingsOk, settingsErrors = settings.configure({userPath = settings.defaultUserPath()})
if not settingsOk and hs.alert then
    hs.alert.show("Settings: " .. tostring(settingsErrors and settingsErrors[1] or "invalid settings file"))
end

local desktops = require("desktops")

-- The `hs` command line tool talks to Hammerspoon over this module; without it
-- the CLI (used by install.sh) cannot reach a running instance.
pcall(require, "hs.ipc")

-- ----------------------------------------------------------------------------
-- SECTION 1: SPACES AND MISSION CONTROL FUNCTIONS
-- ----------------------------------------------------------------------------
local spaceScrollStates = {}
local lastSpaceScrollConsumed = false

-- Native Dock shortcuts are resolved by desktops.lua for the hovered monitor.
-- Returns true only when a Space transition is handled. With a single Space,
-- scrolling remains available to the application.
local function cycleSpaceOnCurrentScreen(direction, screen)
    return desktops.cycle(direction, screen or hs.mouse.getCurrentScreen())
end

-- Open / close Workspace Overview (Mission Control)
local function toggleWorkspaceOverview()
    if spaces and spaces.toggleMissionControl then
        spaces.toggleMissionControl()
    else
        hs.application.launchOrFocus("Mission Control")
    end
end


-- ----------------------------------------------------------------------------
-- SECTION 2: MOUSE WATCHERS (Scroll & Middle Click)
-- ----------------------------------------------------------------------------
hs_window_cycler = hs_window_cycler or {}

if hs_window_cycler.scrollWatcher then
    pcall(function() hs_window_cycler.scrollWatcher:stop() end)
end
if hs_window_cycler.flagsWatcher then
    pcall(function() hs_window_cycler.flagsWatcher:stop() end)
end
if hs_window_cycler.middleClickWatcher then
    pcall(function() hs_window_cycler.middleClickWatcher:stop() end)
end
if hs_window_cycler.watchdogTimer then
    pcall(function() hs_window_cycler.watchdogTimer:stop() end)
end

-- Window cycling session
local cycleSession = {
    active = false,
    windows = {},
    index = 1,
    screenId = nil,
    lastTime = 0
}

local function endCycleSession()
    if cycleSession.focusTimer then
        pcall(function() cycleSession.focusTimer:stop() end)
        cycleSession.focusTimer = nil
    end
    cycleSession.active = false
    cycleSession.windows = {}
    cycleSession.index = 1
    cycleSession.screenId = nil
end

-- macOS adds an aggregate Ctrl bit to Cmd+scroll (legacy zoom mapping).
-- Read the physical key (device* bit) instead of aggregate Ctrl.
-- Masks are resolved once; this runs on every scroll event system-wide.
local rawFlagMasks = hs.eventtap.event.rawFlagMasks
local function flagMask(name) return rawFlagMasks[name] or 0 end
local CMD_MASK = flagMask("deviceLeftCommand") | flagMask("deviceRightCommand") | flagMask("command")
local CTRL_MASK = flagMask("deviceLeftControl") | flagMask("deviceRightControl")
local ALT_MASK = flagMask("deviceLeftAlternate") | flagMask("deviceRightAlternate")
local SHIFT_MASK = flagMask("deviceLeftShift") | flagMask("deviceRightShift")
local function deviceMods(raw)
    return {
        cmd = raw & CMD_MASK ~= 0,
        ctrl = raw & CTRL_MASK ~= 0,
        alt = raw & ALT_MASK ~= 0,
        shift = raw & SHIFT_MASK ~= 0,
    }
end

local scrollProps = hs.eventtap.event.properties
local P_LINE_Y, P_LINE_X = scrollProps.scrollWheelEventDeltaAxis1, scrollProps.scrollWheelEventDeltaAxis2
local P_POINT_Y, P_POINT_X = scrollProps.scrollWheelEventPointDeltaAxis1, scrollProps.scrollWheelEventPointDeltaAxis2
local P_FIXED_Y, P_FIXED_X = scrollProps.scrollWheelEventFixedPtDeltaAxis1, scrollProps.scrollWheelEventFixedPtDeltaAxis2
local P_MOMENTUM = scrollProps.scrollWheelEventMomentumPhase

local physMods = { cmd = false, ctrl = false, alt = false, shift = false }

hs_window_cycler.flagsWatcher = hs.eventtap.new({hs.eventtap.event.types.flagsChanged}, function(e)
    physMods = deviceMods(e:rawFlags())
    if not (physMods.cmd and physMods.ctrl) then
        if cycleSession.active then
            endCycleSession()
        end
    end
    return false
end)
hs_window_cycler.flagsWatcher:start()

local function getTargetScreenForWindows(windows)
    local mouseScreen = hs.mouse.getCurrentScreen()
    local focusedWin = hs.window.focusedWindow()
    local focusedScreen = focusedWin and focusedWin:screen()
    -- Single pass counts both candidate displays.
    local mouseId = mouseScreen and mouseScreen:id()
    local focusedId = focusedScreen and focusedScreen:id()
    local mouseCount, focusedCount = 0, 0
    for _, w in ipairs(windows) do
        local ok, s = pcall(function() return w:screen() end)
        local okStd, isStd = pcall(function() return w:isStandard() end)
        local okMin, isMin = pcall(function() return w:isMinimized() end)
        if ok and s and okStd and isStd and okMin and not isMin then
            if s:id() == mouseId then mouseCount = mouseCount + 1 end
            if s:id() == focusedId then focusedCount = focusedCount + 1 end
        end
    end
    if mouseCount > 1 then return mouseScreen end
    if focusedScreen and focusedCount > 1 then return focusedScreen end
    return mouseScreen or focusedScreen
end

-- 1. SCROLL WATCHER (Cmd + Scroll & Cmd + Ctrl + Scroll)
hs_window_cycler.scrollWatcher = hs.eventtap.new({hs.eventtap.event.types.scrollWheel}, function(e)
    -- Fast path: plain scrolling (no Cmd) is not ours. This callback sees
    -- every scroll event system-wide, so leave before any heavier work.
    local rawFlags = e:rawFlags()
    if CMD_MASK ~= 0 and rawFlags & CMD_MASK == 0 then return false end
    local fromEvent = deviceMods(rawFlags)
    -- Cmd scroll events also contain a synthetic Ctrl flag (legacy zoom mapping).
    -- Read Ctrl/Alt/Shift from the current physical keyboard state.
    -- Poll physical keyboard state for each scroll. A cached flagsChanged event
    -- can leave Ctrl stuck after a synthetic shortcut, routing Cmd+scroll to
    -- the window cycler instead of Spaces. Ignore Ctrl added to scroll events.
    local live = deviceMods(hs.eventtap.checkKeyboardModifiers(true)._raw or 0)
    local flags = {
        cmd = live.cmd or fromEvent.cmd,
        ctrl = live.ctrl,
        alt = live.alt,
        shift = live.shift,
    }
    local now = hs.timer.secondsSinceEpoch()

    local function axis(prop) return e:getProperty(prop) or 0 end
    local lineY, lineX = axis(P_LINE_Y), axis(P_LINE_X)
    local pointY, pointX = axis(P_POINT_Y), axis(P_POINT_X)
    if pointY == 0 then pointY = axis(P_FIXED_Y) end
    if pointX == 0 then pointX = axis(P_FIXED_X) end
    local vertical = math.abs(pointY) >= math.abs(pointX)
    if pointY == 0 and pointX == 0 then vertical = math.abs(lineY) >= math.abs(lineX) end
    local line, point = vertical and lineY or lineX, vertical and pointY or pointX
    if line == 0 and point == 0 then return false end

    -- CMD + SCROLL -> one desktop per scroll. The wheel emits a burst, and a
    -- second step is never queued while the first transition is still running.
    if flags.cmd and not (flags.ctrl or flags.alt or flags.shift) then
        -- Gesture state is per display: scrolling on another monitor inside
        -- the lockout window must still switch that monitor.
        local screen = hs.mouse.getCurrentScreen()
        local stateId = screen and screen:id() or 0
        local state = spaceScrollStates[stateId]
        if not state then state = {}; spaceScrollStates[stateId] = state end
        local direction, consume = desktops.scrollGesture(
            state, now, line, point, axis(P_MOMENTUM))
        if not consume then return false end
        if direction and not desktops.isChanging() then
            lastSpaceScrollConsumed = cycleSpaceOnCurrentScreen(direction, screen) == true
        elseif direction then
            lastSpaceScrollConsumed = true
        end
        return lastSpaceScrollConsumed
    end

    -- CMD + CTRL + SCROLL -> Cycle windows on the current display
    if flags.cmd and flags.ctrl and not (flags.alt or flags.shift) then
        if now - cycleSession.lastTime < 0.18 then
            return true
        end

        -- Reuse the session inventory while it is fresh and the pointer or
        -- focus is still on its display; take a new inventory only to start
        -- or move a session. getWindows plus per-window AX checks per step
        -- was the main cost of cycling.
        local reuse = false
        if cycleSession.active and (now - cycleSession.lastTime <= 1.5) then
            local mouseScr = hs.mouse.getCurrentScreen()
            local focusedWin = hs.window.focusedWindow()
            local focusedScr = focusedWin and focusedWin:screen()
            if (mouseScr and mouseScr:id() == cycleSession.screenId)
                or (focusedScr and focusedScr:id() == cycleSession.screenId) then
                reuse = true
            end
        end

        local rawWindows, screenId
        if not reuse then
            rawWindows = omarchy and omarchy.windowFilter:getWindows(hs.window.filter.sortByFocusedLast)
                or hs.window.orderedWindows()
            local screen = getTargetScreenForWindows(rawWindows)
            if not screen then return true end
            screenId = screen:id()
        end

        if not reuse and (not cycleSession.active or (now - cycleSession.lastTime > 1.5) or (cycleSession.screenId ~= screenId)) then
            local screenWindows = {}
            for _, w in ipairs(rawWindows) do
                local ok, s = pcall(function() return w:screen() end)
                local okStd, isStd = pcall(function() return w:isStandard() end)
                local okMin, isMin = pcall(function() return w:isMinimized() end)
                if ok and s and s:id() == screenId and okStd and isStd and okMin and not isMin then
                    table.insert(screenWindows, w)
                end
            end

            if #screenWindows <= 1 then return true end

            cycleSession.active = true
            cycleSession.windows = screenWindows
            cycleSession.screenId = screenId
            cycleSession.index = 1

            local focused = hs.window.focusedWindow()
            if focused then
                for i, w in ipairs(screenWindows) do
                    if w:id() == focused:id() then
                        cycleSession.index = i
                        break
                    end
                end
            end
        end

        cycleSession.lastTime = now
        local count = #cycleSession.windows

        if count > 1 then
            local delta = line ~= 0 and line or point
            if delta > 0 then
                cycleSession.index = cycleSession.index - 1
                if cycleSession.index < 1 then
                    cycleSession.index = count
                end
            else
                cycleSession.index = cycleSession.index + 1
                if cycleSession.index > count then
                    cycleSession.index = 1
                end
            end

            local targetWin = cycleSession.windows[cycleSession.index]
            if targetWin then
                -- Coalesce rapid steps: only the latest target gets focused.
                if cycleSession.focusTimer then cycleSession.focusTimer:stop() end
                cycleSession.focusTimer = hs.timer.doAfter(0.001, function()
                    cycleSession.focusTimer = nil
                    pcall(function() targetWin:focus() end)
                end)
            end
        end

        return true
    end

    return false
end)
hs_window_cycler.scrollWatcher:start()

-- 2. MIDDLE CLICK WATCHER (Cmd + Middle Click -> Workspace Overview)
local middleClickSwallowed = false

hs_window_cycler.middleClickWatcher = hs.eventtap.new({
    hs.eventtap.event.types.otherMouseDown,
    hs.eventtap.event.types.otherMouseUp
}, function(e)
    local eventType = e:getType()
    local btn = e:getProperty(hs.eventtap.event.properties.mouseEventButtonNumber)
    local flags = e:getFlags()

    if btn == 2 then
        if eventType == hs.eventtap.event.types.otherMouseDown then
            -- Cmd + Middle Click (without Ctrl, Alt, Shift)
            if flags.cmd and not (flags.ctrl or flags.alt or flags.shift) then
                middleClickSwallowed = true
                hs.timer.doAfter(0.001, function()
                    toggleWorkspaceOverview()
                end)
                return true
            end
        elseif eventType == hs.eventtap.event.types.otherMouseUp then
            if middleClickSwallowed then
                middleClickSwallowed = false
                return true
            end
        end
    end

    return false
end)
hs_window_cycler.middleClickWatcher:start()

-- Watchdog timer
hs_window_cycler.watchdogTimer = hs.timer.doEvery(5, function()
    if hs_window_cycler.scrollWatcher and not hs_window_cycler.scrollWatcher:isEnabled() then
        hs_window_cycler.scrollWatcher:start()
    end
    if hs_window_cycler.flagsWatcher and not hs_window_cycler.flagsWatcher:isEnabled() then
        hs_window_cycler.flagsWatcher:start()
    end
    if hs_window_cycler.middleClickWatcher and not hs_window_cycler.middleClickWatcher:isEnabled() then
        hs_window_cycler.middleClickWatcher:start()
    end
    if hs_focus_follow and hs_focus_follow.tap and not hs_focus_follow.tap:isEnabled() then
        hs_focus_follow.tap:start()
    end
end)


-- ----------------------------------------------------------------------------
-- SECTION 3: CLIPBOARD MANAGER (Ctrl + V)
-- ----------------------------------------------------------------------------
-- A clipboard failure must not stop tiling. Image files live beside the history JSON.
local clipboardOk, clipboardOrErr = pcall(require, "clipboard")
if not clipboardOk then
    hs.alert.show("Clipboard history failed to load")
else
    local started, startErr = pcall(clipboardOrErr.start)
    if not started then
        hs.alert.show("Clipboard history: " .. tostring(startErr):gsub("%s+", " "):sub(1, 120))
    end
end

-- ============================================================================
omarchy = require("omarchy")
if omarchy.watchSettings then omarchy.watchSettings() end

-- Both command menus are normal windows, so a hover elsewhere would activate
-- another application and close them mid-typing.
local function menuOpen()
    for _, name in ipairs({"omarchy", "clipboard"}) do
        local owner = package.loaded[name]
        local chooser = owner and owner.chooser
        if chooser and chooser.isVisible then
            local ok, visible = pcall(function() return chooser:isVisible() end)
            if ok and visible then return true end
        end
    end
    return false
end

-- Focus follows the pointer is off unless it was explicitly turned on with
-- Ctrl + Option + P, the command menu, or the menu bar item. The choice is
-- remembered between reloads; only then is the pointer watcher started.
local focus = require("focus")
focus.configure({
    filter = omarchy.windowFilter,
    suspended = function() return cycleSession.active or menuOpen() end,
})
-- settings.json is authoritative. On the first run after an upgrade, adopt a
-- legacy "on" choice from focus-follows-mouse.txt and persist it so the CLI and
-- the settings window agree. A legacy "off" needs no override.
local explicitFocus = settings.user and settings.user.focus and settings.user.focus.enabled
if explicitFocus ~= nil then
    focus.setEnabled(settings.values.focus.enabled == true, true)
else
    local focusEnabled = focus.loadEnabled()
    focus.setEnabled(focusEnabled, false)
    if focusEnabled and not settings.set("focus.enabled", true) then
        settings.values.focus.enabled = true
    end
end
hs.alert.show("Hammerspoon + macOS Omarchy are ready!")
