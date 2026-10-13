-- Exercise real event wiring without launching applications or moving windows.
local events,requests,forgotten={},{},{}
local moved,settled=0,0
local function chain()
    return setmetatable({}, {__index=function(self) return function() return self end end})
end
local filter=chain()
function filter:setCurrentSpace(value) assert(value);self.currentSpace=value;return self end
function filter:getWindows() return {'cached'} end
function filter:subscribe(names,fn)
    if type(names)~='table' then names={names} end
    for _,name in ipairs(names) do events[name]=fn end
    return self
end
local spaceCallback,screenCallback
local function watcher(fn) return {start=function(self) return self end,fn=fn} end
hs={configdir='/tmp',
    window={filter={new=function() return filter end}},
    hotkey={bind=function() return {} end},
    chooser={new=chain},menubar={new=chain},
    timer={doEvery=function() return {} end},
    screen={mainScreen=function() return nil end,watcher={new=function(fn) screenCallback=fn;return watcher(fn) end}},
    spaces={watcher={new=function(fn) spaceCallback=fn;return watcher(fn) end}},
}
for _,name in ipairs({'windowCreated','windowVisible','windowNotVisible','windowMinimized',
    'windowUnminimized','windowDestroyed','windowMoved'}) do hs.window.filter[name]=name end
package.loaded.desktops={settle=function() settled=settled+1 end}
package.loaded.tiler={commands={},
    schedule=function(delay) requests[#requests+1]=delay or 0.04 end,
    forget=function(id) forgotten[#forgotten+1]=id end,
    windowMoved=function() moved=moved+1 end,
}
local M=dofile('config/omarchy.lua')
assert(M.tiler.windowSource()[1]=='cached' and filter.currentSpace,'cached inventory restricted to active Spaces')
for _,name in ipairs({'windowCreated','windowVisible','windowNotVisible','windowMinimized','windowUnminimized'}) do
    events[name]()
end
assert(#requests==5,'all lifecycle events schedule tiling')
events.windowDestroyed({id=function() return 42 end})
assert(forgotten[1]==42,'destroy forwards cleanup')
events.windowMoved();assert(moved==1,'geometry events forward to self-event suppression')
spaceCallback();assert(settled==1 and requests[#requests]==0.15,'Space watcher starts settle guard')
screenCallback();assert(requests[#requests]==0.04,'display changes schedule tiling')
M.desktops.afterChange();assert(requests[#requests]==0.15,'desktop completion schedules coalesced tiling')
local labels={}
for _,action in ipairs(M.actions) do labels[action.text]=true end
assert(labels['App — exclude from tiling'] and labels['Tiling — manage excluded apps'],'exclude actions are in the command menu')
print('PASS: lifecycle, Space and display event integration')
