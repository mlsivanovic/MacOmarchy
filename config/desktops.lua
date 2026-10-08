-- Use real Dock transitions, not just WindowServer's current-Space metadata.
-- Native shortcuts may be customized: read their actual keycodes and full flags.
local D = { busy = false, moves = {} }
local mouseOrigin, placedMouse
local loader = package.loadlib(os.getenv("HOME") .. "/.hammerspoon/bin/space-move.so", "luaopen_space_move")
local bridgedMove = loader and loader()
function D.moveToSpace(window, target, callback)
    local id = type(window)=="number" and window or window:id()
    if D.moves[id] then D.moves[id]:stop();D.moves[id]=nil end
    local started = bridgedMove and bridgedMove(id,target)
    if not started then started=hs.spaces.moveWindowToSpace(id,target) end
    if not started then if callback then callback(false) end;return false end
    local checks,timer=0,nil
    timer=hs.timer.doEvery(0.1,function()
        checks=checks+1
        local done=false
        for _,space in ipairs(hs.spaces.windowSpaces(id) or {}) do if space==target then done=true end end
        if done or checks>=20 then
            timer:stop();D.moves[id]=nil
            if not done then hs.alert.show("macOS nije premestio prozor na izabrani desktop.") end
            if callback then callback(done) end
        end
    end)
    D.moves[id]=timer
    return true
end
local function sameScreen(a, b) return a and b and a:id() == b:id() end

function D.userSpaces(screen)
    local out = {}
    for _, id in ipairs(hs.spaces.spacesForScreen(screen) or {}) do
        if hs.spaces.spaceType(id) == "user" then table.insert(out, id) end
    end
    return out
end

function D.keyboardScreen()
    local window = hs.window.focusedWindow()
    return (window and window:screen()) or hs.mouse.getCurrentScreen() or hs.screen.mainScreen()
end

local function nativeShortcut(direction)
    local preferences = hs.plist.read(os.getenv("HOME") .. "/Library/Preferences/com.apple.symbolichotkeys.plist")
    local id = direction == "left" and "79" or "81"
    local entry = preferences and preferences.AppleSymbolicHotKeys and preferences.AppleSymbolicHotKeys[id]
    local params = entry and entry.value and entry.value.parameters
    if not entry or not entry.enabled or not params then return nil end
    return { keycode = params[2], flags = params[3] }
end

local function focusScreen(screen)
    mouseOrigin = mouseOrigin or hs.mouse.absolutePosition()
    local frame = screen:frame()
    placedMouse = {x=frame.x+frame.w/2,y=frame.y+frame.h/2}
    hs.mouse.absolutePosition(placedMouse)
    local focused = hs.window.focusedWindow()
    if sameScreen(focused and focused:screen(), screen) then return end
    for _, window in ipairs(hs.window.orderedWindows()) do
        if window:isStandard() and window:isVisible() and sameScreen(window:screen(), screen) then
            window:focus()
            return
        end
    end
    -- No visible window exists here. Click the empty desktop to give this
    -- monitor keyboard focus; the 2px edge lies outside the 8px tiled margin.
    placedMouse = {x=frame.x+2, y=frame.y+frame.h/2}
    hs.eventtap.leftClick(placedMouse)
end

local function finish(errorMessage)
    D.busy = false
    if D.timer then D.timer:stop(); D.timer=nil end
    if mouseOrigin and placedMouse then
        local current = hs.mouse.absolutePosition()
        if math.abs(current.x-placedMouse.x)<4 and math.abs(current.y-placedMouse.y)<4 then
            hs.mouse.absolutePosition(mouseOrigin)
        end
    end
    mouseOrigin, placedMouse = nil, nil
    if errorMessage then hs.alert.show(errorMessage) end
    if D.afterChange then D.afterChange() end
end

function D.goToID(screen, target)
    if D.busy or not screen then return false end
    if hs.spaces.activeSpaceOnScreen(screen) == target then return true end
    local all = hs.spaces.spacesForScreen(screen) or {}
    local targetIndex
    for i,id in ipairs(all) do if id == target then targetIndex=i end end
    if not targetIndex then return false end
    D.busy = true
    local attempts, pendingSpace, deadline = 0, nil, 0
    local function step()
        local current = hs.spaces.activeSpaceOnScreen(screen)
        if current == target then finish(); return end
        if pendingSpace then
            if current == pendingSpace then pendingSpace=nil
            elseif hs.timer.secondsSinceEpoch() < deadline then return
            else finish("Native promena desktopa nije uspela na izabranom monitoru."); return end
        end
        local currentIndex
        for i,id in ipairs(all) do if id == current then currentIndex=i end end
        if not currentIndex or attempts >= #all+1 then finish("Desktop više nije dostupan."); return end
        local delta = currentIndex < targetIndex and 1 or -1
        local shortcut = nativeShortcut(delta == 1 and "right" or "left")
        if not shortcut then finish("Uključi Move left/right a space u macOS Keyboard → Mission Control."); return end
        focusScreen(screen)
        pendingSpace = all[currentIndex+delta]
        deadline = hs.timer.secondsSinceEpoch()+2
        attempts = attempts+1
        -- Fn/numeric-pad flags are part of the saved native arrow shortcut.
        -- keyStroke only sends the named modifiers and can fail to match it.
        D.keyTimer=hs.timer.doAfter(0.15,function()
            if not D.busy then return end
            hs.eventtap.event.newKeyEvent({},shortcut.keycode,true):rawFlags(shortcut.flags):post()
            hs.eventtap.event.newKeyEvent({},shortcut.keycode,false):rawFlags(shortcut.flags):post()
        end)
    end
    D.timer = hs.timer.doEvery(0.12, step)
    step()
    return true
end

function D.goToNumber(number, screen)
    screen = screen or D.keyboardScreen()
    local target = D.userSpaces(screen)[number]
    if not target then hs.alert.show("Na ovom monitoru ne postoji Desktop " .. number); return false end
    return D.goToID(screen, target)
end

function D.cycle(direction, screen)
    screen = screen or hs.mouse.getCurrentScreen()
    local list = D.userSpaces(screen)
    if #list < 2 then return false end
    if D.busy then return true end
    local index = 1
    local current = hs.spaces.activeSpaceOnScreen(screen)
    for i,id in ipairs(list) do if id==current then index=i; break end end
    return D.goToID(screen, list[((index-1+direction)%#list)+1])
end

function D.moveWindow(number)
    local window = hs.window.focusedWindow()
    if not window or not window:isStandard() or window:isFullScreen() then
        hs.alert.show("Izaberi običan prozor za premeštanje."); return false
    end
    local screen = window:screen()
    local target = D.userSpaces(screen)[number]
    if not target then hs.alert.show("Na ovom monitoru ne postoji Desktop " .. number); return false end
    if hs.spaces.activeSpaceOnScreen(screen)==target then return true end
    return D.moveToSpace(window,target,function(done)
        if done and D.afterChange then D.afterChange() end
    end)
end

return D
