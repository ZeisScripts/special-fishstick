--!nocheck
-- RIVALS menu: aimbot, ESP, tracers, fly, infinite jump.
-- RightShift toggles the window. Settings persist to rivals_menu.json.

local Players      = game:GetService("Players")
local RunService   = game:GetService("RunService")
local UIS          = game:GetService("UserInputService")
local Workspace    = game:GetService("Workspace")
local Lighting     = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local HttpService  = game:GetService("HttpService")

local lp  = Players.LocalPlayer
local env = getgenv and getgenv() or _G

local THEME = {
    bg        = Color3.fromRGB(17, 17, 22),
    panel     = Color3.fromRGB(22, 22, 29),
    surface   = Color3.fromRGB(31, 31, 40),
    surface2  = Color3.fromRGB(41, 41, 53),
    accent    = Color3.fromRGB(140, 100, 255),
    accentAlt = Color3.fromRGB(196, 120, 255),
    text      = Color3.fromRGB(238, 238, 246),
    muted     = Color3.fromRGB(138, 138, 158),
    green     = Color3.fromRGB(92, 220, 145),
    red       = Color3.fromRGB(255, 82, 96),
    blue      = Color3.fromRGB(86, 156, 255),
    neutral   = Color3.fromRGB(196, 196, 210),
}

local FONT   = Enum.Font.Gotham
local FONT_B = Enum.Font.GothamBold

local TEAM_COLORS = {
    [1] = THEME.red,
    [2] = THEME.blue,
}

local CONFIG = {
    -- aimbot
    maxDistance = 700,
    smoothTime  = 0.06,
    stickiness  = 0.75,
    wallCheck   = true,
    autoFire    = true,
    fireRate    = 10,
    fireAngle   = 9,
    aimPart     = "Head",
    -- visuals
    espEnabled      = true,
    espEnemiesOnly  = false,
    espRange        = 1500,
    espThroughWalls = true,
    showNames       = true,
    showDistance    = true,
    showHealth      = true,
    showTracers     = true,
    -- movement
    flySpeed     = 60,
    infiniteJump = false,
    -- binds
    keyMenu   = Enum.KeyCode.RightShift,
    keyAimbot = Enum.KeyCode.R,
    keyAimOff = Enum.KeyCode.F,
    keyFly    = Enum.KeyCode.G,
}

local CONFIG_PATH = "rivals_menu.json"

local uiRefs = {}
local hooks = { aimbot = function() end, footer = function() end }
local toast = function() end
local updateFooter = function() end
local destroyMenu = function() end
local menuOpen = true
local connections = {}

local function bind(signal, fn)
    local conn = signal:Connect(fn)
    table.insert(connections, conn)
    return conn
end

local function saveConfig()
    local out = {}
    for key, value in pairs(CONFIG) do
        if typeof(value) == "EnumItem" then
            out[key] = value.Name
        elseif type(value) == "boolean" or type(value) == "number" or type(value) == "string" then
            out[key] = value
        end
    end
    pcall(function()
        writefile(CONFIG_PATH, HttpService:JSONEncode(out))
    end)
end

local saveQueued = false
local function requestSave()
    if saveQueued then return end
    saveQueued = true
    task.delay(0.4, function()
        saveQueued = false
        saveConfig()
    end)
end

local function loadConfig()
    if type(isfile) ~= "function" or type(readfile) ~= "function" then return end
    local readOk, raw = pcall(readfile, CONFIG_PATH)
    if not readOk or type(raw) ~= "string" or #raw == 0 then return end
    local decodeOk, data = pcall(function()
        return HttpService:JSONDecode(raw)
    end)
    if not decodeOk or type(data) ~= "table" then return end
    for key, value in pairs(data) do
        local current = CONFIG[key]
        if current ~= nil then
            if typeof(current) == "EnumItem" then
                local keyOk, keyCode = pcall(function()
                    return Enum.KeyCode[value]
                end)
                if keyOk and keyCode then CONFIG[key] = keyCode end
            elseif type(current) == "number" then
                CONFIG[key] = tonumber(value) or current
            elseif type(current) == "boolean" then
                CONFIG[key] = value and true or false
            elseif type(current) == "string" and type(value) == "string" then
                CONFIG[key] = value
            end
        end
    end
end

loadConfig()

-- tear down any previous builds before creating new ones
local oldMenu = env.__rivalsMenu
if type(oldMenu) == "table" and type(oldMenu.destroy) == "function" then
    pcall(oldMenu.destroy)
end
local oldAimbot = env.__rivalsAimbot
if type(oldAimbot) == "table" and type(oldAimbot.destroy) == "function" then
    pcall(oldAimbot.destroy)
end

local function mk(className, props, parent)
    local inst = Instance.new(className)
    for key, value in pairs(props or {}) do
        inst[key] = value
    end
    if parent then inst.Parent = parent end
    return inst
end

local function round(inst, radius)
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, radius)
    corner.Parent = inst
    return corner
end

local function outline(inst, color, transparency)
    local stroke = Instance.new("UIStroke")
    stroke.Color = color or THEME.surface2
    stroke.Thickness = 1
    stroke.Transparency = transparency or 0
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Parent = inst
    return stroke
end

local function newText(parent, properties)
    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.Font = FONT
    label.TextColor3 = THEME.text
    label.TextSize = 13
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextYAlignment = Enum.TextYAlignment.Center
    for key, value in pairs(properties or {}) do
        label[key] = value
    end
    label.Parent = parent
    return label
end

local function teamIndex(plr)
    local teamId = plr:GetAttribute("TeamID")
    if type(teamId) == "string" and #teamId > 0 then
        return string.byte(teamId, 1)
    end
    return nil
end

local function teamColor(index)
    return TEAM_COLORS[index] or THEME.neutral
end
-- ============================================================
-- aimbot
-- ============================================================
local aimbot = { active = false, target = nil, targetName = nil, aligned = false }
local fireThread
local AIM_BIND = "rivals_menu_aim"

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

local function isEnemy(plr)
    if plr == lp then return false end
    local mine = teamIndex(lp)
    local theirs = teamIndex(plr)
    if not mine or not theirs then return false end
    return mine ~= theirs
end

local function alive(plr)
    local char = plr.Character
    if not char then return end
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health <= 0 then return end
    local part = char:FindFirstChild(CONFIG.aimPart)
        or char:FindFirstChild("Head")
        or char:FindFirstChild("UpperTorso")
        or char:FindFirstChild("Torso")
        or char:FindFirstChild("HumanoidRootPart")
    if not part then return end
    return char, humanoid, part
end

local function releaseMouse()
    if type(mouse1release) == "function" then
        pcall(mouse1release)
    end
end

local function clearShot(origin, part)
    if not CONFIG.wallCheck then return true end
    local filter = {}
    if lp.Character then table.insert(filter, lp.Character) end
    if Workspace.CurrentCamera then table.insert(filter, Workspace.CurrentCamera) end
    rayParams.FilterDescendantsInstances = filter
    local hit = Workspace:Raycast(origin, part.Position - origin, rayParams)
    return hit == nil or hit.Instance:IsDescendantOf(part.Parent)
