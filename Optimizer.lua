-- Optimizer Hub (Full) - v1.0
-- English comments throughout
-- Features:
--  * Auth check (Key + ID) from two separate raw URLs (each line = 1 value)
--  * Tabs: Status, Main, Settings, Optimization, Contact
--  * Restore original Lighting/effects when toggles are turned off
--  * ServerHop, ServerHopLow, Join by JobId
--  * Render distance best-effort, Simplify characters, Remove fog (Blox Fruit friendly)
--  * FPS cap via setfpscap (if supported)
--  * Draggable UI toggle on bottom-left, not overlapping Roblox settings
--  * Contact tab with Discord copy
--  * Safe pcall usage around networking and sensitive operations

-- ============= USER CONFIG (replace these) =================
local KEY_LIST_URL = "https://raw.githubusercontent.com/BooPowerFull/BloxFruitExecute/refs/heads/main/key.txt"  -- <--- replace with raw HTTP link containing keys (1 per line)
local ID_LIST_URL  = "https://raw.githubusercontent.com/BooPowerFull/BloxFruitExecute/refs/heads/main/id.txt"   -- <--- replace with raw HTTP link containing ids (1 per line)
local DISCORD_LINK = "https://discord.gg/yourlink" -- <--- replace your discord invite or text
-- ==============================================================

-- Services
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")
local CoreGui = game:GetService("CoreGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local TeleportService = game:GetService("TeleportService")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer

-- ============= Helper: safe HTTP get and parse lines =================
local function safeHttpGet(url)
    local ok, res = pcall(function()
        return HttpService:GetAsync(url, true)
    end)
    if ok and res then return res end
    return nil, ("HttpGet failed: " .. tostring(res))
end

local function parseLines(raw)
    local out = {}
    if not raw then return out end
    for line in raw:gmatch("[^\r\n]+") do
        local trimmed = line:match("^%s*(.-)%s*$")
        if trimmed ~= "" then
            -- remove all whitespace characters to avoid invisible mismatches
            trimmed = trimmed:gsub("%s+", "")
            table.insert(out, trimmed)
        end
    end
    return out
end

-- ============= Auth check (immediate) ===========================
-- Expectation: user sets getgenv().Key and getgenv().id before loading script.
-- If not set, script will attempt to fetch first lines from remote lists; if mismatch -> kick.

local function authCheck()
    -- fetch lists
    local keyRaw, kerr = safeHttpGet(KEY_LIST_URL)
    local idRaw, ierr  = safeHttpGet(ID_LIST_URL)
    if not keyRaw or not idRaw then
        pcall(function() LocalPlayer:Kick("Auth fetch failed.") end)
        return false
    end

    local keyList = parseLines(keyRaw)
    local idList  = parseLines(idRaw)

    -- require getgenv values
    local providedKey = getgenv().Key and tostring(getgenv().Key):gsub("%s+","") or ""
    local providedId  = getgenv().id  and tostring(getgenv().id):gsub("%s+","") or ""

    -- if user didn't set, attempt to pull first values from lists
    if providedKey == "" and #keyList >= 1 then providedKey = keyList[1] end
    if providedId  == "" and #idList  >= 1 then providedId  = idList[1]  end

    -- check membership
    local function inList(list, val)
        for _,v in ipairs(list) do
            if tostring(v) == tostring(val) then return true end
        end
        return false
    end

    if not (inList(keyList, providedKey) and inList(idList, providedId)) then
        pcall(function() LocalPlayer:Kick("Authorization failed. Invalid Key or ID.") end)
        return false
    end

    -- normalize store back to getgenv
    getgenv().Key = providedKey
    getgenv().id  = providedId
    return true
end

if not authCheck() then
    return
end

-- ============= Basic config & backups ===========================
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

-- Backup Lighting/effects to restore later
local envBackup = {
    FogStart = nil,
    FogEnd = nil,
    FogColor = nil,
    GlobalShadows = nil,
    Atmospheres = {},
    EffectsEnabled = {}, -- map fullName -> enabled
}

local function backupEnvironment()
    pcall(function()
        envBackup.FogStart = Lighting.FogStart
        envBackup.FogEnd = Lighting.FogEnd
        envBackup.FogColor = Lighting.FogColor
        envBackup.GlobalShadows = Lighting.GlobalShadows
        envBackup.Atmospheres = {}
        envBackup.EffectsEnabled = {}
        for _,v in ipairs(Lighting:GetChildren()) do
            if v:IsA("Atmosphere") then
                table.insert(envBackup.Atmospheres, {Density = v.Density, Offset = v.Offset, Name = v.Name})
            end
            if v:IsA("BloomEffect") or v:IsA("ColorCorrectionEffect") or v:IsA("DepthOfFieldEffect") or v:IsA("SunRaysEffect") or v:IsA("BlurEffect") then
                envBackup.EffectsEnabled[v:GetFullName()] = v.Enabled
            end
        end
    end)
end

local function restoreEnvironment()
    pcall(function()
        if envBackup.FogStart ~= nil then Lighting.FogStart = envBackup.FogStart end
        if envBackup.FogEnd ~= nil then Lighting.FogEnd = envBackup.FogEnd end
        if envBackup.FogColor ~= nil then Lighting.FogColor = envBackup.FogColor end
        if envBackup.GlobalShadows ~= nil then Lighting.GlobalShadows = envBackup.GlobalShadows end
        for _,v in ipairs(Lighting:GetChildren()) do
            if v:IsA("Atmosphere") and #envBackup.Atmospheres > 0 then
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

-- ============= Safe FPS setter ==================================
local function safeSetFps(val)
    val = tonumber(val) or initialFPS
    val = math.clamp(val, 15, 240)
    pcall(function()
        if type(setfpscap) == "function" then
            setfpscap(val)
        end
    end)
end
safeSetFps(config.fps)

-- ============= UI root (clear old UI) ===========================
if CoreGui:FindFirstChild("OptimizerUI") then
    pcall(function() CoreGui.OptimizerUI:Destroy() end)
end

local screen = Instance.new("ScreenGui")
screen.Name = "OptimizerUI"
screen.Parent = CoreGui
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = true
screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

-- small popup helper
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
            t:Play(); task.wait(0.28); popup:Destroy()
        end)
    end)
