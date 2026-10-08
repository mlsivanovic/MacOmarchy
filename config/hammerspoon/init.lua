-- ============================================================================
-- ~/.hammerspoon/init.lua
-- 1. Workspace Switcher: Cmd + Scroll (menjanje Space-ova na trenutnom monitoru)
-- 2. Workspace Overview: Cmd + Middle Click (otvara Mission Control pregled)
-- 3. Window Cycler:      Cmd + Ctrl + Scroll (rotiranje prozora na monitoru)
-- 4. Clipboard Manager:  Cmd + Ctrl + V (istorija 100 stavki sa pretragom)
-- ============================================================================

local spaces = require("hs.spaces")
local desktops = require("desktops")

-- ----------------------------------------------------------------------------
-- SEKCIJA 1: FUNKCIJE ZA SPACE-OVE I MISSION CONTROL
-- ----------------------------------------------------------------------------
local lastSpaceScrollTime = 0
local lastSpaceScrollConsumed = false

-- Native Dock shortcuts are resolved by desktops.lua for the hovered monitor.
-- Vraća true samo kad se Space stvarno promeni. Ako monitor ima jedan Space,
-- scroll ostaje normalan umesto da se proguta.
local function cycleSpaceOnCurrentScreen(direction)
    return desktops.cycle(direction, hs.mouse.getCurrentScreen())
end

-- Otvara / zatvara Workspace Overview (Mission Control)
local function toggleWorkspaceOverview()
    if spaces and spaces.toggleMissionControl then
        spaces.toggleMissionControl()
    else
        hs.application.launchOrFocus("Mission Control")
    end
end


-- ----------------------------------------------------------------------------
-- SEKCIJA 2: WATCHERI ZA MIŠ (Scroll & Middle Click)
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

-- Sesija za rotiranje prozora
local cycleSession = {
    active = false,
    windows = {},
    index = 1,
    screenId = nil,
    lastTime = 0
}

local function endCycleSession()
    cycleSession.active = false
    cycleSession.windows = {}
    cycleSession.index = 1
    cycleSession.screenId = nil
end

-- macOS na Cmd+scroll upiše i objedinjeni ctrl bit (staro mapiranje za zoom).
-- Zato se gleda samo fizički taster (device* bit), ne taj objedinjeni ctrl.
local function deviceMods(raw)
    local masks = hs.eventtap.event.rawFlagMasks
    local function down(name)
        local mask = masks[name]
        return mask ~= nil and raw & mask ~= 0
    end
    return {
        cmd = down("deviceLeftCommand") or down("deviceRightCommand") or down("command"),
        ctrl = down("deviceLeftControl") or down("deviceRightControl"),
        alt = down("deviceLeftAlternate") or down("deviceRightAlternate"),
        shift = down("deviceLeftShift") or down("deviceRightShift"),
    }
end

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

local function getTargetScreenForWindows()
    local mouseScreen = hs.mouse.getCurrentScreen()
    local focusedWin = hs.window.focusedWindow()
    local focusedScreen = focusedWin and focusedWin:screen()

    local function countWindowsOnScreen(scr)
        if not scr then return 0 end
        local cnt = 0
        local scrId = scr:id()
        for _, w in ipairs(hs.window.orderedWindows()) do
            local ok, s = pcall(function() return w:screen() end)
            local okStd, isStd = pcall(function() return w:isStandard() end)
            local okMin, isMin = pcall(function() return w:isMinimized() end)
            if ok and s and s:id() == scrId and okStd and isStd and okMin and not isMin then
                cnt = cnt + 1
            end
        end
        return cnt
    end

    if countWindowsOnScreen(mouseScreen) > 1 then
        return mouseScreen
    end
    if focusedScreen and countWindowsOnScreen(focusedScreen) > 1 then
        return focusedScreen
    end
    return mouseScreen or focusedScreen
end

-- 1. SKROL WATCHER (Cmd + Scroll & Cmd + Ctrl + Scroll)
hs_window_cycler.scrollWatcher = hs.eventtap.new({hs.eventtap.event.types.scrollWheel}, function(e)
    local fromEvent = deviceMods(e:rawFlags())
    -- Scroll događaj uz Cmd nosi i lažni Ctrl (staro mapiranje za zoom).
    -- Ctrl/Alt/Shift se proveravaju iz trenutnog stanja fizičkih tastera.
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

    local props = hs.eventtap.event.properties
    local dy = e:getProperty(props.scrollWheelEventDeltaAxis1) or 0
    local dx = e:getProperty(props.scrollWheelEventDeltaAxis2) or 0
    if dy == 0 then dy = e:getProperty(props.scrollWheelEventFixedPtDeltaAxis1) or 0 end
    if dx == 0 then dx = e:getProperty(props.scrollWheelEventFixedPtDeltaAxis2) or 0 end
    if dy == 0 then dy = e:getProperty(props.scrollWheelEventPointDeltaAxis1) or 0 end
    if dx == 0 then dx = e:getProperty(props.scrollWheelEventPointDeltaAxis2) or 0 end

    if dy == 0 and dx == 0 then return false end

    -- CMD + SCROLL -> Promena Workspace-ova na trenutnom monitoru
    if flags.cmd and not (flags.ctrl or flags.alt or flags.shift) then
        if now - lastSpaceScrollTime < 0.35 then
            return lastSpaceScrollConsumed
        end

        lastSpaceScrollTime = now
        local direction = (dy < 0 or dx < 0) and 1 or -1
        lastSpaceScrollConsumed = cycleSpaceOnCurrentScreen(direction)
        return lastSpaceScrollConsumed
    end

    -- CMD + CTRL + SCROLL -> Rotiranje prozora na trenutnom monitoru
    if flags.cmd and flags.ctrl and not (flags.alt or flags.shift) then
        if now - cycleSession.lastTime < 0.18 then
            return true
        end

        local screen = getTargetScreenForWindows()
        if not screen then return true end
        local screenId = screen:id()

        if not cycleSession.active or (now - cycleSession.lastTime > 1.5) or (cycleSession.screenId ~= screenId) then
            local rawWindows = hs.window.orderedWindows()
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
            if dy > 0 or dx > 0 then
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
                hs.timer.doAfter(0.001, function()
                    pcall(function() targetWin:focus() end)
                end)
            end
        end

        return true
    end

    return false
end)
hs_window_cycler.scrollWatcher:start()

