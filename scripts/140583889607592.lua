--[[
    NEXT HUB — PORBOX PVP v3
    - Cached humanoid scan (fix FPS drop)
    - FOV circle (Drawing API)
    - Aim key = Right Mouse Button (E can conflict with game)
    - Debug print when target locked
]]

local repo = "https://raw.githubusercontent.com/violin-suzutsuki/LinoriaLib/main/"
local Library = loadstring(game:HttpGet(repo .. "Library.lua"))()

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS        = game:GetService("UserInputService")
local LP         = Players.LocalPlayer
local function Cam() return workspace.CurrentCamera end

local State = {
    Aimbot      = false,
    TriggerMode = "Hold Key",
    AimKey      = "MouseRight",   -- "MouseRight" / "MouseLeft" / "E" / "Q" / "C"
    AimPoint    = "Head",
    FOV         = 180,
    Smoothing   = 0.4,
    IgnoreNPCs  = false,
    TeamCheck   = false,
    WallCheck   = false,

    ShowFOV     = true,
    FOVColor    = Color3.fromRGB(255, 255, 255),

    ESP         = false,
    NameTag     = false,
    ESPColor    = Color3.fromRGB(255, 50, 50),

    NoRecoil    = false,
}

local toggleState = false
local espCache    = {}

-- ============================================================
-- UI
-- ============================================================
local Window = Library:CreateWindow({
    Title = "NEXT HUB  |  v3  |  PORBOX",
    Center = true, AutoShow = true, TabPadding = 8, MenuFadeTime = 0.2,
})

local Tabs = {
    Home    = Window:AddTab("Home"),
    Combat  = Window:AddTab("Combat"),
    Visuals = Window:AddTab("Visuals"),
    System  = Window:AddTab("System"),
}

do
    local b = Tabs.Home:AddLeftGroupbox("Info")
    b:AddLabel("Place:   " .. game.PlaceId)
    b:AddLabel("Player:  " .. LP.Name)
    b:AddLabel("UI Toggle:   Right Shift")
    b:AddLabel("Aimbot Key:  Right Mouse (default)")
end

-- Combat
do
    local L = Tabs.Combat:AddLeftGroupbox("Aimbot")
    local R = Tabs.Combat:AddRightGroupbox("Filters")

    L:AddToggle("Aimbot", { Text = "Aimbot", Default = false, Callback = function(v) State.Aimbot = v end })
    L:AddToggle("NoRecoil", { Text = "No Recoil (cam lock)", Default = false, Callback = function(v) State.NoRecoil = v end })

    L:AddDropdown("TriggerMode", {
        Text = "Trigger", Values = { "Hold Key", "Toggle Key", "Always" }, Default = "Hold Key",
        Callback = function(v) State.TriggerMode = v end,
    })
    L:AddDropdown("AimKey", {
        Text = "Aim Key",
        Values = { "MouseRight", "MouseLeft", "E", "Q", "C", "F", "V" },
        Default = "MouseRight",
        Callback = function(v) State.AimKey = v end,
    })
    L:AddDropdown("AimPoint", {
        Text = "Aim Point",
        Values = { "Head", "HumanoidRootPart", "UpperTorso", "Torso" },
        Default = "Head",
        Callback = function(v) State.AimPoint = v end,
    })
    L:AddSlider("FOV", { Text = "FOV (deg)", Default = 180, Min = 10, Max = 360, Rounding = 0,
        Callback = function(v) State.FOV = v end })
    L:AddSlider("Smoothing", { Text = "Smoothing", Default = 0.4, Min = 0.05, Max = 1, Rounding = 2,
        Callback = function(v) State.Smoothing = v end })

    R:AddToggle("IgnoreNPCs", { Text = "Ignore NPCs (players only)", Default = false, Callback = function(v) State.IgnoreNPCs = v end })
    R:AddToggle("TeamCheck",  { Text = "Team Check",                 Default = false, Callback = function(v) State.TeamCheck = v end })
    R:AddToggle("WallCheck",  { Text = "Wall Check",                 Default = false, Callback = function(v) State.WallCheck = v end })
end

