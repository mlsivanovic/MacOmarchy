local timerAPI, advance = dofile("tests/timers.lua")()
package.path = "config/?.lua;" .. package.path
local changing, creating, suspended, missionOpen = false, false, false, false
local buttons = {}
local modifiers = {}
local focused
local windows = {}
local listed = {}
local screens = {}
local taps = {}
local pointer = {x = 0, y = 0}
local fieldClicks = 0
local axAt = function() end
local axFocusedElement
local axCalls = 0

local function makeWindow(id)
    local window = {n = 0}
    function window:id() return id end
    function window:focus()
        self.n = self.n + 1
        focused = self
    end
    windows[id] = window
    return window
end

local function cg(id, x, y, w, h, extra)
    local entry = {
        kCGWindowNumber = id,
        kCGWindowLayer = 0,
        kCGWindowAlpha = 1,
        kCGWindowBounds = {X = x, Y = y, Width = w, Height = h},
    }
    if extra then for k, v in pairs(extra) do entry[k] = v end end
    return entry
end

package.loaded.desktops = {
    isChanging = function() return changing end,
}
setmetatable(package.loaded.desktops, {__index = function(_, key)
    if key == "creating" then return creating end
end})
package.loaded["mission-control"] = {isOpen = function() return missionOpen end}

hs = {
    timer = timerAPI,
    window = {
        list = function() return listed end,
        orderedWindows = function() return {} end,
        focusedWindow = function() return focused end,
        filter = {
            new = function() return {subscribe = function(self) return self end, unsubscribe = function() end, getWindows = function() return {} end} end,
            windowCreated = "windowCreated",
        },
    },
    screen = {allScreens = function() return screens end},
    mouse = {absolutePosition = function() return {x = pointer.x, y = pointer.y} end},
    axuielement = {
        systemElementAtPosition = function(x, y)
            axCalls = axCalls + 1
            return axAt(x, y)
        end,
        systemWideElement = function()
            return {
                attributeValue = function(_, name)
                    if name == "AXFocusedUIElement" then return axFocusedElement end
                end,
            }
        end,
    },
    eventtap = {
        checkMouseButtons = function() return buttons end,
        checkKeyboardModifiers = function() return modifiers end,
        event = {types = {
            mouseMoved = "mouseMoved",
            leftMouseDown = "leftMouseDown",
            rightMouseDown = "rightMouseDown",
            otherMouseDown = "otherMouseDown",
            flagsChanged = "flagsChanged",
        }},
        new = function(_, fn)
            local tap = {fn = fn, enabled = false}
            function tap:start() self.enabled = true return self end
            function tap:stop() self.enabled = false return self end
            function tap:isEnabled() return self.enabled end
            taps[#taps + 1] = tap
            return tap
        end,
    },
}

local F = dofile("config/focus.lua")
local left = makeWindow(1)
local right = makeWindow(2)
local back = makeWindow(3)

local function rect(x, y, w, h) return {x = x, y = y, w = w, h = h} end
assert(F.contains(rect(0, 25, 100, 100), {x = 0, y = 25}), "top-left corner belongs to the window")
assert(not F.contains(rect(0, 25, 100, 100), {x = 100, y = 25}), "right edge belongs to the next window")
assert(F.windowAt({x = 10, y = 10}, {
    {id = 1, frame = rect(0, 0, 50, 50), allowed = true},
    {id = 2, frame = rect(0, 0, 50, 50), allowed = true},
}).id == 1, "front window wins an overlap")
assert(F.windowAt({x = 10, y = 10}, {
    {id = 9, frame = rect(0, 0, 50, 50), allowed = false},
    {id = 1, frame = rect(0, 0, 50, 50), allowed = true},
}) == nil, "an overlay hides the window behind it")
assert(F.windowAt({x = 1200, y = 40}, {
    {id = 1, frame = rect(0, 25, 900, 700)},
    {id = 2, frame = rect(1000, 25, 900, 700)},
}).id == 2, "the monitor under the pointer supplies the window")
assert(F.windowAt({x = 4, y = 40}, {
    {id = 1, frame = rect(8, 25, 400, 700)},
}) == nil, "a gap between tiles changes nothing")

local areas = {rect(0, 25, 1000, 775), rect(1000, 25, 1000, 775)}
assert(not F.inWorkingArea({x = 10, y = 4}, areas), "menu bar is outside the working area")
assert(not F.inWorkingArea({x = 10, y = 820}, areas), "Dock is outside the working area")
assert(F.inWorkingArea({x = 1400, y = 40}, areas), "each display has its own working area")
assert(F.decide(nil, nil, {x = 10, y = 4}, {{id = 1, frame = rect(0, 0, 1000, 1000), allowed = true}}, false, areas) == "drop",
    "menu bar does not steal focus")
assert(F.decide(1, nil, {x = 20, y = 40}, {{id = 1, frame = rect(0, 25, 400, 400), allowed = true}}, false, areas) == "drop",
    "the focused window is left alone")
assert(F.decide(1, nil, {x = 20, y = 40}, {{id = 2, frame = rect(0, 25, 400, 400), allowed = true}}, true, areas) == "drop",
    "a paused pointer does not arm focus")
local action, id = F.decide(1, nil, {x = 20, y = 40}, {{id = 2, frame = rect(0, 25, 400, 400), allowed = true}}, false, areas)
assert(action == "arm" and id == 2, "a new window under the pointer arms focus")
assert(F.decide(1, 2, {x = 20, y = 40}, {{id = 2, frame = rect(0, 25, 400, 400), allowed = true}}, false, areas) == "wait",
    "staying on the pending window keeps the original delay")
assert(F.confirm(2, 1, {x = 20, y = 40}, {{id = 2, frame = rect(0, 25, 400, 400), allowed = true}}, false, areas) == 2,
    "the delay focuses the window that is still under the pointer")
assert(F.confirm(2, 1, {x = 800, y = 40}, {{id = 2, frame = rect(0, 25, 400, 400), allowed = true}}, false, areas) == nil,
    "leaving the window before the delay cancels it")
assert(F.confirm(2, 1, {x = 20, y = 40}, {{id = 2, frame = rect(0, 25, 400, 400), allowed = true}}, true, areas) == nil,
    "a pause at the end of the delay cancels it")

local stacked = F.stack({
    cg(8, 0, 25, 400, 300, {kCGWindowAlpha = 0}),
    cg(9, 0, 25, 80, 40, {kCGWindowLayer = 3}),
    cg(2, 0, 25, 400, 300),
    cg(1, 0, 25, 400, 300),
}, {[1] = left, [2] = right})
assert(F.windowAt({x = 10, y = 40}, stacked) == nil, "a menu-level window blocks the window below")
assert(F.windowAt({x = 100, y = 40}, stacked).id == 2, "a transparent window does not hide the window below")
assert(stacked[#stacked].window == left, "stack keeps the window object needed to focus")

local behindCursor = F.stack({
    cg(99, 1390, 150, 57, 81, {kCGWindowLayer = 2147483630}),
    cg(2, 0, 25, 1920, 1080),
}, {[2] = right})
assert(F.windowAt({x = 1407, y = 165}, behindCursor).id == 2, "the cursor window is not a focus target")
assert(F.windowAt({x = 10, y = 40}, F.stack({
    cg(7, 0, 25, 80, 40, {kCGWindowLayer = 999}),
    cg(2, 0, 25, 400, 300),
}, {[2] = right})) == nil, "an overlay below the cursor level still blocks")
assert(not F.moved({x = 10, y = 10}, {x = 17, y = 10}), "a move under 8 px stays settled")
assert(F.moved({x = 10, y = 10}, {x = 18, y = 10}), "an 8 px move counts")
assert(F.moved(nil, {x = 1, y = 1}), "a missing point counts as movement")

local function axElement(role, parent, x, y, w, h)
    local element = {role = role, parent = parent, x = x, y = y, w = w, h = h, writes = 0, children = {}}
    if parent then parent.children[#parent.children + 1] = element end
    function element:attributeValue(name)
        if name == "AXRole" then return self.role end
        if name == "AXParent" then return self.parent end
        if name == "AXChildren" then return self.children end
        if name == "AXPosition" then return {x = self.x, y = self.y} end
        if name == "AXSize" then return {w = self.w, h = self.h} end
    end
    function element:setAttributeValue(name, value)
        assert(name == "AXFocused" and value == true)
        self.writes = self.writes + 1
        if self.accepts ~= false then axFocusedElement = self end
    end
    return element
end

local windowEl = axElement("AXWindow", nil, 0, 25, 500, 700)
local group = axElement("AXGroup", windowEl, 0, 80, 500, 600)
local body = axElement("AXStaticText", group, 100, 200, 80, 20)
local address = axElement("AXTextField", windowEl, 80, 36, 400, 28)
local combo = axElement("AXComboBox", windowEl, 80, 36, 400, 28)
assert(F.textField(address) == address, "an address bar is a text field")
assert(F.textField(combo) == combo, "a combo box is a text field")
assert(F.textField(body) == nil, "page text is not a text field")
local page = axElement("AXWebArea", windowEl, 0, 80, 500, 600)
local pageGroup = axElement("AXGroup", page, 0, 80, 500, 600)
local input = axElement("AXTextField", pageGroup, 40, 300, 200, 24)
axElement("AXTextField", pageGroup, 40, 400, 200, 24)
assert(F.textAt(page, {x = 50, y = 310}) == input, "a page input under the pointer is found")
assert(F.textAt(page, {x = 50, y = 200}) == nil, "a page input elsewhere is not the target")
local clear = axElement("AXButton", address, 450, 40, 16, 16)
assert(F.textAt(clear, {x = 455, y = 48}) == nil, "a button inside the address bar is not clicked")
assert(F.textAt(address, {x = 100, y = 50}) == address, "the address bar text itself is the target")

local function screen(frame)
    return {frame = function() return frame end}
end
screens = {screen(areas[1]), screen(areas[2])}
local filter = {getWindows = function() return {left, right, back} end}
local function bounds(id)
    for _, entry in ipairs(listed) do
        if entry.kCGWindowNumber == id then return entry.kCGWindowBounds end
    end
end

local function reset()
    -- The acceptance window is internal. Let it expire so a cleared
    -- focused window is not still treated as focused.
    advance(0.06)
    changing, creating, suspended, missionOpen = false, false, false, false
    buttons, modifiers, focused = {}, {}, nil
    left.n, right.n, back.n = 0, 0, 0
    listed = {
        cg(1, 0, 25, 500, 700),
        cg(2, 1000, 25, 500, 700),
        cg(3, 0, 25, 500, 700),
    }
end

local function event(kind, x, y, flags)
    return {
        getType = function() return kind end,
        getFlags = function() return flags or {} end,
        location = function() return {x = x, y = y} end,
    }
end

local function move(x, y, flags)
    pointer.x, pointer.y = x, y
    taps[#taps].fn(event("mouseMoved", x, y, flags))
end

hs.eventtap.leftClick = function(point)
    fieldClicks = fieldClicks + 1
    taps[#taps].fn(event("leftMouseDown", point.x, point.y))
end

reset()
F.start({filter = filter, suspended = function() return suspended end})
assert(taps[1]:isEnabled(), "pointer watcher is running")
move(20, 40)
advance(0)
assert(left.n == 0, "hover does not focus immediately")
advance(0.05)
assert(left.n == 0, "focus waits out the full delay")
advance(0.05)
assert(left.n == 1 and focused == left, "resting on a window focuses it")
move(30, 50)
advance(0.2)
assert(left.n == 1, "moving inside the focused window does not focus again")

reset()
move(20, 40)
advance(0)
bounds(1).X = 800
advance(0.1)
assert(left.n == 0, "a window that moves away during the delay is not focused")

reset()
move(20, 40)
move(1200, 40)
advance(0)
advance(0.1)
assert(left.n == 0 and right.n == 1, "a burst of movement focuses only the latest window")

reset()
move(20, 40)
advance(0)
move(1200, 40)
advance(0)
advance(0.05)
assert(left.n == 0 and right.n == 0, "switching windows restarts the delay")
advance(0.05)
assert(right.n == 1 and left.n == 0, "the window under the pointer at the end of the delay wins")

reset()
listed = {cg(3, 0, 25, 500, 700)}
move(20, 40)
advance(0)
table.insert(listed, 1, cg(1, 0, 25, 500, 700))
move(30, 50)
advance(0)
advance(0.1)
assert(left.n == 1 and back.n == 0, "a window that covers the pointer takes the pending focus")

reset()
move(20, 40, {cmd = true})
advance(0.2)
assert(left.n == 0, "Command keeps the current focus")
move(20, 40)
advance(0)
taps[#taps].fn(event("flagsChanged", 20, 40, {cmd = true}))
advance(0.2)
assert(left.n == 0, "pressing Command cancels a pending focus")
modifiers = {}
taps[#taps].fn(event("flagsChanged", 20, 40, {}))
advance(0.1)
assert(left.n == 1, "releasing Command focuses the window still under the pointer")

reset()
move(20, 40)
advance(0)
buttons.left = true
taps[#taps].fn(event("leftMouseDown", 20, 40))
advance(0.2)
assert(left.n == 0, "a mouse button cancels a pending focus")

reset()
suspended = true
move(20, 40)
advance(0.2)
assert(left.n == 0, "window cycling keeps its own target")

reset()
move(20, 40)
advance(0)
changing = true
advance(0.2)
assert(left.n == 0, "a desktop transition is left alone")

reset()
move(20, 40)
advance(0)
creating = true
advance(0.2)
assert(left.n == 0, "desktop creation is left alone")

reset()
move(20, 40)
advance(0)
missionOpen = true
advance(0.2)
assert(left.n == 0, "Mission Control is left alone")

reset()
listed[1].kCGWindowBounds.Y = 0
listed[1].kCGWindowBounds.Height = 900
move(20, 4)
advance(0.2)
assert(left.n == 0, "the menu bar does not focus the window below it")
move(20, 820)
advance(0.2)
assert(left.n == 0, "the Dock does not focus the window below it")
listed[1].kCGWindowBounds.X = 8
move(4, 40)
advance(0.2)
assert(left.n == 0, "empty desktop and tile gaps do not change focus")

reset()
listed[1] = cg(9, 0, 25, 500, 700, {kCGWindowLayer = 8})
table.insert(listed, 2, cg(1, 0, 25, 500, 700))
move(20, 40)
advance(0.2)
assert(left.n == 0, "a popup over the window is not looked through")

reset()
focused = left
move(20, 40)
advance(0.2)
assert(left.n == 0, "hovering the already focused window does not activate it again")

local first = taps[#taps]
F.start({filter = filter, suspended = function() return suspended end})
assert(not first:isEnabled() and taps[#taps]:isEnabled(), "reloading replaces the previous watcher")
F.stop()
assert(not taps[#taps]:isEnabled(), "stopping releases the watcher")

F.start({filter = filter, suspended = function() return suspended end})

reset()
focused = left
address.writes = 0
axFocusedElement = nil
axAt = function() return address end
move(100, 50)
advance(0.2)
assert(left.n == 0, "an already focused window is not activated for its address bar")
assert(address.writes == 1 and fieldClicks == 0, "resting on the address bar moves the keyboard into it")
move(104, 53)
advance(0.2)
assert(address.writes == 1, "a tiny move does not focus the address bar again")
move(130, 50)
advance(0.2)
assert(address.writes == 1 and left.n == 0, "the address bar is not focused again once it has the keyboard")

reset()
address.writes = 0
axFocusedElement = nil
axAt = function() return address end
move(100, 50)
advance(0)
advance(0.1)
assert(left.n == 1 and address.writes == 0, "the address bar waits until the window is key")
advance(0.06)
assert(address.writes == 1, "the address bar receives the keyboard after the window")

reset()
address.writes = 0
axFocusedElement = nil
local seen = 0
axAt = function()
    seen = seen + 1
    if seen == 1 then return nil end
    return address
end
move(220, 80)
advance(0)
advance(0.1)
advance(0.06)
assert(left.n == 1 and address.writes == 0 and seen == 1, "a late address bar is not missed on the first look")
advance(0.12)
assert(address.writes == 1 and seen == 2, "the address bar is focused on the second look")

reset()
focused = left
address.writes, body.writes = 0, 0
axFocusedElement = nil
axAt = function() return body end
move(120, 210)
advance(0.2)
assert(address.writes == 0 and body.writes == 0 and left.n == 0, "page text does not take the keyboard")

reset()
focused = left
address.writes = 0
axFocusedElement = nil
axAt = function() return address end
missionOpen = true
move(100, 50)
advance(0.2)
assert(address.writes == 0 and left.n == 0, "Mission Control does not move the keyboard into a field")

reset()
focused = left
address.writes = 0
axFocusedElement = nil
axAt = function() return address end
move(100, 50)
advance(0)
modifiers.cmd = true
advance(0.2)
assert(address.writes == 0 and left.n == 0, "Command does not move the keyboard into a field")

reset()
address.writes = 0
axFocusedElement = nil
axAt = function() return address end
move(100, 50)
advance(0)
bounds(1).X = 800
advance(0.2)
assert(left.n == 0 and address.writes == 0, "a window that leaves does not take the address bar")

reset()
focused = left
local stubborn = axElement("AXTextField", windowEl, 80, 60, 400, 28)
stubborn.accepts = false
stubborn.writes = 0
fieldClicks = 0
axFocusedElement = nil
axAt = function() return stubborn end
move(120, 70)
advance(0.2)
assert(stubborn.writes == 1 and fieldClicks == 1 and left.n == 0,
    "a field that ignores accessibility focus is clicked once")
move(123, 72)
advance(0.2)
assert(fieldClicks == 1, "that click does not arm another click")

F.stop()

-- The toggle is remembered, and a missing or unreadable file means off.
local settingsPath = os.tmpname()
os.remove(settingsPath)
F._settingsFile = settingsPath
F.configure({filter = filter, suspended = function() return suspended end})
assert(F.loadEnabled() == false, "focus follows the pointer is off when never configured")
local on, saved = F.setEnabled(true, true)
assert(on == true and saved == true and F.loadEnabled() == true, "enabling is remembered")
assert(taps[#taps]:isEnabled(), "enabling starts the pointer watcher")
local off = F.setEnabled(false, true)
assert(off == false and F.loadEnabled() == false and not taps[#taps]:isEnabled(),
    "disabling stops the watcher and is remembered")
assert(F.toggle() == true and taps[#taps]:isEnabled(), "the toggle turns focus following on")
assert(F.toggle() == false and not taps[#taps]:isEnabled(), "the toggle turns focus following off")
local settingsFile = io.open(settingsPath, "w")
settingsFile:write("maybe\n")
settingsFile:close()
assert(F.loadEnabled() == false, "an unknown saved value falls back to off")
os.remove(settingsPath)
F._settingsFile = nil
print("PASS: focus follows the pointer")
