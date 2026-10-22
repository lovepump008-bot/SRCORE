--[[
    NEXT HUB — PORBOX PVP  v8
    Minimal UX: just toggle + aim, no fiddly knobs
    Right Shift / Insert / End = toggle UI (multiple fallbacks)
]]

local repo = "https://raw.githubusercontent.com/violin-suzutsuki/LinoriaLib/main/"
local Library = loadstring(game:HttpGet(repo .. "Library.lua"))()

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS        = game:GetService("UserInputService")
local LP         = Players.LocalPlayer
local function Cam() return workspace.CurrentCamera end

local State = {
    Aimbot    = false,
    AimPart   = "Head",
    ESP       = false,
    NameTag   = false,
    NoRecoil  = false,
}

-- fixed sensible defaults (no sliders)
local AIM_FOV_PX    = 500        -- pixel radius from crosshair (no tan math — direct)
local AIM_SMOOTH    = 0.65       -- stronger
local AIM_PREDICT   = 0.12
local ESP_MAX       = 20
local ESP_MAX_DIST  = 1000
local AIM_KEY_MOUSE = Enum.UserInputType.MouseButton2

-- diagnostic once
do
    local mmr = rawget(getfenv(), "mousemoverel") or mousemoverel
    print("[NextHub] mousemoverel " .. (mmr and "AVAILABLE" or "MISSING"))
end

-- ============================================================
-- Window
-- ============================================================
local Window = Library:CreateWindow({
    Title = "NEXT HUB  |  v8",
    Center = true, AutoShow = true, TabPadding = 8, MenuFadeTime = 0.2,
})

local Tabs = {
    Main = Window:AddTab("Main"),
    More = Window:AddTab("More"),
}

do
    local L = Tabs.Main:AddLeftGroupbox("Combat")
    L:AddToggle("Aimbot", { Text = "Aimbot  (hold Right Mouse)", Default = false, Callback = function(v) State.Aimbot = v end })
    L:AddDropdown("AimPart", {
        Text = "Aim at",
        Values = { "Head", "HumanoidRootPart", "UpperTorso" },
        Default = "Head",
        Callback = function(v) State.AimPart = v end,
    })
    L:AddToggle("NoRecoil", { Text = "No Recoil (cam lock)", Default = false, Callback = function(v) State.NoRecoil = v end })

    local R = Tabs.Main:AddRightGroupbox("ESP")
    R:AddToggle("ESP",     { Text = "Highlight players", Default = false, Callback = function(v) State.ESP = v end })
    R:AddToggle("NameTag", { Text = "Name + Distance",   Default = false, Callback = function(v) State.NameTag = v end })

    local B = Tabs.Main:AddLeftGroupbox("Window")
    B:AddLabel("Press RIGHT SHIFT to hide/show UI")
    B:AddButton("Hide UI now", function() Library.Toggled = false end)
    B:AddButton("UNLOAD (remove everything)", function()
        State.Aimbot = false; State.ESP = false; State.NameTag = false; State.NoRecoil = false
        pcall(function() RunService:UnbindFromRenderStep("SRCORE_AIM") end)
        task.wait(0.2)
        for _, d in ipairs(workspace:GetDescendants()) do
            if d:IsA("Highlight") or d:IsA("BillboardGui") then d:Destroy() end
        end
        pcall(function() Library:Unload() end)
        _G.NEXTHUB_LOADED = nil
    end)
end

do
    local L = Tabs.More:AddLeftGroupbox("Info")
    L:AddLabel("Place:  " .. game.PlaceId)
    L:AddLabel("Player: " .. LP.Name)
    L:AddLabel("Aimbot: hold RIGHT MOUSE while enabled")
    L:AddLabel("Aim target = closest enemy to crosshair")
end

-- ============================================================
-- UI toggle — multiple fallbacks
-- ============================================================
local function toggleUI()
    pcall(function() Library.Toggled = not Library.Toggled end)
    -- also try common Linoria methods
    pcall(function() Library:Toggle() end)
