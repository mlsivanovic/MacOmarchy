-- Use real Dock transitions, not just WindowServer's current-Space metadata.
-- Native shortcuts may be customized: read their actual keycodes and full flags.
local D = { busy = false, moves = {} }
local missionControl=require("mission-control")
local mouseOrigin, placedMouse
local drainNavigation
function D.settle()
    D.settleUntil=hs.timer.secondsSinceEpoch()+0.15
end
function D.isChanging()
    return D.busy or D.transfer or next(D.moves)~=nil
        or hs.timer.secondsSinceEpoch()<(D.settleUntil or 0)
end
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
            if not done then hs.alert.show("macOS did not move the window to the selected desktop.") end
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

local function nativeShortcut(direction, preferences)
    local id = direction == "left" and "79" or "81"
    local entry = preferences and preferences.AppleSymbolicHotKeys and preferences.AppleSymbolicHotKeys[id]
    local params = entry and entry.value and entry.value.parameters
    if not entry or not entry.enabled or not params then return nil end
    return { keycode = params[2], flags = params[3] }
end

local function focusScreen(screen)
    -- The native shortcut acts on the display under the pointer, so the
    -- pointer must be on the target display -- but only move it when it is
    -- not already there, and only scan/focus windows when focus must move.
    local focused = hs.window.focusedWindow()
    local focusedHere = sameScreen(focused and focused:screen(), screen)
    if not sameScreen(hs.mouse.getCurrentScreen(), screen) then
        mouseOrigin = mouseOrigin or hs.mouse.absolutePosition()
        local frame = screen:frame()
        placedMouse = {x=frame.x+frame.w/2,y=frame.y+frame.h/2}
        hs.mouse.absolutePosition(placedMouse)
    end
    if focusedHere then return false end
    for _, window in ipairs(hs.window.orderedWindows()) do
        if window:isStandard() and window:isVisible() and sameScreen(window:screen(), screen) then
            window:focus()
            return true
        end
    end
    -- No visible window exists here. Click the empty desktop to give this
    -- monitor keyboard focus; the 2px edge lies outside the 4px tiled margin.
    mouseOrigin = mouseOrigin or hs.mouse.absolutePosition()
    local frame = screen:frame()
    placedMouse = {x=frame.x+2, y=frame.y+frame.h/2}
    hs.eventtap.leftClick(placedMouse)
    return true
end

local function finish(errorMessage)
    D.busy = false
    D.destination=nil
    D.settle()
    local completion=D.completion;D.completion=nil
    if D.timer then D.timer:stop(); D.timer=nil end
    if D.keyTimer then D.keyTimer:stop();D.keyTimer=nil end
    if mouseOrigin and placedMouse then
        local current = hs.mouse.absolutePosition()
        if math.abs(current.x-placedMouse.x)<4 and math.abs(current.y-placedMouse.y)<4 then
            hs.mouse.absolutePosition(mouseOrigin)
        end
    end
    mouseOrigin, placedMouse = nil, nil
    if errorMessage then hs.alert.show(errorMessage) end
    if D.afterChange then D.afterChange() end
    if errorMessage and D.queued then
        local queued=D.queued;D.queued=nil
        if queued.completion then queued.completion(false) end
    end
    if completion then completion(not errorMessage) end
    drainNavigation()
end

drainNavigation=function()
    if D.busy or D.transfer or not D.queued then return end
    local request=D.queued;D.queued=nil
    D.goToID(request.screen,request.target,request.completion)
end

-- Cache shortcut preferences by plist mtime; without hs.fs (tests) the
-- cache never engages and every transition reads the file as before.
local cachedPreferences, cachedPreferencesMtime
local function readPreferences()
    local path=os.getenv("HOME") .. "/Library/Preferences/com.apple.symbolichotkeys.plist"
    local mtime=nil
    if hs.fs and hs.fs.attributes then
        local ok, attrs=pcall(hs.fs.attributes, path)
        if ok and attrs then mtime=attrs.modification end
    end
    if mtime and cachedPreferences and cachedPreferencesMtime==mtime then
        return cachedPreferences
    end
    local ok, preferences=pcall(hs.plist.read, path)
    if not ok then return nil end
    if mtime then cachedPreferences, cachedPreferencesMtime=preferences, mtime end
    return preferences
