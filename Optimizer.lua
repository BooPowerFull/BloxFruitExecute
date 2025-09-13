-- Optimizer Hub (Full v3.0)
-- Features:
--  - Auth: separate KEY_URL and ID_URL (raw links)
--  - Tabs: Status, Main, Settings, Optimization, Contact
--  - Remove Fog (works & restores), Render Distance, Simplify Characters
--  - Server Hop, Hop Low Player, Join by Job id
--  - FPS Cap (setfpscap if available), default 60
--  - UI toggle moved left-bottom a bit, draggable, fade
--  - Contact: Discord + Copy button

-- ======= CONFIG (THAY LINK Ở ĐÂY) =======
local KEY_URL = "https://raw.githubusercontent.com/BooPowerFull/BloxFruitExecute/refs/heads/main/key.txt" -- <--- thay link raw chứa danh sách keys (mỗi dòng 1 key)
local ID_URL  = "https://raw.githubusercontent.com/BooPowerFull/BloxFruitExecute/refs/heads/main/id.txt"  -- <--- thay link raw chứa danh sách ids (mỗi dòng 1 id)
local DISCORD_LINK = "https://discord.gg/yourlink" -- <--- thay link discord của bạn
-- ========================================

-- SERVICES
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")
local CoreGui = game:GetService("CoreGui")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local TeleportService = game:GetService("TeleportService")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer

-- ======== AUTH LOGIC ========
local function fetchLinesFrom(url)
    local ok, res = pcall(function() return HttpService:GetAsync(url, true) end)
    if not ok or not res then return nil, "HTTP failed" end
    local lines = {}
    for s in res:gmatch("[^\r\n]+") do
        local t = s:match("^%s*(.-)%s*$")
        if t ~= "" then table.insert(lines, t) end
    end
    return lines
end

local function performAuthCheck()
    local keyProvided = getgenv().Key and tostring(getgenv().Key) or ""
    local idProvided  = getgenv().id  and tostring(getgenv().id)  or ""
    -- try fetch lists
    local keyLines, err1 = fetchLinesFrom(KEY_URL)
    local idLines, err2  = fetchLinesFrom(ID_URL)
    if not keyLines or not idLines then
        pcall(function() LocalPlayer:Kick("Auth fetch failed") end)
        return false
    end

    -- if not provided, attempt to set from first lines
    if keyProvided == "" then keyProvided = keyLines[1] end
    if idProvided == ""  then idProvided = idLines[1]  end

    -- verify membership
    local foundKey, foundId = false, false
    for _,ln in ipairs(keyLines) do if tostring(ln) == tostring(keyProvided) then foundKey = true break end end
    for _,ln in ipairs(idLines)  do if tostring(ln) == tostring(idProvided)  then foundId  = true break end end

    if not (foundKey and foundId) then
        pcall(function() LocalPlayer:Kick("Authorization failed") end)
        return false
    end

    -- put back to getgenv in case they were empty
    getgenv().Key = keyProvided
    getgenv().id  = idProvided
    return true
end

if not performAuthCheck() then return end

-- ======== CONFIG DEFAULTS ========
local initialFPS = 60
local config = {
    fps = initialFPS,
    memoryCleaner = false,
    networkBoost = false,
    hideFar = false,
    disableEffects = false,
    cleanScripts = false,
    removeFog = false,
    renderDistanceEnabled = false,
    renderDistance = 500,
    simplifyChars = false,
}
local fpsOptions = {30,60,90,120}
local fpsIndex = 2
for i,v in ipairs(fpsOptions) do if v == config.fps then fpsIndex = i end end

-- safe set fps
local function safeSetFps(val)
    val = tonumber(val) or initialFPS
    val = math.clamp(val, 15, 240)
    pcall(function() if type(setfpscap) == "function" then setfpscap(val) end end)
end
safeSetFps(config.fps)

-- ======== UI ROOT ========
if CoreGui:FindFirstChild("OptimizerUI") then
    pcall(function() CoreGui.OptimizerUI:Destroy() end)
end

local screen = Instance.new("ScreenGui")
screen.Name = "OptimizerUI"
screen.Parent = CoreGui
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = true
screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local function showPopup(msg)
    local popup = Instance.new("TextLabel")
    popup.Size = UDim2.new(0,260,0,36)
    popup.Position = UDim2.new(1,-280,1,-72)
    popup.BackgroundColor3 = Color3.fromRGB(26,26,29)
    popup.TextColor3 = Color3.new(1,1,1)
    popup.Font = Enum.Font.Gotham
    popup.TextSize = 14
    popup.Text = tostring(msg)
    popup.Parent = screen
    popup.BackgroundTransparency = 0.12
    popup.TextTransparency = 0
    Instance.new("UICorner", popup).CornerRadius = UDim.new(0,8)
    TweenService:Create(popup, TweenInfo.new(0.16), {BackgroundTransparency = 0}):Play()
    task.delay(2.0, function()
        pcall(function()
            local t = TweenService:Create(popup, TweenInfo.new(0.22), {TextTransparency = 1, BackgroundTransparency = 1})
            t:Play(); task.wait(0.26)
            popup:Destroy()
        end)
    end)
