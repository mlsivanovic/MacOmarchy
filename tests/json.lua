-- JSON codec round trips, escapes and rejection cases.
local json = dofile("config/json.lua")

local function check(condition, message)
    if not condition then error(message or "assertion failed", 2) end
end

local value = {
    name = "Mac \"Omarchy\"\nsettings",
    enabled = true,
    disabled = false,
    count = 42,
    ratio = 0.5,
    negative = -3.25,
    exponent = 1e10,
    list = {"tall", "wide", 3, true},
    nested = {a = {b = "c"}},
}
local encoded = json.encode(value, {indent = 2, sort = true})
local decoded = json.decode(encoded)
check(decoded.name == value.name, "string escapes survive a round trip")
check(decoded.enabled == true and decoded.disabled == false, "booleans survive")
check(decoded.count == 42 and decoded.ratio == 0.5, "numbers survive")
check(decoded.negative == -3.25 and decoded.exponent == 1e10, "negative and exponent numbers survive")
check(decoded.list[1] == "tall" and decoded.list[4] == true, "arrays keep order")
check(decoded.nested.a.b == "c", "nested objects survive")

check(json.encode({}) == "{}", "an empty table is an object")
check(json.encode({x = 7.0}) == '{"x":7}', "integral floats encode as integers")
check(json.encode(json.array({})) == "[]", "the array marker preserves an empty array")
check(json.decode("[]") ~= nil and json.decode("{}") ~= nil, "empty containers decode")

local unicode = json.decode('"caf\\u00e9 \\ud83d\\ude00"')
check(unicode == "café 😀", "BMP and surrogate-pair escapes decode to UTF-8")
check(json.decode(json.encode(unicode)) == unicode, "UTF-8 survives a round trip")

local nullValue = json.decode('{"a":null}')
check(nullValue.a == json.null, "null uses an explicit sentinel")
check(json.encode(nullValue) == '{"a":null}', "null encodes back to null")

local pretty = json.encode({b = 1, a = 2}, {indent = 2, sort = true})
check(pretty == table.concat({"{\n  \"a\": 2,\n  \"b\": 1\n}"}), "pretty output is sorted and indented")
check(json.encode({b = 1, a = 2}) == '{"a":2,"b":1}', "compact output is sorted")

local invalid = {
    '{"a":1,}',
    '{a:1}',
    '"unterminated',
    "01",
    "1.",
    "[1,]",
    '{"a" 1}',
    '{"a":1} trailing',
    '"\\ud800"',
    '"\\q"',
}
for _, text in ipairs(invalid) do
    local ok = pcall(json.decode, text)
    check(not ok, "invalid JSON is rejected: " .. text)
end

local deep = json.decode('{"a":{"b":{"c":[1,2,{"d":"e"}]}}}')
check(deep.a.b.c[3].d == "e", "deeply nested values decode")

print("PASS: JSON codec round trips and rejects malformed input")
