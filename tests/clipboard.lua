-- Clipboard history stores pictures as images and leaves real text as text.
package.path = "config/?.lua;" .. package.path
local root = "/tmp/mac-omarchy-clipboard-test"
os.execute('rm -rf "' .. root .. '" && mkdir -p "' .. root .. '/clipboard-images"')

local function check(cond, message)
    if not cond then error(message or "assertion failed", 2) end
end

local function readFile(path)
    local f = assert(io.open(path, "rb"))
    local data = f:read("*a")
    f:close()
    return data
end

local function writeFile(path, data)
    local f = assert(io.open(path, "wb"))
    f:write(data)
    f:close()
end

local function countFiles(dir)
    local n = 0
    local pipe = assert(io.popen('ls -1 "' .. dir .. '" 2>/dev/null'))
    for _ in pipe:lines() do n = n + 1 end
    pipe:close()
    return n
end

local function imageObject(w, h, payload)
    local image
    image = {
        size = function() return { w = w, h = h } end,
        setSize = function(_, size)
            return imageObject(size.w, size.h, "thumb:" .. tostring(payload))
        end,
        saveToFile = function(_, path, scale)
            if type(scale) == "number" then error("saveToFile scale is a boolean, not a number") end
            writeFile(path, payload)
            return true
        end,
    }
    return image
end

local board
local reads
local function installBoard()
    reads = { image = 0, uti = 0 }
    hs.pasteboard = {}
    hs.pasteboard.contentTypes = function() return board.types or {} end
    hs.pasteboard.getContents = function() return board.text end
    hs.pasteboard.readURL = function() return board.url end
    hs.pasteboard.readImage = function()
        reads.image = reads.image + 1
        return board.image
    end
    hs.pasteboard.readDataForUTI = function(_, uti)
        reads.uti = reads.uti + 1
        return board.data and board.data[uti] or nil
    end
    hs.pasteboard.clearContents = function() board.cleared = true end
    hs.pasteboard.setContents = function(text)
        board.setText = text
        return true
    end
    hs.pasteboard.writeDataForUTI = function(_, uti, data, add)
        board.wrote = { uti = uti, data = data, add = add }
        return board.writeOk ~= false
    end
    hs.pasteboard.writeObjects = function(image)
        board.wroteObject = image
        return true
    end
    hs.pasteboard.changeCount = function() return board.count or 1 end
end

