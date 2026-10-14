-- macOS 27 moved Mission Control's AX tree from Dock to WindowManager.
-- Use fresh elements and full display frames; never cache the empty Dock stub.
local C={}
local modern=hs.host.operatingSystemVersion().major>=27
local function displays()
    local apps=hs.application.applicationsForBundleID('com.apple.WindowManager')
    local app=apps and apps[1]
    if not app then return {} end
    local root=hs.axuielement.applicationElement(app)
    local out={}
    for _,e in ipairs(root:attributeValue('AXChildren') or {}) do
        if e:attributeValue('AXIdentifier')=='mc.display' then out[#out+1]=e end
    end
    return out
end
-- Toggling is the only close primitive on macOS 27, and the AX tree stays
-- visible during the close animation. Remember a close we started so a
-- repeated close inside that window cannot toggle Mission Control back open.
local closingSince=nil
local function nowSeconds()
    if hs.timer and hs.timer.secondsSinceEpoch then return hs.timer.secondsSinceEpoch() end
    return os.time()
end
function C.open()
    if not modern then hs.spaces.openMissionControl();return end
    if #displays()==0 then closingSince=nil;hs.spaces.toggleMissionControl() end
end
function C.close()
    if not modern then hs.spaces.closeMissionControl();return end
    if #displays()==0 then closingSince=nil;return end
    local now=nowSeconds()
    if closingSince and now-closingSince<1 then return end
    closingSince=now
    hs.spaces.toggleMissionControl()
end
function C.add(screen)
    if not modern then return hs.spaces.addSpaceToScreen(screen,false) end
    local expected=screen:fullFrame()
    for _,display in ipairs(displays()) do
        local f=display:attributeValue('AXFrame')
        if f and math.abs(f.x-expected.x)<4 and math.abs(f.y-expected.y)<4
          and math.abs(f.w-expected.w)<4 and math.abs(f.h-expected.h)<4 then
            for _,group in ipairs(display:attributeValue('AXChildren') or {}) do
                if group:attributeValue('AXIdentifier')=='mc.spaces' then
                    for _,button in ipairs(group:attributeValue('AXChildren') or {}) do
                        if button:attributeValue('AXIdentifier')=='mc.spaces.add' then
                            local ok,err=button:performAction('AXPress')
                            return ok~=nil and ok~=false,err
                        end
                    end
                end
            end
        end
    end
    return nil,'pending'
end
return C
