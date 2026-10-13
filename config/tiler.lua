-- One owner of window geometry. Groups are native display UUID + active Space.
local desktops = require("desktops")
local E = {enabled=true, groups={}, floating={}, screens={}, targets={}, errors={}, attempts={}}
local layouts = {"tall", "wide", "fullscreen", "floating"}
local excluded = { ["org.hammerspoon.Hammerspoon"]=true,
    ["com.apple.systempreferences"]=true, ["org.keepassxc.keepassxc"]=true }
local function key(screen, space) return screen:getUUID() .. ":" .. tostring(space) end
local function currentGroup()
    local w=hs.window.focusedWindow()
    local s=(w and w:screen()) or hs.mouse.getCurrentScreen() or hs.screen.mainScreen()
    if not s then return end
    local k=key(s,hs.spaces.activeSpaceOnScreen(s))
    E.groups[k]=E.groups[k] or {order={},layout="tall",ratio=0.5}
    return E.groups[k],s,w
end
local function onSpace(window, space)
    for _,id in ipairs(hs.spaces.windowSpaces(window) or {}) do if id==space then return true end end
    return false
end
local function manageable(w)
    if not w:isStandard() or w:isFullScreen() or w:isMinimized() or not w:isVisible() then return false end
    local app=w:application()
    if not app or app:isHidden() or excluded[app:bundleID()] or E.floating[w:id()] then return false end
    return true
end
local function different(a,b)
    return math.abs(a.x-b.x)>2 or math.abs(a.y-b.y)>2 or math.abs(a.w-b.w)>2 or math.abs(a.h-b.h)>2
end
local function rects(frame,n,layout,ratio)
    local gap=4
    local f={x=frame.x+gap,y=frame.y+gap,w=frame.w-2*gap,h=frame.h-2*gap}
    if n==1 or layout=="fullscreen" then
        local out={};for i=1,n do out[i]={x=f.x,y=f.y,w=f.w,h=f.h} end;return out
    end
    local out={}
    if layout=="wide" then
        local height=math.floor((f.h-gap)*ratio)
        out[1]={x=f.x,y=f.y,w=f.w,h=height}
        local width=(f.w-gap*(n-2))/(n-1)
        for i=2,n do out[i]={x=f.x+(i-2)*(width+gap),y=f.y+height+gap,w=width,h=f.h-height-gap} end
    else
        local width=math.floor((f.w-gap)*ratio)
        out[1]={x=f.x,y=f.y,w=width,h=f.h}
        local height=(f.h-gap*(n-2))/(n-1)
        for i=2,n do out[i]={x=f.x+width+gap,y=f.y+(i-2)*(height+gap),w=f.w-width-gap,h=height} end
    end
    return out
end

-- One pending pass merges bursts without indefinitely postponing work.
function E.schedule(delay)
    if E.pending then return end
    E.pending=hs.timer.doAfter(delay or 0.04,function()
        E.pending=nil
        E.reflow()
    end)
end

function E.forget(id)
    if not id then return end
    E.screens[id],E.floating[id],E.targets[id],E.errors[id],E.attempts[id]=nil,nil,nil,nil,nil
    for _,g in pairs(E.groups) do
        for i=#g.order,1,-1 do if g.order[i]==id then table.remove(g.order,i) end end
    end
    E.schedule()
end

function E.windowMoved(w)
    local id=w:id()
    if not id then return end
    local target=E.targets[id]
    local attempt=E.attempts[id]
    local frame=w:frame()
    -- Ignore our own AX notifications, including a constrained accepted size.
    if target and not different(frame,target) then return end
    if attempt and attempt.actual and not different(frame,attempt.actual) then return end
    E.schedule()
end

