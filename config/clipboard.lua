-- Clipboard history for Ctrl+V.
-- Text stays a string in clipboard_history.json, as earlier versions stored it.
-- Pictures are files in clipboard-images/ plus a record in that same history.
-- PNG/JPEG/GIF/HEIC/WebP on the pasteboard is the picture the user copied, so it
-- wins over a URL or caption that rides along. A TIFF by itself is a screenshot.
-- A TIFF next to a sentence is only a preview of that text, so the text is kept.
-- Copying an image file reads the file. Finder's TIFF icon is not the picture.

local M = { MAX_HISTORY = 100, MAX_BYTES = 32 * 1024 * 1024 }

local RAW = {
    { uti = "public.png", ext = "png" },
    { uti = "image/png", ext = "png", storeAs = "public.png" },
    { uti = "public.jpeg", ext = "jpg" },
    { uti = "public.jpg", ext = "jpg", storeAs = "public.jpeg" },
    { uti = "image/jpeg", ext = "jpg", storeAs = "public.jpeg" },
    { uti = "public.gif", ext = "gif" },
    { uti = "com.compuserve.gif", ext = "gif", storeAs = "public.gif" },
    { uti = "image/gif", ext = "gif", storeAs = "public.gif" },
    { uti = "public.heic", ext = "heic" },
    { uti = "public.heif", ext = "heif" },
    { uti = "public.webp", ext = "webp" },
    { uti = "org.webmproject.webp", ext = "webp", storeAs = "public.webp" },
}

local FILE_TYPES = {
    png = { uti = "public.png", ext = "png" },
    jpg = { uti = "public.jpeg", ext = "jpg" },
    jpeg = { uti = "public.jpeg", ext = "jpg" },
    gif = { uti = "public.gif", ext = "gif" },
    tif = { uti = "public.tiff", ext = "tiff" },
    tiff = { uti = "public.tiff", ext = "tiff" },
    heic = { uti = "public.heic", ext = "heic" },
    heif = { uti = "public.heif", ext = "heif" },
    webp = { uti = "public.webp", ext = "webp" },
    bmp = { uti = "com.microsoft.bmp", ext = "bmp" },
}

local PREVIEW = { "public.tiff", "public.tif", "image/tiff", "com.apple.pict" }

local UTI_LABEL = {
    ["public.png"] = "PNG", ["public.jpeg"] = "JPEG", ["public.gif"] = "GIF",
    ["public.tiff"] = "TIFF", ["public.heic"] = "HEIC", ["public.heif"] = "HEIF",
    ["public.webp"] = "WebP", ["com.microsoft.bmp"] = "BMP",
}

local seq = 0

function M.rootDir()
    if M.root then return M.root end
    local home = os.getenv("HOME")
    if type(home) ~= "string" or home == "" then home = "/tmp" end
    return home .. "/.hammerspoon"
end

function M.historyPath() return M.rootDir() .. "/clipboard_history.json" end
function M.imageDir() return M.rootDir() .. "/clipboard-images" end

function M.safeName(name)
    if type(name) ~= "string" then return false end
    if name:match("^%d+%-%d+%-%d+%.[a-z0-9]+$") then return true end
    if name:match("^%d+%-%d+%-%d+%.[a-z0-9]+%.thumb%.png$") then return true end
    return false
end

function M.imagePath(name, dir)
    if not M.safeName(name) then return nil end
    return (dir or M.imageDir()) .. "/" .. name
end

function M.ensureDir(path)
    if hs and hs.fs and hs.fs.mkdir then pcall(hs.fs.mkdir, path) end
end

