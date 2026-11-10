-- Minimal JSON (RFC 8259) codec used by the settings layer.
-- Works in Hammerspoon and in a plain Lua interpreter, so the same files can be
-- validated in tests and from the CLI without depending on hs.json.
local json = {}

-- A decoded null. Returning nil would drop the key from an object, so null is a
-- sentinel; settings validation rejects it, but the codec stays lossless.
local null = {}
json.null = null

-- Marker for empty arrays: an empty Lua table is otherwise indistinguishable
-- from an empty object. Non-empty arrays are detected by their length.
local array_mt = {}
function json.array(t)
    if t == nil then t = {} end
    if type(t) ~= "table" then error("json.array expects a table", 2) end
    return setmetatable(t, array_mt)
end

local function utf8char(code)
    if code < 0x80 then
        return string.char(code)
    elseif code < 0x800 then
        return string.char(0xC0 + math.floor(code / 0x40), 0x80 + code % 0x40)
    elseif code < 0x10000 then
        return string.char(0xE0 + math.floor(code / 0x1000),
            0x80 + math.floor(code / 0x40) % 0x40, 0x80 + code % 0x40)
    elseif code < 0x110000 then
        return string.char(0xF0 + math.floor(code / 0x40000),
            0x80 + math.floor(code / 0x1000) % 0x40,
            0x80 + math.floor(code / 0x40) % 0x40, 0x80 + code % 0x40)
    end
    error("json: invalid unicode code point", 0)
end