end

-- ============= Remove Fog (apply & restore) =====================
local fogApplied = false
local function applyRemoveFog(enable)
    if enable then
        if not fogApplied then
            backupEnvironment()
            pcall(function()
                Lighting.FogStart = 0
                Lighting.FogEnd = 1e6
                Lighting.FogColor = Color3.new(1,1,1)
                for _,v in ipairs(Lighting:GetChildren()) do
                    if v:IsA("Atmosphere") then v.Density = 0 end
                    if v:IsA("BloomEffect") or v:IsA("ColorCorrectionEffect") or v:IsA("DepthOfFieldEffect") or v:IsA("SunRaysEffect") or v:IsA("BlurEffect") then
                        v.Enabled = false
                    end
                end
                Lighting.GlobalShadows = false
            end)
            fogApplied = true
        end
    else
        if fogApplied then
            restoreEnvironment()
            fogApplied = false
        end
    end
end

-- ============= Render Distance control (best-effort) ===========
local renderControlled = false
local function setRenderDistanceEnable(enable, radius)
    config.renderDistance = radius or config.renderDistance
    config.renderDistanceEnabled = enable and true or false
    if enable then
        if renderControlled then return end
        renderControlled = true
        spawn(function()
            while config.renderDistanceEnabled do
                local char = LocalPlayer.Character
                local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChildWhichIsA("BasePart"))
                if root then
                    local rpos = root.Position
                    for _,obj in ipairs(Workspace:GetDescendants()) do
                        if obj:IsA("BasePart") and obj ~= root then
                            local ok, dist = pcall(function() return (obj.Position - rpos).Magnitude end)
                            if ok and dist then
                                if dist > config.renderDistance then
                                    pcall(function()
                                        if rawget(obj, "LocalTransparencyModifier") ~= nil then
                                            obj.LocalTransparencyModifier = 1
                                        else
                                            if obj.Transparency < 0.9 then obj.Transparency = 0.9 end
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
            -- cleanup restore attempt
            for _,obj in ipairs(Workspace:GetDescendants()) do
                pcall(function()
                    if rawget(obj, "LocalTransparencyModifier") ~= nil then obj.LocalTransparencyModifier = 0 end
                    if obj:IsA("BasePart") and obj.Transparency >= 0.9 then obj.Transparency = 0 end
                end)
            end
            renderControlled = false
        end)
    else
        config.renderDistanceEnabled = false
    end