function E.reflow()
    if not E.enabled then return end
    if hs.eventtap.checkMouseButtons().left or (desktops.isChanging and desktops.isChanging()) then
        E.schedule(0.05)
        return
    end
    local buckets,active={},{}
    for _,screen in ipairs(hs.screen.allScreens()) do
        local space=hs.spaces.activeSpaceOnScreen(screen)
        active[screen:id()]=space
        if space then buckets[key(screen,space)]={screen=screen,windows={}} end
    end
    local windows=E.windowSource and E.windowSource() or hs.window.visibleWindows()
    for _,w in ipairs(windows) do
        local id=w:id()
        if id then
            local s=w:screen()
            if s then
                local previous=E.screens[id]
                E.screens[id]=s:id()
                local space=active[s:id()]
                local eligible=space and manageable(w)
                -- Dragging across displays must join that display's active Space.
                if previous and previous~=s:id() and eligible and not onSpace(w,space) then
                    desktops.moveToSpace(w,space,function() E.schedule() end)
                end
                if eligible and onSpace(w,space) then
                    local k=key(s,space)
                    buckets[k]=buckets[k] or {screen=s,windows={}}
                    buckets[k].windows[id]=w
                end
            end
        end
    end
    E.targets={}
    for k,bucket in pairs(buckets) do
        local g=E.groups[k] or {order={},layout="tall",ratio=0.5}
        E.groups[k]=g
        local order,present={},{}
        for _,id in ipairs(g.order) do
            if bucket.windows[id] then table.insert(order,id);present[id]=true end
        end
        local added={}
        for id in pairs(bucket.windows) do if not present[id] then table.insert(added,id) end end
        table.sort(added)
        for _,id in ipairs(added) do table.insert(order,id) end
        g.order=order
        if g.layout~="floating" and #order>0 then
            local frames=rects(bucket.screen:frame(),#order,g.layout,g.ratio)
            for i,id in ipairs(order) do
                local w,frame=bucket.windows[id],frames[i]
                E.targets[id]=frame
                local actual=w:frame()
                local attempt=E.attempts[id]
                if not attempt or different(attempt.target,frame)
                  or (attempt.actual and different(attempt.actual,actual)) then
                    attempt={target=frame,count=0}
                    E.attempts[id]=attempt
                end
                if different(actual,frame) and attempt.count<2 then
                    attempt.count=attempt.count+1
                    local ok,err=pcall(function() w:setFrame(frame,0) end)
                    attempt.actual=w:frame()
                    E.errors[id]=not ok and tostring(err) or nil
                end
            end
        end
    end
    -- Only active groups were reconciled. Inactive desktops keep their order;
    -- windowDestroyed removes known closed IDs even from inactive groups.
end

function E.setLayout(layout)
    local g=currentGroup();if not g then return end
    g.layout=layout;E.reflow();hs.alert.show(layout == "tall" and "Tall" or layout)
end
function E.cycle(delta)
    local g=currentGroup();if not g then return end
    local index=1;for i,l in ipairs(layouts) do if l==g.layout then index=i end end
    E.setLayout(layouts[((index-1+delta)%#layouts)+1])
end
function E.toggleFloat()
    local w=hs.window.focusedWindow();if not w then return end
    E.floating[w:id()]=not E.floating[w:id()];E.reflow()
    hs.alert.show(E.floating[w:id()] and "Floating window" or "Tiled window")
end
function E.toggle()
    E.enabled=not E.enabled;E.reflow();hs.alert.show(E.enabled and "Tiling enabled" or "Tiling disabled")
end
function E.showLayout()
    local g=currentGroup();hs.alert.show(E.enabled and (g and g.layout or "tall") or "Tiling disabled")
end
function E.resize(delta)
    local g=currentGroup();if not g then return end
    g.ratio=math.max(0.2,math.min(0.8,g.ratio+delta));E.reflow()
end
function E.swap(delta,main)
    local g,_,w=currentGroup();if not g or not w then return end
    for i,id in ipairs(g.order) do
        if id==w:id() then
            local target=main and 1 or (((i-1+delta)%#g.order)+1)
            g.order[i],g.order[target]=g.order[target],g.order[i];E.reflow();return
        end
    end
end
function E.moveMonitor(delta)
    local w=hs.window.focusedWindow();if not w then return end
    local screens=hs.screen.allScreens()
    table.sort(screens,function(a,b) return a:fullFrame().x<b:fullFrame().x end)
    for i,s in ipairs(screens) do
        if s:id()==w:screen():id() then
            w:moveToScreen(screens[((i-1+delta)%#screens)+1]);hs.timer.doAfter(0.3,E.reflow);return
        end
    end
end

E.commands={
    l=function() E.cycle(1) end, ["shift:l"]=function() E.cycle(-1) end,
    a=function() E.setLayout("tall") end,b=function() E.setLayout("tall") end,
    w=function() E.setLayout("wide") end,f=function() E.setLayout("fullscreen") end,
    ["shift:f"]=function() E.setLayout("floating") end,t=E.toggleFloat,["shift:t"]=E.toggle,
    i=E.showLayout,r=function() E.attempts={};E.reflow() end,m=function() E.swap(0,true) end,
    ["-"]=function() E.resize(-0.05) end,["="]=function() E.resize(0.05) end,
    ["shift:left"]=function() E.swap(-1) end,["shift:right"]=function() E.swap(1) end,
    ["shift:up"]=function() E.moveMonitor(-1) end,["shift:down"]=function() E.moveMonitor(1) end,
}
-- Events drive normal work; this slower scan recovers missed notifications.
E.timer=hs.timer.doEvery(2,function()
    E.windowSource=nil
    E.reflow()
    E.windowSource=E.cachedWindowSource
end)
E.reflow()
return E
