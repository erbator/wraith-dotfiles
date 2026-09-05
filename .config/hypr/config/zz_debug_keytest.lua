-- TEMPORARY: logs raw keyboard events to diagnose Fn-row keys. Safe to delete after debugging.
local logpath = "/tmp/claude-1000/-home-bator/71bd8e28-9e1b-43d1-9dfa-5070f7a60615/scratchpad/hypr_keytest.log"

local function dump(v, depth)
    depth = depth or 0
    if depth > 2 then return "..." end
    local t = type(v)
    if t == "table" then
        local parts = {}
        for k, val in pairs(v) do
            table.insert(parts, tostring(k) .. "=" .. dump(val, depth + 1))
        end
        return "{" .. table.concat(parts, ", ") .. "}"
    else
        return tostring(v)
    end
end

hl.on("input.keyboard.key", function(...)
    local f = io.open(logpath, "a")
    if f then
        local n = select('#', ...)
        local parts = {}
        for i = 1, n do
            local v = select(i, ...)
            table.insert(parts, dump(v))
        end
        f:write(os.date("%H:%M:%S") .. " keyboard.key(" .. table.concat(parts, " | ") .. ")\n")
        f:close()
    end
end)