end

function D.goToID(screen, target, completion, transferOwner)
    if not screen then return false end
    if D.busy or (D.transfer and not transferOwner) then
        -- Preserve the latest intent instead of silently swallowing input.
        local replaced=D.queued
        D.queued={screen=screen,target=target,completion=completion}
        if replaced and replaced.completion then replaced.completion(false) end
        return true
    end
    if hs.spaces.activeSpaceOnScreen(screen) == target then
        if completion then completion(true) end
        return true
    end
    local all = hs.spaces.spacesForScreen(screen) or {}
    local targetIndex
    for i,id in ipairs(all) do if id == target then targetIndex=i end end
    if not targetIndex then return false end
    -- Read preferences before marking busy so a failure cannot wedge D.busy.
    local preferences=readPreferences()
    if not preferences then
        if completion then completion(false) end
        return false
    end
    D.busy = true
    D.destination={screen=screen,target=target}
    D.completion=completion
    local attempts, pendingSpace, deadline = 0, nil, 0
    local function step()
        local current = hs.spaces.activeSpaceOnScreen(screen)
        if current == target then finish(); return end
        if pendingSpace then
            if current == pendingSpace then pendingSpace=nil
            elseif hs.timer.secondsSinceEpoch() < deadline then return
            else finish("Native desktop switching failed on the selected display."); return end
        end
        local currentIndex
        for i,id in ipairs(all) do if id == current then currentIndex=i end end
        if not currentIndex or attempts >= #all+1 then finish("The desktop is no longer available."); return end
        local delta = currentIndex < targetIndex and 1 or -1
        local shortcut = nativeShortcut(delta == 1 and "right" or "left",preferences)
        if not shortcut then finish("Enable Move left/right a space in macOS Keyboard → Mission Control."); return end
        local changedFocus=focusScreen(screen)
        pendingSpace = all[currentIndex+delta]
        deadline = hs.timer.secondsSinceEpoch()+2
        attempts = attempts+1
        -- Fn/numeric-pad flags are part of the saved native arrow shortcut.
        -- keyStroke only sends the named modifiers and can fail to match it.
        D.keyTimer=hs.timer.doAfter(changedFocus and 0.15 or 0,function()
            D.keyTimer=nil
            if not D.busy then return end
            hs.eventtap.event.newKeyEvent({},shortcut.keycode,true):rawFlags(shortcut.flags):post()
            hs.eventtap.event.newKeyEvent({},shortcut.keycode,false):rawFlags(shortcut.flags):post()
        end)
    end
    D.timer = hs.timer.doEvery(0.04, step)
    step()
    return true
end

function D.goToNumber(number, screen)
    screen = screen or D.keyboardScreen()
    local target = D.userSpaces(screen)[number]
    if not target then hs.alert.show("This display does not have Desktop " .. number); return false end
    return D.goToID(screen, target)
end

-- One Cmd+scroll moves one desktop. A notch is a burst of wheel events, so
-- further events are swallowed for a full second after the accepted one.
-- The window is anchored, not sliding: events inside it do not extend it,
-- so a continuous scroll advances again once the second has elapsed.
-- Sub-point fragments accumulate instead of being discarded, so a slow
-- precise scroll still crosses the threshold. Returns direction, consume.
function D.scrollGesture(state, now, line, point, momentum)
    line, point, momentum = line or 0, point or 0, momentum or 0
    if momentum ~= 0 then return nil, true end
    if line == 0 and point == 0 then return nil, false end
    if state.last and now - state.last < 1 then return nil, true end
    if line == 0 then
        state.acc = (state.acc or 0) + point
        if math.abs(state.acc) < 1 then return nil, true end
        point, state.acc = state.acc, 0
    end
    state.last = now
    local delta = line ~= 0 and line or point
    return (delta < 0) and 1 or -1, true