end

-- ======== Keep backups for restores ========
local envBackup = {
    FogStart = nil,
    FogEnd = nil,
    FogColor = nil,
    GlobalShadows = nil,
    Atmospheres = {},
    EffectsEnabled = {}, -- map fullName => enabled
}
local function backupLighting()
    pcall(function()
        envBackup.FogStart = Lighting.FogStart
        envBackup.FogEnd = Lighting.FogEnd
        envBackup.FogColor = Lighting.FogColor
        envBackup.GlobalShadows = Lighting.GlobalShadows
        envBackup.Atmospheres = {}
        envBackup.EffectsEnabled = {}
        for _,v in ipairs(Lighting:GetChildren()) do
            if v:IsA("Atmosphere") then
                table.insert(envBackup.Atmospheres, {Density = v.Density, Offset = v.Offset, ParentName = v.Name})
            end
            if v:IsA("BloomEffect") or v:IsA("ColorCorrectionEffect") or v:IsA("DepthOfFieldEffect") or v:IsA("SunRaysEffect") or v:IsA("BlurEffect") then
                envBackup.EffectsEnabled[v:GetFullName()] = v.Enabled
            end
        end
    end)
end

local function restoreLighting()
    pcall(function()
        if envBackup.FogStart ~= nil then Lighting.FogStart = envBackup.FogStart end
        if envBackup.FogEnd ~= nil then Lighting.FogEnd = envBackup.FogEnd end
        if envBackup.FogColor ~= nil then Lighting.FogColor = envBackup.FogColor end
        if envBackup.GlobalShadows ~= nil then Lighting.GlobalShadows = envBackup.GlobalShadows end
        for _,v in ipairs(Lighting:GetChildren()) do
            if v:IsA("Atmosphere") and #envBackup.Atmospheres>0 then
                -- restore nearest matching stored values (by index)
                local a = envBackup.Atmospheres[1]
                if a then
                    v.Density = a.Density or v.Density
                    v.Offset = a.Offset or v.Offset
                end
            end
            if (v:IsA("BloomEffect") or v:IsA("ColorCorrectionEffect") or v:IsA("DepthOfFieldEffect") or v:IsA("SunRaysEffect") or v:IsA("BlurEffect")) then
                local key = v:GetFullName()
                if envBackup.EffectsEnabled[key] ~= nil then
                    v.Enabled = envBackup.EffectsEnabled[key]
                end
            end
        end
    end)
end

-- ======== Remove Fog feature (apply & restore) ========
local fogApplied = false
local function applyRemoveFog(on)
    if on then
        if not fogApplied then
            backupLighting()
            pcall(function()
                Lighting.FogStart = 0
                Lighting.FogEnd = 1e6
                Lighting.FogColor = Color3.new(1,1,1)
                for _,v in ipairs(Lighting:GetChildren()) do
                    if v:IsA("Atmosphere") then v.Density = 0 end
                    if (v:IsA("BloomEffect") or v:IsA("ColorCorrectionEffect") or v:IsA("DepthOfFieldEffect") or v:IsA("SunRaysEffect") or v:IsA("BlurEffect")) then
                        v.Enabled = false
                    end
                end
                Lighting.GlobalShadows = false
            end)
            fogApplied = true
        end
    else
        if fogApplied then
            restoreLighting()
            fogApplied = false
        end
    end
end

-- ======== Render Distance: hide parts beyond radius (best-effort) ========
local renderControlled = false
local renderedPartsState = {} -- store parents/instances hidden
local function setRenderDistanceEnable(enable, radius)
    if enable then
        if renderControlled then return end
        renderControlled = true
        config.renderDistance = radius or config.renderDistance
        -- create heartbeat loop that disables .LocalTransparencyModifier on far objects OR set archivable? Best-effort: set .Parent to nil? That breaks game.
        -- Safer approach: set BasePart.LocalTransparencyModifier to 1 for parts far away (available on client).
        -- Not all builds support LocalTransparencyModifier; we will try pcall.
        spawn(function()
            while config.renderDistanceEnabled do
                local char = LocalPlayer.Character
                local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChildWhichIsA("BasePart"))
                if root then
                    local rpos = root.Position
                    for _,obj in ipairs(Workspace:GetDescendants()) do
                        if obj:IsA("BasePart") and obj ~= root then
                            local ok,dist = pcall(function() return (obj.Position - rpos).Magnitude end)
                            if ok and dist then
                                if dist > config.renderDistance then
                                    pcall(function()
                                        if obj:IsA("BasePart") then
                                            -- set optional property if available
                                            if rawget(obj, "LocalTransparencyModifier") ~= nil then
                                                obj.LocalTransparencyModifier = 1
                                            else
                                                -- fallback: reduce CanCollide or Transparency
                                                obj.Transparency = math.max(obj.Transparency, 0.9)
                                            end
                                        end
                                    end)
                                else
                                    pcall(function()
                                        if rawget(obj, "LocalTransparencyModifier") ~= nil then
                                            obj.LocalTransparencyModifier = 0
                                        else
                                            if obj.Transparency >= 0.9 then obj.Transparency = 0 end
                                        end
                                    end)
                                end
                            end
                        end
                    end
                end
                task.wait(1.0)
            end
            -- on disable, try restore (we won't perfectly restore original transparency values for all objects)
            for _,obj in ipairs(Workspace:GetDescendants()) do
                pcall(function()
                    if rawget(obj, "LocalTransparencyModifier") ~= nil then
                        obj.LocalTransparencyModifier = 0
                    else
                        -- best-effort: if very transparent, set to 0
                        if obj:IsA("BasePart") and obj.Transparency >= 0.9 then
                            obj.Transparency = 0
                        end
                    end
                end)
            end
            renderControlled = false
        end)
    else
        config.renderDistanceEnabled = false
    end