end

UIS.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.KeyCode == Enum.KeyCode.RightShift
    or input.KeyCode == Enum.KeyCode.Insert
    or input.KeyCode == Enum.KeyCode.End then
        toggleUI()
    end
end)

-- ============================================================
-- Humanoid cache (0.25s)
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

-- ============================================================
-- Aim
-- ============================================================
local function getPart(model)
    local p = model:FindFirstChild(State.AimPart)
    if p and p:IsA("BasePart") then return p end
    for _, n in ipairs({ "HumanoidRootPart", "UpperTorso", "Torso", "Head" }) do
        local q = model:FindFirstChild(n)
        if q and q:IsA("BasePart") then return q end
    end
    return nil
end

local function getTarget()
    local cam = Cam()
    local center = Vector2.new(cam.ViewportSize.X / 2, cam.ViewportSize.Y / 2)
    local best, bestPart = AIM_FOV_PX, nil
    for _, e in ipairs(humanoidCache) do
        local model = e.model
        if not model.Parent then continue end
        local part = getPart(model)
        if not part then continue end
        local sp, onScreen = cam:WorldToViewportPoint(part.Position)
        if not onScreen then continue end
        local dist = (Vector2.new(sp.X, sp.Y) - center).Magnitude
        if dist < best then best, bestPart = dist, part end
    end
    return bestPart
end

-- Aim: 3-method attempt
local AIM_BIND_NAME = "SRCORE_AIM"
local MMR  = rawget(getfenv(), "mousemoverel") or mousemoverel
local VIM  = pcall(function() return game:GetService("VirtualInputManager") end) and game:GetService("VirtualInputManager") or nil

print("[NextHub] mmr=" .. tostring(MMR ~= nil) .. "  vim=" .. tostring(VIM ~= nil))

local function keyDown()
    return UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
        or UIS:IsKeyDown(Enum.KeyCode.E)
end

local lastAimDbg = 0
local function dbg(msg)
    if tick() - lastAimDbg > 1 then
        print("[aim] " .. msg)
        lastAimDbg = tick()
    end
end

pcall(function() RunService:UnbindFromRenderStep(AIM_BIND_NAME) end)

RunService:BindToRenderStep(AIM_BIND_NAME, Enum.RenderPriority.Camera.Value + 10, function()
    if not State.Aimbot then return end
    if not keyDown() then return end

    local cacheSize = #humanoidCache
    local target = getTarget()
    if not target then
        dbg("no target | humanoidCache=" .. cacheSize)
        return
    end

    local pos = target.Position
    local v = target.AssemblyLinearVelocity
    if typeof(v) == "Vector3" then pos = pos + v * AIM_PREDICT end

    local cam = Cam()
    local sp, onScreen = cam:WorldToViewportPoint(pos)
    if not onScreen then dbg("target not on screen"); return end

    local center = cam.ViewportSize / 2
    local dx = (sp.X - center.X) * AIM_SMOOTH
    local dy = (sp.Y - center.Y) * AIM_SMOOTH

    -- method 1: mousemoverel
    local m1 = false
    if MMR then m1 = pcall(MMR, dx, dy) end

    -- method 2: VirtualInputManager
    local m2 = false
    if VIM then
        m2 = pcall(function()
            VIM:SendMouseMoveEvent(sp.X, sp.Y, nil)
        end)
    end

    -- method 3: direct CFrame
    local cfBefore = cam.CFrame
    local goal = CFrame.new(cam.CFrame.Position, pos)
    local m3 = pcall(function() cam.CFrame = cam.CFrame:Lerp(goal, AIM_SMOOTH) end)
    local cfChanged = (cam.CFrame.LookVector - cfBefore.LookVector).Magnitude > 0.0001

    dbg(string.format("tgt=%s | dx=%.0f dy=%.0f | mmr=%s vim=%s cf=%s(moved=%s)",
        target.Parent and target.Parent.Name or "?",
        dx, dy, tostring(m1), tostring(m2), tostring(m3), tostring(cfChanged)))
end)

