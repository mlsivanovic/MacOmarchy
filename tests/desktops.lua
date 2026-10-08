local timers,alerts={},{}
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
function w:focus() end
local focused=w
local function timer(fn)
    local t={fn=fn,stopped=false}
    function t:stop() self.stopped=true end
    timers[#timers+1]=t;return t
end
local posted={}
local clock=0
local function drain()
    for _=1,30 do
        clock=clock+0.1
        local snapshot={table.unpack(timers)}
        for _,t in ipairs(snapshot) do if not t.stopped then t.fn() end end
    end
end
local originalLoadlib=package.loadlib
local moveWorks=true
package.loadlib=function() return function() return function(_,space) if moveWorks then w.space=space end;return true end end end
hs={
    spaces={
        spacesForScreen=function(s) return s.spaces end,
        spaceType=function(id) return id==11 and 'fullscreen' or 'user' end,
        activeSpaceOnScreen=function(s) return s.active end,
        windowSpaces=function() return {w.space} end,
    },
    window={focusedWindow=function() return focused end,orderedWindows=function() return {w} end},
    mouse={getCurrentScreen=function() return pointer.x>=1000 and right or left end,
        absolutePosition=function(p) if p then pointer={x=p.x,y=p.y} end;return pointer end},
    screen={mainScreen=function() return left end},
    plist={read=function() return {AppleSymbolicHotKeys={
        ['79']={enabled=true,value={parameters={65535,123,11534336}}},
        ['81']={enabled=true,value={parameters={65535,124,11534336}}},
    }} end},
    eventtap={leftClick=function() end,event={newKeyEvent=function(_,code,down)
        local event={}
        function event:rawFlags(flags) self.flags=flags;return self end
        function event:post()
            posted[#posted+1]={flags=self.flags,code=code,down=down}
            if down then
                local s=pointer.x>=1000 and right or left
                for i,id in ipairs(s.spaces) do if id==s.active then s.active=s.spaces[i+(code==124 and 1 or -1)];break end end
            end
        end
        return event
    end}},
    timer={secondsSinceEpoch=function() return clock end,
        doEvery=function(_,fn) return timer(fn) end,
        doAfter=function(_,fn) local t;t=timer(function() t:stop();fn() end);return t end},
    alert={show=function(message) alerts[#alerts+1]=message end}
}
local D=dofile('config/desktops.lua');package.loadlib=originalLoadlib
assert(D.keyboardScreen()==left,'keyboard follows focused window, not pointer')
local list=D.userSpaces(left);assert(#list==2 and list[2]==12,'local numbering excludes fullscreen Space')
assert(D.goToNumber(2));drain()
assert(left.active==12 and right.active==20,'only selected monitor changes, across fullscreen Space')
assert(posted[1].flags==11534336,'native customized modifier flags preserved')
assert(pointer.x==1200 and pointer.y==200,'pointer restored after switching')
assert(not D.goToNumber(3,left) and #alerts==1,'nonexistent local number rejected')
assert(D.cycle(1,left));drain();assert(left.active==10,'scroll wraps existing user desktops')
assert(D.moveWindow(2));drain();assert(w.space==12 and left.active==10,'move changes membership without switching desktop')
moveWorks=false;w.space=10
local result
D.moveToSpace(w,12,function(ok) result=ok end);drain()
assert(result==false and #alerts==2,'verify actual membership and report silent API failure')
focused=nil;assert(D.keyboardScreen()==right,'empty desktop falls back to pointer monitor')
print('PASS: 10 desktop behaviors')