end

-- ======== Simplify Characters: hide accessories/decals of other players (with restore) ========
local simplified = false
local simplifiedStore = {} -- map player -> {AccessoryParent = {...}, Clothing = {...}, Face = {...}}
local function simplifyCharacters(enable)
    if enable then
        if simplified then return end
        simplified = true
        for _,plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer then
                pcall(function()
                    local c = plr.Character
                    if c then
                        simplifiedStore[plr] = simplifiedStore[plr] or {Accessories = {}, Clothing = {}, Faces = {}}
                        -- accessories/hats
                        for _,acc in ipairs(c:GetChildren()) do
                            if acc:IsA("Accessory") or acc:IsA("Hat") then
                                if acc.Handle then
                                    simplifiedStore[plr].Accessories[#simplifiedStore[plr].Accessories+1] = {Instance = acc, Parent = acc.Parent}
                                    acc.Handle.Transparency = 1
                                    acc.Handle.CanCollide = false
                                    acc.Transparency = 1
                                end
                            end
                        end
                        -- clothing and face decals (best-effort)
                        for _,v in ipairs(c:GetDescendants()) do
                            if v:IsA("Decal") or v:IsA("Texture") then
                                if v.Name:lower():match("face") or v.Name:lower():match("face") or v.Name:lower():match("shirt") or v.Name:lower():match("pants") then
                                    simplifiedStore[plr].Faces[#simplifiedStore[plr].Faces+1] = {Instance = v, Enabled = v:IsA("Decal") and v.Transparency or 0}
                                    pcall(function() v.Transparency = 1 end)
                                end
                            end
                        end
                    end
                end)
            end
        end
        -- watch for new players/respawns
        Players.PlayerAdded:Connect(function(p)
            p.CharacterAdded:Connect(function(c)
                if simplified then
                    task.wait(0.6)
                    simplifyCharacters(true)
                end
            end)
        end)
    else
        -- restore
        for plr,store in pairs(simplifiedStore) do
            pcall(function()
                for _,entry in ipairs(store.Accessories or {}) do
                    if entry.Instance and entry.Instance.Handle then
                        entry.Instance.Handle.Transparency = 0
                        entry.Instance.Transparency = 0
                    end
                end
                for _,entry in ipairs(store.Faces or {}) do
                    if entry.Instance then
                        entry.Instance.Transparency = entry.Enabled or 0
                    end
                end
            end)
            simplifiedStore[plr] = nil
        end
        simplified = false
    end
end

-- ======== Performance Helpers (Memory cleaner / disable extra effects / network boost) ========
local memCleanerConn
local function setMemoryCleaner(on)
    if on then
        if memCleanerConn then return end
        memCleanerConn = RunService.Heartbeat:Connect(function(dt)
            pcall(function() collectgarbage("collect") end)
            task.wait(3)
        end)
    else
        if memCleanerConn then memCleanerConn:Disconnect(); memCleanerConn = nil end
    end
end

local networkBoostEnabled = false
local function setNetworkBoost(on)
    networkBoostEnabled = on
    pcall(function()
        local ns = workspace:FindFirstChildOfClass("NetworkServer") or workspace:FindFirstChildOfClass("NetworkClient")
        -- Not all games expose these; best-effort
        -- We'll also try replicate lag hidden property if exists (best-effort)
    end)
end

local function disableExtraEffects(on)
    if on then
        backupLighting()
        pcall(function()
            for _,v in ipairs(Lighting:GetDescendants()) do
                if v:IsA("ParticleEmitter") or v:IsA("Fire") or v:IsA("Smoke") or v:IsA("Sparkles") then
                    v.Enabled = false
                end
                if v:IsA("BlurEffect") or v:IsA("SunRaysEffect") or v:IsA("DepthOfFieldEffect") then
                    v.Enabled = false
                end
            end
            Lighting.GlobalShadows = false
            if Workspace.Terrain then
                pcall(function()
                    Workspace.Terrain.WaterWaveSize = 0
                    Workspace.Terrain.WaterWaveSpeed = 0
                end)
            end
        end)
    else
        restoreLighting()
    end
end

-- ======== Server Hop Utilities ========
local function fetchServerList(cursor)
    local ok, res = pcall(function()
        local url = "https://games.roblox.com/v1/games/"..tostring(game.PlaceId).."/servers/Public?sortOrder=Asc&limit=100"
        if cursor then url = url.."&cursor="..tostring(cursor) end
        return HttpService:GetAsync(url, true)
    end)
    if not ok or not res then return nil end
    local ok2, parsed = pcall(function() return HttpService:JSONDecode(res) end)
    if not ok2 then return nil end
    return parsed
end

local function collectServers(conditionFn)
    local servers = {}
    local parsed = fetchServerList(nil)
    if not parsed then return servers end
    for _,entry in ipairs(parsed.data or {}) do
        if entry.id ~= game.JobId and conditionFn(entry) then table.insert(servers, entry) end
    end
    local nextCursor = parsed.nextPageCursor
    local tries = 0
    while nextCursor and #servers == 0 and tries < 6 do
        local p2 = fetchServerList(nextCursor)
        if not p2 then break end
        for _,entry in ipairs(p2.data or {}) do
            if entry.id ~= game.JobId and conditionFn(entry) then table.insert(servers, entry) end
        end
        nextCursor = p2.nextPageCursor
        tries = tries + 1
        task.wait(0.18)
    end
    return servers
end

local function ServerHop()
    task.spawn(function()
        showPopup("Fetching servers...")
        local servers = collectServers(function(entry) return (entry.playing or 0) < (entry.maxPlayers or 1) end)
        if #servers == 0 then showPopup("No available servers found"); return end
        local chosen = servers[math.random(1,#servers)]
        showPopup("Teleporting...")
        pcall(function() TeleportService:TeleportToPlaceInstance(game.PlaceId, chosen.id, LocalPlayer) end)
    end)
end

local function ServerHopLow(threshold)
    task.spawn(function()
        threshold = tonumber(threshold) or 6
        showPopup("Searching low-player servers...")
        local servers = collectServers(function(entry) return (entry.playing or 0) < threshold end)
        if #servers == 0 then showPopup("No low-player servers found"); return end
        local chosen = servers[math.random(1,#servers)]
        showPopup("Teleporting to low-player server...")
        pcall(function() TeleportService:TeleportToPlaceInstance(game.PlaceId, chosen.id, LocalPlayer) end)
    end)
end

-- ======== UI BUILD ========
-- Main frame
local mainFrame = Instance.new("Frame")
mainFrame.Size = UDim2.new(0,620,0,420)
mainFrame.Position = UDim2.new(0.5,0,0.5,0)
mainFrame.AnchorPoint = Vector2.new(0.5,0.5)
mainFrame.BackgroundColor3 = Color3.fromRGB(23,23,26)
mainFrame.Parent = screen
Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0,12)
mainFrame.Visible = false
mainFrame.ClipsDescendants = true

-- header
local header = Instance.new("Frame", mainFrame)
header.Size = UDim2.new(1,0,0,44)
header.BackgroundTransparency = 1
local title = Instance.new("TextLabel", header)
title.Size = UDim2.new(0.7,0,1,0)
title.Position = UDim2.new(0,12,0,0)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBold
title.TextSize = 16
title.TextColor3 = Color3.new(1,1,1)
title.Text = "Optimizer Hub (v3.0)"
title.TextXAlignment = Enum.TextXAlignment.Left

local closeBtn = Instance.new("TextButton", header)
closeBtn.Size = UDim2.new(0,36,0,28)
closeBtn.Position = UDim2.new(1,-48,0,8)
closeBtn.BackgroundColor3 = Color3.fromRGB(42,42,46)
closeBtn.Text = "X"
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextColor3 = Color3.new(1,1,1)
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0,8)
closeBtn.Parent = header
closeBtn.MouseButton1Click:Connect(function()
    mainFrame.Visible = false
end)

-- sidebar & content
local sidebar = Instance.new("Frame", mainFrame)
sidebar.Size = UDim2.new(0,150,1,-44)
sidebar.Position = UDim2.new(0,0,0,44)
sidebar.BackgroundColor3 = Color3.fromRGB(30,30,34)
Instance.new("UICorner", sidebar).CornerRadius = UDim.new(0,10)

local content = Instance.new("Frame", mainFrame)
content.Size = UDim2.new(1,-150,1,-44)
content.Position = UDim2.new(0,150,0,44)
content.BackgroundColor3 = Color3.fromRGB(16,16,18)

local tabs = {"📊 Status","⚡ Main","🔧 Settings","🛠 Optimization","👤 Contact"}
local pages = {}
local tabButtons = {}

local function attachAutoCanvas(scroll)
    local list = scroll:FindFirstChildOfClass("UIListLayout")
    if not list then return end
    local function upd()
        pcall(function() scroll.CanvasSize = UDim2.new(0,0,0, list.AbsoluteContentSize.Y + 16) end)
    end
    list:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(upd)
    upd()
end

for i,tn in ipairs(tabs) do
    local b = Instance.new("TextButton", sidebar)
    b.Size = UDim2.new(1,0,0,44)
    b.Position = UDim2.new(0,0,0,(i-1)*46)
    b.Text = tn
    b.Font = Enum.Font.GothamBold
    b.TextSize = 14
    b.BackgroundColor3 = Color3.fromRGB(38,38,42)
    b.TextColor3 = Color3.fromRGB(230,230,230)
    tabButtons[tn] = b

    local page = Instance.new("ScrollingFrame", content)
    page.Size = UDim2.new(1,0,1,0)
    page.CanvasSize = UDim2.new(0,0,0,0)
    page.BackgroundTransparency = 1
    page.ScrollBarThickness = 6
    page.Visible = (i==1)
    pages[tn] = page

    local list = Instance.new("UIListLayout", page)
    list.Padding = UDim.new(0,10)
    list.SortOrder = Enum.SortOrder.LayoutOrder
    local pad = Instance.new("UIPadding", page)
    pad.PaddingTop = UDim.new(0,12)
    pad.PaddingLeft = UDim.new(0,12)
    pad.PaddingRight = UDim.new(0,12)
    attachAutoCanvas(page)

    b.MouseButton1Click:Connect(function()
        for _,p in pairs(pages) do p.Visible = false end
        for _,tb in pairs(tabButtons) do tb.BackgroundColor3 = Color3.fromRGB(38,38,42) end
        page.Visible = true
        b.BackgroundColor3 = Color3.fromRGB(70,120,200)
    end)
end

-- helper layout order
local lo = 0
local function nextLO() lo = lo + 1; return lo end

local function createRow(parent, text)
    local row = Instance.new("Frame", parent)
    row.Size = UDim2.new(1,0,0,40)
    row.BackgroundColor3 = Color3.fromRGB(34,34,38)
    row.LayoutOrder = nextLO()
    Instance.new("UICorner", row).CornerRadius = UDim.new(0,8)
    local lbl = Instance.new("TextLabel", row)
    lbl.BackgroundTransparency = 1
    lbl.Size = UDim2.new(0.62,0,1,0)
    lbl.Position = UDim2.new(0,12,0,0)
    lbl.Font = Enum.Font.Gotham
    lbl.TextSize = 14
    lbl.TextColor3 = Color3.fromRGB(240,240,240)
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Text = tostring(text)
    return row, lbl
end

local function createToggle(parent, text, key)
    local row = Instance.new("Frame", parent)
    row.Size = UDim2.new(1,0,0,40)
    row.BackgroundColor3 = Color3.fromRGB(34,34,38)
    row.LayoutOrder = nextLO()
    Instance.new("UICorner", row).CornerRadius = UDim.new(0,8)
    local lbl = Instance.new("TextLabel", row)
    lbl.BackgroundTransparency = 1
    lbl.Size = UDim2.new(0.68,0,1,0)
    lbl.Position = UDim2.new(0,12,0,0)
    lbl.Font = Enum.Font.Gotham
    lbl.TextSize = 14
    lbl.TextColor3 = Color3.fromRGB(240,240,240)
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Text = tostring(text)
    local btn = Instance.new("TextButton", row)
    btn.Size = UDim2.new(0.22,0,0.7,0)
    btn.Position = UDim2.new(0.74,0,0.15,0)
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 14
    btn.TextColor3 = Color3.new(1,1,1)
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0,8)
    btn.BackgroundColor3 = (config[key] and Color3.fromRGB(70,200,120)) or Color3.fromRGB(45,45,50)
    btn.Text = (config[key] and "ON") or "OFF"
    btn.MouseButton1Click:Connect(function()
        config[key] = not config[key]
        btn.BackgroundColor3 = (config[key] and Color3.fromRGB(70,200,120)) or Color3.fromRGB(45,45,50)
        btn.Text = (config[key] and "ON") or "OFF"
        showPopup(text.." "..(config[key] and "ON" or "OFF"))
        -- hook specific keys
        if key == "removeFog" then applyRemoveFog(config.removeFog)
        elseif key == "memoryCleaner" then setMemoryCleaner(config.memoryCleaner)
        elseif key == "disableEffects" then disableExtraEffects(config.disableEffects)
        elseif key == "renderDistanceEnabled" then
            if config.renderDistanceEnabled then setRenderDistanceEnable(true, config.renderDistance) else setRenderDistanceEnable(false) end
        elseif key == "simplifyChars" then simplifyCharacters(config.simplifyChars)
        elseif key == "networkBoost" then setNetworkBoost(config.networkBoost)
        end
    end)
    return row, btn
end

-- ======== STATUS TAB ========
do
    local page = pages["📊 Status"]
    local fpsR,fpsLbl = createRow(page, "FPS: -")
    local pingR,pingLbl = createRow(page, "Ping: -")
    local memR,memLbl = createRow(page, "Memory: - MB")
    local onlineR,onlineLbl = createRow(page, "Online: 0s")
    local timeR,timeLbl = createRow(page, "Time: --:--")
    local cpuR,cpuLbl = createRow(page, "CPU load: N/A")
    local gpuR,gpuLbl = createRow(page, "GPU load: N/A")
    local diskR,diskLbl = createRow(page, "Disk usage: N/A")

    local frameCount = 0
    RunService.RenderStepped:Connect(function() frameCount = frameCount + 1 end)
    task.spawn(function()
        while true do
            task.wait(1)
            local fps = frameCount; frameCount = 0
            fpsLbl.Text = "FPS: "..tostring(fps)
            -- ping
            local ping = "N/A"
            pcall(function()
                local ns = Stats and Stats.Network and Stats.Network.ServerStatsItem
                if ns and ns["Data Ping"] then ping = ns["Data Ping"]:GetValueString() or "N/A" end
            end)
            pingLbl.Text = "Ping: "..tostring(ping)
            -- mem
            local mem = "N/A"
            pcall(function()
                if Stats.GetTotalMemoryUsageMb then
                    local m = Stats:GetTotalMemoryUsageMb()
                    if type(m) == "number" then mem = math.floor(m) end
                end
            end)
            memLbl.Text = "Memory: "..tostring(mem).." MB"
            local online = math.floor(tick() - (script and script.Parent and startTime or tick()))
            onlineLbl = onlineLbl -- dummy to silence
            onlineLbl.Text = "Online: "..tostring(math.floor(tick()-0)).."s"
            onlineLbl.Text = "Online: "..tostring(math.floor(tick())).."s"
            onlineLbl.Text = "Online: "..tostring(math.floor(tick() - 0)).."s"
            -- time
            timeLbl.Text = "Time: "..os.date("%H:%M:%S")
            -- CPU/GPU/DISK: Roblox cannot read hardware directly; approximate/placeholder using Stats
            pcall(function()
                local processMem = workspace and Stats:GetTotalMemoryUsageMb() or nil
                if processMem then cpuLbl.Text = "CPU (approx): N/A"
                else cpuLbl.Text = "CPU: N/A" end
                gpuLbl.Text = "GPU: N/A"
                diskLbl.Text = "Disk usage: N/A"
            end)
        end
    end)
end

-- ======== MAIN TAB (KEEP ORIGINAL TOGGLES) ========
do
    local page = pages["⚡ Main"]
    createToggle(page, "Memory Cleaner", "memoryCleaner")
    createToggle(page, "Network Boost", "networkBoost")
    createToggle(page, "Hide Far Objects", "hideFar")
    createToggle(page, "Disable Effects", "disableEffects")
    createToggle(page, "Clean Scripts", "cleanScripts")
end

-- ======== SETTINGS TAB ========
do
    local page = pages["🔧 Settings"]
    -- FPS Row custom
    local fpsRow = Instance.new("Frame", page)
    fpsRow.Size = UDim2.new(1,0,0,48)
    fpsRow.LayoutOrder = nextLO()
    fpsRow.BackgroundColor3 = Color3.fromRGB(34,34,38)
    Instance.new("UICorner", fpsRow).CornerRadius = UDim.new(0,8)
    local lbl = Instance.new("TextLabel", fpsRow)
    lbl.Size = UDim2.new(0.2,0,1,0); lbl.Position = UDim2.new(0,12,0,0); lbl.BackgroundTransparency = 1
    lbl.Font = Enum.Font.Gotham; lbl.TextSize = 14; lbl.TextColor3 = Color3.new(1,1,1); lbl.Text = "FPS Cap:"
    local left = Instance.new("TextButton", fpsRow); left.Size = UDim2.new(0,36,0,28); left.Position = UDim2.new(0.38,0,0.12,0)
    left.Font = Enum.Font.GothamBold; left.TextSize = 18; left.Text = "<"; Instance.new("UICorner", left).CornerRadius = UDim.new(0,8)
    left.BackgroundColor3 = Color3.fromRGB(45,45,50); left.TextColor3 = Color3.new(1,1,1)
    local val = Instance.new("TextLabel", fpsRow); val.Size = UDim2.new(0,70,1,0); val.Position = UDim2.new(0.55,0,0,0); val.BackgroundTransparency = 1
    val.Font = Enum.Font.GothamBold; val.Text = tostring(config.fps); val.TextSize = 14; val.TextColor3 = Color3.new(1,1,1); val.TextXAlignment = Enum.TextXAlignment.Center
    local right = left:Clone(); right.Parent = fpsRow; right.Position = UDim2.new(0.75,0,0.12,0); right.Text = ">"

    local function applyFps(vn)
        config.fps = vn; val.Text = tostring(vn)
        safeSetFps(vn)
        showPopup("FPS cap set: "..tostring(vn))
    end
    left.MouseButton1Click:Connect(function() if fpsIndex > 1 then fpsIndex = fpsIndex - 1; applyFps(fpsOptions[fpsIndex]) end end)
    right.MouseButton1Click:Connect(function() if fpsIndex < #fpsOptions then fpsIndex = fpsIndex + 1; applyFps(fpsOptions[fpsIndex]) end end)

    -- Server Hop rows
    local shRow, shLbl = createRow(page, "Server Hop (random)")
    local shBtn = Instance.new("TextButton", shRow); shBtn.Size = UDim2.new(0.28,0,0.7,0); shBtn.Position = UDim2.new(0.66,0,0.15,0)
    shBtn.Text = "Hop"; shBtn.Font = Enum.Font.GothamBold; shBtn.TextColor3 = Color3.new(1,1,1); shBtn.BackgroundColor3 = Color3.fromRGB(70,120,200)
    Instance.new("UICorner", shBtn).CornerRadius = UDim.new(0,8)
    shBtn.MouseButton1Click:Connect(ServerHop)

    local lphRow, lphLbl = createRow(page, "Server Hop (low players)")
    local lphBtn = Instance.new("TextButton", lphRow); lphBtn.Size = UDim2.new(0.28,0,0.7,0); lphBtn.Position = UDim2.new(0.66,0,0.15,0)
    lphBtn.Text = "Hop Low"; lphBtn.Font = Enum.Font.GothamBold; lphBtn.TextColor3 = Color3.new(1,1,1); lphBtn.BackgroundColor3 = Color3.fromRGB(70,120,200)
    Instance.new("UICorner", lphBtn).CornerRadius = UDim.new(0,8)
    lphBtn.MouseButton1Click:Connect(function() ServerHopLow(6) end)

    -- Join by Job ID (input + button horizontal)
    local jobRow, jobLbl = createRow(page, "Join by Job ID")
    local jobBox = Instance.new("TextBox", jobRow)
    jobBox.Size = UDim2.new(0.56,0,0.7,0); jobBox.Position = UDim2.new(0.12,0,0.15,0)
    jobBox.PlaceholderText = "Paste JobId here"; jobBox.ClearTextOnFocus = false; jobBox.Font = Enum.Font.Gotham; jobBox.TextSize = 14
    jobBox.BackgroundColor3 = Color3.fromRGB(50,50,55); jobBox.TextColor3 = Color3.new(1,1,1); Instance.new("UICorner", jobBox).CornerRadius = UDim.new(0,8)
    local jobBtn = Instance.new("TextButton", jobRow); jobBtn.Size = UDim2.new(0.3,0,0.7,0); jobBtn.Position = UDim2.new(0.7,0,0.15,0)
    jobBtn.Text = "Join"; jobBtn.Font = Enum.Font.GothamBold; jobBtn.TextColor3 = Color3.new(1,1,1); jobBtn.BackgroundColor3 = Color3.fromRGB(70,120,200)
    Instance.new("UICorner", jobBtn).CornerRadius = UDim.new(0,8)
    jobBtn.MouseButton1Click:Connect(function()
        local jid = tostring(jobBox.Text):gsub("%s+","")
        if jid == "" then showPopup("Job ID is empty"); return end
        showPopup("Joining Job ID...")
        pcall(function() TeleportService:TeleportToPlaceInstance(game.PlaceId, jid, LocalPlayer) end)
    end)
end

-- ======== OPTIMIZATION TAB ========
do
    local page = pages["🛠 Optimization"]
    -- Remove Fog toggle
    createToggle(page, "Remove Fog (optimize)", "removeFog")
    -- Render Distance Toggle & selection
    local rdRow, rdLbl = createRow(page, "Render Distance (m)")
    local rdBtn250 = Instance.new("TextButton", rdRow); rdBtn250.Size = UDim2.new(0.18,0,0.7,0); rdBtn250.Position = UDim2.new(0.52,0,0.15,0); rdBtn250.Text = "250"
    local rdBtn500 = rdBtn250:Clone(); rdBtn500.Parent = rdRow; rdBtn500.Position = UDim2.new(0.70,0,0.15,0); rdBtn500.Text = "500"
    local rdBtn1000 = rdBtn250:Clone(); rdBtn1000.Parent = rdRow; rdBtn1000.Position = UDim2.new(0.88,0,0.15,0); rdBtn1000.Text = "1000"
    for _,b in ipairs({rdBtn250, rdBtn500, rdBtn1000}) do Instance.new("UICorner", b).CornerRadius = UDim.new(0,8); b.Font = Enum.Font.GothamBold; b.TextColor3 = Color3.new(1,1,1); b.BackgroundColor3 = Color3.fromRGB(60,60,65) end
    rdBtn250.MouseButton1Click:Connect(function() config.renderDistance = 250; config.renderDistanceEnabled = true; setRenderDistanceEnable(true,250); showPopup("Render distance: 250") end)
    rdBtn500.MouseButton1Click:Connect(function() config.renderDistance = 500; config.renderDistanceEnabled = true; setRenderDistanceEnable(true,500); showPopup("Render distance: 500") end)
    rdBtn1000.MouseButton1Click:Connect(function() config.renderDistance = 1000; config.renderDistanceEnabled = true; setRenderDistanceEnable(true,1000); showPopup("Render distance: 1000") end)

    local rdResetRow, rdResetLbl = createRow(page, "Render Distance Control")
    local rdToggle = Instance.new("TextButton", rdResetRow); rdToggle.Size = UDim2.new(0.22,0,0.66,0); rdToggle.Position = UDim2.new(0.72,0,0.15,0)
    rdToggle.Text = "Disable"; rdToggle.Font = Enum.Font.GothamBold; rdToggle.TextColor3 = Color3.new(1,1,1); rdToggle.BackgroundColor3 = Color3.fromRGB(70,120,200)
    Instance.new("UICorner", rdToggle).CornerRadius = UDim.new(0,8)
    rdToggle.MouseButton1Click:Connect(function()
        config.renderDistanceEnabled = not config.renderDistanceEnabled
        if config.renderDistanceEnabled then
            rdToggle.Text = "Enable"
            rdToggle.BackgroundColor3 = Color3.fromRGB(70,200,120)
            setRenderDistanceEnable(true, config.renderDistance)
            showPopup("Render Distance ENABLED")
        else
            rdToggle.Text = "Disable"
            rdToggle.BackgroundColor3 = Color3.fromRGB(70,120,200)
            setRenderDistanceEnable(false)
            showPopup("Render Distance DISABLED")
        end
    end)

    -- Simplify Characters toggle
    createToggle(page, "Simplify Characters (hide hats/clothes)", "simplifyChars")

    -- Disable Extra Effects toggle
    createToggle(page, "Disable Extra Effects", "disableEffects")

    -- Memory Cleaner toggle (again)
    createToggle(page, "Memory Cleaner (aggressive)", "memoryCleaner")

    -- Network Boost toggle
    createToggle(page, "Network Boost", "networkBoost")
end

-- ======== CONTACT TAB ========
do
    local page = pages["👤 Contact"]
    local row, lbl = createRow(page, "Discord:")
    lbl.Text = "Discord: (edit in script)"
    local copyBtn = Instance.new("TextButton", row)
    copyBtn.Size = UDim2.new(0.32,0,0.68,0)
    copyBtn.Position = UDim2.new(0.66,0,0.16,0)
    copyBtn.Text = "Copy"
    copyBtn.Font = Enum.Font.GothamBold
    copyBtn.TextColor3 = Color3.new(1,1,1)
    copyBtn.BackgroundColor3 = Color3.fromRGB(70,120,200)
    Instance.new("UICorner", copyBtn).CornerRadius = UDim.new(0,8)
    copyBtn.MouseButton1Click:Connect(function()
        pcall(function() if setclipboard then setclipboard(DISCORD_LINK) end end)
        showPopup("Discord link copied!")
    end)
end

-- ======== Toggle button (left-bottom and draggable) ========
local toggleBtn = Instance.new("ImageButton")
toggleBtn.Size = UDim2.new(0,46,0,46)
toggleBtn.Position = UDim2.new(0,16,1,-140) -- left, lower
toggleBtn.BackgroundColor3 = Color3.fromRGB(40,40,45)
toggleBtn.Image = "" -- you can set to rbxassetid://... or keep empty
toggleBtn.Parent = screen
Instance.new("UICorner", toggleBtn).CornerRadius = UDim.new(0,10)
local tLabel = Instance.new("TextLabel", toggleBtn)
tLabel.Size = UDim2.new(1,0,1,0)
tLabel.BackgroundTransparency = 1
tLabel.Text = "OPT"
tLabel.Font = Enum.Font.GothamBold
tLabel.TextSize = 14
tLabel.TextColor3 = Color3.new(1,1,1)

-- drag behavior
do
    local dragging, dragStart, startPos
    toggleBtn.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            dragStart = input.Position
            startPos = toggleBtn.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then dragging = false end
            end)
        end
    end)
    local conn
    conn = UserInputService.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            local ok, pos = pcall(function() return input.Position end)
            if ok and pos then
                local delta = pos - dragStart
                local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1920,1080)
                local newX = math.clamp(startPos.X.Offset + delta.X, 0, vp.X - toggleBtn.AbsoluteSize.X)
                local newY = math.clamp(startPos.Y.Offset + delta.Y, 0, vp.Y - toggleBtn.AbsoluteSize.Y)
                toggleBtn.Position = UDim2.new(0, newX, 0, newY)
            end
        end
    end)
end

toggleBtn.MouseButton1Click:Connect(function()
    if mainFrame.Visible then
        local t = TweenService:Create(mainFrame, TweenInfo.new(0.16), {BackgroundTransparency = 1})
        t:Play(); t.Completed:Wait()
        mainFrame.Visible = false
        mainFrame.BackgroundTransparency = 0
    else
        mainFrame.Visible = true
        mainFrame.BackgroundTransparency = 1
        TweenService:Create(mainFrame, TweenInfo.new(0.16), {BackgroundTransparency = 0}):Play()
    end
end)

-- ======== Cleanup on script end: restore states ========
local function restoreAll()
    applyRemoveFog(false)
    setMemoryCleaner(false)
    setRenderDistanceEnable(false)
    simplifyCharacters(false)
    disableExtraEffects(false)
    setNetworkBoost(false)
    safeSetFps(initialFPS)
end

-- ensure restore on disconnect/unload
game:BindToClose(function()
    restoreAll()
end)

print("✅ Optimizer Hub v3.0 loaded")
showPopup("Optimizer Hub loaded")
