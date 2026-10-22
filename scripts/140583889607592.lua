--[[
    NEXT HUB — PORBOX PVP (PlaceId 86075649546448 / 140583889607592)
    v2: scan workspace for every Humanoid (handles players + NPCs/zombies/bandits)
]]

-- ============================================================
-- 1) Load LinoriaLib
-- ============================================================
local repo = "https://raw.githubusercontent.com/violin-suzutsuki/LinoriaLib/main/"
local Library = loadstring(game:HttpGet(repo .. "Library.lua"))()

-- ============================================================
-- 2) Services + State
-- ============================================================
local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS        = game:GetService("UserInputService")
local LP         = Players.LocalPlayer
local function Cam() return workspace.CurrentCamera end

local State = {
    Aimbot        = false,
    TriggerMode   = "Hold Key",
    AimPoint      = "Head",
    FOV           = 180,
    Smoothing     = 0.3,
    IgnoreNPCs    = false,
    TeamCheck     = false,
    WallCheck     = false,
    HoldKey       = Enum.KeyCode.E,

    ESP           = false,
    NameTag       = false,
    ESPColor      = Color3.fromRGB(255, 50, 50),

    NoRecoil      = false,
}

local toggleState = false
local espCache    = setmetatable({}, { __mode = "k" }) -- weak keys: cleared when model gone

-- ============================================================
-- 3) Window
-- ============================================================
local Window = Library:CreateWindow({
    Title = "NEXT HUB  |  v2.0  |  PORBOX",
    Center = true, AutoShow = true, TabPadding = 8, MenuFadeTime = 0.2,
})

local Tabs = {
    Home    = Window:AddTab("Home"),
    Combat  = Window:AddTab("Combat"),
    Visuals = Window:AddTab("Visuals"),
    System  = Window:AddTab("System"),
}

-- Home
do
    local box = Tabs.Home:AddLeftGroupbox("Info")
    box:AddLabel("Place:   " .. game.PlaceId)
    box:AddLabel("Player:  " .. LP.Name)
    box:AddLabel("UI Toggle: Right Shift")
    box:AddLabel("Aimbot Key: E (hold)")
    local box2 = Tabs.Home:AddRightGroupbox("Status")
    box2:AddLabel("Targets scanned: workspace Humanoids")
    box2:AddLabel("Includes NPCs by default")
end

-- Combat
do
    local L = Tabs.Combat:AddLeftGroupbox("Aimbot")
    local R = Tabs.Combat:AddRightGroupbox("Filters")

    L:AddToggle("Aimbot",   { Text = "Aimbot",         Default = false, Callback = function(v) State.Aimbot = v end })
    L:AddToggle("NoRecoil", { Text = "No Recoil (cam lock)", Default = false, Callback = function(v) State.NoRecoil = v end })

    L:AddDropdown("TriggerMode", {
        Text = "Trigger",
        Values = { "Hold Key", "Toggle Key", "Always" },
        Default = "Hold Key",
        Callback = function(v) State.TriggerMode = v end,
    })

    L:AddDropdown("AimPoint", {
        Text = "Aim Point",
        Values = { "Head", "HumanoidRootPart", "UpperTorso", "Torso" },
        Default = "Head",
        Callback = function(v) State.AimPoint = v end,
    })

    L:AddSlider("FOV", {
        Text = "FOV (deg)", Default = 180, Min = 10, Max = 360, Rounding = 0,
        Callback = function(v) State.FOV = v end,
    })

    L:AddSlider("Smoothing", {
        Text = "Smoothing", Default = 0.3, Min = 0.05, Max = 1, Rounding = 2,
        Callback = function(v) State.Smoothing = v end,
    })

    R:AddToggle("IgnoreNPCs", { Text = "Ignore NPCs (players only)", Default = false, Callback = function(v) State.IgnoreNPCs = v end })
    R:AddToggle("TeamCheck",  { Text = "Team Check",                 Default = false, Callback = function(v) State.TeamCheck = v end })
    R:AddToggle("WallCheck",  { Text = "Wall Check",                 Default = false, Callback = function(v) State.WallCheck = v end })
end

