--[[
    NEXT HUB — Loader (Router)
    Repo: https://github.com/lovepump008-bot/SRCORE
    User command:
        loadstring(game:HttpGet("https://raw.githubusercontent.com/lovepump008-bot/SRCORE/main/loader.lua"))()
]]

-- guard set AFTER successful run (see end of file)
if _G.NEXTHUB_LOADED then
    warn("[NextHub] Already loaded")
    return
end

local BASE = "https://raw.githubusercontent.com/lovepump008-bot/SRCORE/main/"

-- PlaceId -> { file, version }
local PLACES = {
    [140583889607592] = { file = "scripts/140583889607592.lua", version = "4.0" },
    [86075649546448]  = { file = "scripts/140583889607592.lua", version = "4.0" },  -- PORBOX PVP (lobby)
    [124382071157432] = { file = "scripts/140583889607592.lua", version = "4.0" },  -- PORBOX PVP (match)
}

local function fetch(url)
    local ok, body = pcall(function() return game:HttpGet(url, true) end)
    if not ok then
        ok, body = pcall(function() return game:HttpGet(url) end)
    end
    if not ok then return nil, body end
    return body
end

local function notify(title, text, t)
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification", {
            Title    = title,
            Text     = text,
            Duration = t or 4,
        })
    end)
end

-- wait for game to be ready
if not game:IsLoaded() then game.Loaded:Wait() end

local pid = game.PlaceId
local entry = PLACES[pid]
if not entry then
    -- fallback: unknown place → run main PORBOX script anyway (dev mode)
    warn("[NextHub] Unknown PlaceId " .. pid .. " — using fallback script")
    entry = { file = "scripts/140583889607592.lua", version = "4.0" }
end

local url = BASE .. entry.file .. "?v=" .. entry.version .. "&t=" .. tostring(os.time())
local src, err = fetch(url)
if not src then
    notify("NEXT HUB", "Download failed", 5)
    warn("[NextHub] Fetch error: " .. tostring(err))
    return
end

local chunk, loadErr = loadstring(src, "NextHub:" .. entry.file)
if not chunk then
    notify("NEXT HUB", "Compile failed", 5)
    warn("[NextHub] loadstring error: " .. tostring(loadErr))
    return
end

local ok, runErr = pcall(chunk)
if not ok then
    notify("NEXT HUB", "Runtime error", 5)
    warn("[NextHub] Runtime error: " .. tostring(runErr))
    return
end

_G.NEXTHUB_LOADED = true
notify("NEXT HUB", "Loaded v" .. entry.version .. "  |  R-Shift toggle", 4)
print("[NextHub] Loaded " .. entry.file .. " v" .. entry.version)