end

local function pickTarget()
    local camera = Workspace.CurrentCamera
    if not camera then return end
    local origin = camera.CFrame.Position
    local candidates = {}

    for _, plr in ipairs(Players:GetPlayers()) do
        if isEnemy(plr) then
            local char, humanoid, part = alive(plr)
            if char then
                local distance = (part.Position - origin).Magnitude
                if distance <= CONFIG.maxDistance and clearShot(origin, part) then
                    table.insert(candidates, { plr = plr, part = part, dist = distance })
                end
            end
        end
    end

    if #candidates == 0 then return end
    table.sort(candidates, function(a, b)
        return a.dist < b.dist
    end)

    if aimbot.target then
        for _, candidate in ipairs(candidates) do
            if candidate.plr == aimbot.target then
                if candidate.dist <= candidates[1].dist / CONFIG.stickiness then
                    return candidate
                end
                break
            end
        end
    end

    return candidates[1]
end

local function aimStep(delta)
    if not aimbot.active then return end
    local camera = Workspace.CurrentCamera
    if not camera then return end

    local best = pickTarget()
    aimbot.target = best and best.plr or nil
    aimbot.targetName = best and best.plr.Name or nil
    if not best then
        aimbot.aligned = false
        return
    end

    local origin = camera.CFrame.Position
    local goal = CFrame.lookAt(origin, best.part.Position)
    if CONFIG.smoothTime <= 0 then
        camera.CFrame = goal
    else
        local alpha = 1 - math.exp(-delta / CONFIG.smoothTime)
        camera.CFrame = camera.CFrame:Lerp(goal, math.clamp(alpha, 0, 1))
    end

    local dot = camera.CFrame.LookVector:Dot((best.part.Position - origin).Unit)
    aimbot.aligned = dot >= math.cos(math.rad(CONFIG.fireAngle))
end

local function inMatch()
    return teamIndex(lp) ~= nil
end

local function canFire()
    if not aimbot.active or not aimbot.target or not aimbot.aligned then return false end
    if not CONFIG.autoFire or not inMatch() then return false end
    if menuOpen or UIS:GetFocusedTextBox() then return false end
    local char = lp.Character
    if not char then return false end
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health <= 0 then return false end
    return type(mouse1press) == "function" and type(mouse1release) == "function"
end

local function fireLoop()
    local interval = 1 / math.max(CONFIG.fireRate, 1)
    while aimbot.active do
        if canFire() then
            pcall(mouse1press)
            task.wait(0.025)
            pcall(mouse1release)
            task.wait(math.max(interval - 0.025, 0.005))
        else
            releaseMouse()
            task.wait(0.05)
        end
    end
    releaseMouse()
end

local function disableAimbot()
    aimbot.active = false
    aimbot.target, aimbot.targetName, aimbot.aligned = nil, nil, false
    pcall(RunService.UnbindFromRenderStep, AIM_BIND)
    releaseMouse()
    hooks.aimbot()
end

local function enableAimbot()
    if aimbot.active then return end
    aimbot.active = true
    pcall(RunService.UnbindFromRenderStep, AIM_BIND)
    RunService:BindToRenderStep(AIM_BIND, Enum.RenderPriority.Camera.Value + 10, aimStep)
    if fireThread then pcall(task.cancel, fireThread) end
    fireThread = task.spawn(fireLoop)
    hooks.aimbot()
    toast("Aimbot enabled")
end

-- ============================================================
-- esp / tracers
-- ============================================================
local drawingReady = false
pcall(function()
    drawingReady = type(Drawing) == "table" and type(Drawing.new) == "function"
end)

local espFolder
local espCache = {}
local espCount = 0

local function createEspObjects(plr)
    local entry = {}

    local highlight = Instance.new("Highlight")
    highlight.Name = "RivalsESPFill"
    highlight.FillTransparency = 0.75
    highlight.OutlineTransparency = 0.2
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.Parent = espFolder
    entry.highlight = highlight

    local billboard = Instance.new("BillboardGui")
    billboard.Name = "RivalsESPTag"
    billboard.Size = UDim2.fromOffset(180, 50)
    billboard.StudsOffset = Vector3.new(0, 2.4, 0)
    billboard.AlwaysOnTop = true
    billboard.LightInfluence = 0
    billboard.MaxDistance = CONFIG.espRange
    billboard.ResetOnSpawn = false
    billboard.Parent = espFolder
    entry.billboard = billboard

    entry.name = newText(billboard, {
        Size = UDim2.new(1, 0, 0, 17),
        Text = plr.DisplayName,
        TextSize = 13,
        Font = FONT_B,
        TextXAlignment = Enum.TextXAlignment.Center,
        TextStrokeTransparency = 0.35,
        TextStrokeColor3 = Color3.fromRGB(0, 0, 0),
    })

    entry.dist = newText(billboard, {
        Size = UDim2.new(1, 0, 0, 13),
        Position = UDim2.new(0, 0, 0, 17),
        Text = "",
        TextSize = 11,
        TextColor3 = THEME.muted,
        TextXAlignment = Enum.TextXAlignment.Center,
        TextStrokeTransparency = 0.45,
        TextStrokeColor3 = Color3.fromRGB(0, 0, 0),
    })

    local healthBack = mk("Frame", {
        Size = UDim2.fromOffset(104, 4),
        Position = UDim2.new(0.5, 0, 1, -7),
        AnchorPoint = Vector2.new(0.5, 1),
        BackgroundColor3 = Color3.fromRGB(14, 14, 18),
        BackgroundTransparency = 0.2,
        BorderSizePixel = 0,
    }, billboard)
    round(healthBack, 2)

    entry.healthFill = mk("Frame", {
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundColor3 = THEME.green,
        BorderSizePixel = 0,
    }, healthBack)
    round(entry.healthFill, 2)
    entry.healthBack = healthBack

    if drawingReady then
        local line = Drawing.new("Line")
        line.Thickness = 1.5
        line.Transparency = 0.7
        line.Visible = false
        entry.tracer = line
    end

    return entry
end

local function destroyEspEntry(entry)
    if entry.highlight then entry.highlight:Destroy() end
    if entry.billboard then entry.billboard:Destroy() end
    if entry.tracer then pcall(function() entry.tracer:Remove() end) end
end

local function clearEsp()
    for plr, entry in pairs(espCache) do
        destroyEspEntry(entry)
        espCache[plr] = nil
    end
    espCount = 0
end

