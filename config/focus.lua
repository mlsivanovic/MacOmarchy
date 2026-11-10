-- Focus the window under the pointer so typing follows the mouse.
-- macOS raises an application when it takes the keyboard, so the hovered
-- window also comes forward. The hit test uses the window server's stacking
-- order and ignores the menu bar, the Dock, and anything that is not a
-- normal window on the current Space. A text field under the pointer then
-- takes the caret. Applications that ignore an accessibility focus request
-- get one left click on that field instead.
local desktops = require("desktops")
local S = require("settings")

local F = { enabled = false }

local SETTINGS_NAME = "focus-follows-mouse.txt"

local function shellQuote(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

-- Remembered in ~/.config so copying the Hammerspoon config does not
-- resurrect the old choice. A missing or unreadable file means the default:
-- off.
function F.settingsFile()
    if F._settingsFile ~= nil then
        if F._settingsFile == false then return nil end
        return F._settingsFile
    end
    local home = os.getenv("HOME")
    if not home or home == "" then return nil end
    return home .. "/.config/mac-omarchy/" .. SETTINGS_NAME
end

-- Accept the words a hand-edited file is likely to contain.
function F.parseEnabled(raw)
    if type(raw) ~= "string" then return nil end
    local value = raw:match("^%s*(%a+)%s*$")
    if not value then return nil end
    value = value:lower()
    if value == "on" or value == "true" or value == "enabled" then return true end
    if value == "off" or value == "false" or value == "disabled" then return false end
end

function F.loadEnabled()
    local path = F.settingsFile()
    if not path then return false end
    local file = io.open(path, "r")
    if not file then return false end
    local raw = file:read("*a")
    file:close()
    return F.parseEnabled(raw or "") == true
end

function F.saveEnabled(enabled)
    local path = F.settingsFile()
    if not path then return false end
    local dir = path:match("^(.*)/")
    if dir and dir ~= "" then os.execute("mkdir -p " .. shellQuote(dir)) end
    local file = io.open(path, "w")
    if not file then return false end
    file:write(enabled == true and "on\n" or "off\n")
    file:close()
    return true
end

local TEXT_ROLES = {
    AXTextField = true,
    AXTextArea = true,
    AXComboBox = true,
    AXSearchField = true,
}

-- Clicking one of these would activate it. A text field behind the control
-- must not turn a rest on the control into that activation.
local CONTROL_ROLES = {
    AXButton = true,
    AXLink = true,
    AXMenuButton = true,
    AXMenuItem = true,
    AXCheckBox = true,
    AXRadioButton = true,
    AXPopUpButton = true,
    AXSlider = true,
    AXIncrementor = true,
    AXDisclosureTriangle = true,
    AXImage = true,
}

function F.contains(frame, point)
    return frame and point
        and type(point.x) == "number" and type(point.y) == "number"
        and point.x >= frame.x and point.x < frame.x + frame.w
        and point.y >= frame.y and point.y < frame.y + frame.h
end

-- Empty or missing screens means the check is unavailable, not that the
-- pointer is in the menu bar.
function F.inWorkingArea(point, areas)
    if not areas or not areas[1] then return true end
    for i = 1, #areas do
        if F.contains(areas[i], point) then return true end
    end
    return false
end

function F.moved(a, b)
    if not a or not b then return true end
    local slop = S.get("focus.slop")
    return math.abs(a.x - b.x) >= slop or math.abs(a.y - b.y) >= slop
end

function F.frameOf(entry)
    if type(entry) ~= "table" then return nil end
    local bounds = entry.kCGWindowBounds or entry.bounds or entry.frame
    if type(bounds) ~= "table" then return nil end
    local x = bounds.X or bounds.x
    local y = bounds.Y or bounds.y
    local w = bounds.Width or bounds.w
    local h = bounds.Height or bounds.h
    if type(x) ~= "number" or type(y) ~= "number" or type(w) ~= "number" or type(h) ~= "number" then
        return nil
    end
    if w <= 1 or h <= 1 then return nil end
    return {x = x, y = y, w = w, h = h}
end

-- Front to back. A window above the hovered one that we do not type into
-- (menu, overlay, status chrome) hides the windows behind it.
function F.stack(entries, known)
    local list = {}
    for _, entry in ipairs(entries or {}) do
        local layer = entry.kCGWindowLayer
        local alpha = entry.kCGWindowAlpha
        local normalLayer = type(layer) ~= "number" or layer == 0
        local visible = type(alpha) ~= "number" or alpha > 0
        -- The pointer's own window uses a huge level and always contains the
        -- cursor. Looking through it is required; menus stay at small levels
        -- and still hide the window behind them.
        local cursor = type(layer) == "number" and layer >= 1000
        local aboveDesktop = not cursor and (type(layer) ~= "number" or layer >= 0)
        if aboveDesktop and visible then
            local frame = F.frameOf(entry)
            local id = entry.kCGWindowNumber or entry.id
            if frame and type(id) == "number" then
                local window = known and known[id] or nil
                local permitted = normalLayer and (not known or window ~= nil)
                list[#list + 1] = {
                    id = id,
                    frame = frame,
                    allowed = permitted,
                    window = permitted and window or nil,
                }
            end
        end
    end
    return list
end

function F.windowAt(point, windows)
    if not point or not windows then return nil end
    for i = 1, #windows do
        local window = windows[i]
        if F.contains(window.frame, point) then
            if window.allowed == false then return nil end
            return window
        end
    end
end

-- Returns "arm", id or "wait" or "drop".
function F.decide(focusedId, pendingId, point, windows, paused, areas)
    if paused or not F.inWorkingArea(point, areas) then return "drop" end
    local hit = F.windowAt(point, windows)
    if not hit or hit.id == focusedId then return "drop" end
    if hit.id == pendingId then return "wait" end
    return "arm", hit.id
end

function F.confirm(pendingId, focusedId, point, windows, paused, areas)
    if paused or not pendingId or not F.inWorkingArea(point, areas) then return nil end
    local hit = F.windowAt(point, windows)
    if not hit or hit.id ~= pendingId or hit.id == focusedId then return nil end
    return hit.id
end

local function buttonsDown()
    local buttons = hs.eventtap.checkMouseButtons() or {}
    if buttons.left or buttons.right or buttons.middle then return true end
    for _, down in pairs(buttons) do
        if down == true then return true end
    end
    return false
end

local function shortcutModifierDown(event)
    if event and event.getFlags then
        local flags = event:getFlags()
        if flags.cmd or flags.ctrl or flags.alt or flags.shift then return true end
    end
    local mods = hs.eventtap.checkKeyboardModifiers(true)
    return mods and (mods.cmd or mods.ctrl or mods.alt or mods.shift) or false
end

local function transitions()
    if desktops.isChanging and desktops.isChanging() then return true end
    if desktops.creating then return true end
    return false
end

local function missionControlOpen(now, fresh)
    local state = hs_focus_follow
    if not fresh and state and state.missionAt and now and now - state.missionAt < 0.15 then
        return state.mission
    end
    local mission = package.loaded["mission-control"]
    local open = false
    if mission and mission.isOpen then
        local ok, result = pcall(mission.isOpen)
        open = ok and result == true
    end
    if state then state.mission, state.missionAt = open, now or 0 end
    return open
end

local function knownWindows(filter)
    local set = {}
    if not filter or not filter.getWindows then return set end
    local ok, windows = pcall(function() return filter:getWindows() end)
    if not ok or type(windows) ~= "table" then return set end
    for _, window in ipairs(windows) do
        local okId, id = pcall(function() return window:id() end)
        if okId and type(id) == "number" then set[id] = window end
    end
    return set
end

local function snapshot(filter)
    local known = knownWindows(filter)
    if hs.window.list then
        local ok, entries = pcall(hs.window.list, false)
        if ok and type(entries) == "table" then return F.stack(entries, known) end
    end
    local list = {}
    local ok, windows = pcall(hs.window.orderedWindows)
    if not ok or type(windows) ~= "table" then return list end
    for _, window in ipairs(windows) do
        local idOk, id = pcall(function() return window:id() end)
        local frameOk, frame = pcall(function() return window:frame() end)
        if idOk and frameOk and known[id] then
            list[#list + 1] = {id = id, frame = frame, allowed = true, window = window}
        end
    end
    return list
end

local function workingAreas()
    local areas = {}
    local screens = hs.screen.allScreens() or {}
    for _, screen in ipairs(screens) do
        local ok, frame = pcall(function() return screen:frame() end)
        if ok and frame then areas[#areas + 1] = frame end
    end
    return areas
end

local function elementValue(element, name)
    if not element or not element.attributeValue then return nil end
    local ok, value = pcall(function() return element:attributeValue(name) end)
    if ok then return value end
end

local function elementFrame(element)
    local pos = elementValue(element, "AXPosition") or {}
    local size = elementValue(element, "AXSize") or {}
    local x = pos.x or pos.X
    local y = pos.y or pos.Y
    local w = size.w or size.Width or size.width
    local h = size.h or size.Height or size.height
    if type(x) ~= "number" or type(y) ~= "number" or type(w) ~= "number" or type(h) ~= "number" then
        return nil
    end
    return {x = x, y = y, w = w, h = h}
end

local function sameField(a, b)
    if not a or not b then return false end
    if a == b then return true end
    if elementValue(a, "AXRole") ~= elementValue(b, "AXRole") then return false end
    local fa, fb = elementFrame(a), elementFrame(b)
    if not fa or not fb then return false end
    return math.abs(fa.x - fb.x) < 2 and math.abs(fa.y - fb.y) < 2
        and math.abs(fa.w - fb.w) < 2 and math.abs(fa.h - fb.h) < 2
end

-- The address bar and other text fields are inside the window. Focusing the
-- window leaves the keyboard wherever the app last had it, so the field under
-- the pointer has to be focused on its own.
function F.textField(element)
    local guard = 0
    while element and guard < 16 do
        guard = guard + 1
        local role = elementValue(element, "AXRole")
        if TEXT_ROLES[role] then return element end
        if role == "AXWindow" or role == "AXSheet" or role == "AXDialog" then return nil end
        local parent = elementValue(element, "AXParent")
        if not parent or parent == element then return nil end
        element = parent
    end
end

-- Hit testing returns the deepest element. Walk up to its text field, but
-- stop at a button or link so a rest there does not click the field behind
-- it. A browser page often reports only the web area; then follow the child
-- whose frame contains the pointer.
function F.textAt(element, point)
    local guard = 0
    local node = element
    while node and guard < 16 do
        guard = guard + 1
        local role = elementValue(node, "AXRole")
        if TEXT_ROLES[role] then return node end
        if CONTROL_ROLES[role] then return nil end
        if role == "AXWindow" or role == "AXSheet" or role == "AXDialog" then break end
        local parent = elementValue(node, "AXParent")
        if not parent or parent == node then break end
        node = parent
    end
    if not element or not point then return nil end
    local seen = 0
    local function walk(current, depth)
        if not current or depth > 8 or seen >= 40 then return nil end
        local children = elementValue(current, "AXChildren")
        if type(children) ~= "table" then return nil end
        for i = 1, #children do
            local child = children[i]
            local frame = elementFrame(child)
            if not frame or F.contains(frame, point) then
                seen = seen + 1
                local role = elementValue(child, "AXRole")
                if TEXT_ROLES[role] and frame and F.contains(frame, point) then return child end
                if not CONTROL_ROLES[role] then
                    local nested = walk(child, depth + 1)
                    if nested then return nested end
                end
            end
            if seen >= 40 then return nil end
        end
    end
    return walk(element, 0)
end

-- While this is in the future, a click this module just posted must not
-- cancel the rest that sent it.
local ignoreClicksUntil = 0

local function focusedUIElement()
    local ax = hs.axuielement
    if not ax or not ax.systemWideElement then return nil end
    local ok, system = pcall(ax.systemWideElement)
    if not ok then return nil end
    return elementValue(system, "AXFocusedUIElement")
end

local function clickField(point)
    if not hs.eventtap or not hs.eventtap.leftClick or not point then return false end
    ignoreClicksUntil = hs.timer.secondsSinceEpoch() + 0.15
    local ok = pcall(hs.eventtap.leftClick, {x = point.x, y = point.y}, 0)
    return ok
end

-- nil: nothing under the pointer to type into. true: the field has the
-- keyboard, or a click was sent to it. false: the field refused both.
local function focusTextField(point)
    local ax = hs.axuielement
    if not ax or not ax.systemElementAtPosition or not point then return nil end
    local ok, element = pcall(ax.systemElementAtPosition, point.x, point.y)
    if not ok or not element then return nil end
    local field = F.textAt(element, point)
    if not field then return nil end
    if sameField(focusedUIElement(), field) then return true end
    local enabled = elementValue(field, "AXEnabled")
    if enabled == false then return nil end
    local settable = true
    if field.isAttributeSettable then
        local okSet, result = pcall(function() return field:isAttributeSettable("AXFocused") end)
        if okSet and result == false then settable = false end
    end
    -- A successful write is not proof. Browsers often accept AXFocused and
    -- leave the caret where it was, without reporting an error.
    if settable and field.setAttributeValue then
        pcall(function() field:setAttributeValue("AXFocused", true) end)
        if sameField(focusedUIElement(), field) then return true end
    end
    if S.get("focus.clickTextFields", true) ~= false and clickField(point) then return true end
    return false
end

local function focusedWindowId()
    local ok, window = pcall(hs.window.focusedWindow)
    if not ok or not window then return nil end
    local idOk, id = pcall(function() return window:id() end)
    if idOk then return id end
end

function F.isEnabled()
    return F.enabled == true
end

-- The caller supplies the window filter and suspend checks once; a later
-- toggle starts the same watcher with those options.
function F.configure(options)
    F.options = options or {}
    return F
end

-- Starts or stops the watcher and optionally remembers the choice. Returns
-- the new state and whether it was saved.
function F.setEnabled(enabled, persist)
    enabled = enabled == true
    if enabled then
        F.start(F.options or {})
    else
        F.stop()
    end
    local saved = true
    if persist then saved = F.saveEnabled(enabled) end
    return enabled, saved
end

function F.toggle()
    return F.setEnabled(not F.isEnabled(), true)
end

function F.stop()
    F.enabled = false
    local state = hs_focus_follow
    if not state then return end
    state.running = false
    if state.tap then pcall(function() state.tap:stop() end) end
    if state.eval then pcall(function() state.eval:stop() end) end
    if state.dwell then pcall(function() state.dwell:stop() end) end
    if state.field then pcall(function() state.field:stop() end) end
    if state.caffeinateWatcher then pcall(function() state.caffeinateWatcher:stop() end) end
    if state.unsubscribe then pcall(state.unsubscribe) end
    hs_focus_follow = nil
end

function F.start(options)
    F.stop()
    options = options or {}
    local suspended = options.suspended or function() return false end
    local filter = options.filter
    local releaseFilter = false
    if not filter then
        filter = hs.window.filter.new():setCurrentSpace(true)
        local keepAlive = function() end
        filter:subscribe(hs.window.filter.windowCreated, keepAlive)
        releaseFilter = function() filter:unsubscribe(keepAlive) end
    end

    hs_focus_follow = {running = true, unsubscribe = releaseFilter}
    local state = hs_focus_follow
    local pendingId, latest, settled
    local acceptedId, acceptedUntil = nil, 0

    local function gesturePaused(event)
        local now = hs.timer.secondsSinceEpoch()
        return buttonsDown() or shortcutModifierDown(event) or suspended() or transitions()
            or state.locked or state.sleeping or now < (state.resumeAfter or 0)
    end

    local function keyboardId(now)
        -- Activation lags the focus call by a moment. Ignore that gap so a
        -- pointer twitch does not activate the same window twice.
        if acceptedId and now < acceptedUntil then return acceptedId end
        return focusedWindowId()
    end

    local function cancel()
        pendingId = nil
        settled = nil
        if state.dwell then state.dwell:stop(); state.dwell = nil end
        if state.field then state.field:stop(); state.field = nil end
    end

    local function arm(id)
        pendingId = id
        if state.dwell then state.dwell:stop() end
        if state.field then state.field:stop(); state.field = nil end
        state.dwell = hs.timer.doAfter(S.get("focus.delay"), function()
            state.dwell = nil
            if not state.running then return end
            local now = hs.timer.secondsSinceEpoch()
            local areas = workingAreas()
            local windows = snapshot(filter)
            local armed = pendingId
            local keyboard = keyboardId(now)
            local paused = gesturePaused() or missionControlOpen(now, true)
            local chosen = F.confirm(armed, keyboard, latest, windows, paused, areas)
            pendingId = nil
            local point = latest
            local switched = false
            if not chosen then
                -- Confirm refuses a window that is already key. That rest can
                -- still move the keyboard into the text field under the pointer.
                -- A pause, Mission Control, or a missed window must not.
                local hit = point and F.windowAt(point, windows)
                if paused or not hit or hit.id ~= armed or hit.id ~= keyboard
                    or not F.inWorkingArea(point, areas) then
                    return
                end
            else
                local target
                for i = 1, #windows do
                    if windows[i].id == chosen then target = windows[i].window break end
                end
                if not target then return end
                switched = chosen ~= keyboard
                if switched then
                    local ok = pcall(function() target:focus() end)
                    if not ok then return end
                    acceptedId, acceptedUntil = chosen, now + 0.05
                end
            end
            settled = point
            local function applyField(attempt)
                if not state.running or not point then return end
                local current = hs.mouse and hs.mouse.absolutePosition and hs.mouse.absolutePosition()
                if F.moved(point, current) then return end
                local placed = focusTextField(current)
                if placed == true or attempt > 1 then return end
                -- Activation replaces the accessibility tree. One later look
                -- covers a field that was not there, or a write that did not stick.
                if placed == false or switched then
                    state.field = hs.timer.doAfter(S.get("focus.fieldRetryDelay", 0.12), function()
                        state.field = nil
                        applyField(2)
                    end)
                end
            end
            -- Activation is asynchronous. A field focused in the same turn
            -- is overwritten by the window becoming key.
            state.field = hs.timer.doAfter(switched and 0.06 or 0, function()
                state.field = nil
                applyField(1)
            end)
        end)
    end

    local function evaluate()
        if not state.running or not latest then return end
        local now = hs.timer.secondsSinceEpoch()
        local areas = workingAreas()
        if gesturePaused() or not F.inWorkingArea(latest, areas) then
            cancel()
            return
        end
        -- Restack on every lookup. A dialog can cover the window the pointer
        -- was already inside, and the front window is the one that should focus.
        local windows = snapshot(filter)
        local keyboard = keyboardId(now)
        local action, id = F.decide(keyboard, pendingId, latest, windows, false, areas)
        local hit = F.windowAt(latest, windows)
        -- The window can already be key while the address bar is not. A rest
        -- on that window still has to move the keyboard into the text field.
        if action == "drop" then
            if hit and hit.id == keyboard and pendingId ~= hit.id
                and not missionControlOpen(now, false) then
                arm(hit.id)
            else
                cancel()
            end
            return
        end
        if action == "wait" then return end
        if missionControlOpen(now, false) then cancel(); return end
        arm(id)
    end

    local function schedule()
        if state.eval then return end
        -- Leave the event callback before asking the window server who is
        -- under the pointer. Moves that arrive before it runs share one lookup.
        state.eval = hs.timer.doAfter(0, function()
            state.eval = nil
            if state.running then evaluate() end
        end)
    end

    -- A dwell timer can be suspended by macOS and fire after unlock against a
    -- window server snapshot from before sleep. Drop all pending hover work at
    -- the lifecycle boundary, then require fresh pointer movement after resume.
    local watcherAPI = hs.caffeinate and hs.caffeinate.watcher
    if watcherAPI and watcherAPI.new then
        local function pause()
            cancel()
            latest = nil
            acceptedId, acceptedUntil = nil, 0
        end
        local ok, watcher = pcall(function()
            return watcherAPI.new(function(event)
                if event == watcherAPI.screensDidLock then
                    state.locked = true
                    pause()
                elseif event == watcherAPI.systemWillSleep or event == watcherAPI.screensDidSleep then
                    state.sleeping = true
                    pause()
                elseif event == watcherAPI.systemDidWake or event == watcherAPI.screensDidWake then
                    state.sleeping = false
                    state.resumeAfter = hs.timer.secondsSinceEpoch() + 0.5
                elseif event == watcherAPI.screensDidUnlock then
                    state.locked = false
                    state.resumeAfter = hs.timer.secondsSinceEpoch() + 0.5
                end
            end)
        end)
        if ok and watcher then
            local started = pcall(function() watcher:start() end)
            if started then state.caffeinateWatcher = watcher end
        end
    end

    local types = hs.eventtap.event.types
    state.tap = hs.eventtap.new({
        types.mouseMoved,
        types.leftMouseDown,
        types.rightMouseDown,
        types.otherMouseDown,
        types.flagsChanged,
    }, function(event)
        if not state.running then return false end
        local kind = event:getType()
        if kind == types.flagsChanged then
            if shortcutModifierDown(event) then cancel()
            elseif latest then schedule() end
            return false
        end
        if kind ~= types.mouseMoved then
            -- The click posted for a text field is delivered back through
            -- this tap. Treating it as a user click would undo the rest.
            if hs.timer.secondsSinceEpoch() < ignoreClicksUntil then return false end
            cancel()
            return false
        end
        local point = event:location()
        if type(point) ~= "table" then return false end
        -- A resting pointer still emits tiny moves. Resetting on those
        -- would never let the delay elapse, and would refocus the address
        -- bar while typing.
        if settled and not F.moved(settled, point) then return false end
        settled = nil
        latest = point
        if gesturePaused(event) then
            cancel()
            return false
        end
        schedule()
        return false
    end)
    state.tap:start()
    F.enabled = true
    return F
end

return F