end

-- ============= Simplify Characters (hide accessories/decals) ======
local simplified = false
local simplifiedStore = {}
local function simplifyCharacters(enable)
    if enable then
        if simplified then return end
        simplified = true
        for _,plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer then
                pcall(function()
                    local c = plr.Character
                    if c then
                        simplifiedStore[plr] = simplifiedStore[plr] or {Accessories = {}, Decals = {}}
                        for _,child in ipairs(c:GetChildren()) do
                            if child:IsA("Accessory") or child:IsA("Hat") then
                                simplifiedStore[plr].Accessories[#simplifiedStore[plr].Accessories+1] = child
                                pcall(function()
                                    if child:FindFirstChild("Handle") then
                                        child.Handle.Transparency = 1
                                        child.Handle.CanCollide = false
                                    end
                                    child.Transparency = 1
                                end)
                            end
                        end
                        for _,desc in ipairs(c:GetDescendants()) do
                            if desc:IsA("Decal") or desc:IsA("Texture") then
                                if desc.Name:lower():find("face") or desc.Name:lower():find("shirt") or desc.Name:lower():find("pants") then
                                    simplifiedStore[plr].Decals[#simplifiedStore[plr].Decals+1] = desc
                                    pcall(function() desc.Transparency = 1 end)
                                end
                            end
                        end
                    end
                end)
            end
        end
        -- reconnect for new players/respawns
        Players.PlayerAdded:Connect(function(p)
            p.CharacterAdded:Connect(function()
                if simplified then task.wait(0.6); simplifyCharacters(true) end
            end)
        end)
    else
        -- restore
        for plr,store in pairs(simplifiedStore) do
            pcall(function()
                for _,acc in ipairs(store.Accessories or {}) do
                    if acc and acc:IsDescendantOf(game) then
                        if acc:FindFirstChild("Handle") then
                            acc.Handle.Transparency = 0
                        end
                        acc.Transparency = 0
                    end
                end
                for _,dec in ipairs(store.Decals or {}) do
                    if dec and dec:IsDescendantOf(game) then
                        dec.Transparency = 0
                    end
                end
            end)
            simplifiedStore[plr] = nil
        end
        simplified = false
    end
end

-- ============= Memory Cleaner ===================================
local memCleanerConn
local function setMemoryCleaner(on)
    if on then
        if memCleanerConn then return end
        memCleanerConn = RunService.Heartbeat:Connect(function()
            pcall(function() collectgarbage("collect") end)
            task.wait(3)
        end)
    else
        if memCleanerConn then memCleanerConn:Disconnect(); memCleanerConn = nil end
    end
end

-- ============= Disable Extra Effects ============================
local effectsDisabled = false
local function disableExtraEffects(on)
    if on then
        backupEnvironment()
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
        effectsDisabled = true
    else
        restoreEnvironment()
        effectsDisabled = false
    end
end

-- ============= Network Boost (best-effort) =======================
local function setNetworkBoost(on)
    config.networkBoost = on
    -- Many properties are not exposed; this is a best-effort placeholder.
    -- You can extend with exploit specific functions if desired.
    if on then
        showPopup("Network boost enabled (best-effort)")
    else
        showPopup("Network boost disabled")
    end
end

-- ============= Server Hop helpers =================================
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

-- ============= UI BUILD ==========================================
-- Main frame
local mainFrame = Instance.new("Frame")
mainFrame.Size = UDim2.new(0,640,0,460)
mainFrame.Position = UDim2.new(0.5,0,0.5,0)
mainFrame.AnchorPoint = Vector2.new(0.5,0.5)
mainFrame.BackgroundColor3 = Color3.fromRGB(23,23,26)
mainFrame.Parent = screen
Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0,12)
mainFrame.Visible = false
mainFrame.ClipsDescendants = true

-- Header
local header = Instance.new("Frame", mainFrame)
header.Size = UDim2.new(1,0,0,44)
header.BackgroundTransparency = 1
local title = Instance.new("TextLabel", header)
title.Size = UDim2.new(0.7,0,1,0)
title.Position = UDim2.new(0,12,0,0)
title.BackgroundTransparency = 1
title.Text = "Optimizer Hub"
title.TextColor3 = Color3.new(1,1,1)
title.Font = Enum.Font.GothamBold
title.TextSize = 16
title.TextXAlignment = Enum.TextXAlignment.Left

local closeBtn = Instance.new("TextButton", header)
closeBtn.Size = UDim2.new(0,36,0,28)
closeBtn.Position = UDim2.new(1,-48,0,8)
closeBtn.BackgroundColor3 = Color3.fromRGB(42,42,46)
closeBtn.Text = "X"
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextColor3 = Color3.new(1,1,1)
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0,8)
closeBtn.MouseButton1Click:Connect(function() mainFrame.Visible = false end)

