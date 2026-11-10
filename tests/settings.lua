-- Settings schema/defaults parity, sparse overrides and validation.
local S = dofile("config/settings.lua")

local function check(condition, message)
    if not condition then error(message or "assertion failed", 2) end
end

local function getPath(root, path)
    local node = root
    for key in tostring(path):gmatch("[^%.]+") do
        if type(node) ~= "table" then return nil end
        node = node[key]
    end
    return node
end

local function join(path, key)
    if path == "" then return key end
    return path .. "." .. key
end

local function read(path)
    local file = assert(io.open(path, "r"))
    local data = file:read("*a")
    file:close()
    return data
end

local function write(path, data)
    local file = assert(io.open(path, "w"))
    file:write(data)
    file:close()
end

-- Load defaults only: no user path is configured yet.
check(S.get("tiler.gap") == 4 and S.get("tiler.margin") == 4, "tiling defaults load")
check(S.get("tiler.layout") == "tall" and S.get("tiler.ratio") == 0.5, "layout defaults load")
check(S.get("tiler.layouts")[4] == "floating", "the layout cycle loads as an array")
check(S.get("desktops.maxNumber") == 9, "desktop defaults load")
check(S.get("focus.delay") == 0.1 and S.get("focus.slop") == 8, "focus defaults load")
check(S.get("clipboard.maxItems") == 100 and S.get("clipboard.maxImageMB") == 32, "clipboard defaults load")
check(S.get("ui.alerts") == true and S.get("ui.alertDuration") == 2, "notification defaults load")
check(S.get("tiler.enabled") == true, "tiling starts enabled")
check(S.get("focus.enabled") == false, "focus following starts off")
check(S.get("tiler.tolerance") == 2 and S.get("tiler.newWindowPosition") == "end", "tiling detail defaults load")
check(S.get("desktops.pollInterval") == 0.04 and S.get("desktops.checkInterval") == 0.1
    and S.get("desktops.focusDelay") == 0.15, "desktop timing defaults load")
check(S.get("focus.clickTextFields") == true and S.get("focus.fieldRetryDelay") == 0.12,
    "focus text-field defaults load")
check(S.get("clipboard.storeImages") == true and S.get("clipboard.previewSize") == 72
    and S.get("clipboard.pollInterval") == 0.4 and S.get("clipboard.saveDelay") == 0.5
    and S.get("clipboard.chooserRows") == 9 and S.get("clipboard.pasteDelay") == 0.12,
    "clipboard interaction defaults load")

-- Shortcut values use one canonical format and must not collide.
check(S.formatShortcut({"alt", "ctrl"}, "L") == "ctrl+alt+l", "shortcut formatting is canonical")
local shortcutModifiers, shortcutKey = S.parseShortcut("Cmd + Shift + Return")
check(shortcutModifiers[1] == "cmd" and shortcutModifiers[2] == "shift" and shortcutKey == "return",
    "shortcut parsing accepts aliases, spacing and case")
check(S.parseShortcut("ctrl+alt+") == nil, "a missing key is rejected")
check(S.parseShortcut("ctrl+ctrl+l") == nil, "duplicate modifiers are rejected")
check(S.parseShortcut("f12") ~= nil, "function keys work without a modifier")
check(S.isShortcutDisabled("None") == true, "None disables a shortcut")
check(S.shortcutLabel("ctrl+alt+l") == "Ctrl + Option + L", "shortcuts have readable labels")
local conflictConfig = S.merge(S.defaults, {shortcuts = {layout_next = "ctrl+alt+a"}})
local conflictOk, conflictErrors = S.validate(conflictConfig)
check(not conflictOk and conflictErrors[1]:match("conflicts with shortcuts"), "shortcut conflicts are rejected")
local invalidConfig = S.merge(S.defaults, {shortcuts = {layout_next = "ctrl+alt++"}})
local invalidOk, invalidErrors = S.validate(invalidConfig)
check(not invalidOk and invalidErrors[1]:match("invalid shortcut"), "malformed shortcuts are rejected")
check(S.validate(S.defaults) == true, "the default shortcuts do not conflict")

