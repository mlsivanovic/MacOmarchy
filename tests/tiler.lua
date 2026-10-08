-- Behavioral tests: desktop isolation, lifecycle and cross-display placement.
local windows, focused, held={},nil,false
local screens={}
local function screen(id,x,space)
    local s={sid=id,x=x,space=space}
    function s:id() return self.sid end
    function s:getUUID() return 'display-'..self.sid end
    function s:frame() return {x=self.x,y=30,w=1920,h=1050} end
    function s:fullFrame() return self:frame() end
    screens[#screens+1]=s;return s
end
local left=screen(1,0,10)
local right=screen(2,1920,20)
local function window(id,s,space)
    local w={wid=id,s=s,space=space or s.space,f={x=s.x+100,y=100,w=600,h=400},visible=true}
    function w:id() return self.wid end
    function w:screen() return self.s end
    function w:frame() return self.f end
    function w:setFrame(f) self.f=f end
    function w:isStandard() return not self.dialog end
    function w:isFullScreen() return self.fullscreen or false end
    function w:isMinimized() return self.minimized or false end
    function w:isVisible() return self.visible end
    function w:application() return {isHidden=function() return false end,bundleID=function() return 'test.app' end} end
    function w:moveToScreen(s) self.s=s;self.f={x=s.x+100,y=100,w=600,h=400} end
    windows[#windows+1]=w;return w
end
hs={
    window={visibleWindows=function() return windows end,focusedWindow=function() return focused end},
    mouse={getCurrentScreen=function() return left end},
    screen={mainScreen=function() return left end,allScreens=function() return screens end},
    spaces={activeSpaceOnScreen=function(s) return s.space end,windowSpaces=function(w) return {w.space} end},
    eventtap={checkMouseButtons=function() return {left=held} end},
    timer={doEvery=function() return {} end,doAfter=function(_,fn) fn();return {} end},
    alert={show=function() end}
}
package.loaded.desktops={moveToSpace=function(w,space) w.space=space;return true end}
local E=dofile('config/tiler.lua')
local first=window(101,left)
E.reflow()
assert(first.f.x==4 and first.f.y==34 and first.f.w==1912 and first.f.h==1042,'one window fills usable desktop')
local second=window(102,left)
E.reflow()
assert(first.f.w==954 and second.f.w==954 and second.f.x==962,'two windows split with gap')
local inactive=window(103,left,11)
local dialog=window(104,left);dialog.dialog=true
E.reflow()
assert(first.f.w==954 and inactive.f.w==600 and dialog.f.w==600,'inactive desktop and dialog excluded')
first:moveToScreen(right)
E.reflow()
assert(first.space==20 and first.f.x==1924 and first.f.w==1912,'cross-monitor joins destination active desktop and fills')
assert(second.f.w==1912,'source desktop reflows after move')
local third=window(105,right)
E.reflow()
assert(first.f.w==954 and third.f.w==954,'destination splits when occupied')
held=true;third:moveToScreen(left);E.reflow()
assert(third.f.w==600,'do not fight mouse drag')
held=false;E.reflow()
assert(third.space==10 and third.f.w==954 and second.f.w==954,'mouse-up tiles destination')
focused=third;E.toggleFloat()
assert(second.f.w==1912,'floating window does not reserve tile')
E.toggleFloat();assert(second.f.w==954,'toggle returns window to tiles')
windows={second,inactive,dialog};E.reflow()
assert(second.f.w==1912,'closure restores remaining window full size')
E.enabled=false;second.f.w=555;E.reflow();assert(second.f.w==555,'disabled tiling leaves frame alone')
print('PASS: 11 tiling behaviors')
