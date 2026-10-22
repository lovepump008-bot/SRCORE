--[[
    NEXT HUB — PORBOX PVP  v11
    Modes: Snap / Smooth / Silent / Mouse Delta
    Silent = redirect bullets without moving camera (hook namecall + Mouse.Hit + raycast)
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
    Mode      = "Snap",        -- Snap / Smooth / Silent / Mouse Delta
    AimPart   = "Head",
    SmoothLerp= 0.35,
    ESP       = false,
    NameTag   = false,
    NoRecoil  = false,
}

local AIM_FOV_PX    = 1400
local AIM_PREDICT   = 0.14
local ESP_MAX       = 20
local ESP_MAX_DIST  = 1500

-- ============================================================
-- Window
-- ============================================================
local Window = Library:CreateWindow({
    Title = "NEXT HUB  |  v11  |  PORBOX",
    Center = true, AutoShow = true, TabPadding = 8, MenuFadeTime = 0.2,
})
local Tabs = { Main = Window:AddTab("Main"), More = Window:AddTab("More") }

do
    local L = Tabs.Main:AddLeftGroupbox("Combat")
    L:AddToggle("Aimbot", { Text = "Aimbot (hold Right Mouse or E)", Default = false,
        Callback = function(v) State.Aimbot = v end })
    L:AddDropdown("Mode", {
        Text = "Mode",
        Values = { "Snap", "Smooth", "Silent", "Mouse Delta" },
        Default = "Snap",
        Callback = function(v) State.Mode = v end,
    })
    L:AddDropdown("AimPart", {
        Text = "Aim at",
        Values = { "Head", "HumanoidRootPart", "UpperTorso", "Torso" },
        Default = "Head",
        Callback = function(v) State.AimPart = v end,
    })
    L:AddSlider("SmoothLerp", {
        Text = "Smooth strength", Default = 0.35, Min = 0.05, Max = 1, Rounding = 2,
        Callback = function(v) State.SmoothLerp = v end,
    })
    L:AddToggle("NoRecoil", { Text = "No Recoil (cam lock)", Default = false,
        Callback = function(v) State.NoRecoil = v end })

    local R = Tabs.Main:AddRightGroupbox("ESP")
    R:AddToggle("ESP",     { Text = "Highlight players", Default = false, Callback = function(v) State.ESP = v end })
    R:AddToggle("NameTag", { Text = "Name + Distance",   Default = false, Callback = function(v) State.NameTag = v end })

    local M = Tabs.Main:AddLeftGroupbox("Mode guide")
    M:AddLabel("Snap: camera jumps to target (crude)")
    M:AddLabel("Smooth: lerp — looks natural")
    M:AddLabel("Silent: NO camera move, bullets redirect")
    M:AddLabel("Mouse Delta: moves OS mouse")

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
    L:AddLabel("Hold Right Mouse OR E = aim")
end

-- UI toggle
UIS.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.KeyCode == Enum.KeyCode.RightShift
    or input.KeyCode == Enum.KeyCode.Insert
    or input.KeyCode == Enum.KeyCode.End then
        pcall(function() Library.Toggled = not Library.Toggled end)
    end
end)

-- ============================================================
-- Humanoid cache
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
-- Target picker
-- ============================================================
local function getPart(model)
    local p = model:FindFirstChild(State.AimPart)
    if p and p:IsA("BasePart") then return p end
    for _, n in ipairs({ "Head", "HumanoidRootPart", "UpperTorso", "Torso" }) do
        local q = model:FindFirstChild(n)
        if q and q:IsA("BasePart") then return q end
    end
    return nil
end

local function keyDown()
    return UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
        or UIS:IsKeyDown(Enum.KeyCode.E)
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

-- Shared target state (also used by Silent hooks)
local silentTarget = nil

local function getAimPos()
    local t = silentTarget
    if not t or not t.Parent then return nil end
    local pos = t.Position
    local v = t.AssemblyLinearVelocity
    if typeof(v) == "Vector3" then pos = pos + v * AIM_PREDICT end
    return pos, t
end

-- ============================================================
-- Modes 1-2-4 (Snap / Smooth / Mouse Delta) — uses BindToRenderStep
-- ============================================================
local AIM_BIND = "SRCORE_AIM"
pcall(function() RunService:UnbindFromRenderStep(AIM_BIND) end)

local wasDown = false
local MMR = rawget(getfenv(), "mousemoverel") or mousemoverel

