local timerAPI,advance=dofile("tests/timers.lua")()
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
    function w:application()
        return {
            isHidden=function() return false end,
            bundleID=function() return self.bundleID or 'test.app' end,
            name=function() return self.appName or 'Test' end,
        }
    end
    function w:moveToScreen(s) self.s=s;self.f={x=s.x+100,y=100,w=600,h=400} end
    windows[#windows+1]=w;return w
end
hs={
    window={visibleWindows=function() return windows end,focusedWindow=function() return focused end},
    mouse={getCurrentScreen=function() return left end},
    screen={mainScreen=function() return left end,allScreens=function() return screens end},
    spaces={activeSpaceOnScreen=function(s) return s.space end,windowSpaces=function(w) return {w.space} end},
    eventtap={checkMouseButtons=function() return {left=held} end},
    timer=timerAPI,
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
-- Preserve a user-selected main window over an inactive-desktop round trip.
E.enabled=true;windows={};E.groups={};E.screens={};E.floating={}
left.space=10
local a=window(201,left,10)
local b=window(202,left,10)
focused=b;E.reflow();E.swap(0,true)
assert(E.groups['display-1:10'].order[1]==202)
left.space=11;E.reflow();left.space=10;E.reflow()
assert(E.groups['display-1:10'].order[1]==202,'workspace round trip preserves main window')

-- An app enforcing minimum width must not receive endless resize attempts.
local writes=0
function a:setFrame(frame)
    writes=writes+1
    self.f={x=frame.x,y=frame.y,w=1200,h=frame.h}
end
a.f.w=1200
for _=1,10 do E.reflow() end
assert(writes<=2,'bounded retries for constrained window')
local previous=writes
E.resize(-0.05)
assert(writes>previous,'changed layout target retries constrained window')
previous=writes
a.f.x=a.f.x+50;E.reflow()
assert(writes>previous,'external geometry change permits retry')

local changing=true
package.loaded.desktops.isChanging=function() return changing end
b.f.w=400;E.reflow();advance(0.1)
assert(b.f.w==400,'no geometry changes during desktop transition')
changing=false;advance(0.06)
assert(b.f.w~=400,'pending tiling resumes after transition')
held=true;b.f.w=410;E.schedule();advance(0.2)
assert(b.f.w==410,'scheduled tiling waits for drag release')
held=false;advance(0.06)
assert(b.f.w~=410,'drag release tiles without waiting for fallback poll')

local scans=0
E.windowSource=function() scans=scans+1;return windows end
E.schedule();E.schedule();E.schedule();advance(0.041)
assert(scans==1,'event burst coalesces into one inventory read')
local activeCalls=0
local originalActive=hs.spaces.activeSpaceOnScreen
hs.spaces.activeSpaceOnScreen=function(s) activeCalls=activeCalls+1;return originalActive(s) end
E.reflow();assert(activeCalls==#screens,'one active-Space query per display')

-- Destroyed IDs disappear from hidden groups and per-window state too.
E.floating[202]=true;left.space=11
E.forget(202)
assert(#E.groups['display-1:10'].order==1 and E.floating[202]==nil,'destroy cleans inactive state')
left.space=10;windows={};E.reflow()
assert(#E.groups['display-1:10'].order==0,'empty active desktop is reconciled')
assert(E.excludesFile()==nil,'tests do not read the home excludes file')
windows={};E.groups={};E.screens={};E.floating={};E.userExcluded={};E.targets={};E.attempts={}
left.space=10
local zoom=window(301,left);zoom.bundleID='us.zoom.xos';zoom.appName='Zoom'
local notes=window(302,left);notes.bundleID='com.apple.Notes';notes.appName='Notes'
E.reflow()
assert(zoom.f.w==954 and notes.f.w==954,'both apps tile before an exclude')
focused=zoom
assert(E.toggleFocused()=='excluded','focused app can be excluded without a bundle id lookup')
assert(zoom.f.w==954 and notes.f.w==1912,'excluded app keeps its frame and the other window fills')
local zoom2=window(303,left);zoom2.bundleID='us.zoom.xos'
E.reflow()
assert(zoom2.f.w==600 and notes.f.w==1912,'new window of an excluded app is not tiled')
assert(E.toggleApp('us.zoom.xos','Zoom')=='tiled')
assert(notes.f.w==954,'including the app tiles it with the others again')
local kp=window(304,left);kp.bundleID='org.keepassxc.keepassxc';kp.appName='KeePassXC'
local only=window(305,left)
windows={kp,only};E.groups={};E.reflow()
assert(only.f.w==1912 and kp.f.w==600,'built-in exclude skips KeePassXC')
assert(E.toggleApp('org.keepassxc.keepassxc','KeePassXC')=='builtin')
assert(E.userExcluded['org.keepassxc.keepassxc']==nil,'built-in exclude cannot be removed')

local dir=os.tmpname();os.remove(dir)
local path=dir..'/tiling-excludes.json'
E._excludesFile=path
E.userExcluded={}
assert(E.toggleApp('us.zoom.xos','Zoom')=='excluded')
assert(E.toggleApp('com.example.App','Weird "Name"')=='excluded')
E.userExcluded={leftover='x'}
assert(E.loadExcludes()==true)
assert(E.userExcluded['us.zoom.xos']=='Zoom' and E.userExcluded['com.example.App']=='Weird "Name"'
    and E.userExcluded.leftover==nil,'exclude file round-trips names and replaces memory')
local saved=E.userExcluded
local corrupt=io.open(path,'w');corrupt:write('{');corrupt:close()
assert(E.loadExcludes()==false and E.userExcluded==saved,'invalid exclude file keeps the previous list')
os.remove(path);os.remove(dir)
E._excludesFile=nil
local listed=E.excludedApps()
assert(listed[1].builtin==false and listed[#listed].builtin==true,'user excludes sort before built-ins')
print('PASS: tiling lifecycle, ordering, scheduling and constrained geometry')