local function refreshEsp()
    if not CONFIG.espEnabled then
        if espCount > 0 or next(espCache) ~= nil then
            clearEsp()
        end
        updateFooter()
        return
    end

    local camera = Workspace.CurrentCamera
    if not camera then return end
    local camPos = camera.CFrame.Position
    local myTeam = teamIndex(lp)
    local seen = {}

    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= lp then
            local char = plr.Character
            local humanoid = char and char:FindFirstChildOfClass("Humanoid")
            local head = char and char:FindFirstChild("Head")
            local theirTeam = teamIndex(plr)
            local enemy = myTeam ~= nil and theirTeam ~= nil and theirTeam ~= myTeam
            local inRange = head ~= nil and (head.Position - camPos).Magnitude <= CONFIG.espRange
            local visible = humanoid ~= nil and humanoid.Health > 0 and inRange
                and (not CONFIG.espEnemiesOnly or enemy)

            if visible then
                seen[plr] = true
                local entry = espCache[plr]
                if not entry or not entry.billboard.Parent or not entry.highlight.Parent then
                    if entry then destroyEspEntry(entry) end
                    entry = createEspObjects(plr)
                    espCache[plr] = entry
                end

                local color = teamColor(theirTeam)
                entry.highlight.Adornee = char
                entry.highlight.FillColor = color
                entry.highlight.OutlineColor = color
                entry.highlight.FillTransparency = enemy and 0.68 or 0.8
                entry.highlight.OutlineTransparency = enemy and 0.1 or 0.35
                entry.highlight.DepthMode = CONFIG.espThroughWalls
                    and Enum.HighlightDepthMode.AlwaysOnTop
                    or Enum.HighlightDepthMode.Occluded

                entry.billboard.MaxDistance = CONFIG.espRange
                entry.billboard.AlwaysOnTop = CONFIG.espThroughWalls
                if entry.billboard.Parent ~= head then
                    entry.billboard.Parent = head
                end

                entry.name.Text = plr.DisplayName
                entry.name.Visible = CONFIG.showNames
                entry.dist.Visible = CONFIG.showDistance
                entry.dist.Text = tostring(math.floor((head.Position - camPos).Magnitude)) .. " studs"
                entry.healthBack.Visible = CONFIG.showHealth

                local maxHealth = math.max(humanoid.MaxHealth, 1)
                entry.healthFill.Size = UDim2.new(math.clamp(humanoid.Health / maxHealth, 0, 1), 0, 1, 0)
                entry.healthFill.BackgroundColor3 = color

                if entry.tracer then
                    entry.tracer.Color = color
                end
            end
        end
    end

    for plr, entry in pairs(espCache) do
        if not seen[plr] then
            destroyEspEntry(entry)
            espCache[plr] = nil
        end
    end

    espCount = 0
    for _ in pairs(espCache) do
        espCount += 1
    end

    if uiRefs.youTeam then
        if myTeam then
            uiRefs.youTeam.Text = "YOU: TEAM " .. tostring(myTeam)
            uiRefs.youTeam.TextColor3 = teamColor(myTeam)
        else
            uiRefs.youTeam.Text = "YOU: NO TEAM"
            uiRefs.youTeam.TextColor3 = THEME.muted
        end
    end

    updateFooter()
end

local function updateTracers()
    local camera = Workspace.CurrentCamera
    if not camera then return end
    local cameraViewport = camera.ViewportSize
    local from = Vector2.new(cameraViewport.X * 0.5, cameraViewport.Y)
    local enabled = CONFIG.espEnabled and CONFIG.showTracers and drawingReady

    for plr, entry in pairs(espCache) do
        local line = entry.tracer
        if line then
            local visible = false
            if enabled then
                local char = plr.Character
                local head = char and char:FindFirstChild("Head")
                if head then
                    local screen, onScreen = camera:WorldToViewportPoint(head.Position)
                    if onScreen and screen.Z > 0 then
                        line.From = from
                        line.To = Vector2.new(screen.X, screen.Y)
                        visible = true
                    end
                end
            end
            line.Visible = visible
        end
    end
end
-- ============================================================
-- movement
-- ============================================================
local fly = { active = false, bv = nil, conn = nil }

local function stopFly()
    fly.active = false
    if fly.conn then
        fly.conn:Disconnect()
        fly.conn = nil
    end
    if fly.bv then
        fly.bv:Destroy()
        fly.bv = nil
    end
    hooks.footer()
end

local function flyDirection()
    local camera = Workspace.CurrentCamera
    if not camera then return Vector3.zero end
    local look = camera.CFrame.LookVector
    local right = camera.CFrame.RightVector
    local move = Vector3.zero
    if UIS:IsKeyDown(Enum.KeyCode.W) then move += look end
    if UIS:IsKeyDown(Enum.KeyCode.S) then move -= look end
    if UIS:IsKeyDown(Enum.KeyCode.D) then move += right end
    if UIS:IsKeyDown(Enum.KeyCode.A) then move -= right end
    if UIS:IsKeyDown(Enum.KeyCode.Space) then move += Vector3.yAxis end
    if UIS:IsKeyDown(Enum.KeyCode.LeftControl) then move -= Vector3.yAxis end
    if move.Magnitude > 0 then
        return move.Unit * CONFIG.flySpeed
    end
    return Vector3.zero
end

local function startFly()
    stopFly()
    local char = lp.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root then return false end

    local body = Instance.new("BodyVelocity")
    body.Name = "RivalsFlyVelocity"
    body.MaxForce = Vector3.new(1e5, 1e5, 1e5)
    body.P = 2000
    body.Velocity = Vector3.zero
    body.Parent = root

    fly.bv = body
    fly.active = true
    fly.conn = RunService.RenderStepped:Connect(function()
        if not fly.active then return end
        local character = lp.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        local hrp = character and character:FindFirstChild("HumanoidRootPart")
        if not hrp or not body.Parent or not humanoid or humanoid.Health <= 0 then
            stopFly()
            if uiRefs.fly then uiRefs.fly.silent(false) end
            return
        end
        body.Velocity = flyDirection()
    end)

    hooks.footer()
    return true
end

bind(UIS.JumpRequest, function()
    if not CONFIG.infiniteJump then return end
    local char = lp.Character
    local humanoid = char and char:FindFirstChildOfClass("Humanoid")
    if humanoid and humanoid.Health > 0 then
        humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
    end
end)

bind(lp.CharacterAdded, function()
    aimbot.target, aimbot.targetName, aimbot.aligned = nil, nil, false
    releaseMouse()
    clearEsp()
    if fly.active then
        task.defer(function()
            task.wait(0.25)
            if fly.active then startFly() end
        end)
    end
end)

-- ============================================================
-- window
-- ============================================================
local function hiddenParent()
    if type(gethui) == "function" then
        local ok, folder = pcall(gethui)
        if ok and folder then return folder end
    end
    return game:GetService("CoreGui")
end

local guiParent = hiddenParent()

local gui = Instance.new("ScreenGui")
gui.Name = "RivalsMenu"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 200

local parented = pcall(function()
    gui.Parent = guiParent
end)
if not parented or not gui.Parent then
    gui.Parent = lp:FindFirstChildOfClass("PlayerGui") or guiParent