RunService:BindToRenderStep(AIM_BIND, Enum.RenderPriority.Camera.Value + 10, function()
    if not State.Aimbot then
        silentTarget = nil; wasDown = false; return
    end
    local down = keyDown()
    if not down then
        silentTarget = nil; wasDown = false; return
    end

    -- lock target on press, keep until released / dead
    if not wasDown then
        wasDown = true
        silentTarget = getTarget()
    else
        if not silentTarget or not silentTarget.Parent then
            silentTarget = getTarget()
        else
            local hum = silentTarget.Parent:FindFirstChildOfClass("Humanoid")
            if not hum or hum.Health <= 0 then silentTarget = getTarget() end
        end
    end

    if State.Mode == "Silent" then return end  -- Silent handled by hooks

    local pos, t = getAimPos()
    if not pos then return end
    local cam = Cam()

    if State.Mode == "Snap" then
        pcall(function() cam.CFrame = CFrame.new(cam.CFrame.Position, pos) end)
    elseif State.Mode == "Smooth" then
        local goal = CFrame.new(cam.CFrame.Position, pos)
        pcall(function() cam.CFrame = cam.CFrame:Lerp(goal, State.SmoothLerp) end)
    elseif State.Mode == "Mouse Delta" then
        if MMR then
            local sp, on = cam:WorldToViewportPoint(pos)
            if on then
                local c = cam.ViewportSize / 2
                pcall(MMR, (sp.X - c.X) * State.SmoothLerp, (sp.Y - c.Y) * State.SmoothLerp)
            end
        end
    end
end)

-- ============================================================
-- Mode 3: SILENT — redirect bullets by rewriting args / rays
-- ============================================================
do
    local meta  = getrawmetatable(game)
    local setro = setreadonly or make_writeable
    local oldNC = meta.__namecall
    local oldIndex = meta.__index

    if setro and newcclosure and checkcaller and hookfunction then
        setro(meta, false)

        -- Hook __namecall for FireServer / InvokeServer
        meta.__namecall = newcclosure(function(self, ...)
            if State.Aimbot and State.Mode == "Silent" and silentTarget and silentTarget.Parent then
                local method = getnamecallmethod and getnamecallmethod() or ""
                if method == "FireServer" or method == "InvokeServer" then
                    local args = { ... }
                    local pos = silentTarget.Position
                    local hit = silentTarget
                    local changed = false
                    for i, a in ipairs(args) do
                        if typeof(a) == "Vector3" then args[i] = pos; changed = true
                        elseif typeof(a) == "CFrame" then args[i] = CFrame.new(pos); changed = true
                        elseif typeof(a) == "Instance" and a:IsA("BasePart") then
                            if a.Name == "Head" or a.Name == "HumanoidRootPart" or a.Name == "UpperTorso"
                               or a.Name == "Torso" or a.Name == "LowerTorso" then
                                args[i] = hit; changed = true
                            end
                        end
                    end
                    if changed then return oldNC(self, unpack(args)) end
                end
            end
            return oldNC(self, ...)
        end)

        -- Hook __index for Mouse.Hit / Mouse.Target
        meta.__index = newcclosure(function(self, k)
            if State.Aimbot and State.Mode == "Silent" and silentTarget and silentTarget.Parent then
                if typeof(self) == "Instance" and self:IsA("PlayerMouse") then
                    if k == "Hit" then return CFrame.new(silentTarget.Position) end
                    if k == "Target" then return silentTarget end
                    if k == "UnitRay" then
                        local cam = Cam()
                        return Ray.new(cam.CFrame.Position, (silentTarget.Position - cam.CFrame.Position).Unit)
                    end
                end
            end
            return oldIndex(self, k)
        end)

        setro(meta, true)
        print("[NextHub] silent hooks installed")
    else
        warn("[NextHub] executor missing setreadonly/newcclosure/hookfunction — Silent mode disabled")
    end
end

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
-- ESP
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
            local r = ranked[i]; keep[r.model] = true
            local pack = espCache[r.model] or {}; espCache[r.model] = pack

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
                lbl.Size = UDim2.new(1,0,1,0); lbl.BackgroundTransparency = 1
                lbl.TextColor3 = Color3.fromRGB(255,255,0); lbl.TextStrokeTransparency = 0
                lbl.Font = Enum.Font.GothamBold; lbl.TextScaled = true; lbl.Parent = bb
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

print("[NextHub] v11 loaded  —  modes: Snap / Smooth / Silent / Mouse Delta")