-- Sidebar & content
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
        pcall(function()
            scroll.CanvasSize = UDim2.new(0,0,0, list.AbsoluteContentSize.Y + 16)
        end)
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

-- helper for layout order
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
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0,8)
    btn.BackgroundColor3 = (config[key] and Color3.fromRGB(70,200,120)) or Color3.fromRGB(45,45,50)
    btn.Text = (config[key] and "ON") or "OFF"
    btn.TextColor3 = Color3.new(1,1,1)
    btn.MouseButton1Click:Connect(function()
        config[key] = not config[key]
        btn.BackgroundColor3 = (config[key] and Color3.fromRGB(70,200,120)) or Color3.fromRGB(45,45,50)
        btn.Text = (config[key] and "ON") or "OFF"
        showPopup(text.." "..(config[key] and "ON" or "OFF"))
        -- hooks
        if key == "removeFog" then applyRemoveFog(config.removeFog)
        elseif key == "memoryCleaner" then setMemoryCleaner(config.memoryCleaner)
        elseif key == "disableEffects" then disableExtraEffects(config.disableEffects)
        elseif key == "renderDistanceEnabled" then
            if config.renderDistanceEnabled then setRenderDistanceEnable(true, config.renderDistance) else setRenderDistanceEnable(false) end
        elseif key == "simplifyChars" then simplifyCharacters(config.simplifyChars)
        elseif key == "networkBoost" then setNetworkBoost(config.networkBoost) end
    end)
    return row, btn
end

-- ============= Status tab =======================================
do
    local page = pages["📊 Status"]
    local fpsRow,fpsLbl = createRow(page,"FPS: -")
    local pingRow,pingLbl = createRow(page,"Ping: -")
    local memRow,memLbl = createRow(page,"Memory: - MB")
    local onRow,onLbl = createRow(page,"Online: 0s")
    local timeRow,timeLbl = createRow(page,"Time: --:--:--")
    local cpuRow,cpuLbl = createRow(page,"CPU: N/A")
    local gpuRow,gpuLbl = createRow(page,"GPU: N/A")
    local diskRow,diskLbl = createRow(page,"Disk: N/A")

    local frameCount = 0
    RunService.RenderStepped:Connect(function() frameCount = frameCount + 1 end)
    local startTime = tick()
    task.spawn(function()
        while true do
            task.wait(1)
            local fps = frameCount; frameCount = 0
            fpsLbl.Text = "FPS: "..tostring(fps)
            local ping = "N/A"
            pcall(function()
                local ns = Stats and Stats.Network and Stats.Network.ServerStatsItem
                if ns and ns["Data Ping"] then ping = ns["Data Ping"]:GetValueString() or "N/A" end
            end)
            pingLbl.Text = "Ping: "..tostring(ping)
            local mem = "N/A"
            pcall(function()
                if Stats.GetTotalMemoryUsageMb then local m = Stats:GetTotalMemoryUsageMb(); if type(m)=="number" then mem = math.floor(m) end end
            end)
            memLbl.Text = "Memory: "..tostring(mem).." MB"
            onLbl.Text = "Online: "..tostring(math.floor(tick()-startTime)).."s"
            timeLbl.Text = "Time: "..os.date("%H:%M:%S")
            -- CPU/GPU/Disk placeholders (Roblox cannot read hardware directly). Keep as N/A or approximate with Stats if desired.
            cpuLbl.Text = "CPU: N/A"
            gpuLbl.Text = "GPU: N/A"
            diskLbl.Text = "Disk: N/A"
        end
    end)
end