function M.readBytes(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local data = f:read("*a")
    f:close()
    return data
end

function M.writeBytes(path, data)
    local f = io.open(path, "wb")
    if not f then return false end
    local ok = f:write(data)
    f:close()
    return ok and true or false
end

function M.fileSize(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local size = f:seek("end")
    f:close()
    return size
end

function M.digest(data)
    if hs and hs.hash then
        if type(hs.hash.SHA256) == "function" then
            local ok, value = pcall(hs.hash.SHA256, data)
            if ok and type(value) == "string" and value:match("^[%x]+$") and #value >= 32 then
                return value
            end
        end
        if type(hs.hash.new) == "function" then
            local ok, value = pcall(function()
                return hs.hash.new("SHA256"):append(data):finish():value()
            end)
            if ok and type(value) == "string" and value:match("^[%x]+$") and #value >= 32 then
                return value
            end
        end
    end
    local n = #data
    local function hexRange(i, j)
        local parts = {}
        for k = i, j do parts[#parts + 1] = string.format("%02x", data:byte(k)) end
        return table.concat(parts)
    end
    local head = n > 0 and hexRange(1, math.min(16, n)) or ""
    local tail = n > 16 and hexRange(n - 15, n) or ""
    return string.format("len%d.%s.%s", n, head, tail)
end

function M.newName(ext)
    seq = seq + 1
    return string.format("%d-%d-%d.%s", os.time(), math.random(100000, 999999), seq, ext)
end

function M.filePath(url)
    if type(url) ~= "string" then return nil end
    local path = url:match("^file://localhost(.*)$") or url:match("^file://(.*)$")
    if not path or path == "" then return nil end
    path = path:gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end)
    if path:sub(1, 1) ~= "/" then return nil end
    return path
end

-- True when the string is empty, a URL, a path, or a bare filename.
-- A sentence is real clipboard text and must not be replaced by a TIFF preview.
function M.textIsSecondary(text)
    if type(text) ~= "string" then return true end
    local trimmed = text:match("^%s*(.-)%s*$")
    if not trimmed or trimmed == "" then return true end
    if trimmed:match("^https?://%S+$") then return true end
    if trimmed:match("^file://%S+$") then return true end
    if trimmed:match("^/%S+$") then return true end
    if not trimmed:find("[/%s]") and trimmed:match("^[%w%._+-]+%.[A-Za-z0-9]+$") then return true end
    return false
end

function M.dimensions(image)
    if not image or type(image.size) ~= "function" then return nil, nil end
    local ok, size = pcall(function() return image:size() end)
    if not ok or type(size) ~= "table" then return nil, nil end
    local w, h = size.w or size.width, size.h or size.height
    if type(w) ~= "number" or type(h) ~= "number" or w <= 0 or h <= 0 then return nil, nil end
    return math.floor(w), math.floor(h)
end

function M.loadImage(path)
    if not hs or not hs.image or type(hs.image.imageFromPath) ~= "function" then return nil end
    local ok, image = pcall(hs.image.imageFromPath, path)
    if ok then return image end
    return nil
end

function M.writeThumb(image, path)
    if type(image) ~= "table" and type(image) ~= "userdata" then return false end
    local w, h = M.dimensions(image)
    local target = image
    if w and h and (w > 72 or h > 72) then
        if type(image.setSize) ~= "function" then return false end
        local scale = math.min(72 / w, 72 / h)
        local ok, scaled = pcall(function()
            return image:setSize({
                w = math.max(1, math.floor(w * scale)),
                h = math.max(1, math.floor(h * scale)),
            }, true)
        end)
        if not ok or type(scaled) ~= "table" and type(scaled) ~= "userdata" then return false end
        if type(scaled.saveToFile) ~= "function" then return false end
        target = scaled
    end
    if type(target.saveToFile) ~= "function" then return false end
    -- scale is a boolean in Hammerspoon. true saves point size and shrinks Retina images.
    local ok, saved = pcall(function() return target:saveToFile(path, false, "PNG") end)
    return ok and saved ~= false and M.fileSize(path) ~= nil
end

function M.finishImage(file, path, data, uti, image)
    local entry = {
        kind = "image", file = file, uti = uti, bytes = #data, digest = M.digest(data),
    }
    local w, h = M.dimensions(image)
    if not w then
        image = M.loadImage(path)
        w, h = M.dimensions(image)
    end
    entry.w, entry.h = w, h
    if image then
        local thumb = file .. ".thumb.png"
        if M.writeThumb(image, M.imageDir() .. "/" .. thumb) then entry.thumb = thumb end
    end
    return entry
end

function M.storeBytes(data, uti, ext)
    if type(data) ~= "string" or #data == 0 or #data > M.MAX_BYTES then return nil end
    local dir = M.imageDir()
    M.ensureDir(dir)
    local file = M.newName(ext)
    local path = dir .. "/" .. file
    if not M.writeBytes(path, data) then return nil end
    return M.finishImage(file, path, data, uti, nil)
end

function M.capLabel(text)
    if type(text) ~= "string" or text == "" then return nil end
    if #text > 300 then return text:sub(1, 300) end
    return text
end

local function readUTI(uti)
    if not hs or not hs.pasteboard or type(hs.pasteboard.readDataForUTI) ~= "function" then return nil end
    local ok, data = pcall(function() return hs.pasteboard.readDataForUTI(nil, uti) end)
    if ok and type(data) == "string" and #data > 0 then return data end
    return nil
end

local function plainText()
    if not hs or not hs.pasteboard or type(hs.pasteboard.getContents) ~= "function" then return nil end
    local ok, text = pcall(hs.pasteboard.getContents)
    if ok and type(text) == "string" and text:match("%S") then return text end
    return nil
end

local function readURL()
    if not hs or not hs.pasteboard or type(hs.pasteboard.readURL) ~= "function" then return nil end
    local ok, url = pcall(hs.pasteboard.readURL)
    if ok and type(url) == "string" then return url end
    return nil
end

local function contentTypeSet()
    local set = {}
    if not hs or not hs.pasteboard or type(hs.pasteboard.contentTypes) ~= "function" then return set end
    local ok, listed = pcall(hs.pasteboard.contentTypes)
    if not ok or type(listed) ~= "table" then return set end
    for _, uti in ipairs(listed) do
        if type(uti) == "string" then set[uti] = true end
    end
    return set
end

local function hasPrimary(types)
    for _, spec in ipairs(RAW) do
        if types[spec.uti] then return true end
    end
    return false
end

local function hasPreview(types)
    for _, uti in ipairs(PREVIEW) do
        if types[uti] then return true end
    end
    return false
end

local function storePrimary(types)
    for _, spec in ipairs(RAW) do
        if types[spec.uti] then
            local data = readUTI(spec.uti)
            if data then
                local stored = M.storeBytes(data, spec.storeAs or spec.uti, spec.ext)
                if stored then return stored end
            end
        end
    end
    return nil
end

local function storeImageObject(image)
    if type(image) ~= "table" and type(image) ~= "userdata" then return nil end
    if type(image.saveToFile) ~= "function" then return nil end
    local dir = M.imageDir()
    M.ensureDir(dir)
    local file = M.newName("png")
    local path = dir .. "/" .. file
    local ok, saved = pcall(function() return image:saveToFile(path, false, "PNG") end)
    if not ok or saved == false then
        os.remove(path)
        return nil
    end
    local data = M.readBytes(path)
    if type(data) ~= "string" or #data == 0 or #data > M.MAX_BYTES then
        os.remove(path)
        return nil
    end
    return M.finishImage(file, path, data, "public.png", image)
end

local function readImage()
    if not hs or not hs.pasteboard or type(hs.pasteboard.readImage) ~= "function" then return nil end
    local ok, image = pcall(hs.pasteboard.readImage)
    if ok then return image end
    return nil
end

-- Screenshots are often TIFF. Re-encode through hs.image so the archived file is a PNG.
local function storeRendered()
    local fromImage = storeImageObject(readImage())
    if fromImage then return fromImage end
    for _, uti in ipairs({ "public.tiff", "public.tif", "image/tiff" }) do
        local data = readUTI(uti)
        if data and #data <= M.MAX_BYTES then
            return M.storeBytes(data, "public.tiff", "tiff")
        end
    end
    return nil
end

local function storeFileIfImage(path)
    local ext = path:match("%.([A-Za-z0-9]+)$")
    local spec = ext and FILE_TYPES[ext:lower()]
    if not spec then return nil end
    local size = M.fileSize(path)
    if not size or size <= 0 or size > M.MAX_BYTES then return nil end
    local data = M.readBytes(path)
    if type(data) ~= "string" or #data == 0 or #data > M.MAX_BYTES then return nil end
    return M.storeBytes(data, spec.uti, spec.ext)
end

function M.capture()
    local text = plainText()
    local types = contentTypeSet()
    if types["public.file-url"] then
        local path = M.filePath(readURL())
        if path then
            local image = storeFileIfImage(path)
            if image then
                image.label = M.capLabel(text)
                return image
            end
            -- A file copy that is not a picture. Do not archive Finder's icon.
            if text then return { kind = "text", text = text } end
            return { kind = "text", text = path }
        end
    end
    if hasPrimary(types) then
        local image = storePrimary(types)
        if image then
            image.label = M.capLabel(text)
            return image
        end
    end
    if (hasPreview(types) or not next(types)) and M.textIsSecondary(text) then
        local image = storeRendered()
        if image then
            image.label = M.capLabel(text)
            return image
        end
    end
    if text then return { kind = "text", text = text } end
    return nil
end

local function cleanUTI(uti)
    if type(uti) == "string" and uti:match("^[%w%.%-%/]+$") and #uti <= 80 then return uti end
    return "public.png"
end

function M.normalize(data, imageDir)
    local out = {}
    if type(data) ~= "table" then return out end
    for _, entry in ipairs(data) do
        if type(entry) == "string" and entry ~= "" then
            out[#out + 1] = { kind = "text", text = entry }
        elseif type(entry) == "table" and entry.kind == "text" and type(entry.text) == "string" and entry.text ~= "" then
            out[#out + 1] = { kind = "text", text = entry.text }
        elseif type(entry) == "table" and entry.kind == "image" and M.safeName(entry.file) then
            local path = M.imagePath(entry.file, imageDir)
            if path and M.fileSize(path) then
                local digest = entry.digest
                if type(digest) ~= "string" or digest == "" then
                    local bytes = M.readBytes(path)
                    digest = bytes and M.digest(bytes) or nil
                end
                out[#out + 1] = {
                    kind = "image",
                    file = entry.file,
                    thumb = M.safeName(entry.thumb) and entry.thumb or nil,
                    uti = cleanUTI(entry.uti),
                    bytes = type(entry.bytes) == "number" and entry.bytes or M.fileSize(path),
                    digest = digest,
                    w = type(entry.w) == "number" and entry.w or nil,
                    h = type(entry.h) == "number" and entry.h or nil,
                    label = type(entry.label) == "string" and entry.label or nil,
                }
            end
        end
    end
    return out
end

function M.serializable(history)
    local out = {}
    for _, entry in ipairs(history) do
        if entry.kind == "text" and type(entry.text) == "string" then
            out[#out + 1] = entry.text
        elseif entry.kind == "image" and M.safeName(entry.file) then
            local copy = {
                kind = "image", file = entry.file, uti = entry.uti, bytes = entry.bytes, digest = entry.digest,
            }
            if M.safeName(entry.thumb) then copy.thumb = entry.thumb end
            if entry.w then copy.w = entry.w end
            if entry.h then copy.h = entry.h end
            if type(entry.label) == "string" and entry.label ~= "" then copy.label = entry.label end
            out[#out + 1] = copy
        end
    end
    return out
end

function M.key(entry)
    if type(entry) ~= "table" then return nil end
    if entry.kind == "image" then return "i:" .. (entry.digest or entry.file or "") end
    if entry.kind == "text" then return "t:" .. (entry.text or "") end
    return nil
end

function M.filesOf(entry)
    local names = {}
    if type(entry) == "table" and entry.kind == "image" then
        if M.safeName(entry.file) then names[#names + 1] = entry.file end
        if M.safeName(entry.thumb) then names[#names + 1] = entry.thumb end
    end
    return names
end

function M.deleteFiles(names, dir)
    if type(names) ~= "table" then return end
    for _, name in ipairs(names) do
        local path = M.imagePath(name, dir)
        if path then os.remove(path) end
    end
end

function M.add(history, entry)
    local removed = {}
    local id = M.key(entry)
    local i = 1
    while i <= #history do
        local old = history[i]
        if M.key(old) == id then
            if old.kind == "image" and old.file ~= entry.file then
                for _, name in ipairs(M.filesOf(old)) do removed[#removed + 1] = name end
            end
            table.remove(history, i)
        else
            i = i + 1
        end
    end
    table.insert(history, 1, entry)
    while #history > M.MAX_HISTORY do
        local old = table.remove(history)
        for _, name in ipairs(M.filesOf(old)) do removed[#removed + 1] = name end
    end
    return removed
end

function M.ingest(history)
    local entry = M.capture()
    if not entry then return nil end
    if history[1] and M.key(history[1]) == M.key(entry) then
        if entry.kind == "image" then M.deleteFiles(M.filesOf(entry)) end
        return nil
    end
    M.deleteFiles(M.add(history, entry))
    return entry
end

local function short(text, limit)
    local preview = text:gsub("[%c]+", " ")
    if #preview > limit then preview = preview:sub(1, limit) .. "…" end
    return preview
end

function M.formatBytes(bytes)
    bytes = tonumber(bytes) or 0
    if bytes < 1024 then return string.format("%d B", bytes) end
    if bytes < 1024 * 1024 then return string.format("%d KB", math.floor(bytes / 1024 + 0.5)) end
    return string.format("%.1f MB", bytes / (1024 * 1024))
end

function M.previewFor(entry)
    if entry._previewTried then return entry._preview end
    entry._previewTried = true
    local image
    if entry.thumb then
        local path = M.imagePath(entry.thumb)
        image = path and M.loadImage(path) or nil
    end
    if not image then
        local path = M.imagePath(entry.file)
        image = path and M.loadImage(path) or nil
    end
    entry._preview = image
    return image
end

function M.choices(history)
    local choices = {}
    for i, entry in ipairs(history) do
        if entry.kind == "image" then
            local title = (entry.w and entry.h) and string.format("Image %d×%d", entry.w, entry.h) or "Image"
            local sub = string.format("#%d • %s • %s", i, UTI_LABEL[entry.uti] or "image", M.formatBytes(entry.bytes))
            if entry.w and entry.h then sub = string.format("%s • %d×%d", sub, entry.w, entry.h) end
            if type(entry.label) == "string" and entry.label ~= "" then
                sub = sub .. " • " .. short(entry.label, 80)
            end
            local choice = { text = title, subText = sub, entry = entry }
            local image = M.previewFor(entry)
            if image then choice.image = image end
            choices[#choices + 1] = choice
        elseif entry.kind == "text" and type(entry.text) == "string" then
            local item = entry.text
            local firstLine = item:match("([^\r\n]+)") or item
            if #firstLine > 75 then firstLine = firstLine:sub(1, 75) .. "…" end
            choices[#choices + 1] = {
                text = firstLine,
                subText = string.format("#%d (%d characters) • %s", i, #item, short(item, 110)),
                entry = entry,
            }
        end
    end
    return choices
end

function M.restore(entry)
    if type(entry) ~= "table" then return false end
    if entry.kind == "image" then
        local path = M.imagePath(entry.file)
        local data = path and M.readBytes(path)
        if type(data) ~= "string" or data == "" then return false end
        if hs.pasteboard.clearContents then hs.pasteboard.clearContents() end
        local uti = cleanUTI(entry.uti)
        if type(hs.pasteboard.writeDataForUTI) == "function" then
            local ok, wrote = pcall(function() return hs.pasteboard.writeDataForUTI(nil, uti, data, true) end)
            if ok and wrote ~= false then return true end
        end
        local image = M.loadImage(path)
        if image and type(hs.pasteboard.writeObjects) == "function" then
            local ok, wrote = pcall(function() return hs.pasteboard.writeObjects(image) end)
            return ok and wrote ~= false
        end
        return false
    end
    if entry.kind == "text" and type(entry.text) == "string" and entry.text ~= "" then
        hs.pasteboard.setContents(entry.text)
        return true
    end
    return false
end

function M.load(historyFile, imageDir)
    if not hs or not hs.json or type(hs.json.read) ~= "function" then return {}, false end
    local ok, data = pcall(function() return hs.json.read(historyFile) end)
    if not ok or type(data) ~= "table" then return {}, false end
    local history = M.normalize(data, imageDir)
    return history, #history ~= #data
end

function M.save(historyFile, history)
    if not hs or not hs.json or type(hs.json.write) ~= "function" then return end
    pcall(function() hs.json.write(M.serializable(history), historyFile, true, true) end)
end

function M.scheduleSave()
    if M.saveTimer then M.saveTimer:stop() end
    M.saveTimer = hs.timer.doAfter(0.5, function()
        M.saveTimer = nil
        if M.history then M.save(M.historyPath(), M.history) end
    end)
end

function M.stop()
    if M.saveTimer then pcall(function() M.saveTimer:stop() end); M.saveTimer = nil end
    if M.watcher then pcall(function() M.watcher:stop() end); M.watcher = nil end
    if M.hotkey then pcall(function() M.hotkey:delete() end); M.hotkey = nil end
    if M.chooser then pcall(function() M.chooser:delete() end); M.chooser = nil end
end

function M.start()
    M.stop()
    if type(hs_clipboard) == "table" then
        if hs_clipboard.watcher then pcall(function() hs_clipboard.watcher:stop() end) end
        if hs_clipboard.hotkey then pcall(function() hs_clipboard.hotkey:delete() end) end
    end
    local historyFile, imageDir = M.historyPath(), M.imageDir()
    M.ensureDir(imageDir)
    local history, dropped = M.load(historyFile, imageDir)
    M.history = history
    if dropped then M.save(historyFile, history) end
    if #history == 0 then
        local entry = M.capture()
        if entry then
            M.deleteFiles(M.add(history, entry))
            M.save(historyFile, history)
        end
    end
    M.lastChange = hs.pasteboard.changeCount()
    M.paused = false
    M.watcher = hs.timer.doEvery(0.4, function()
        if M.paused then return end
        local count = hs.pasteboard.changeCount()
        if count == M.lastChange then return end
        M.lastChange = count
        local ok, added = pcall(M.ingest, M.history)
        if not ok then
            hs.alert.show("Clipboard history: " .. tostring(added):gsub("%s+", " "):sub(1, 120))
            return
        end
        if added then M.scheduleSave() end
    end)
    M.chooser = hs.chooser.new(function(choice)
        if not choice or type(choice.entry) ~= "table" then return end
        M.paused = true
        local ok, restored = pcall(M.restore, choice.entry)
        M.paused = false
        M.lastChange = hs.pasteboard.changeCount()
        if not ok or not restored then
            local message = choice.entry.kind == "image" and "Image file is missing" or "Could not restore that item"
            hs.alert.show(message)
            return
        end
        M.deleteFiles(M.add(M.history, choice.entry))
        M.scheduleSave()
        hs.timer.doAfter(0.12, function() hs.eventtap.keyStroke({"cmd"}, "v") end)
    end)
    M.chooser:searchSubText(true)
    M.chooser:rows(9)
    M.chooser:placeholderText("Search history (text and images)...")
    M.hotkey = hs.hotkey.bind({"ctrl"}, "v", function()
        if #M.history == 0 then
            hs.alert.show("Clipboard history is empty")
            return
        end
        M.chooser:choices(M.choices(M.history))
        M.chooser:show()
    end)
    hs_clipboard = { watcher = M.watcher, hotkey = M.hotkey, chooser = M.chooser }
end

return M