local function parse(text)
    if type(text) ~= "string" then error("json: expected a string", 0) end
    local pos, length = 1, #text

    local function fail(message)
        error(string.format("json: %s at byte %d", message, pos), 0)
    end

    local function peek() return text:sub(pos, pos) end

    local function skip()
        while pos <= length and text:sub(pos, pos):match("%s") do pos = pos + 1 end
    end

    local parseValue

    local function parseString()
        if peek() ~= '"' then fail("expected string") end
        pos = pos + 1
        local out = {}
        while true do
            local c = text:sub(pos, pos)
            if c == "" then fail("unterminated string") end
            if c == '"' then
                pos = pos + 1
                return table.concat(out)
            elseif c == "\\" then
                local escape = text:sub(pos + 1, pos + 1)
                if escape == '"' or escape == "\\" or escape == "/" then
                    out[#out + 1] = escape
                    pos = pos + 2
                elseif escape == "b" then out[#out + 1] = "\b"; pos = pos + 2
                elseif escape == "f" then out[#out + 1] = "\f"; pos = pos + 2
                elseif escape == "n" then out[#out + 1] = "\n"; pos = pos + 2
                elseif escape == "r" then out[#out + 1] = "\r"; pos = pos + 2
                elseif escape == "t" then out[#out + 1] = "\t"; pos = pos + 2
                elseif escape == "u" then
                    local hex = text:sub(pos + 2, pos + 5)
                    if not hex:match("^%x%x%x%x$") then fail("invalid unicode escape") end
                    local code = tonumber(hex, 16)
                    pos = pos + 6
                    if code >= 0xD800 and code <= 0xDBFF then
                        local pair = text:sub(pos, pos + 1)
                        local low = text:sub(pos + 2, pos + 5)
                        if pair ~= "\\u" or not low:match("^%x%x%x%x$") then
                            fail("unpaired high surrogate")
                        end
                        local lowCode = tonumber(low, 16)
                        if lowCode < 0xDC00 or lowCode > 0xDFFF then
                            fail("invalid low surrogate")
                        end
                        code = 0x10000 + (code - 0xD800) * 0x400 + (lowCode - 0xDC00)
                        pos = pos + 6
                    elseif code >= 0xDC00 and code <= 0xDFFF then
                        fail("unpaired low surrogate")
                    end
                    out[#out + 1] = utf8char(code)
                else
                    fail("invalid escape")
                end
            elseif c:byte() < 0x20 then
                fail("control character in string")
            else
                out[#out + 1] = c
                pos = pos + 1
            end
        end
    end

    local function parseNumber()
        local start = pos
        if peek() == "-" then pos = pos + 1 end
        local first = peek()
        if first == "0" then
            pos = pos + 1
            if peek():match("%d") then fail("leading zero in number") end
        elseif first:match("[1-9]") then
            repeat pos = pos + 1 until not peek():match("%d")
        else
            fail("invalid number")
        end
        if peek() == "." then
            pos = pos + 1
            if not peek():match("%d") then fail("invalid fraction") end
            repeat pos = pos + 1 until not peek():match("%d")
        end
        if peek() == "e" or peek() == "E" then
            pos = pos + 1
            if peek() == "+" or peek() == "-" then pos = pos + 1 end
            if not peek():match("%d") then fail("invalid exponent") end
            repeat pos = pos + 1 until not peek():match("%d")
        end
        local value = tonumber(text:sub(start, pos - 1))
        if value == nil then fail("invalid number") end
        return value
    end

    local function parseObject(depth)
        pos = pos + 1 -- {
        local out = {}
        skip()
        if peek() == "}" then pos = pos + 1; return out end
        while true do
            skip()
            if peek() ~= '"' then fail("expected object key") end
            local key = parseString()
            skip()
            if peek() ~= ":" then fail("expected ':'") end
            pos = pos + 1
            out[key] = parseValue(depth + 1)
            skip()
            local c = peek()
            if c == "," then
                pos = pos + 1
            elseif c == "}" then
                pos = pos + 1
                return out
            else
                fail("expected ',' or '}'")
            end
        end
    end

    local function parseArray(depth)
        pos = pos + 1 -- [
        local out, n = {}, 0
        skip()
        if peek() == "]" then pos = pos + 1; return setmetatable(out, array_mt) end
        while true do
            n = n + 1
            out[n] = parseValue(depth + 1)
            skip()
            local c = peek()
            if c == "," then
                pos = pos + 1
            elseif c == "]" then
                pos = pos + 1
                return setmetatable(out, array_mt)
            else
                fail("expected ',' or ']'")
            end
        end
    end

    parseValue = function(depth)
        if depth > 200 then fail("nesting too deep") end
        skip()
        local c = peek()
        if c == "" then fail("unexpected end of input") end
        if c == "{" then return parseObject(depth) end
        if c == "[" then return parseArray(depth) end
        if c == '"' then return parseString() end
        if c == "t" then
            if text:sub(pos, pos + 3) ~= "true" then fail("invalid literal") end
            pos = pos + 4
            return true
        end
        if c == "f" then
            if text:sub(pos, pos + 4) ~= "false" then fail("invalid literal") end
            pos = pos + 5
            return false
        end
        if c == "n" then
            if text:sub(pos, pos + 3) ~= "null" then fail("invalid literal") end
            pos = pos + 4
            return null
        end
        return parseNumber()
    end

    local value = parseValue(0)
    skip()
    if pos <= length then fail("trailing characters") end
    return value
end

local function encodeString(value)
    local escapes = {
        ['"'] = '\\"', ["\\"] = "\\\\", ["\b"] = "\\b", ["\f"] = "\\f",
        ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t",
    }
    return '"' .. value:gsub('[%z\1-\31\\"]', function(c)
        return escapes[c] or string.format("\\u%04x", c:byte())
    end) .. '"'
end

local function isArray(value)
    return getmetatable(value) == array_mt or #value > 0
end

local function encodeValue(value, options, level, out)
    local kind = type(value)
    if value == null or value == nil then
        out[#out + 1] = "null"
    elseif kind == "boolean" then
        out[#out + 1] = value and "true" or "false"
    elseif kind == "number" then
        if value ~= value or value == math.huge or value == -math.huge then
            error("json: cannot encode a non-finite number", 0)
        end
        -- Lua 5.3+ keeps floats distinct from integers; JSON does not, so an
        -- integral float (7.0 from JavaScript) is written as 7, not 7.0.
        if math.type(value) == "float" and value == math.floor(value) and math.abs(value) < 1e15 then
            out[#out + 1] = string.format("%d", value)
        else
            out[#out + 1] = tostring(value)
        end
    elseif kind == "string" then
        out[#out + 1] = encodeString(value)
    elseif kind == "table" then
        local indent = options.indent
        local pad = indent and string.rep(" ", indent * (level + 1)) or ""
        local closePad = indent and string.rep(" ", indent * level) or ""
        local newline = indent and "\n" or ""
        local separator = indent and ": " or ":"
        if isArray(value) then
            if #value == 0 then
                out[#out + 1] = "[]"
                return
            end
            out[#out + 1] = "["
            for i = 1, #value do
                if i > 1 then out[#out + 1] = "," end
                out[#out + 1] = newline .. pad
                encodeValue(value[i], options, level + 1, out)
            end
            out[#out + 1] = newline .. closePad .. "]"
        else
            local keys = {}
            for key in pairs(value) do
                if type(key) ~= "string" then
                    error("json: object keys must be strings", 0)
                end
                keys[#keys + 1] = key
            end
            if #keys == 0 then
                out[#out + 1] = "{}"
                return
            end
            if options.sort then table.sort(keys) end
            out[#out + 1] = "{"
            for i, key in ipairs(keys) do
                if i > 1 then out[#out + 1] = "," end
                out[#out + 1] = newline .. pad
                out[#out + 1] = encodeString(key) .. separator
                encodeValue(value[key], options, level + 1, out)
            end
            out[#out + 1] = newline .. closePad .. "}"
        end
    else
        error("json: cannot encode a " .. kind, 0)
    end
end

function json.encode(value, options)
    options = options or {}
    local out = {}
    encodeValue(value, {indent = options.indent, sort = options.sort ~= false}, 0, out)
    return table.concat(out)
end

function json.decode(text)
    return parse(text)
end

-- Human-readable aliases used by callers that do not need the codec object.
function json.read(path)
    local file = io.open(path, "r")
    if not file then return nil end
    local raw = file:read("*a")
    file:close()
    if raw == nil then return nil end
    return json.decode(raw)
end

function json.write(value, path, pretty)
    local file = assert(io.open(path, "w"))
    file:write(json.encode(value, {indent = pretty and 2 or nil, sort = true}) .. "\n")
    file:close()
    return true
end

return json