end

function D.cycle(direction, screen)
    screen = screen or hs.mouse.getCurrentScreen()
    local list = D.userSpaces(screen)
    if #list < 2 then return false end
    local index = 1
    local intended=D.queued or D.destination
    local current = intended and sameScreen(intended.screen,screen) and intended.target
        or hs.spaces.activeSpaceOnScreen(screen)
    for i,id in ipairs(list) do if id==current then index=i; break end end
    return D.goToID(screen, list[((index-1+direction)%#list)+1])
end

-- Create missing local user desktops in order, verify each addition before
-- requesting another, and close Mission Control once for the whole batch.
function D.ensureNumber(number, screen, callback)
    if type(number)~="number" or number%1~=0 or number<1 or number>9 then
        callback(nil,"The desktop number must be 1–9.");return false
    end
    local target=D.userSpaces(screen)[number]
    if target then callback(target);return true end
    -- Serialize creations: parallel calls share D.creationTimer, so a second
    -- call must queue instead of overwriting the first call's timer.
    if D.creating then
        D.creationQueue=D.creationQueue or {}
        D.creationQueue[#D.creationQueue+1]={number=number,screen=screen,callback=callback}
        return true
    end
    D.creating=true
    local pendingCount,deadline=nil,0
    local readyDeadline=hs.timer.secondsSinceEpoch()+3
    local completed=false
    local function complete(id,errorMessage)
        if completed then return end
        completed=true
        if D.creationTimer then D.creationTimer:stop();D.creationTimer=nil end
        missionControl.close()
        D.creationFinish=hs.timer.doAfter(0.2,function()
            D.creationFinish=nil
            D.creating=nil
            callback(id,errorMessage)
            local queue=D.creationQueue
            if queue and #queue>0 then
                local nextRequest=table.remove(queue,1)
                D.ensureNumber(nextRequest.number,nextRequest.screen,nextRequest.callback)
            end
        end)
    end
    -- A throwing open must release the caller's transfer lock, not wedge it.
    local openOk, openErr=pcall(missionControl.open)
    if not openOk then complete(nil,tostring(openErr));return true end
    local function step()
        local list=D.userSpaces(screen)
        if list[number] then complete(list[number]);return end
        if pendingCount then
            if #list>pendingCount then pendingCount=nil
            elseif hs.timer.secondsSinceEpoch()<deadline then return
            else complete(nil,"macOS did not create a new desktop on this display.");return end
        end
        local called,ok,err=pcall(missionControl.add,screen)
        if called and not ok and err=="pending" then
            if hs.timer.secondsSinceEpoch()>=readyDeadline then complete(nil,"Mission Control did not show the selected display.") end
            return
        end
        if not called or not ok then complete(nil,tostring(err or ok or "The desktop was not created."));return end
        pendingCount=#list
        deadline=hs.timer.secondsSinceEpoch()+3
        readyDeadline=deadline
    end
    D.creationTimer=hs.timer.doEvery(0.1,step)
    step()
    return true
end

function D.moveWindow(number)
    if D.busy or D.transfer then hs.alert.show("Wait for the desktop transition to finish.");return false end
    local window = hs.window.focusedWindow()
    if not window or not window:isStandard() or window:isFullScreen() then
        hs.alert.show("Select a standard window to move."); return false
    end
    local screen = window:screen()
    D.transfer=true
    local function done(ok)
        D.transfer=false
        D.settle()
        if ok then window:focus() end
        if D.afterChange then D.afterChange() end
        drainNavigation()
    end
    return D.ensureNumber(number,screen,function(target,errorMessage)
        if not target then
            hs.alert.show(errorMessage);done(false);return
        end
        if hs.spaces.activeSpaceOnScreen(screen)==target then done(true);return end
        local started=D.moveToSpace(window,target,function(moved)
            if not moved then done(false);return end
            if not D.goToID(screen,target,done,true) then done(false) end
        end)
        if not started then D.transfer=false end
    end)
end

return D