-- Visuals
do
    local L = Tabs.Visuals:AddLeftGroupbox("ESP")
    L:AddToggle("ESP",     { Text = "Highlight ESP",   Default = false, Callback = function(v) State.ESP = v end })
    L:AddToggle("NameTag", { Text = "Name + Distance", Default = false, Callback = function(v) State.NameTag = v end })
    L:AddLabel("ESP Color"):AddColorPicker("ESPColor", {
        Default = Color3.fromRGB(255, 50, 50),
        Callback = function(c) State.ESPColor = c end,
    })

    local R = Tabs.Visuals:AddRightGroupbox("FOV")
    R:AddToggle("ShowFOV", { Text = "Show FOV circle", Default = true, Callback = function(v)
        State.ShowFOV = v
    end })
    R:AddLabel("FOV Color"):AddColorPicker("FOVColor", {
        Default = Color3.fromRGB(255, 255, 255),
        Callback = function(c) State.FOVColor = c end,
    })

    local S = Tabs.Visuals:AddLeftGroupbox("Controls")
    S:AddButton("Unload", function()
        for _, pack in pairs(espCache) do
            for _, inst in pairs(pack) do if typeof(inst) == "Instance" then inst:Destroy() end end
        end
        espCache = {}
        if fovCircle then fovCircle:Remove(); fovCircle = nil end
        Library:Unload()
        _G.NEXTHUB_LOADED = nil
    end)
end

do
    Tabs.System:AddLeftGroupbox("About"):AddLabel("NEXT HUB v3  —  PORBOX build  (cached scan)")
end

-- R-Shift toggle UI + toggle-mode key
UIS.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.KeyCode == Enum.KeyCode.RightShift then
        Library.Toggled = not Library.Toggled
    end
end)

-- ============================================================
-- Humanoid cache (refreshed every 0.25s)
-- ============================================================
local humanoidCache = {}
task.spawn(function()
    while true do
        local list = {}
        for _, d in ipairs(workspace:GetDescendants()) do
            if d:IsA("Humanoid") and d.Health > 0 and d.Parent and d.Parent ~= LP.Character then
                table.insert(list, { hum = d, model = d.Parent })
            end
        end
        humanoidCache = list
        task.wait(0.25)
    end
end)

local function playerOwnerOf(model)
    for _, p in ipairs(Players:GetPlayers()) do
        if p.Character == model then return p end
    end
    return nil
end

local function keyHeld()
    local k = State.AimKey
    if     k == "MouseRight" then return UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
    elseif k == "MouseLeft"  then return UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
    elseif k == "E" then return UIS:IsKeyDown(Enum.KeyCode.E)
    elseif k == "Q" then return UIS:IsKeyDown(Enum.KeyCode.Q)
    elseif k == "C" then return UIS:IsKeyDown(Enum.KeyCode.C)
    elseif k == "F" then return UIS:IsKeyDown(Enum.KeyCode.F)
    elseif k == "V" then return UIS:IsKeyDown(Enum.KeyCode.V)
    end
    return false
end

UIS.InputBegan:Connect(function(input, processed)
    if processed then return end
    if State.TriggerMode == "Toggle Key" then
        local k = State.AimKey
        local match = false
        if k == "MouseRight" and input.UserInputType == Enum.UserInputType.MouseButton2 then match = true end
        if k == "MouseLeft"  and input.UserInputType == Enum.UserInputType.MouseButton1 then match = true end
        if input.UserInputType == Enum.UserInputType.Keyboard and tostring(input.KeyCode) == "Enum.KeyCode." .. k then match = true end
        if match then toggleState = not toggleState end
    end
end)

-- ============================================================
-- Target
-- ============================================================
local function getPart(model)
    local wanted = State.AimPoint
    local p = model:FindFirstChild(wanted)
    if p and p:IsA("BasePart") then return p end
    for _, n in ipairs({ "HumanoidRootPart", "UpperTorso", "Torso", "LowerTorso", "Head" }) do
        local q = model:FindFirstChild(n)
        if q and q:IsA("BasePart") then return q end
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

local function getTarget()
    local cam = Cam()
    local center = Vector2.new(cam.ViewportSize.X / 2, cam.ViewportSize.Y / 2)
    local fovPx = math.tan(math.rad(State.FOV) / 2) * cam.ViewportSize.Y
    local best, bestPart = fovPx, nil
    local myHead = LP.Character and LP.Character:FindFirstChild("Head")

    for _, e in ipairs(humanoidCache) do
        local model = e.model
        if not model.Parent then continue end
        if State.IgnoreNPCs and not playerOwnerOf(model) then continue end
        if State.TeamCheck then
            local p = playerOwnerOf(model)
            if p and p.Team and p.Team == LP.Team then continue end
        end
        local part = getPart(model)
        if not part then continue end
        local sp, onScreen = cam:WorldToViewportPoint(part.Position)
        if not onScreen then continue end
        local dist = (Vector2.new(sp.X, sp.Y) - center).Magnitude
        if dist > best then continue end
        if State.WallCheck and myHead and not lineOfSight(myHead, part) then continue end
        best, bestPart = dist, part
    end
    return bestPart