-- 2. SREDNJI KLIK WATCHER (Cmd + Middle Click -> Workspace Overview)
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
            -- Cmd + Middle Click (bez Ctrl, Alt, Shift)
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

-- Watchdog tajmer
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
end)


-- ----------------------------------------------------------------------------
-- SEKCIJA 3: CLIPBOARD MANAGER (Cmd + Ctrl + V)
-- ----------------------------------------------------------------------------
hs_clipboard = hs_clipboard or {}

if hs_clipboard.watcher then pcall(function() hs_clipboard.watcher:stop() end) end
if hs_clipboard.hotkey then pcall(function() hs_clipboard.hotkey:delete() end) end

local MAX_HISTORY = 100
local historyFile = os.getenv("HOME") .. "/.hammerspoon/clipboard_history.json"

local function loadHistory()
    local ok, data = pcall(function() return hs.json.read(historyFile) end)
    if ok and type(data) == "table" then return data end
    return {}
end

local function saveHistory(hist)
    pcall(function() hs.json.write(hist, historyFile, true, true) end)
end

hs_clipboard.history = loadHistory()
local lastChangeCount = hs.pasteboard.changeCount()

local initialClip = hs.pasteboard.getContents()
if #hs_clipboard.history == 0 and initialClip and initialClip ~= "" then
    table.insert(hs_clipboard.history, initialClip)
    saveHistory(hs_clipboard.history)
end

local function addClip(text)
    if not text or text == "" or type(text) ~= "string" then return end

    for i, item in ipairs(hs_clipboard.history) do
        if item == text then
            table.remove(hs_clipboard.history, i)
            break
        end
    end

    table.insert(hs_clipboard.history, 1, text)

    while #hs_clipboard.history > MAX_HISTORY do
        table.remove(hs_clipboard.history)
    end

    saveHistory(hs_clipboard.history)
end

hs_clipboard.watcher = hs.timer.doEvery(0.4, function()
    local currentCount = hs.pasteboard.changeCount()
    if currentCount ~= lastChangeCount then
        lastChangeCount = currentCount
        local text = hs.pasteboard.getContents()
        if text and text ~= "" and text ~= hs_clipboard.history[1] then
            addClip(text)
        end
    end
end)

hs_clipboard.chooser = hs.chooser.new(function(choice)
    if choice and choice.fullText then
        lastChangeCount = hs.pasteboard.changeCount()
        hs.pasteboard.setContents(choice.fullText)
        lastChangeCount = hs.pasteboard.changeCount()

        addClip(choice.fullText)

        hs.timer.doAfter(0.12, function()
            hs.eventtap.keyStroke({"cmd"}, "v")
        end)
    end
end)

hs_clipboard.chooser:searchSubText(true)
hs_clipboard.chooser:rows(9)
hs_clipboard.chooser:placeholderText("Pretraži istoriju (kucaj za filtriranje 100 stavki)...")

hs_clipboard.hotkey = hs.hotkey.bind({"cmd", "ctrl"}, "v", function()
    if #hs_clipboard.history == 0 then
        hs.alert.show("Clipboard istorija je prazna")
        return
    end

    local choices = {}
    for i, item in ipairs(hs_clipboard.history) do
        local firstLine = item:match("([^\r\n]+)") or item
        if #firstLine > 75 then firstLine = firstLine:sub(1, 75) .. "…" end

        local preview = item:gsub("[\r\n\t]+", " ")
        if #preview > 110 then preview = preview:sub(1, 110) .. "…" end

        table.insert(choices, {
            text = firstLine,
            subText = string.format("#%d (%d karaktera) • %s", i, #item, preview),
            fullText = item
        })
    end

    hs_clipboard.chooser:choices(choices)
    hs_clipboard.chooser:show()
end)

-- ============================================================================
omarchy = require("omarchy")
hs.alert.show("Hammerspoon + macOS Omarchy su spremni!")