-- ============================================================
-- No Recoil
-- ============================================================
RunService.RenderStepped:Connect(function()
    if not State.NoRecoil then return end
    local cam = Cam()
    local cf = cam.CFrame
    local x, y, _ = cf:ToEulerAnglesYXZ()
    cam.CFrame = CFrame.new(cf.Position) * CFrame.fromEulerAnglesYXZ(math.clamp(x, -1.4, 1.4), y, 0)
end)

-- ============================================================
-- ESP (0.1s refresh, cap 20, 1000m)
-- ============================================================
local espCache = {}

local function clearEsp(model)
    local pack = espCache[model]; if not pack then return end
    for _, v in pairs(pack) do if typeof(v) == "Instance" and v.Parent then v:Destroy() end end
    espCache[model] = nil
end

task.spawn(function()
    while true do
        local wants = State.ESP or State.NameTag
        if not wants then
            for m, _ in pairs(espCache) do clearEsp(m) end
            task.wait(0.3); continue
        end
        local myHrp = LP.Character and (LP.Character:FindFirstChild("HumanoidRootPart") or LP.Character:FindFirstChild("Head"))
        if not myHrp then task.wait(0.1); continue end

        local ranked = {}
        for _, e in ipairs(humanoidCache) do
            local m = e.model
            local hrp = m:FindFirstChild("HumanoidRootPart") or m:FindFirstChild("Head")
            if hrp and m.Parent then
                local d = (hrp.Position - myHrp.Position).Magnitude
                if d <= ESP_MAX_DIST then
                    table.insert(ranked, { model = m, hrp = hrp, d = d })
                end
            end
        end
        table.sort(ranked, function(a, b) return a.d < b.d end)

        local keep = {}
        for i = 1, math.min(ESP_MAX, #ranked) do
            local r = ranked[i]
            keep[r.model] = true
            local pack = espCache[r.model] or {}
            espCache[r.model] = pack

            if State.ESP and not pack.h then
                local h = Instance.new("Highlight")
                h.FillColor = Color3.fromRGB(255, 40, 40)
                h.OutlineColor = Color3.new(1, 1, 1)
                h.FillTransparency = 0.5
                h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                h.Parent = r.model
                pack.h = h
            elseif not State.ESP and pack.h then
                pack.h:Destroy(); pack.h = nil
            end

            if State.NameTag and not pack.bb then
                local bb = Instance.new("BillboardGui")
                bb.Size = UDim2.new(0, 140, 0, 40)
                bb.StudsOffset = Vector3.new(0, 3, 0)
                bb.AlwaysOnTop = true
                bb.Parent = r.hrp
                local lbl = Instance.new("TextLabel")
                lbl.Size = UDim2.new(1, 0, 1, 0)
                lbl.BackgroundTransparency = 1
                lbl.TextColor3 = Color3.fromRGB(255, 255, 0)
                lbl.TextStrokeTransparency = 0
                lbl.Font = Enum.Font.GothamBold
                lbl.TextScaled = true
                lbl.Parent = bb
                pack.bb, pack.lbl, pack.hrp = bb, lbl, r.hrp
            elseif not State.NameTag and pack.bb then
                pack.bb:Destroy(); pack.bb = nil; pack.lbl = nil
            end

            if pack.lbl then pack.lbl.Text = (r.model.Name or "?") .. "\n" .. math.floor(r.d) .. "m" end
        end

        for m, _ in pairs(espCache) do
            if not keep[m] then clearEsp(m) end
        end
        task.wait(0.1)
    end
end)

print("[NextHub] v8 loaded  |  R-Shift / Insert / End = toggle UI")
