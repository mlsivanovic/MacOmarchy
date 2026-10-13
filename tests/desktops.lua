local alerts={}
local timerAPI,advance=dofile("tests/timers.lua")()
local screens={}
local function screen(id,x,spaces,active)
    local s={sid=id,x=x,spaces=spaces,active=active}
    function s:id() return self.sid end
    function s:frame() return {x=self.x,y=30,w=1000,h=800} end
    screens[#screens+1]=s;return s
end
local left=screen(1,0,{10,11,12},10)
local right=screen(2,1000,{20,21},20)
local pointer={x=1200,y=200}
local w={s=left,space=10}
function w:screen() return self.s end
function w:id() return 99 end
function w:isStandard() return true end
function w:isFullScreen() return false end
function w:isVisible() return true end
local focusCount=0
function w:focus() focusCount=focusCount+1 end
local focused=w
local posted={}
local shortcutsWork=true
local preferenceReads=0
local function drain() advance(10) end
local originalLoadlib=package.loadlib
local moveWorks=true
local creationWorks=true
local additions=0
local closedMC=0
local nextID=100
package.loadlib=function() return function() return function(_,space) if moveWorks then w.space=space end;return true end end end
hs={
    spaces={
        spacesForScreen=function(s) return s.spaces end,
        spaceType=function(id) return id==11 and 'fullscreen' or 'user' end,
        activeSpaceOnScreen=function(s) return s.active end,
        windowSpaces=function() return {w.space} end,
        addSpaceToScreen=function(s,close)
            assert(close==false,'batch keeps Mission Control open')
            additions=additions+1
            if creationWorks then nextID=nextID+1;s.spaces[#s.spaces+1]=nextID end
            return true
        end,
        closeMissionControl=function() closedMC=closedMC+1 end,
    },
    window={focusedWindow=function() return focused end,orderedWindows=function() return {w} end},
    mouse={getCurrentScreen=function() return pointer.x>=1000 and right or left end,
        absolutePosition=function(p) if p then pointer={x=p.x,y=p.y} end;return pointer end},
    screen={mainScreen=function() return left end},
    plist={read=function() preferenceReads=preferenceReads+1;return {AppleSymbolicHotKeys={
        ['79']={enabled=true,value={parameters={65535,123,11534336}}},
        ['81']={enabled=true,value={parameters={65535,124,11534336}}},
    }} end},
    eventtap={leftClick=function() end,event={newKeyEvent=function(_,code,down)
        local event={}
        function event:rawFlags(flags) self.flags=flags;return self end
        function event:post()
            posted[#posted+1]={flags=self.flags,code=code,down=down}
            if down and shortcutsWork then
                local s=pointer.x>=1000 and right or left
                for i,id in ipairs(s.spaces) do if id==s.active then s.active=s.spaces[i+(code==124 and 1 or -1)];break end end
            end
        end
        return event
    end}},
    timer=timerAPI,
    alert={show=function(message) alerts[#alerts+1]=message end}
}
package.loaded['mission-control']={open=function() end,close=hs.spaces.closeMissionControl,add=function(s) return hs.spaces.addSpaceToScreen(s,false) end}
local D=dofile('config/desktops.lua');package.loadlib=originalLoadlib
assert(D.keyboardScreen()==left,'keyboard follows focused window, not pointer')
local list=D.userSpaces(left);assert(#list==2 and list[2]==12,'local numbering excludes fullscreen Space')
assert(D.goToNumber(2));drain()
assert(left.active==12 and right.active==20,'only selected monitor changes, across fullscreen Space')
assert(posted[1].flags==11534336,'native customized modifier flags preserved')
assert(pointer.x==1200 and pointer.y==200,'pointer restored after switching')
assert(not D.goToNumber(3,left) and #alerts==1,'nonexistent local number rejected')
assert(D.cycle(1,left));drain();assert(left.active==10,'scroll wraps existing user desktops')
assert(D.moveWindow(2));drain()
assert(w.space==12 and left.active==12 and right.active==20,'move follows target on same monitor')
assert(focusCount>0 and not D.transfer,'focus moved window after arrival and release operation')
assert(D.moveWindow(5));drain()
local target=D.userSpaces(left)[5]
assert(additions==3 and #D.userSpaces(left)==5,'create every missing local desktop up to requested number')
assert(w.space==target and left.active==target and right.active==20,'create then move then follow; other monitor unchanged')
assert(closedMC==1,'close Mission Control once for batch')
local additionsBefore=additions
assert(D.moveWindow(5));drain();assert(additions==additionsBefore,'existing destination does not create duplicate desktops')
creationWorks=false
assert(D.moveWindow(6));drain()
assert(not D.transfer and additions==additionsBefore+1 and #alerts==2,'silent creation failure stops without endless desktop creation')
assert(w.space==target and left.active==target,'failed creation leaves window and view in place')
moveWorks=false;w.space=10
local result
D.moveToSpace(w,12,function(ok) result=ok end);drain()
assert(result==false and #alerts==3,'verify actual membership and report silent API failure')
focused=nil;assert(D.keyboardScreen()==right,'empty desktop falls back to pointer monitor')
focused=w;moveWorks=true;creationWorks=true
left.active=10;w.space=10
assert(D.goToNumber(2,left))
assert(D.goToNumber(3,left))
assert(D.goToNumber(4,left))
drain()
assert(left.active==D.userSpaces(left)[4] and not D.queued,'latest queued number wins')
left.active=10
D.cycle(1,left);D.cycle(1,left);D.cycle(1,left);drain()
assert(left.active==D.userSpaces(left)[4],'scroll accumulates against intended destination')

left.active=10;w.space=10
assert(D.moveWindow(2))
assert(D.goToNumber(4,left))
assert(D.transfer and not D.busy and D.queued,'navigation waits for transfer owner')
drain()
assert(w.space==12 and left.active==D.userSpaces(left)[4] and not D.transfer,'transfer completes before queued navigation')

left.active=10;w.space=10
local before=#posted
D.goToNumber(2,left);advance(0.001)
assert(#posted==before+2,'already focused display sends shortcut without 150ms delay')
drain()
assert(not D.isChanging(),'transition and settle guards released')
-- One preferences read for the complete multi-hop transition.
left.active=10
local reads=preferenceReads
D.goToNumber(5,left);drain()
assert(preferenceReads==reads+1,'shortcut preferences cached for one transition')

-- A failed transition clears pending work and every transition timer.
left.active=10;shortcutsWork=false
D.goToNumber(2,left);D.goToNumber(4,left);drain()
assert(not D.busy and not D.queued and not D.keyTimer and not D.isChanging(),'timeout releases transition state and cancels queued intent')
shortcutsWork=true
D.goToNumber(2,left);drain()
assert(left.active==12,'navigation recovers after timeout')

-- If native state reaches the destination before a delayed key, cancel it.
left.active=10;focused=nil;pointer={x=1200,y=200}
local count=#posted
D.goToNumber(2,left);left.active=12;advance(0.2)
assert(#posted==count and not D.keyTimer,'completion cancels delayed stale shortcut')
print('PASS: desktop navigation, transfers, creation, queueing and timing')