-- Every schema leaf has a default and every default leaf has a schema entry.
local schemaLeaves, defaultLeaves = {}, {}
local function walkSchema(node, path)
    if node.type == "object" and node.properties then
        for key, child in pairs(node.properties) do walkSchema(child, join(path, key)) end
    else
        schemaLeaves[#schemaLeaves + 1] = path
    end
end
local function walkDefaults(node, path)
    if type(node) == "table" and not S.isArray(node) and next(node) ~= nil then
        for key, child in pairs(node) do walkDefaults(child, join(path, key)) end
    else
        defaultLeaves[#defaultLeaves + 1] = path
    end
end
local function schemaAt(path)
    local node = S.schema
    for key in tostring(path):gmatch("[^%.]+") do
        if type(node) ~= "table" or type(node.properties) ~= "table" then return nil end
        node = node.properties[key]
        if node == nil then return nil end
    end
    return node
end

walkSchema(S.schema, "")
walkDefaults(S.defaults, "")
for _, path in ipairs(schemaLeaves) do
    check(getPath(S.defaults, path) ~= nil, "schema leaf has a default: " .. path)
end
for _, path in ipairs(defaultLeaves) do
    check(schemaAt(path) ~= nil, "default leaf has a schema entry: " .. path)
end

local root = "/tmp/mac-omarchy-settings-test-" .. tostring(os.time())
os.execute('rm -rf "' .. root .. '" && mkdir -p "' .. root .. '"')
local userPath = root .. "/settings.json"

local ok, errors = S.configure({userPath = userPath})
check(ok, "a missing user file is a valid empty override: " .. tostring(errors and errors[1]))
check(S.get("tiler.gap") == 4, "defaults remain after configure")

-- Sparse write: only the changed leaf is stored.
ok, errors = S.set("tiler.gap", 6)
check(ok, "a valid override is saved: " .. tostring(errors and errors[1]))
check(S.get("tiler.gap") == 6 and S.get("tiler.margin") == 4, "the override merges over defaults")
local sparse = read(userPath)
check(sparse:match('"gap": 6') ~= nil, "the changed value is written")
check(sparse:match('"desktops"') == nil and sparse:match('"margin"') == nil,
    "unchanged sections are not written")

-- A rejected write leaves the file alone.
local before = read(userPath)
ok, errors = S.set("tiler.gap", -1)
check(not ok and errors[1]:match("at least 0"), "out-of-range values are rejected")
check(read(userPath) == before, "a rejected write does not touch the file")

ok, errors = S.set("tiler.gap", "wide")
check(not ok and errors[1]:match("expected number"), "wrong types are rejected")
ok, errors = S.set("tiler.unknown", 1)
check(not ok and errors[1]:match("unknown setting"), "unknown settings are rejected")
ok, errors = S.set("tiler.layout", "grid")
check(not ok and errors[1]:match("must be one of"), "enum values are enforced")
ok, errors = S.set("tiler.ratio", 0.85)
check(not ok and errors[1]:match("between"), "cross-field ratio bounds are enforced")
ok, errors = S.set("tiler.ratioMin", 0.9)
check(not ok and errors[1]:match("smaller"), "cross-field ratio order is enforced")
ok, errors = S.set("tiler.layouts", {"wide", "wide"})
check(not ok and errors[1]:match("duplicate"), "duplicate layout entries are rejected")

ok, errors = S.set("tiler.layouts", {"wide", "tall"})
check(ok, "an array override is accepted: " .. tostring(errors and errors[1]))
check(S.get("tiler.layouts")[1] == "wide", "arrays replace rather than merge")
ok, errors = S.set("tiler.layout", "fullscreen")
check(not ok and errors[1]:match("tiler.layouts"), "the default layout must be in the cycle")

-- Listener notification and reload from disk.
local notified = 0
local unsubscribe = S.onChange(function() notified = notified + 1 end)
ok = S.set("focus.delay", 0.2)
check(ok and notified == 1, "a valid write notifies listeners")
check(S.reload() and S.get("focus.delay") == 0.2, "reload reads the saved override")
unsubscribe()
S.set("focus.delay", 0.1)
check(notified == 1, "unsubscribed listeners stop receiving changes")

-- Unset returns to the default and prunes empty parents.
ok, errors = S.unset("tiler.gap")
check(ok and S.get("tiler.gap") == 4, "unset restores the default")
check(not read(userPath):match('"gap"'), "unset removes the stored leaf")

-- Invalid or malformed user files keep the last good values.
local good = S.get("tiler.gap")
write(userPath, '{"tiler":{"gap":"bad"}}')
ok, errors = S.reload()
check(not ok and S.get("tiler.gap") == good, "invalid values keep the last good config")
check(errors[1]:match("expected number"), "reload reports the offending path")
write(userPath, '{"tiler":{"gap":null}}')
ok = S.reload()
check(not ok and S.get("tiler.gap") == good, "null values are rejected")
write(userPath, '{"tiler":')
ok = S.reload()
check(not ok and S.get("tiler.gap") == good, "malformed JSON keeps the last good config")
ok, errors = S.set("tiler.gap", 5)
check(not ok and errors[1]:match("fix the invalid"), "writes are refused while the file is invalid")

-- Reset writes an empty override.
write(userPath, '{"tiler":{"gap":7}}')
check(S.reload() and S.get("tiler.gap") == 7, "a valid file loads before reset")
ok = S.reset()
check(ok and S.get("tiler.gap") == 4, "reset restores all defaults")
check(read(userPath):match("^{}") ~= nil, "reset leaves an empty override object")

os.execute('rm -rf "' .. root .. '"')
print("PASS: settings schema, sparse overrides and validation")