hs = {
    fs = { mkdir = function(path) os.execute('mkdir -p "' .. path .. '"') end },
    image = {
        imageFromPath = function(path)
            local f = io.open(path, "rb")
            if not f then return nil end
            f:close()
            return imageObject(80, 40, "decoded")
        end,
    },
    alert = { show = function(message) hs.alerts[#hs.alerts + 1] = message end },
    alerts = {},
}
installBoard()

local M = dofile("config/clipboard.lua")
M.root = root
local images = M.imageDir()

check(M.filePath("file:///tmp/My%20Shot.png") == "/tmp/My Shot.png", "percent-encoded file URL")
check(M.filePath("file://localhost/tmp/a.png") == "/tmp/a.png", "localhost file URL")
check(M.filePath("https://example.com/a.png") == nil, "remote URL is not a file path")
check(M.textIsSecondary(nil) and M.textIsSecondary("https://example.com/a.png"), "url is not body text")
check(M.textIsSecondary("/tmp/a.png") and M.textIsSecondary("photo.png"), "path and filename are not body text")
check(not M.textIsSecondary("A sentence about a photo"), "a sentence stays text")
check(not M.textIsSecondary("Hello"), "a word stays text")

local function use(nextBoard)
    board = nextBoard
    installBoard()
end

use({ types = { "public.utf8-plain-text" }, text = "A sentence about a photo" })
local textEntry = M.capture()
check(textEntry.kind == "text" and textEntry.text == "A sentence about a photo", "plain text is stored as text")
check(reads.image == 0 and reads.uti == 0, "plain text does not touch image data")

use({
    types = { "public.tiff", "public.utf8-plain-text" },
    text = "A sentence about a photo",
    image = imageObject(12, 12, "ICON"),
})
local before = countFiles(images)
local previewText = M.capture()
check(previewText.kind == "text", "TIFF beside a sentence stays text")
check(countFiles(images) == before and reads.image == 0, "rich text does not archive the TIFF preview")

use({
    types = { "public.png", "public.utf8-plain-text" },
    text = "A sentence about a photo",
    data = { ["public.png"] = "PNGBYTES" },
})
local png = M.capture()
check(png.kind == "image" and png.uti == "public.png", "PNG is stored as an image")
check(png.label == "A sentence about a photo", "caption is kept as a label")
check(png.w == 80 and png.h == 40, "dimensions come from the decoded image")
check(readFile(M.imagePath(png.file)) == "PNGBYTES", "original PNG bytes are kept")
check(reads.image == 0, "primary image bytes are not re-encoded")
check(M.safeName(png.thumb), "thumbnail name is local")

use({ types = { "image/png" }, data = { ["image/png"] = "ALIAS" } })
local alias = M.capture()
check(alias.kind == "image" and alias.uti == "public.png", "image/png is stored as public.png")
check(readFile(M.imagePath(alias.file)) == "ALIAS", "alias bytes are the pasted image")

use({ types = { "public.tiff" }, image = imageObject(200, 100, "PNGDATA") })
local shot = M.capture()
check(shot.kind == "image" and shot.uti == "public.png", "screenshot TIFF is archived as PNG")
check(shot.w == 200 and shot.h == 100, "screenshot dimensions are kept")
check(readFile(M.imagePath(shot.file)) == "PNGDATA", "re-encoded screenshot is the saved file")
check(reads.uti == 0, "rendered screenshot does not also copy the TIFF blob")

use({ types = { "public.tiff" }, text = "https://cdn.example/shot.png", image = imageObject(90, 30, "URLPNG") })
local linked = M.capture()
check(linked.kind == "image" and linked.label == "https://cdn.example/shot.png", "image URL is a label, not the item")

local shotFile = root .. "/Shot Name.png"
writeFile(shotFile, "FROMDISK")
use({
    types = { "public.file-url", "public.tiff" },
    url = "file://" .. root .. "/Shot%20Name.png",
    image = imageObject(8, 8, "ICON"),
})
local fromDisk = M.capture()
check(fromDisk.kind == "image", "an image file is stored as an image")
check(readFile(M.imagePath(fromDisk.file)) == "FROMDISK", "file bytes win over the Finder icon")
check(reads.image == 0, "Finder icon is not read for an image file")

writeFile(root .. "/notes.txt", "notes")
use({
    types = { "public.file-url", "public.tiff" },
    url = "file://" .. root .. "/notes.txt",
    image = imageObject(8, 8, "ICON"),
})
local notes = M.capture()
check(notes.kind == "text" and notes.text == root .. "/notes.txt", "a non-image file stays a path")
check(reads.image == 0, "a document copy does not archive the Finder icon")

local savedStoreImages = M.STORE_IMAGES
M.STORE_IMAGES = false
use({ types = { "public.png" }, data = { ["public.png"] = "NOSTORE" } })
check(M.capture() == nil, "images are not archived when archiving is disabled")
use({ types = { "public.png", "public.utf8-plain-text" }, text = "caption", data = { ["public.png"] = "NOSTORE" } })
local captionOnly = M.capture()
check(captionOnly and captionOnly.kind == "text" and captionOnly.text == "caption",
    "text next to a disabled image is still archived")
M.STORE_IMAGES = savedStoreImages

local savedMaxBytes = M.MAX_BYTES
M.MAX_BYTES = 4
use({ types = { "public.png" }, data = { ["public.png"] = "12345" } })
local skipped = M.capture()
check(skipped == nil, "an image over the size cap is not archived")
writeFile(root .. "/big.png", "12345")
use({ types = { "public.file-url" }, url = "file://" .. root .. "/big.png" })
local bigFile = M.capture()
check(bigFile.kind == "text" and bigFile.text == root .. "/big.png", "an oversized image file falls back to its path")
M.MAX_BYTES = savedMaxBytes

board.wrote = nil
board.setText = nil
board.writeOk = true
check(M.restore(png) == true, "image restore succeeds")
check(board.cleared, "image restore clears other pasteboard types")
check(board.wrote and board.wrote.uti == "public.png" and board.wrote.data == "PNGBYTES" and board.wrote.add == true,
    "image restore writes the original bytes")
check(board.setText == nil, "image restore does not replace the picture with text")

board.writeOk = false
board.wroteObject = nil
check(M.restore(png) == true, "failed raw write falls back to an image object")
check(board.wroteObject ~= nil, "fallback puts an image object on the pasteboard")
check(M.restore({ kind = "image", file = "9-9-9.png", uti = "public.png" }) == false, "missing image file does not paste")
board.setText = nil
check(M.restore(textEntry) == true and board.setText == textEntry.text, "text restore writes the string")

local history = {}
use({ types = { "public.png" }, data = { ["public.png"] = "SAME" } })
check(M.ingest(history).kind == "image", "first image is recorded")
local kept = history[1].file
local filesAfterFirst = countFiles(images)
check(M.ingest(history) == nil and history[1].file == kept, "the same image is not duplicated")
check(countFiles(images) == filesAfterFirst, "duplicate capture deletes its new files")
check(M.fileSize(M.imagePath(kept)) ~= nil, "the original image file stays")

use({ types = { "public.utf8-plain-text" }, text = "alpha" })
M.ingest(history)
use({ types = { "public.utf8-plain-text" }, text = "beta" })
M.ingest(history)
use({ types = { "public.utf8-plain-text" }, text = "alpha" })
M.ingest(history)
check(history[1].text == "alpha" and history[2].text == "beta", "copied text moves to the front")

local savedMax = M.MAX_HISTORY
M.MAX_HISTORY = 1
use({ types = { "public.png" }, data = { ["public.png"] = "EVICT" } })
local evicted = {}
M.ingest(evicted)
local evictPath = M.imagePath(evicted[1].file)
check(M.fileSize(evictPath) ~= nil, "image file exists before eviction")
use({ types = { "public.utf8-plain-text" }, text = "newer" })
M.ingest(evicted)
check(#evicted == 1 and evicted[1].text == "newer", "history stays at the cap")
check(M.fileSize(evictPath) == nil, "evicted image file is deleted")
M.MAX_HISTORY = savedMax

local legacy = M.normalize({
    "alpha",
    { kind = "image", file = "../x.png" },
    { kind = "image", file = "1-2-3.png", uti = "public.png" },
}, images)
check(#legacy == 1 and legacy[1].kind == "text" and legacy[1].text == "alpha", "legacy strings survive and bad image records do not")
check(M.serializable(legacy)[1] == "alpha", "text is still saved as a string")
writeFile(images .. "/1-2-3.png", "kept-bytes")
local withFile = M.normalize({
    { kind = "image", file = "1-2-3.png", uti = "public.png", bytes = 10, w = 3, h = 4, label = "cap" },
}, images)
check(#withFile == 1 and withFile[1].digest ~= nil and withFile[1].label == "cap", "an image record reloads when its file exists")
local saved = M.serializable({ legacy[1], withFile[1] })
check(saved[1] == "alpha" and saved[2].kind == "image" and saved[2].file == "1-2-3.png", "mixed history keeps text strings and image records")

local choices = M.choices({ legacy[1], withFile[1] })
check(choices[1].text == "alpha" and choices[1].subText:find("characters", 1, true), "text rows keep the character count")
check(choices[2].text == "Image 3×4" and choices[2].image ~= nil, "image rows show a thumbnail")
check(choices[2].subText:find("PNG", 1, true) and choices[2].subText:find("cap", 1, true), "image rows name the format and label")

local chooserFn, hotkeyFn, pasteFn
local hotkeyMods, hotkeyKey
local savedJson
hs.json = {
    read = function() return { { kind = "image", file = "../secret.png" }, "kept" } end,
    write = function(data) savedJson = data end,
}
hs.timer = {
    doEvery = function() return { stop = function() end } end,
    doAfter = function(_, fn) pasteFn = fn; return { stop = function() end } end,
}
hs.eventtap = { keyStroke = function(mods, key) hs.stroke = table.concat(mods, "+") .. " " .. key end }
hs.chooser = { new = function(fn)
    chooserFn = fn
    return {
        searchSubText = function() end, rows = function() end, placeholderText = function() end,
        choices = function() end, show = function() end, delete = function() end,
    }
end }
hs.hotkey = { bind = function(mods, key, fn)
    hotkeyMods, hotkeyKey, hotkeyFn = mods, key, fn
    return { delete = function() end }
end }
hs.alerts = {}
use({ types = { "public.utf8-plain-text" }, text = "should-not-seed", count = 7 })
M.start()
check(hotkeyMods[1] == "ctrl" and hotkeyKey == "v", "clipboard starts on the configured default shortcut")
local S = require("settings")
S.values.shortcuts.clipboard_history = "ctrl+alt+u"
M.applySettings()
check(hotkeyMods[1] == "ctrl" and hotkeyMods[2] == "alt" and hotkeyKey == "u", "clipboard rebinds live")
S.values.shortcuts.clipboard_history = "none"
M.applySettings()
check(M.hotkey == nil and hs_clipboard.hotkey == nil, "None disables the clipboard shortcut")
S.values.shortcuts.clipboard_history = "ctrl+v"
M.applySettings()
check(hotkeyMods[1] == "ctrl" and hotkeyKey == "v", "clipboard can be re-enabled")
M.suspendHotkey()
check(M.hotkey == nil and M.captureSuspended == true, "recording suspends the clipboard shortcut")
M.resumeHotkey()
check(M.hotkey ~= nil and M.captureSuspended == false, "finishing recording restores the clipboard shortcut")
check(M.history[1].text == "kept" and #M.history == 1, "startup drops a path-traversal image record")
check(savedJson and savedJson[1] == "kept", "startup rewrites history after dropping a bad record")
check(M.lastChange == 7, "startup remembers the pasteboard change count")
hotkeyFn()
local shown
hs.chooser.new = function(fn)
    chooserFn = fn
    return {
        searchSubText = function() end, rows = function() end, placeholderText = function() end,
        choices = function(_, rows) shown = rows end, show = function() end, delete = function() end,
    }
end
-- Hotkey from the running chooser uses the closure created in start, so call choices directly.
shown = M.choices(M.history)
check(shown[1].entry.text == "kept", "history rows carry the entry that paste restores")
chooserFn(shown[1])
check(board.setText == "kept", "choosing a row restores that item")
check(type(pasteFn) == "function", "restore schedules a paste")
pasteFn()
check(hs.stroke == "cmd v", "paste is Cmd+V and does not reopen history")

os.execute('rm -rf "' .. root .. '"')
print("PASS: clipboard text, images, files, eviction and paste")
