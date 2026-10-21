--[[
    NEXT HUB — PlaceId 140583889607592
    UI: LinoriaLib
    Toggle: Right Shift
]]

-- ============================================================
-- 1) Load LinoriaLib
-- ============================================================
local repo = "https://raw.githubusercontent.com/violin-suzutsuki/LinoriaLib/main/"

local Library       = loadstring(game:HttpGet(repo .. "Library.lua"))()
local ThemeManager  = loadstring(game:HttpGet(repo .. "addons/ThemeManager.lua"))()
local SaveManager   = loadstring(game:HttpGet(repo .. "addons/SaveManager.lua"))()

-- ============================================================
-- 2) Services + State
-- ============================================================
local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS        = game:GetService("UserInputService")
local Camera     = workspace.CurrentCamera
local LP         = Players.LocalPlayer

local State = {
    Aimbot      = false,
    NoRecoil    = false,
    NoSpread    = false,
    TriggerMode = "Hold Key",
    AimPoint    = "Head",
    FOV         = 60,
    Smoothing   = 0.25,
    TeamCheck   = true,
    WallCheck   = false,
    HoldKey     = Enum.KeyCode.E,
    ESP         = false,
    NameTag     = false,
    ESPColor    = Color3.fromRGB(255, 0, 0),
}

local toggleState = false
local espCache    = {}

-- ============================================================
-- 3) Window
-- ============================================================
local Window = Library:CreateWindow({
    Title        = "NEXT HUB  |  v1.0",
    Center       = true,
    AutoShow     = true,
    TabPadding   = 8,
    MenuFadeTime = 0.2,
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
end

-- Combat
do
    local L = Tabs.Combat:AddLeftGroupbox("Aimbot")
    local R = Tabs.Combat:AddRightGroupbox("Filters")

    L:AddToggle("Aimbot",   { Text = "Aimbot",         Default = false, Callback = function(v) State.Aimbot = v end })
    L:AddToggle("NoRecoil", { Text = "No Recoil (Aim)",Default = false, Callback = function(v) State.NoRecoil = v end })
    L:AddToggle("NoSpread", { Text = "No Spread",      Default = false, Callback = function(v) State.NoSpread = v end })

    L:AddDropdown("TriggerMode", {
        Text = "Trigger",
        Values = { "Hold Key", "Toggle Key", "Always", "Mobile Fire" },
        Default = "Hold Key",
        Callback = function(v) State.TriggerMode = v end,
    })

    L:AddDropdown("AimPoint", {
        Text = "Aim Point",
        Values = { "Head", "HumanoidRootPart", "UpperTorso", "LowerTorso" },
        Default = "Head",
        Callback = function(v) State.AimPoint = v end,
    })

    L:AddSlider("FOV", {
        Text = "FOV (deg)", Default = 60, Min = 10, Max = 360, Rounding = 0,
        Callback = function(v) State.FOV = v end,
    })

    L:AddSlider("Smoothing", {
        Text = "Smoothing", Default = 0.25, Min = 0.05, Max = 1, Rounding = 2,
        Callback = function(v) State.Smoothing = v end,
    })

    R:AddToggle("TeamCheck", { Text = "Team Check", Default = true,  Callback = function(v) State.TeamCheck = v end })
    R:AddToggle("WallCheck", { Text = "Wall Check", Default = false, Callback = function(v) State.WallCheck = v end })
    R:AddKeyPicker("HoldKey", { Text = "Aimbot Key", Default = "E", Mode = "Hold", Callback = function() end })
end

-- Visuals
do
    local L = Tabs.Visuals:AddLeftGroupbox("ESP")
    L:AddToggle("ESP",     { Text = "Highlight ESP",     Default = false, Callback = function(v) State.ESP = v end })
    L:AddToggle("NameTag", { Text = "Name + Distance",   Default = false, Callback = function(v) State.NameTag = v end })
    L:AddLabel("ESP Color"):AddColorPicker("ESPColor", {
        Default = Color3.fromRGB(255, 0, 0),
        Callback = function(c) State.ESPColor = c end,
    })
end

-- System
do
    ThemeManager:SetLibrary(Library)
    SaveManager:SetLibrary(Library)
    SaveManager:IgnoreThemeSettings()
    SaveManager:SetIgnoreIndexes({})
    ThemeManager:SetFolder("NextHub")
    SaveManager:SetFolder("NextHub")
    SaveManager:BuildConfigSection(Tabs.System)
    ThemeManager:ApplyToTab(Tabs.System)
    pcall(function() SaveManager:LoadAutoloadConfig() end)
end

-- Menu toggle via R-Shift
if Library.SetMenuKeybind then
    pcall(function() Library:SetMenuKeybind(Enum.KeyCode.RightShift) end)
end

-- ============================================================
-- 4) Target selection
-- ============================================================
local function hasLineOfSight(fromPart, toPart)
    local origin = fromPart.Position
    local dir    = (toPart.Position - origin)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { LP.Character, Camera }
    local hit = workspace:Raycast(origin, dir, params)
    if not hit then return true end
    return hit.Instance:IsDescendantOf(toPart.Parent)
end

local function getTarget()
    local center = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
    local fovPx  = math.tan(math.rad(State.FOV) / 2) * Camera.ViewportSize.Y
    local best, bestPart = fovPx, nil

    for _, p in ipairs(Players:GetPlayers()) do
        if p == LP then continue end
        if State.TeamCheck and p.Team and p.Team == LP.Team then continue end

        local char = p.Character
        if not char then continue end
        local hum  = char:FindFirstChildOfClass("Humanoid")
        local part = char:FindFirstChild(State.AimPoint) or char:FindFirstChild("HumanoidRootPart")
        if not (hum and part) or hum.Health <= 0 then continue end

        local screenPos, onScreen = Camera:WorldToViewportPoint(part.Position)
        if not onScreen then continue end

        local dist = (Vector2.new(screenPos.X, screenPos.Y) - center).Magnitude
        if dist > best then continue end

        if State.WallCheck and LP.Character and LP.Character:FindFirstChild("Head") then
            if not hasLineOfSight(LP.Character.Head, part) then continue end
        end

        best, bestPart = dist, part
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
    if     mode == "Hold Key"    then active = UIS:IsKeyDown(State.HoldKey)
    elseif mode == "Toggle Key"  then active = toggleState
    elseif mode == "Always"      then active = true
    elseif mode == "Mobile Fire" then active = UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
    end
    if not active then return end

    local target = getTarget()
    if not target then return end

    local goal = CFrame.new(Camera.CFrame.Position, target.Position)
    Camera.CFrame = Camera.CFrame:Lerp(goal, State.Smoothing)
end)