end

espFolder = Instance.new("Folder")
espFolder.Name = "RivalsESP"
local folderOk = pcall(function()
    espFolder.Parent = guiParent
end)
if not folderOk or not espFolder.Parent then
    espFolder.Parent = gui
end

local blur = Instance.new("BlurEffect")
blur.Name = "RivalsMenuBlur"
blur.Size = 0
blur.Parent = Lighting

local function setOpen(open)
    menuOpen = open and true or false
    gui.Enabled = menuOpen
    TweenService:Create(blur, TweenInfo.new(0.25), {
        Size = menuOpen and 14 or 0,
    }):Play()
end

local screen = Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize or Vector2.new(1536, 864)
local WIN_W, WIN_H = 680, 470

local shadow = mk("Frame", {
    Size = UDim2.fromOffset(WIN_W, WIN_H),
    Position = UDim2.fromOffset((screen.X - WIN_W) / 2, (screen.Y - WIN_H) / 2 + 8),
    BackgroundColor3 = Color3.fromRGB(0, 0, 0),
    BackgroundTransparency = 0.55,
    BorderSizePixel = 0,
    ZIndex = 1,
}, gui)
round(shadow, 16)

local main = mk("Frame", {
    Name = "Window",
    Size = UDim2.fromOffset(WIN_W, WIN_H),
    Position = UDim2.fromOffset((screen.X - WIN_W) / 2, (screen.Y - WIN_H) / 2),
    BackgroundColor3 = THEME.bg,
    BackgroundTransparency = 0.04,
    BorderSizePixel = 0,
    ClipsDescendants = false,
    ZIndex = 2,
}, gui)
round(main, 14)
outline(main, Color3.fromRGB(64, 64, 82), 0.25)

local strip = mk("Frame", {
    Size = UDim2.new(1, -28, 0, 2),
    Position = UDim2.fromOffset(14, 0),
    BackgroundColor3 = THEME.accent,
    BorderSizePixel = 0,
    ZIndex = 3,
}, main)
round(strip, 2)
mk("UIGradient", {
    Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, THEME.accent),
        ColorSequenceKeypoint.new(0.5, THEME.accentAlt),
        ColorSequenceKeypoint.new(1, THEME.accent),
    }),
    Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 1),
        NumberSequenceKeypoint.new(0.16, 0.15),
        NumberSequenceKeypoint.new(0.84, 0.15),
        NumberSequenceKeypoint.new(1, 1),
    }),
}, strip)

local titlebar = mk("Frame", {
    Size = UDim2.new(1, 0, 0, 50),
    BackgroundTransparency = 1,
    ZIndex = 3,
}, main)

local logo = mk("Frame", {
    Size = UDim2.fromOffset(28, 28),
    Position = UDim2.fromOffset(18, 11),
    BackgroundColor3 = THEME.accent,
    BorderSizePixel = 0,
    ZIndex = 3,
}, titlebar)
round(logo, 8)
mk("UIGradient", {
    Color = ColorSequence.new(THEME.accent, THEME.accentAlt),
    Rotation = 45,
}, logo)
newText(logo, {
    Size = UDim2.new(1, 0, 1, 0),
    Text = "R",
    Font = FONT_B,
    TextSize = 16,
    TextColor3 = Color3.fromRGB(20, 14, 34),
    TextXAlignment = Enum.TextXAlignment.Center,
    ZIndex = 4,
})

newText(titlebar, {
    Position = UDim2.fromOffset(56, 9),
    Size = UDim2.new(0, 200, 0, 18),
    Text = "RIVALS",
    Font = FONT_B,
    TextSize = 15,
    ZIndex = 3,
})
newText(titlebar, {
    Position = UDim2.fromOffset(56, 27),
    Size = UDim2.new(0, 220, 0, 14),
    Text = "control panel",
    TextSize = 10,
    TextColor3 = THEME.muted,
    ZIndex = 3,
})
newText(titlebar, {
    Position = UDim2.new(1, -120, 0, 17),
    Size = UDim2.fromOffset(44, 16),
    Text = "v1.0",
    Font = FONT_B,
    TextSize = 10,
    TextColor3 = Color3.fromRGB(92, 92, 110),
    TextXAlignment = Enum.TextXAlignment.Right,
    ZIndex = 3,
})

local close = mk("TextButton", {
    Size = UDim2.fromOffset(30, 30),
    Position = UDim2.new(1, -16, 0, 10),
    AnchorPoint = Vector2.new(1, 0),
    BackgroundColor3 = THEME.surface,
    BackgroundTransparency = 0.15,
    Text = "×",
    Font = FONT,
    TextSize = 19,
    TextColor3 = THEME.muted,
    AutoButtonColor = false,
    BorderSizePixel = 0,
    ZIndex = 4,
}, titlebar)
round(close, 8)
outline(close, THEME.surface2, 0.2)
close.MouseButton1Click:Connect(function()
    setOpen(false)
end)

local sidebar = mk("Frame", {
    Size = UDim2.new(0, 148, 1, -66),
    Position = UDim2.fromOffset(8, 58),
    BackgroundColor3 = THEME.panel,
    BackgroundTransparency = 0.2,
    BorderSizePixel = 0,
    ZIndex = 3,
}, main)
round(sidebar, 10)
outline(sidebar, Color3.fromRGB(48, 48, 62), 0.4)

newText(sidebar, {
    Position = UDim2.fromOffset(12, 11),
    Size = UDim2.new(1, -16, 0, 14),
    Text = "NAVIGATION",
    Font = FONT_B,
    TextSize = 10,
    TextColor3 = Color3.fromRGB(96, 96, 116),
})

local navList = mk("Frame", {
    Position = UDim2.fromOffset(8, 34),
    Size = UDim2.new(1, -16, 0, 0),
    AutomaticSize = Enum.AutomaticSize.Y,
    BackgroundTransparency = 1,
}, sidebar)
mk("UIListLayout", {
    Padding = UDim.new(0, 4),
    SortOrder = Enum.SortOrder.LayoutOrder,
}, navList)

local footer = mk("Frame", {
    Size = UDim2.new(1, -16, 0, 78),
    Position = UDim2.new(0, 8, 1, -86),
    BackgroundColor3 = THEME.surface,
    BackgroundTransparency = 0.45,
    BorderSizePixel = 0,
}, sidebar)
round(footer, 9)
outline(footer, Color3.fromRGB(48, 48, 62), 0.55)

uiRefs.footerDot = mk("Frame", {
    Size = UDim2.fromOffset(7, 7),
    Position = UDim2.fromOffset(10, 13),
    BackgroundColor3 = THEME.muted,
    BorderSizePixel = 0,
}, footer)
round(uiRefs.footerDot, 4)