-- ============= Main tab (original toggles) ======================
do
    local page = pages["⚡ Main"]
    createToggle(page, "Memory Cleaner", "memoryCleaner")
    createToggle(page, "Network Boost", "networkBoost")
    createToggle(page, "Hide Far Objects", "hideFar")
    createToggle(page, "Disable Effects", "disableEffects")
    createToggle(page, "Clean Scripts", "cleanScripts")
    createToggle(page, "Remove Fog", "removeFog")
end

-- ============= Settings tab =====================================
do
    local page = pages["🔧 Settings"]

    -- FPS cap row (left & right)
    local fpsRow = Instance.new("Frame", page)
    fpsRow.Size = UDim2.new(1,0,0,48)
    fpsRow.LayoutOrder = nextLO()
    fpsRow.BackgroundColor3 = Color3.fromRGB(34,34,38)
    Instance.new("UICorner", fpsRow).CornerRadius = UDim.new(0,8)

    local lbl = Instance.new("TextLabel", fpsRow)
    lbl.Size = UDim2.new(0.2,0,1,0); lbl.Position = UDim2.new(0,12,0,0); lbl.BackgroundTransparency = 1
    lbl.Font = Enum.Font.Gotham; lbl.TextSize = 14; lbl.TextColor3 = Color3.new(1,1,1); lbl.Text = "FPS Cap:"

    local left = Instance.new("TextButton", fpsRow)
    left.Size = UDim2.new(0,36,0,28); left.Position = UDim2.new(0.38,0,0.12,0)
    left.Text = "<"; left.Font = Enum.Font.GothamBold; left.TextSize = 18; left.BackgroundColor3 = Color3.fromRGB(45,45,50); left.TextColor3 = Color3.new(1,1,1)
    Instance.new("UICorner", left).CornerRadius = UDim.new(0,8)

    local val = Instance.new("TextLabel", fpsRow)
    val.Size = UDim2.new(0,70,1,0); val.Position = UDim2.new(0.55,0,0,0); val.BackgroundTransparency = 1
    val.Font = Enum.Font.GothamBold; val.Text = tostring(config.fps); val.TextSize = 14; val.TextColor3 = Color3.new(1,1,1); val.TextXAlignment = Enum.TextXAlignment.Center

    local right = left:Clone(); right.Parent = fpsRow; right.Position = UDim2.new(0.75,0,0.12,0); right.Text = ">"

    local fpsOptions = {30,60,90,120}
    local fpsIndex = 2
    for i,v in ipairs(fpsOptions) do if v == config.fps then fpsIndex = i end end

    local function applyFps(vn)
        config.fps = vn
        val.Text = tostring(vn)
        safeSetFps(vn)
        showPopup("FPS cap "..vn)
    end

    left.MouseButton1Click:Connect(function()
        if fpsIndex > 1 then fpsIndex = fpsIndex - 1; applyFps(fpsOptions[fpsIndex]) end
    end)
    right.MouseButton1Click:Connect(function()
        if fpsIndex < #fpsOptions then fpsIndex = fpsIndex + 1; applyFps(fpsOptions[fpsIndex]) end
    end)

    -- Server Hop
    local shRow, shLbl = createRow(page, "Server Hop (random)")
    local shBtn = Instance.new("TextButton", shRow)
    shBtn.Size = UDim2.new(0.28,0,0.7,0)
    shBtn.Position = UDim2.new(0.66,0,0.15,0)
    shBtn.Text = "Hop"; shBtn.BackgroundColor3 = Color3.fromRGB(70,120,200); shBtn.Font = Enum.Font.GothamBold; shBtn.TextColor3 = Color3.new(1,1,1)
    Instance.new("UICorner", shBtn).CornerRadius = UDim.new(0,8)
    shBtn.MouseButton1Click:Connect(function() showPopup("Searching servers..."); ServerHop() end)

    -- Server Hop Low
    local lphRow, lphLbl = createRow(page, "Server Hop (low players)")
    local lphBtn = Instance.new("TextButton", lphRow)
    lphBtn.Size = UDim2.new(0.28,0,0.7,0)
    lphBtn.Position = UDim2.new(0.66,0,0.15,0)
    lphBtn.Text = "Hop Low"; lphBtn.BackgroundColor3 = Color3.fromRGB(70,120,200); lphBtn.Font = Enum.Font.GothamBold; lphBtn.TextColor3 = Color3.new(1,1,1)
    Instance.new("UICorner", lphBtn).CornerRadius = UDim.new(0,8)
    lphBtn.MouseButton1Click:Connect(function() showPopup("Searching low-player servers..."); ServerHopLow(6) end)

    -- Join by Job ID (input + button horizontal)
    local jobRow, jobLbl = createRow(page, "Join by Job ID")
    local jobBox = Instance.new("TextBox", jobRow)
    jobBox.Size = UDim2.new(0.56,0,0.7,0)
    jobBox.Position = UDim2.new(0.12,0,0.15,0)
    jobBox.PlaceholderText = "Paste JobId here"
    jobBox.ClearTextOnFocus = false
    jobBox.Font = Enum.Font.Gotham
    jobBox.TextSize = 14
    jobBox.BackgroundColor3 = Color3.fromRGB(50,50,55)
    jobBox.TextColor3 = Color3.new(1,1,1)
    Instance.new("UICorner", jobBox).CornerRadius = UDim.new(0,8)

    local jobBtn = Instance.new("TextButton", jobRow)
    jobBtn.Size = UDim2.new(0.3,0,0.7,0)
    jobBtn.Position = UDim2.new(0.7,0,0.15,0)
    jobBtn.Text = "Join"
    jobBtn.BackgroundColor3 = Color3.fromRGB(70,120,200)
    jobBtn.TextColor3 = Color3.new(1,1,1)
    jobBtn.Font = Enum.Font.GothamBold
    jobBtn.TextSize = 14
    Instance.new("UICorner", jobBtn).CornerRadius = UDim.new(0,8)

    jobBtn.MouseButton1Click:Connect(function()
        local jid = tostring(jobBox.Text):gsub("%s+","")
        if jid == "" then showPopup("Job ID is empty"); return end
        showPopup("Joining Job ID...")
        pcall(function()
            TeleportService:TeleportToPlaceInstance(game.PlaceId, jid, LocalPlayer)
        end)
    end)
