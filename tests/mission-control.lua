local children,toggles={},0
local pressed={}
local function element(attrs)
    local e={attrs=attrs}
    function e:attributeValue(k) return self.attrs[k] end
    function e:performAction(action) assert(action=='AXPress');pressed[#pressed+1]=self.attrs.screen;return self end
    return e
end
local function display(x,id)
    local button=element({AXIdentifier='mc.spaces.add',screen=id})
    local group=element({AXIdentifier='mc.spaces',AXChildren={element({AXIdentifier='mc.spaces.list'}),button}})
    return element({AXIdentifier='mc.display',AXDisplayID=id,AXFrame={x=x,y=0,w=1000,h=800},AXChildren={group}})
end
local root=element({})
function root:attributeValue(k) if k=='AXChildren' then return children end end
hs={
    host={operatingSystemVersion=function() return {major=27} end},
    application={applicationsForBundleID=function(name) assert(name=='com.apple.WindowManager');return {'manager'} end},
    axuielement={applicationElement=function(app) assert(app=='manager');return root end},
    spaces={toggleMissionControl=function()
        toggles=toggles+1
        children=#children==0 and {display(0,31),display(1000,32)} or {}
    end}
}
local C=dofile('config/mission-control.lua')
C.open();assert(toggles==1,'open native Mission Control when fresh tree absent')
C.open();assert(toggles==1,'do not close already open Mission Control')
local screen={fullFrame=function() return {x=1000,y=0,w=1000,h=800} end,frame=function() return {x=1000,y=30,w=1000,h=770} end}
assert(C.add(screen));assert(pressed[1]==32,'match full display frame and AXPress correct monitor')
local bad={fullFrame=function() return {x=3000,y=0,w=1000,h=800} end}
local ok,err=C.add(bad);assert(not ok and err=='pending' and #pressed==1,'never add to wrong monitor')
C.close();assert(toggles==2 and #children==0,'close active Mission Control')
C.close();assert(toggles==2,'closed tree does not get toggled open by close')
C.open();assert(toggles==3,'fresh read after closure, no stale element cache')
print('PASS: 7 Mission Control behaviors')