uiRefs.footerAim = newText(footer, {
    Position = UDim2.fromOffset(23, 6),
    Size = UDim2.new(1, -30, 0, 16),
    Text = "AIMBOT  IDLE",
    Font = FONT_B,
    TextSize = 10,
    TextColor3 = THEME.muted,
})
uiRefs.footerEsp = newText(footer, {
    Position = UDim2.fromOffset(10, 28),
    Size = UDim2.new(1, -18, 0, 14),
    Text = "ESP  0 tracked",
    TextSize = 10,
    TextColor3 = THEME.muted,
})
uiRefs.footerFly = newText(footer, {
    Position = UDim2.fromOffset(10, 45),
    Size = UDim2.new(1, -18, 0, 14),
    Text = "FLY  OFF",
    TextSize = 10,
    TextColor3 = THEME.muted,
})

local content = mk("Frame", {
    Position = UDim2.fromOffset(164, 58),
    Size = UDim2.new(1, -172, 1, -66),
    BackgroundTransparency = 1,
    ZIndex = 3,
}, main)

local function makePage(name, order)
    local page = mk("ScrollingFrame", {
        Name = name .. "Page",
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 2,
        ScrollBarImageColor3 = THEME.accent,
        ScrollBarImageTransparency = 0.4,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        Visible = false,
        LayoutOrder = order,
    }, content)
    mk("UIPadding", {
        PaddingTop = UDim.new(0, 8),
        PaddingBottom = UDim.new(0, 10),
        PaddingLeft = UDim.new(0, 4),
        PaddingRight = UDim.new(0, 12),
    }, page)
    mk("UIListLayout", {
        Padding = UDim.new(0, 14),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, page)
    return page
end

local aimPage = makePage("Aimbot", 1)
local visualPage = makePage("Visuals", 2)
local movePage = makePage("Movement", 3)
local bindPage = makePage("Keybinds", 4)

local sectionOrder = 0
local function makeSection(page, title)
    sectionOrder += 1
    local section = mk("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        LayoutOrder = sectionOrder,
    }, page)
    mk("UIListLayout", {
        Padding = UDim.new(0, 4),
        SortOrder = Enum.SortOrder.LayoutOrder,
    }, section)

    local header = mk("Frame", {
        Size = UDim2.new(1, 0, 0, 20),
        BackgroundTransparency = 1,
        LayoutOrder = -1,
    }, section)
    newText(header, {
        Position = UDim2.fromOffset(10, 0),
        Size = UDim2.new(1, -10, 1, 0),
        Text = string.upper(title),
        Font = FONT_B,
        TextSize = 10,
        TextColor3 = Color3.fromRGB(108, 108, 128),
    })

    return section
end

local function cardRow(parent, height)
    local row = mk("Frame", {
        Size = UDim2.new(1, 0, 0, height),
        BackgroundColor3 = THEME.surface,
        BackgroundTransparency = 0.42,
        BorderSizePixel = 0,
    }, parent)
    round(row, 8)
    mk("UIPadding", {
        PaddingLeft = UDim.new(0, 12),
        PaddingRight = UDim.new(0, 10),
    }, row)
    return row
end

local activeSlider

local function makeToggle(parent, title, initial, changed)
    local row = cardRow(parent, 34)
    newText(row, {
        Size = UDim2.new(1, -62, 1, 0),
        Text = title,
        TextSize = 13,
    })

    local pill = mk("TextButton", {
        Size = UDim2.fromOffset(40, 22),
        Position = UDim2.new(1, 0, 0.5, 0),
        AnchorPoint = Vector2.new(1, 0.5),
        BackgroundColor3 = THEME.surface2,
        Text = "",
        AutoButtonColor = false,
        BorderSizePixel = 0,
    }, row)
    round(pill, 11)

    local knob = mk("Frame", {
        Size = UDim2.fromOffset(16, 16),
        Position = UDim2.new(0, 3, 0.5, 0),
        AnchorPoint = Vector2.new(0, 0.5),
        BackgroundColor3 = THEME.text,
        BorderSizePixel = 0,
    }, pill)
    round(knob, 8)

    local value = initial and true or false
    local function apply(nextValue, fire)
        value = nextValue and true or false
        TweenService:Create(knob, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            Position = UDim2.new(0, value and 21 or 3, 0.5, 0),
        }):Play()
        pill.BackgroundColor3 = value and THEME.accent or THEME.surface2
        if fire then changed(value) end
    end

    apply(value, false)
    pill.MouseButton1Click:Connect(function()
        apply(not value, true)
    end)

    return {
        get = function() return value end,
        set = function(nextValue) apply(nextValue, true) end,
        silent = function(nextValue) apply(nextValue, false) end,
    }
end

local function makeSlider(parent, title, initial, minValue, maxValue, step, suffix, changed)
    local row = cardRow(parent, 48)
    newText(row, {
        Size = UDim2.new(1, -80, 0, 18),
        Text = title,
        TextSize = 12,
        TextColor3 = THEME.muted,
    })
    local valueLabel = newText(row, {
        Size = UDim2.new(0, 76, 0, 18),
        Position = UDim2.new(1, -76, 0, 0),
        Text = "",
        Font = FONT_B,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Right,
    })

    local hit = mk("Frame", {
        Size = UDim2.new(1, 0, 0, 16),
        Position = UDim2.new(0, 0, 0, 28),
        BackgroundTransparency = 1,
    }, row)
    local track = mk("Frame", {
        Size = UDim2.new(1, 0, 0, 4),
        Position = UDim2.new(0, 0, 0.5, -2),
        BackgroundColor3 = THEME.surface2,
        BorderSizePixel = 0,
    }, hit)
    round(track, 2)
    local fill = mk("Frame", {
        Size = UDim2.new(0, 0, 1, 0),
        BackgroundColor3 = THEME.accent,
        BorderSizePixel = 0,
    }, track)
    round(fill, 2)
    local knob = mk("Frame", {
        Size = UDim2.fromOffset(10, 10),
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0, 0, 0.5, 0),
        BackgroundColor3 = THEME.text,
        BorderSizePixel = 0,
    }, hit)
    round(knob, 5)

    local value = initial
    local function formatValue(v)
        local body = (step and step < 1) and string.format("%.2f", v) or tostring(math.floor(v + 0.5))
        return body .. (suffix or "")
    end

    local function apply(nextValue, fire)
        if step and step > 0 then
            nextValue = math.floor((nextValue - minValue) / step + 0.5) * step + minValue
        end
        nextValue = math.clamp(nextValue, minValue, maxValue)
        value = nextValue
        local percent = (nextValue - minValue) / math.max(maxValue - minValue, 0.0001)
        fill.Size = UDim2.new(percent, 0, 1, 0)
        knob.Position = UDim2.new(percent, 0, 0.5, 0)
        valueLabel.Text = formatValue(nextValue)
        if fire then changed(nextValue) end
    end

    apply(initial, false)

    local function fromX(x)
        local percent = (x - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1)
        apply(minValue + math.clamp(percent, 0, 1) * (maxValue - minValue), true)
    end

    hit.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            activeSlider = fromX
            fromX(input.Position.X)
        end
    end)

    return {
        get = function() return value end,
        set = function(nextValue) apply(nextValue, true) end,
        silent = function(nextValue) apply(nextValue, false) end,
    }