end

-- ============= Optimization tab =================================
do
    local page = pages["🛠 Optimization"]
    -- Remove Fog toggle
    createToggle(page, "Remove Fog", "removeFog")

    -- Render Distance selection
    local rdRow, rdLbl = createRow(page, "Render Distance (m)")
    local rdBtn250 = Instance.new("TextButton", rdRow); rdBtn250.Size = UDim2.new(0.18,0,0.7,0); rdBtn250.Position = UDim2.new(0.52,0,0.15,0); rdBtn250.Text = "250"
    local rdBtn500 = rdBtn250:Clone(); rdBtn500.Parent = rdRow; rdBtn500.Position = UDim2.new(0.70,0,0.15,0); rdBtn500.Text = "500"
    local rdBtn1000 = rdBtn250:Clone(); rdBtn1000.Parent = rdRow; rdBtn1000.Position = UDim2.new(0.88,0,0.15,0); rdBtn1000.Text = "1000"
    for _,b in ipairs({rdBtn250, rdBtn500, rdBtn1000}) do Instance.new("UICorner", b).CornerRadius = UDim.new(0,8); b.Font = Enum.Font.GothamBold; b.TextColor3 = Color3.new(1,1,1); b.BackgroundColor3 = Color3.fromRGB(60,60,65) end
    rdBtn250.MouseButton1Click:Connect(function() config.renderDistance = 250; config.renderDistanceEnabled = true; setRenderDistanceEnable(true,250); showPopup("Render distance: 250") end)
    rdBtn500.MouseButton1Click:Connect(function() config.renderDistance = 500; config.renderDistanceEnabled = true; setRenderDistanceEnable(true,500); showPopup("Render distance: 500") end)
    rdBtn1000.MouseButton1Click:Connect(function() config.renderDistance = 1000; config.renderDistanceEnabled = true; setRenderDistanceEnable(true,1000); showPopup("Render distance: 1000") end)

    -- Render enable/disable
    local rdControlRow, rdControlLbl = createRow(page, "Render Distance Control")
    local rdToggle = Instance.new("TextButton", rdControlRow)
    rdToggle.Size = UDim2.new(0.22,0,0.66,0)
    rdToggle.Position = UDim2.new(0.72,0,0.15,0)
    rdToggle.Text = "Disable"
    rdToggle.Font = Enum.Font.GothamBold
    rdToggle.TextColor3 = Color3.new(1,1,1)
    rdToggle.BackgroundColor3 = Color3.fromRGB(70,120,200)
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

    -- Memory Cleaner (aggressive)
    createToggle(page, "Memory Cleaner (aggressive)", "memoryCleaner")

    -- Network Boost toggle
    createToggle(page, "Network Boost", "networkBoost")
