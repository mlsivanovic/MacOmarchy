-- Exercise real event wiring without launching applications or moving windows.
package.path = "config/?.lua;" .. package.path
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
local bindings={}
hs={configdir='/tmp',
    window={filter={new=function() return filter end}},
    hotkey={bind=function(modifiers,key,fn)
        local hotkey={modifiers=modifiers,key=key,fn=fn}
        function hotkey:delete() self.deleted=true end
        bindings[#bindings+1]=hotkey
        return hotkey
    end},
    chooser={new=chain},menubar={new=chain},
    timer={doEvery=function() return {} end},
    screen={mainScreen=function() return nil end,watcher={new=function(fn) screenCallback=fn;return watcher(fn) end}},
    spaces={watcher={new=function(fn) spaceCallback=fn;return watcher(fn) end}},
}
for _,name in ipairs({'windowCreated','windowVisible','windowNotVisible','windowMinimized',
    'windowUnminimized','windowDestroyed','windowMoved'}) do hs.window.filter[name]=name end
package.loaded.desktops={settle=function() settled=settled+1 end}
local focusEnabled=false
package.loaded.focus={isEnabled=function() return focusEnabled end,
    toggle=function() focusEnabled=not focusEnabled;return focusEnabled,true end}
package.loaded.tiler={commands={},
    schedule=function(delay) requests[#requests+1]=delay or 0.04 end,
    forget=function(id) forgotten[#forgotten+1]=id end,
    windowMoved=function() moved=moved+1 end,
}
local M=dofile('config/omarchy.lua')
local S=require('settings')
local shortcutIds={}
for _,entry in ipairs(M.shortcutEntries) do
    assert(not shortcutIds[entry.id],'shortcut id is registered once: '..entry.id)
    shortcutIds[entry.id]=true
    assert(S.get('shortcuts.'..entry.id)==entry.default,'shortcut default matches schema: '..entry.id)
    assert(entry.default and S.parseShortcut(entry.default),'shortcut default is valid: '..entry.id)
end
local externalShortcuts={clipboard_history=true}
local schemaCount,externalCount=0,0
for id in pairs(S.get('shortcuts')) do
    schemaCount=schemaCount+1
    if externalShortcuts[id] then externalCount=externalCount+1
    else assert(shortcutIds[id],'schema shortcut is registered: '..id) end
end
assert(schemaCount==#M.shortcutEntries+externalCount,'every schema shortcut has an owner')
local nextEntry
for _,entry in ipairs(M.shortcutEntries) do
    if entry.id=='layout_next' then nextEntry=entry end
end
local oldHotkey=nextEntry.hotkey
S.values.shortcuts.layout_next='ctrl+alt+j'
M.rebindShortcuts()
assert(oldHotkey.deleted,'rebinding deletes the previous hotkey')
assert(nextEntry.hotkey and nextEntry.hotkey.key=='j','rebinding uses the new key')
assert(M.shortcutHint(nextEntry)=='Ctrl + Option + J','hints follow the new shortcut')
S.values.shortcuts.layout_next='ctrl+alt+l'
M.rebindShortcuts()
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
assert(labels['Focus — follow the pointer'],'focus following has a command menu toggle')

-- Directional focus must not leave the focused display. Hammerspoon's default
-- (no candidate list) searches every visible window on every display.
local function stubWindow(id,screenId,visible)
    local w={wid=id,sid=screenId,visible=visible~=false}
    function w:id() return self.wid end
    function w:isVisible() return self.visible end
    function w:screen() return {id=function() return w.sid end} end
    return w
end
local current=stubWindow(1,100)
local nearby=stubWindow(2,100)
local elsewhere=stubWindow(3,200)
local hidden=stubWindow(4,100,false)
local received
function current:focusWindowWest(candidates,frontmost,strict)
    received={candidates=candidates,frontmost=frontmost,strict=strict}
end
local originalFocused,originalWindows=hs.window.focusedWindow,filter.getWindows
hs.window.focusedWindow=function() return current end
filter.getWindows=function() return {current,nearby,elsewhere,hidden} end
M.focusNeighbour('left')
assert(received,'directional focus reaches the Hammerspoon API')
assert(#received.candidates==1 and received.candidates[1]==nearby,
    'only visible windows on the focused display are candidates')
assert(received.frontmost==true and received.strict==true,'occluded windows are skipped')
hs.window.focusedWindow,filter.getWindows=originalFocused,originalWindows
print('PASS: lifecycle, Space and display event integration')