end

local function makeChoice(parent, title, initial, options, changed)
    local row = cardRow(parent, 34)
    newText(row, {
        Size = UDim2.new(1, -140, 1, 0),
        Text = title,
        TextSize = 13,
    })
    local button = mk("TextButton", {
        Size = UDim2.fromOffset(128, 26),
        Position = UDim2.new(1, 0, 0.5, 0),
        AnchorPoint = Vector2.new(1, 0.5),
        BackgroundColor3 = THEME.surface2,
        Font = FONT_B,
        TextSize = 12,
        TextColor3 = THEME.text,
        AutoButtonColor = false,
        BorderSizePixel = 0,
    }, row)
    round(button, 6)
    outline(button, Color3.fromRGB(58, 58, 74), 0.2)

    local index = 1
    for position, option in ipairs(options) do
        if option == initial then index = position end
    end

    local function paint()
        button.Text = options[index]
    end
    paint()

    button.MouseButton1Click:Connect(function()
        index = index % #options + 1
        paint()
        changed(options[index])
    end)

    return {
        set = function(option)
            for position, candidate in ipairs(options) do
                if candidate == option then index = position end
            end
            paint()
        end,
    }
end

local pendingBind, pendingReset

local function makeKeybind(parent, title, initial, changed)
    local row = cardRow(parent, 34)
    newText(row, {
        Size = UDim2.new(1, -140, 1, 0),
        Text = title,
        TextSize = 13,
    })
    local button = mk("TextButton", {
        Size = UDim2.fromOffset(128, 26),
        Position = UDim2.new(1, 0, 0.5, 0),
        AnchorPoint = Vector2.new(1, 0.5),
        BackgroundColor3 = THEME.surface2,
        Font = FONT_B,
        TextSize = 11,
        TextColor3 = THEME.text,
        AutoButtonColor = false,
        BorderSizePixel = 0,
    }, row)
    round(button, 6)
    local stroke = outline(button, Color3.fromRGB(58, 58, 74), 0.2)

    local current = initial
    local function paint()
        button.Text = typeof(current) == "EnumItem" and current.Name or "None"
        button.TextColor3 = THEME.text
        stroke.Color = Color3.fromRGB(58, 58, 74)
    end
    paint()

    button.MouseButton1Click:Connect(function()
        if pendingReset then pendingReset() end
        button.Text = "press a key"
        button.TextColor3 = THEME.accent
        stroke.Color = THEME.accent
        pendingBind = function(keyCode)
            current = keyCode
            paint()
            changed(keyCode)
        end
        pendingReset = paint
    end)

    return {
        get = function() return current end,
        set = function(keyCode)
            current = keyCode
            paint()
        end,
    }
end
-- ============================================================
-- aimbot page
-- ============================================================
local combat = makeSection(aimPage, "Combat")
local aimButton = mk("TextButton", {
    Size = UDim2.new(1, 0, 0, 42),
    BackgroundColor3 = THEME.surface2,
    Font = FONT_B,
    TextSize = 13,
    TextColor3 = THEME.text,
    Text = "ENABLE AIMBOT",
    AutoButtonColor = false,
    BorderSizePixel = 0,
}, combat)
round(aimButton, 9)
local aimStroke = outline(aimButton, THEME.surface2, 0.3)
aimButton.MouseButton1Click:Connect(function()
    if aimbot.active then
        disableAimbot()
    else
        enableAimbot()
    end
end)
newText(combat, {
    Size = UDim2.new(1, 0, 0, 22),
    Text = "Locks the nearest opposite-team player. R enables, F disables.",
    TextSize = 11,
    TextColor3 = Color3.fromRGB(108, 108, 128),
    TextWrapped = true,
})

local targeting = makeSection(aimPage, "Targeting")
makeSlider(targeting, "Target range", CONFIG.maxDistance, 50, 2500, 25, " studs", function(value)
    CONFIG.maxDistance = value
    requestSave()
end)
makeSlider(targeting, "Smoothness", CONFIG.smoothTime, 0, 0.5, 0.01, "s", function(value)
    CONFIG.smoothTime = value
    requestSave()
end)
makeSlider(targeting, "Stickiness", CONFIG.stickiness, 0.1, 1, 0.05, "", function(value)
    CONFIG.stickiness = value
    requestSave()
end)
uiRefs.aimPart = makeChoice(targeting, "Target bone", CONFIG.aimPart,
    { "Head", "UpperTorso", "Torso", "HumanoidRootPart" },
    function(value)
        CONFIG.aimPart = value
        requestSave()
    end)

local firing = makeSection(aimPage, "Firing")
makeToggle(firing, "Auto fire", CONFIG.autoFire, function(value)
    CONFIG.autoFire = value
    requestSave()
end)
makeSlider(firing, "Fire rate", CONFIG.fireRate, 2, 20, 1, " /s", function(value)
    CONFIG.fireRate = value
    requestSave()
end)
makeSlider(firing, "Fire angle", CONFIG.fireAngle, 0, 30, 1, "°", function(value)
    CONFIG.fireAngle = value
    requestSave()
end)
makeToggle(firing, "Wall check", CONFIG.wallCheck, function(value)
    CONFIG.wallCheck = value
    requestSave()
end)
newText(firing, {
    Size = UDim2.new(1, 0, 0, 22),
    Text = "Shots fire through the game's normal weapon input, gated on aim alignment.",
    TextSize = 11,
    TextColor3 = Color3.fromRGB(108, 108, 128),
    TextWrapped = true,
})

-- ============================================================
-- visuals page
-- ============================================================
local espSection = makeSection(visualPage, "Player ESP")
makeToggle(espSection, "ESP enabled", CONFIG.espEnabled, function(value)
    CONFIG.espEnabled = value
    refreshEsp()
    requestSave()
end)
makeToggle(espSection, "Enemies only", CONFIG.espEnemiesOnly, function(value)
    CONFIG.espEnemiesOnly = value
    refreshEsp()
    requestSave()
end)
makeToggle(espSection, "Through walls", CONFIG.espThroughWalls, function(value)
    CONFIG.espThroughWalls = value
    refreshEsp()
    requestSave()
end)
makeToggle(espSection, "Names", CONFIG.showNames, function(value)
    CONFIG.showNames = value
    refreshEsp()
    requestSave()
end)
makeToggle(espSection, "Distance", CONFIG.showDistance, function(value)
    CONFIG.showDistance = value
    refreshEsp()
    requestSave()
end)
makeToggle(espSection, "Health bar", CONFIG.showHealth, function(value)
    CONFIG.showHealth = value
    refreshEsp()
    requestSave()
end)