end

-- ============= Contact tab =======================================
do
    local page = pages["👤 Contact"]
    local row, lbl = createRow(page, "Discord:")
    lbl.Text = "Discord: (edit DISCORD_LINK in script)"
    local btn = Instance.new("TextButton", row)
    btn.Size = UDim2.new(0.32,0,0.7,0)
    btn.Position = UDim2.new(0.66,0,0.15,0)
    btn.Text = "Copy"
    btn.BackgroundColor3 = Color3.fromRGB(70,120,200)
    btn.TextColor3 = Color3.new(1,1,1)
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0,8)
    btn.MouseButton1Click:Connect(function()
        pcall(function() if setclipboard then setclipboard(DISCORD_LINK) end end)
        showPopup("Discord link copied!")
    end)
end

-- ============= Toggle button (bottom-left draggable) =================
local toggleBtn = Instance.new("ImageButton")
toggleBtn.Size = UDim2.new(0,46,0,46)
toggleBtn.Position = UDim2.new(0,16,1,-140) -- left, lower
toggleBtn.AnchorPoint = Vector2.new(0,0)
toggleBtn.BackgroundColor3 = Color3.fromRGB(40,40,45)
toggleBtn.Image = "" -- optionally put an image asset
toggleBtn.AutoButtonColor = true
toggleBtn.Parent = screen
Instance.new("UICorner", toggleBtn).CornerRadius = UDim.new(0,10)
local tLabel = Instance.new("TextLabel", toggleBtn)
tLabel.Size = UDim2.new(1,0,1,0)
tLabel.BackgroundTransparency = 1
tLabel.Text = "OPT"
tLabel.Font = Enum.Font.GothamBold
tLabel.TextSize = 14
tLabel.TextColor3 = Color3.new(1,1,1)

-- drag behavior for toggle
do
    local dragging, dragStart, startPos
    toggleBtn.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = toggleBtn.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then dragging = false end
            end)
        end
    end)
    toggleBtn.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and dragInput and input == dragInput then
            local ok, pos = pcall(function() return input.Position end)
            if not ok or not pos then return end
            local delta = pos - dragStart
            local newX = startPos.X.Offset + delta.X
            local newY = startPos.Y.Offset + delta.Y
            local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1920,1080)
            local w,h = toggleBtn.AbsoluteSize.X, toggleBtn.AbsoluteSize.Y
            newX = math.clamp(newX, 0, vp.X - w)
            newY = math.clamp(newY, 0, vp.Y - h)
            toggleBtn.Position = UDim2.new(0, newX, 0, newY)
        end
    end)
end

toggleBtn.MouseButton1Click:Connect(function()
    if mainFrame.Visible then
        local t = TweenService:Create(mainFrame, TweenInfo.new(0.18), {BackgroundTransparency = 1})
        t:Play()
        t.Completed:Wait()
        mainFrame.Visible = false
        mainFrame.BackgroundTransparency = 0
    else
        mainFrame.Visible = true
        mainFrame.BackgroundTransparency = 1
        TweenService:Create(mainFrame, TweenInfo.new(0.18), {BackgroundTransparency = 0}):Play()
    end
end)

-- ============= Clean up / restore when script ends =================
local function restoreAll()
    applyRemoveFog(false)
    setMemoryCleaner(false)
    setRenderDistanceEnable(false)
    simplifyCharacters(false)
    disableExtraEffects(false)
    setNetworkBoost(false)
    safeSetFps(initialFPS)
end

-- bind to close (best-effort)
if game:FindFirstChild("BindToClose") then
    pcall(function() game:BindToClose(restoreAll) end)
else
    -- if BindToClose not available, try to restore when player leaves
    Players.LocalPlayer.AncestryChanged:Connect(function()
        restoreAll()
    end)
end

print("✅ Optimizer Hub loaded (Auth OK).")
showPopup("Optimizer Hub loaded")