-- Visuals
do
    local L = Tabs.Visuals:AddLeftGroupbox("ESP")
    L:AddToggle("ESP",     { Text = "Highlight ESP",     Default = false, Callback = function(v) State.ESP = v end })
    L:AddToggle("NameTag", { Text = "Name + Distance",   Default = false, Callback = function(v) State.NameTag = v end })
    L:AddLabel("ESP Color"):AddColorPicker("ESPColor", {
        Default = Color3.fromRGB(255, 50, 50),
        Callback = function(c) State.ESPColor = c end,
    })

    local R = Tabs.Visuals:AddRightGroupbox("Controls")
    R:AddButton("Unload", function()
        for _, pack in pairs(espCache) do
            for _, inst in pairs(pack) do if typeof(inst) == "Instance" then inst:Destroy() end end
        end
        Library:Unload()
        _G.NEXTHUB_LOADED = nil
    end)
end

-- System
do
    Tabs.System:AddLeftGroupbox("About"):AddLabel("NEXT HUB v2.0  —  PORBOX build")
end

-- Menu toggle via R-Shift
UIS.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.KeyCode == Enum.KeyCode.RightShift then
        Library.Toggled = not Library.Toggled
    end
    if State.TriggerMode == "Toggle Key" and input.KeyCode == State.HoldKey then
        toggleState = not toggleState
    end
end)

-- ============================================================
-- 4) Target discovery — scan workspace, not Players
-- ============================================================
local function getPart(char)
    if not char then return nil end
    local wanted = State.AimPoint
    local part = char:FindFirstChild(wanted)
    if part and part:IsA("BasePart") then return part end
    -- fallbacks
    for _, name in ipairs({ "HumanoidRootPart", "Torso", "UpperTorso", "LowerTorso", "Head" }) do
        local p = char:FindFirstChild(name)
        if p and p:IsA("BasePart") then return p end
    end
    return nil
end

local function isMyChar(model)
    return model == LP.Character
end

local function playerOwnerOf(model)
    for _, p in ipairs(Players:GetPlayers()) do
        if p.Character == model then return p end
    end
    return nil
end

local function lineOfSight(myHead, targetPart)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { LP.Character, Cam() }
    local r = workspace:Raycast(myHead.Position, targetPart.Position - myHead.Position, params)
    if not r then return true end
    return r.Instance:IsDescendantOf(targetPart.Parent)
end

local function iterateCharacters()
    -- yield (model, humanoid) for every alive Humanoid in workspace
    local out = {}
    for _, hum in ipairs(CollectionServiceSafe()) do
        local model = hum.Parent
        if model and hum.Health > 0 and not isMyChar(model) then
            table.insert(out, { model = model, hum = hum })
        end
    end
    return out
end

-- avoid using CollectionService (needs tags); scan descendants instead
function CollectionServiceSafe()
    local hums = {}
    for _, d in ipairs(workspace:GetDescendants()) do
        if d:IsA("Humanoid") then table.insert(hums, d) end
    end
    return hums
end

local function getBestTarget()
    local cam = Cam()
    local center = Vector2.new(cam.ViewportSize.X / 2, cam.ViewportSize.Y / 2)
    local fovPx = math.tan(math.rad(State.FOV) / 2) * cam.ViewportSize.Y
    local bestDist, bestPart = fovPx, nil

    local myHead = LP.Character and LP.Character:FindFirstChild("Head")

    for _, entry in ipairs(iterateCharacters()) do
        local model, hum = entry.model, entry.hum

        if State.IgnoreNPCs then
            if not playerOwnerOf(model) then continue end
        end
        if State.TeamCheck then
            local p = playerOwnerOf(model)
            if p and p.Team and p.Team == LP.Team then continue end
        end

        local part = getPart(model)
        if not part then continue end

        local screenPos, onScreen = cam:WorldToViewportPoint(part.Position)
        if not onScreen then continue end

        local dist = (Vector2.new(screenPos.X, screenPos.Y) - center).Magnitude
        if dist > bestDist then continue end

        if State.WallCheck and myHead then
            if not lineOfSight(myHead, part) then continue end
        end

        bestDist, bestPart = dist, part
    end
    return bestPart
end