local tracerSection = makeSection(visualPage, "Tracers")
makeToggle(tracerSection, "Tracers", CONFIG.showTracers, function(value)
    CONFIG.showTracers = value
    updateTracers()
    requestSave()
end)
newText(tracerSection, {
    Size = UDim2.new(1, 0, 0, 22),
    Text = drawingReady
        and "Lines run from the bottom of the screen to each tagged player."
        or "Drawing library unavailable in this executor; tracers are disabled.",
    TextSize = 11,
    TextColor3 = Color3.fromRGB(108, 108, 128),
    TextWrapped = true,
})

local rangeSection = makeSection(visualPage, "Range")
makeSlider(rangeSection, "ESP range", CONFIG.espRange, 100, 3000, 50, " studs", function(value)
    CONFIG.espRange = value
    requestSave()
end)

local legendSection = makeSection(visualPage, "Team colors")
local legend = mk("Frame", {
    Size = UDim2.new(1, 0, 0, 34),
    BackgroundColor3 = THEME.surface,
    BackgroundTransparency = 0.42,
    BorderSizePixel = 0,
}, legendSection)
round(legend, 8)

local function legendChip(x, text, color)
    local square = mk("Frame", {
        Size = UDim2.fromOffset(8, 8),
        Position = UDim2.new(0, x, 0.5, -4),
        BackgroundColor3 = color,
        BorderSizePixel = 0,
    }, legend)
    round(square, 2)
    newText(legend, {
        Position = UDim2.new(0, x + 14, 0, 0),
        Size = UDim2.new(0, 66, 1, 0),
        Text = text,
        Font = FONT_B,
        TextSize = 10,
        TextColor3 = THEME.muted,
    })
end

legendChip(12, "TEAM 1", THEME.red)
legendChip(96, "TEAM 2", THEME.blue)
uiRefs.youTeam = newText(legend, {
    Position = UDim2.new(1, -100, 0, 0),
    Size = UDim2.new(0, 88, 1, 0),
    Text = "YOU: —",
    Font = FONT_B,
    TextSize = 10,
    TextColor3 = THEME.muted,
    TextXAlignment = Enum.TextXAlignment.Right,
})
-- ============================================================
-- movement page
-- ============================================================
local flight = makeSection(movePage, "Flight")
uiRefs.fly = makeToggle(flight, "Fly", fly.active, function(value)
    if value then
        local ok = startFly()
        uiRefs.fly.silent(ok)
        toast(ok and "Fly enabled" or "Spawn in before flying")
    else
        stopFly()
        toast("Fly disabled")
    end
end)
makeSlider(flight, "Fly speed", CONFIG.flySpeed, 10, 250, 5, " studs/s", function(value)
    CONFIG.flySpeed = value
    requestSave()
end)
newText(flight, {
    Size = UDim2.new(1, 0, 0, 22),
    Text = "WASD to move, Space and LeftCtrl for up and down.",
    TextSize = 11,
    TextColor3 = Color3.fromRGB(108, 108, 128),
    TextWrapped = true,
})

local agility = makeSection(movePage, "Agility")
makeToggle(agility, "Infinite jump", CONFIG.infiniteJump, function(value)
    CONFIG.infiniteJump = value
    requestSave()
end)
newText(agility, {
    Size = UDim2.new(1, 0, 0, 22),
    Text = "Hold jump to keep climbing.",
    TextSize = 11,
    TextColor3 = Color3.fromRGB(108, 108, 128),
    TextWrapped = true,
})

-- ============================================================
-- keybind page
-- ============================================================
local binds = makeSection(bindPage, "Binds")
makeKeybind(binds, "Toggle menu", CONFIG.keyMenu, function(keyCode)
    CONFIG.keyMenu = keyCode
    requestSave()
end)
makeKeybind(binds, "Aimbot on", CONFIG.keyAimbot, function(keyCode)
    CONFIG.keyAimbot = keyCode
    requestSave()
end)
makeKeybind(binds, "Aimbot off", CONFIG.keyAimOff, function(keyCode)
    CONFIG.keyAimOff = keyCode
    requestSave()
end)
makeKeybind(binds, "Toggle fly", CONFIG.keyFly, function(keyCode)
    CONFIG.keyFly = keyCode
    requestSave()
end)
newText(binds, {
    Size = UDim2.new(1, 0, 0, 22),
    Text = "Click a bind, then press a key. Esc cancels the capture.",
    TextSize = 11,
    TextColor3 = Color3.fromRGB(108, 108, 128),
    TextWrapped = true,
})

local session = makeSection(bindPage, "Session")
local unload = mk("TextButton", {
    Size = UDim2.new(1, 0, 0, 38),
    BackgroundColor3 = THEME.surface,
    BackgroundTransparency = 0.25,
    Font = FONT_B,
    TextSize = 12,
    TextColor3 = Color3.fromRGB(255, 138, 148),
    Text = "UNLOAD MENU",
    AutoButtonColor = false,
    BorderSizePixel = 0,
}, session)
round(unload, 8)
outline(unload, Color3.fromRGB(96, 44, 52), 0.3)
unload.MouseButton1Click:Connect(function()
    destroyMenu()
end)
newText(session, {
    Size = UDim2.new(1, 0, 0, 22),
    Text = "Settings save automatically and load on the next run.",
    TextSize = 11,
    TextColor3 = Color3.fromRGB(108, 108, 128),
    TextWrapped = true,
})

-- ============================================================
-- sidebar nav + toast + status
-- ============================================================
local tabs = {
    { name = "Aimbot", page = aimPage },
    { name = "Visuals", page = visualPage },
    { name = "Movement", page = movePage },
    { name = "Keybinds", page = bindPage },
}
local navButtons = {}

local function switchTab(index)
    for i, tab in ipairs(tabs) do
        tab.page.Visible = i == index
        local item = navButtons[i]
        if item then
            local selected = i == index
            item.button.BackgroundColor3 = selected and THEME.accent or THEME.surface
            item.button.BackgroundTransparency = selected and 0.82 or 0.6
            item.button.TextColor3 = selected and THEME.text or THEME.muted
            item.bar.Visible = selected
        end
    end
end

for index, tab in ipairs(tabs) do
    local button = mk("TextButton", {
        Size = UDim2.new(1, 0, 0, 32),
        BackgroundColor3 = THEME.surface,
        BackgroundTransparency = 0.6,
        Text = tab.name,
        Font = FONT,
        TextSize = 12,
        TextColor3 = THEME.muted,
        TextXAlignment = Enum.TextXAlignment.Left,
        AutoButtonColor = false,
        BorderSizePixel = 0,
        LayoutOrder = index,
    }, navList)
    round(button, 8)
    mk("UIPadding", { PaddingLeft = UDim.new(0, 16) }, button)

    local bar = mk("Frame", {
        Size = UDim2.fromOffset(3, 14),
        Position = UDim2.new(0, -11, 0.5, -7),
        BackgroundColor3 = THEME.accent,
        BorderSizePixel = 0,
        Visible = false,
    }, button)
    round(bar, 2)

    button.MouseButton1Click:Connect(function()
        switchTab(index)
    end)
    navButtons[index] = { button = button, bar = bar }