UIS.InputBegan:Connect(function(input, processed)
    if processed then return end
    if State.TriggerMode == "Toggle Key" and input.KeyCode == State.HoldKey then
        toggleState = not toggleState
    end
end)

-- ============================================================
-- 6) No Recoil (basic)
-- ============================================================
RunService.RenderStepped:Connect(function()
    if not State.NoRecoil then return end
    local char = LP.Character
    local tool = char and char:FindFirstChildOfClass("Tool")
    if not tool then return end
    local cf = Camera.CFrame
    local x, y, _ = cf:ToEulerAnglesYXZ()
    Camera.CFrame = CFrame.new(cf.Position) * CFrame.fromEulerAnglesYXZ(math.clamp(x, -1.4, 1.4), y, 0)
end)

-- ============================================================
-- 7) ESP / NameTag
-- ============================================================
local function clearEsp(p)
    if espCache[p] then
        for _, v in pairs(espCache[p]) do
            if typeof(v) == "Instance" and v.Parent then v:Destroy() end
        end
        espCache[p] = nil
    end
end

local function buildEsp(p)
    if p == LP then return end
    clearEsp(p)
    local char = p.Character
    if not char then return end

    local pack = {}
    if State.ESP then
        local h = Instance.new("Highlight")
        h.FillColor        = State.ESPColor
        h.OutlineColor     = Color3.new(1, 1, 1)
        h.FillTransparency = 0.5
        h.DepthMode        = Enum.HighlightDepthMode.AlwaysOnTop
        h.Parent           = char
        pack.h = h
    end
    if State.NameTag then
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if hrp then
            local bb = Instance.new("BillboardGui")
            bb.Size        = UDim2.new(0, 120, 0, 40)
            bb.StudsOffset = Vector3.new(0, 3, 0)
            bb.AlwaysOnTop = true
            bb.Parent      = hrp

            local lbl = Instance.new("TextLabel")
            lbl.Size                 = UDim2.new(1, 0, 1, 0)
            lbl.BackgroundTransparency = 1
            lbl.TextColor3           = Color3.fromRGB(255, 255, 0)
            lbl.TextStrokeTransparency = 0
            lbl.Font                 = Enum.Font.GothamBold
            lbl.TextScaled           = true
            lbl.Parent               = bb
            pack.bb, pack.lbl, pack.hrp = bb, lbl, hrp
        end
    end
    espCache[p] = pack
end

RunService.Heartbeat:Connect(function()
    for _, p in ipairs(Players:GetPlayers()) do
        if p == LP then continue end
        local wants = State.ESP or State.NameTag
        if wants and p.Character and not espCache[p] then
            buildEsp(p)
        elseif not wants and espCache[p] then
            clearEsp(p)
        end
        local cache = espCache[p]
        if cache then
            if cache.h and State.ESP then cache.h.FillColor = State.ESPColor end
            if cache.lbl and LP.Character then
                local myHrp = LP.Character:FindFirstChild("HumanoidRootPart")
                if myHrp and cache.hrp then
                    local d = (cache.hrp.Position - myHrp.Position).Magnitude
                    cache.lbl.Text = p.Name .. "\n" .. math.floor(d) .. "m"
                end
            end
        end
    end
end)

Players.PlayerRemoving:Connect(clearEsp)
Players.PlayerAdded:Connect(function(p)
    p.CharacterAdded:Connect(function()
        task.wait(0.5)
        if State.ESP or State.NameTag then buildEsp(p) end
    end)
end)

print("[NextHub] Combat script loaded on " .. game.PlaceId)