end

-- ============================================================
-- Aimbot
-- ============================================================
local lastDebug = 0
RunService.RenderStepped:Connect(function()
    if not State.Aimbot then return end
    local mode = State.TriggerMode
    local active = false
    if     mode == "Hold Key"   then active = keyHeld()
    elseif mode == "Toggle Key" then active = toggleState
    elseif mode == "Always"     then active = true
    end
    if not active then return end

    local target = getTarget()
    if not target then
        if tick() - lastDebug > 1 then
            print("[NextHub] no target in FOV")
            lastDebug = tick()
        end
        return
    end

    local cam = Cam()
    local goal = CFrame.new(cam.CFrame.Position, target.Position)
    cam.CFrame = cam.CFrame:Lerp(goal, State.Smoothing)
end)

-- No Recoil
RunService.RenderStepped:Connect(function()
    if not State.NoRecoil then return end
    local cam = Cam()
    local cf = cam.CFrame
    local x, y, _ = cf:ToEulerAnglesYXZ()
    cam.CFrame = CFrame.new(cf.Position) * CFrame.fromEulerAnglesYXZ(math.clamp(x, -1.4, 1.4), y, 0)
end)

-- ============================================================
-- FOV circle (Drawing API)
-- ============================================================
local fovCircle = nil
if Drawing then
    local ok, circle = pcall(function() return Drawing.new("Circle") end)
    if ok and circle then
        fovCircle = circle
        fovCircle.Thickness = 1.5
        fovCircle.Transparency = 1
        fovCircle.Filled = false
    end
end

RunService.RenderStepped:Connect(function()
    if not fovCircle then return end
    if not State.ShowFOV then fovCircle.Visible = false; return end
    local cam = Cam()
    local fovPx = math.tan(math.rad(State.FOV) / 2) * cam.ViewportSize.Y
    fovCircle.Position = Vector2.new(cam.ViewportSize.X / 2, cam.ViewportSize.Y / 2)
    fovCircle.Radius = fovPx
    fovCircle.Color = State.FOVColor
    fovCircle.Visible = true
end)

-- ============================================================
-- ESP (cached scan — same loop)
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

-- update ESP + label distance every frame (fast), but add/remove only on cache refresh (0.25s)
task.spawn(function()
    while true do
        local wants = State.ESP or State.NameTag
        local seen  = {}
        for _, e in ipairs(humanoidCache) do
            local model = e.model
            seen[model] = true
            if wants and not espCache[model] then
                makeEsp(model)
            elseif not wants and espCache[model] then
                clearEsp(model)
            end
            local pack = espCache[model]
            if pack then
                if State.ESP and not pack.h then
                    local h = Instance.new("Highlight")
                    h.FillColor = State.ESPColor
                    h.OutlineColor = Color3.new(1, 1, 1)
                    h.FillTransparency = 0.5
                    h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                    h.Parent = model
                    pack.h = h
                elseif not State.ESP and pack.h then
                    pack.h:Destroy(); pack.h = nil
                end
                if State.NameTag and not pack.bb then
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
                elseif not State.NameTag and pack.bb then
                    pack.bb:Destroy(); pack.bb = nil; pack.lbl = nil; pack.hrp = nil
                end
            end
        end
        for model, _ in pairs(espCache) do
            if not seen[model] then clearEsp(model) end
        end
        task.wait(0.25)
    end
end)

-- Update highlight color + distance label frequently (cheap)
RunService.Heartbeat:Connect(function()
    local myHrp = LP.Character and (LP.Character:FindFirstChild("HumanoidRootPart") or LP.Character:FindFirstChild("Head"))
    for model, pack in pairs(espCache) do
        if pack.h and State.ESP then pack.h.FillColor = State.ESPColor end
        if pack.lbl and pack.hrp and pack.hrp.Parent and myHrp then
            local d = (pack.hrp.Position - myHrp.Position).Magnitude
            pack.lbl.Text = (model.Name or "?") .. "\n" .. math.floor(d) .. "m"
        end
    end
end)

print("[NextHub] v3 loaded — cached scan, FOV circle, right-mouse aim")