end
switchTab(1)

local toastFrame = mk("Frame", {
    Size = UDim2.fromOffset(230, 34),
    Position = UDim2.new(0.5, 0, 1, -16),
    AnchorPoint = Vector2.new(0.5, 1),
    BackgroundColor3 = THEME.surface2,
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ZIndex = 20,
}, main)
round(toastFrame, 8)
outline(toastFrame, THEME.accent, 0.45)
local toastLabel = newText(toastFrame, {
    Size = UDim2.new(1, -16, 1, 0),
    Position = UDim2.fromOffset(8, 0),
    Text = "",
    Font = FONT_B,
    TextSize = 11,
    TextXAlignment = Enum.TextXAlignment.Center,
    TextTransparency = 1,
    ZIndex = 21,
})
local toastThread

toast = function(message)
    toastLabel.Text = message
    toastFrame.BackgroundTransparency = 0.08
    toastLabel.TextTransparency = 0
    toastFrame.Visible = true
    if toastThread then pcall(task.cancel, toastThread) end
    toastThread = task.spawn(function()
        task.wait(1.1)
        TweenService:Create(toastFrame, TweenInfo.new(0.25), { BackgroundTransparency = 1 }):Play()
        TweenService:Create(toastLabel, TweenInfo.new(0.25), { TextTransparency = 1 }):Play()
        task.wait(0.28)
        toastFrame.Visible = false
    end)
end

local function syncAimbotUi()
    local active = aimbot.active
    aimButton.Text = active and "DISABLE AIMBOT" or "ENABLE AIMBOT"
    aimButton.BackgroundColor3 = active and THEME.accent or THEME.surface2
    aimButton.TextColor3 = active and Color3.fromRGB(24, 15, 38) or THEME.text
    aimStroke.Color = active and THEME.accent or THEME.surface2
    aimStroke.Transparency = active and 0 or 0.3
    updateFooter()
end

updateFooter = function()
    uiRefs.footerDot.BackgroundColor3 = aimbot.active and THEME.green or THEME.muted
    uiRefs.footerAim.Text = aimbot.active and "AIMBOT  ACTIVE" or "AIMBOT  IDLE"
    uiRefs.footerAim.TextColor3 = aimbot.active and THEME.green or THEME.muted
    uiRefs.footerEsp.Text = "ESP  " .. tostring(espCount) .. " tracked"
    uiRefs.footerFly.Text = "FLY  " .. (fly.active and "ON" or "OFF")
    uiRefs.footerFly.TextColor3 = fly.active and THEME.accent or THEME.muted
end

hooks.aimbot = syncAimbotUi
hooks.footer = updateFooter

updateFooter()
refreshEsp()
setOpen(true)
-- ============================================================
-- input
-- ============================================================
bind(UIS.InputBegan, function(input, _processed)
    if UIS:GetFocusedTextBox() then return end

    if pendingBind then
        local assign, restore = pendingBind, pendingReset
        pendingBind, pendingReset = nil, nil
        if input.UserInputType == Enum.UserInputType.Keyboard then
            if input.KeyCode == Enum.KeyCode.Escape then
                if restore then restore() end
            else
                assign(input.KeyCode)
            end
        end
        return
    end

    if input.UserInputType ~= Enum.UserInputType.Keyboard then return end

    if input.KeyCode == CONFIG.keyMenu then
        setOpen(not menuOpen)
    elseif input.KeyCode == CONFIG.keyAimbot then
        enableAimbot()
    elseif input.KeyCode == CONFIG.keyAimOff then
        disableAimbot()
    elseif input.KeyCode == CONFIG.keyFly then
        if uiRefs.fly then
            uiRefs.fly.set(not fly.active)
        end
    end
end)

local dragging = false
local dragOffset = Vector2.zero

titlebar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = true
        dragOffset = Vector2.new(
            input.Position.X - main.AbsolutePosition.X,
            input.Position.Y - main.AbsolutePosition.Y
        )
    end
end)

bind(UIS.InputChanged, function(input)
    if input.UserInputType ~= Enum.UserInputType.MouseMovement then return end

    if activeSlider then
        if UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
            activeSlider(input.Position.X)
        else
            activeSlider = nil
        end
    end

    if dragging then
        if UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
            local camera = Workspace.CurrentCamera
            local screenSize = camera and camera.ViewportSize or screen
            local x = math.clamp(input.Position.X - dragOffset.X, 0, math.max(screenSize.X - WIN_W, 0))
            local y = math.clamp(input.Position.Y - dragOffset.Y, 0, math.max(screenSize.Y - WIN_H, 0))
            main.Position = UDim2.fromOffset(x, y)
            shadow.Position = UDim2.fromOffset(x, y + 8)
        else
            dragging = false
        end
    end
end)

bind(UIS.InputEnded, function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        activeSlider = nil
        dragging = false
    end
end)

-- ============================================================
-- loops
-- ============================================================
local espClock = 0
bind(RunService.RenderStepped, function(delta)
    espClock += delta
    if espClock >= 0.15 then
        espClock = 0
        refreshEsp()
    end
    updateTracers()
end)

-- ============================================================
-- teardown
-- ============================================================
destroyMenu = function()
    disableAimbot()
    stopFly()
    clearEsp()
    saveConfig()
    for _, conn in ipairs(connections) do
        if typeof(conn) == "RBXScriptConnection" then
            pcall(function() conn:Disconnect() end)
        end
    end
    table.clear(connections)
    if blur then blur:Destroy() end
    if gui then gui:Destroy() end
    if espFolder then espFolder:Destroy() end
    if env.__rivalsMenu and env.__rivalsMenu.destroy == destroyMenu then
        env.__rivalsMenu = nil
    end
end

pcall(function()
    if type(queueonteleport) == "function" and type(readfile) == "function"
        and type(isfile) == "function" and isfile("rivals_menu.lua") then
        queueonteleport([[loadstring(readfile("rivals_menu.lua"))()]])
    end
end)

env.__rivalsMenu = {
    config = CONFIG,
    aimbot = aimbot,
    fly = fly,
    esp = espCache,
    gui = gui,
    enableAimbot = enableAimbot,
    disableAimbot = disableAimbot,
    setOpen = setOpen,
    saveConfig = saveConfig,
    refreshEsp = refreshEsp,
    destroy = destroyMenu,
}

return {
    loaded = true,
    gui = gui:GetFullName(),
    espTargets = espCount,
    aimPart = CONFIG.aimPart,
    binds = {
        menu = CONFIG.keyMenu.Name,
        aimOn = CONFIG.keyAimbot.Name,
        aimOff = CONFIG.keyAimOff.Name,
        fly = CONFIG.keyFly.Name,
    },
    drawing = drawingReady,
}
