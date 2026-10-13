-- Deterministic timers: honor deadlines, intervals and cancellation.
return function()
    local clock,timers=0,{}
    local function timer(delay,fn,repeating)
        local t={due=clock+delay,fn=fn,interval=repeating and delay}
        function t:stop() self.stopped=true end
        timers[#timers+1]=t
        return t
    end
    local api={
        secondsSinceEpoch=function() return clock end,
        doEvery=function(delay,fn) return timer(delay,fn,true) end,
        doAfter=function(delay,fn) return timer(delay,fn,false) end,
    }
    local function advance(seconds)
        local limit=clock+seconds
        local count=0
        while true do
            local nextTimer
            for _,t in ipairs(timers) do
                if not t.stopped and t.due<=limit and (not nextTimer or t.due<nextTimer.due) then nextTimer=t end
            end
            if not nextTimer then break end
            count=count+1;assert(count<10000,'timer loop did not settle')
            clock=nextTimer.due
            if nextTimer.interval then nextTimer.due=clock+nextTimer.interval else nextTimer.stopped=true end
            nextTimer.fn()
        end
        clock=limit
    end
    return api,advance
end