-- ============================================================
-- 5) Aimbot loop
-- ============================================================
RunService.RenderStepped:Connect(function()
    if not State.Aimbot then return end
    local mode = State.TriggerMode
    local active = false
    if     mode == "Hold Key"   then active = UIS:IsKeyDown(State.HoldKey)
    elseif mode == "Toggle Key" then active = toggleState
    elseif mode == "Always"     then active = true
    end
    if not active then return end

    local target = getBestTarget()
    if not target then return end

    local cam = Cam()
    local goal = CFrame.new(cam.CFrame.Position, target.Position)
    cam.CFrame = cam.CFrame:Lerp(goal, State.Smoothing)
end)

-- ============================================================
-- 6) No Recoil (lock camera pitch)
-- ============================================================
RunService.RenderStepped:Connect(function()
    if not State.NoRecoil then return end
    local cam = Cam()
    local cf = cam.CFrame
    local x, y, _ = cf:ToEulerAnglesYXZ()
    cam.CFrame = CFrame.new(cf.Position) * CFrame.fromEulerAnglesYXZ(math.clamp(x, -1.4, 1.4), y, 0)
end)

-- ============================================================
-- 7) ESP — Highlight + BillboardGui on every Humanoid
-- ============================================================
local function makeEsp(model)
    local pack = {}
    if State.ESP then
        local h = Instance.new("Highlight")
        h.FillColor = State.ESPColor
        h.OutlineColor = Color3.new(1, 1, 1)
        h.FillTransparency = 0.5
        h.OutlineTransparency = 0
        h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        h.Parent = model
        pack.h = h
    end
    if State.NameTag then
        local hrp = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Head")
        if hrp then
            local bb = Instance.new("BillboardGui")
            bb.Size = UDim2.new(0, 140, 0, 40)
            bb.StudsOffset = Vector3.new(0, 3, 0)
            bb.AlwaysOnTop = true
            bb.Parent = hrp
            local lbl = Instance.new("TextLabel")
            lbl.Size = UDim2.new(1, 0, 1, 0)
            lbl.BackgroundTransparency = 1
            lbl.TextColor3 = Color3.fromRGB(255, 255, 0)
            lbl.TextStrokeTransparency = 0
            lbl.Font = Enum.Font.GothamBold
            lbl.TextScaled = true
            lbl.Parent = bb
            pack.bb, pack.lbl, pack.hrp = bb, lbl, hrp
        end
    end
    espCache[model] = pack
end

local function clearEsp(model)
    local pack = espCache[model]
    if not pack then return end
    for _, v in pairs(pack) do
        if typeof(v) == "Instance" and v.Parent then v:Destroy() end
    end
    espCache[model] = nil
end

RunService.Heartbeat:Connect(function()
    local wants = State.ESP or State.NameTag
    local seen  = {}

    for _, entry in ipairs(iterateCharacters()) do
        local model = entry.model
        seen[model] = true
        local pack = espCache[model]

        if wants and not pack then
            makeEsp(model)
        elseif not wants and pack then
            clearEsp(model)
        end

        pack = espCache[model]
        if pack then
            if pack.h and State.ESP then pack.h.FillColor = State.ESPColor end
            if not State.ESP and pack.h then pack.h:Destroy(); pack.h = nil end

            if State.NameTag and not pack.bb then
                clearEsp(model); makeEsp(model); pack = espCache[model]
            end
            if not State.NameTag and pack.bb then
                pack.bb:Destroy(); pack.bb = nil; pack.lbl = nil; pack.hrp = nil
            end

            if pack.lbl and LP.Character then
                local myHrp = LP.Character:FindFirstChild("HumanoidRootPart") or LP.Character:FindFirstChild("Head")
                if myHrp and pack.hrp then
                    local d = (pack.hrp.Position - myHrp.Position).Magnitude
                    pack.lbl.Text = (model.Name or "?") .. "\n" .. math.floor(d) .. "m"
                end
            end
        end
    end

    -- clear ESP for models that went away
    for model, _ in pairs(espCache) do
        if not seen[model] then clearEsp(model) end
    end
end)

print("[NextHub] v2.0 loaded on " .. game.PlaceId .. " — scans workspace Humanoids")
