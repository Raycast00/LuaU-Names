local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer

-- ===== SETTINGS =====
local SETTINGS = {
    Enabled = true,
    Visible = true,
    
    -- Text settings
    Font = Drawing.Fonts.UI,
    Size = 14,
    Outline = true,
    OutlineColor = Color3.fromRGB(0, 0, 0),
    
    -- Animation
    Animated = true,
    GradientSpeed = 1.5,
    
    -- Colors for gradient
    Color1 = Color3.fromRGB(105, 245, 66),
    Color2 = Color3.fromRGB(255, 255, 255),
    
    -- Static color (when animation is off)
    StaticColor = Color3.fromRGB(255, 255, 255),
    
    -- Visibility
    MaxDistance = 1000,
    YOffset = 2.5,
}

-- ===== COLOR UTILS =====
local function lerpColor(a, b, t)
    return Color3.new(
        a.R + (b.R - a.R) * t,
        a.G + (b.G - a.G) * t,
        a.B + (b.B - a.B) * t
    )
end

-- ===== ESP OBJECT =====
local ESP = {}
ESP.__index = ESP

function ESP.new()
    local self = setmetatable({}, ESP)
    self.CharTexts = {}
    self.OutlineTexts = {}
    self.Enabled = true
    self.Visible = true
    self.Settings = {}
    self.GetPosition = nil
    self.GetText = nil
    return self
end

function ESP:Cleanup()
    for _, text in ipairs(self.CharTexts) do
        pcall(function() text:Remove() end)
    end
    for _, text in ipairs(self.OutlineTexts) do
        pcall(function() text:Remove() end)
    end
    table.clear(self.CharTexts)
    table.clear(self.OutlineTexts)
end

function ESP:EnsureCharCount(count)
    while #self.CharTexts > count do
        pcall(function() table.remove(self.CharTexts):Remove() end)
        pcall(function() table.remove(self.OutlineTexts):Remove() end)
    end
    
    while #self.CharTexts < count do
        local outline = Drawing.new("Text")
        outline.Font = SETTINGS.Font
        outline.Size = SETTINGS.Size + 2
        outline.Color = SETTINGS.OutlineColor
        outline.Transparency = 0.8
        outline.Outline = false
        outline.Center = true
        outline.Visible = false
        table.insert(self.OutlineTexts, outline)
        
        local text = Drawing.new("Text")
        text.Font = SETTINGS.Font
        text.Size = SETTINGS.Size
        text.Outline = true
        text.Center = true
        text.Visible = false
        table.insert(self.CharTexts, text)
    end
end

-- ===== RENDER =====
function ESP:Render(now, camera)
    if not self.Enabled or not self.Visible then
        self:Hide()
        return
    end
    
    local displayText = ""
    if self.GetText then
        local success, result = pcall(self.GetText)
        if success and result then
            displayText = tostring(result)
        end
    end
    
    if displayText == "" then
        self:Hide()
        return
    end
    
    local worldPosition = nil
    if self.GetPosition then
        local success, result = pcall(self.GetPosition)
        if success and result and typeof(result) == "Vector3" then
            worldPosition = result
        end
    end
    
    if not worldPosition then
        self:Hide()
        return
    end
    
    local yOffset = self.Settings.YOffset or SETTINGS.YOffset
    local maxDistance = self.Settings.MaxDistance or SETTINGS.MaxDistance
    local animated = self.Settings.Animated
    if animated == nil then animated = SETTINGS.Animated end
    
    local camPos = camera.CFrame.Position
    local distance = (camPos - worldPosition).Magnitude
    if distance > maxDistance then
        self:Hide()
        return
    end
    
    local headPos = worldPosition + Vector3.new(0, yOffset, 0)
    local screenPos, onScreen = camera:WorldToViewportPoint(headPos)
    
    if not onScreen or screenPos.Z <= 0 then
        self:Hide()
        return
    end
    
    local textLength = math.min(#displayText, 64)
    self:EnsureCharCount(textLength)
    
    local charWidth = SETTINGS.Size * 0.6
    local scale = math.clamp(1 - (distance / maxDistance), 0.3, 1)
    local finalSize = math.floor(SETTINGS.Size * scale)
    local finalCharWidth = charWidth * scale
    
    local totalWidth = finalCharWidth * textLength
    local startX = screenPos.X - totalWidth / 2 + finalCharWidth / 2
    
    local color1 = self.Settings.Color1 or SETTINGS.Color1
    local color2 = self.Settings.Color2 or SETTINGS.Color2
    local staticColor = self.Settings.StaticColor or SETTINGS.StaticColor
    
    local gradientPhase = (now * SETTINGS.GradientSpeed) % 1
    
    for i = 1, textLength do
        local char = displayText:sub(i, i)
        local charX = startX + (i - 1) * finalCharWidth
        
        local color
        if animated then
            local normalizedPos = textLength > 1 and (i - 1) / (textLength - 1) or 0.5
            local gradientPos = (normalizedPos + gradientPhase) % 1
            color = lerpColor(color1, color2, gradientPos)
        else
            color = staticColor
        end
        
        local isVisible = SETTINGS.Visible and SETTINGS.Enabled
        
        if self.OutlineTexts[i] then
            self.OutlineTexts[i].Position = Vector2.new(charX, screenPos.Y)
            self.OutlineTexts[i].Text = char
            self.OutlineTexts[i].Size = finalSize + 2
            self.OutlineTexts[i].Visible = isVisible
        end
        
        if self.CharTexts[i] then
            self.CharTexts[i].Position = Vector2.new(charX, screenPos.Y)
            self.CharTexts[i].Text = char
            self.CharTexts[i].Size = finalSize
            self.CharTexts[i].Color = color
            self.CharTexts[i].Visible = isVisible
        end
    end
end

function ESP:Hide()
    for _, text in ipairs(self.CharTexts) do
        if text then text.Visible = false end
    end
    for _, text in ipairs(self.OutlineTexts) do
        if text then text.Visible = false end
    end
end

-- ===== ESP MANAGER =====
local playerESPs = {}
local customESPs = {}
local customIdCounter = 0
local renderConnection = nil

-- ===== PLAYER ESP =====
local function createPlayerESP(player)
    local esp = ESP.new()
    
    esp.GetText = function()
        return player.DisplayName
    end
    
    esp.GetPosition = function()
        local char = player.Character
        if not char then return nil end
        local head = char:FindFirstChild("Head")
        if head then return head.Position end
        local root = char:FindFirstChild("HumanoidRootPart")
        if root then return root.Position end
        return nil
    end
    
    playerESPs[player] = esp
    return esp
end

-- ===== RENDER LOOP =====
local function renderAll()
    local camera = workspace.CurrentCamera
    if not camera then return end
    
    local now = tick()
    
    for _, esp in pairs(playerESPs) do
        esp:Render(now, camera)
    end
    
    for _, esp in pairs(customESPs) do
        esp:Render(now, camera)
    end
end

-- ===== START/STOP =====
local function startRender()
    if renderConnection then return end
    renderConnection = RunService:BindToRenderStep("HologramESP", Enum.RenderPriority.Last.Value + 1, renderAll)
end

local function stopRender()
    if renderConnection then
        RunService:UnbindFromRenderStep("HologramESP")
        renderConnection = nil
    end
end

-- Auto-start
startRender()

-- ===== PLAYER EVENTS =====
local playerAddedConn = nil
local playerRemovingConn = nil

local function connectPlayerEvents()
    if playerAddedConn then return end
    
    playerAddedConn = Players.PlayerAdded:Connect(function(player)
        if player == LocalPlayer then return end
        createPlayerESP(player)
    end)
    
    playerRemovingConn = Players.PlayerRemoving:Connect(function(player)
        local esp = playerESPs[player]
        if esp then
            esp:Cleanup()
            playerESPs[player] = nil
        end
    end)
end

local function disconnectPlayerEvents()
    if playerAddedConn then
        playerAddedConn:Disconnect()
        playerAddedConn = nil
    end
    if playerRemovingConn then
        playerRemovingConn:Disconnect()
        playerRemovingConn = nil
    end
end

-- Init
connectPlayerEvents()

for _, player in ipairs(Players:GetPlayers()) do
    if player ~= LocalPlayer then
        createPlayerESP(player)
    end
end

-- ===== CLEANUP =====
local function fullCleanup()
    stopRender()
    disconnectPlayerEvents()
    
    for _, esp in pairs(playerESPs) do
        esp:Cleanup()
    end
    for _, esp in pairs(customESPs) do
        esp:Cleanup()
    end
    table.clear(playerESPs)
    table.clear(customESPs)
end

-- Safe destroy handling
pcall(function()
    if script then
        script.Destroying:Connect(fullCleanup)
    end
end)

-- Also clean up on game close
game:GetService("Players").PlayerRemoving:Connect(function(player)
    if player == LocalPlayer then
        fullCleanup()
    end
end)

-- ===== PUBLIC API =====
local Library = {}

function Library:SetEnabled(state)
    SETTINGS.Enabled = state
end

function Library:SetVisible(state)
    SETTINGS.Visible = state
end

function Library:SetAnimated(state)
    SETTINGS.Animated = state
end

function Library:SetGradientSpeed(speed)
    SETTINGS.GradientSpeed = speed
end

function Library:SetColors(color1, color2)
    SETTINGS.Color1 = color1
    SETTINGS.Color2 = color2
end

function Library:SetStaticColor(color)
    SETTINGS.StaticColor = color
end

function Library:SetSize(size)
    SETTINGS.Size = size
end

function Library:SetMaxDistance(dist)
    SETTINGS.MaxDistance = dist
end

function Library:SetYOffset(offset)
    SETTINGS.YOffset = offset
end

function Library:SetOutline(state)
    SETTINGS.Outline = state
end

function Library:SetOutlineColor(color)
    SETTINGS.OutlineColor = color
end

function Library:Destroy()
    fullCleanup()
end

-- ===== CUSTOM ESP API =====
Library.Custom = {}

function Library.Custom:Add(options)
    if not options then return nil end
    
    customIdCounter = customIdCounter + 1
    local id = customIdCounter
    
    local esp = ESP.new()
    esp.ID = id
    
    if type(options.Text) == "function" then
        esp.GetText = options.Text
    elseif options.Text ~= nil then
        local txt = tostring(options.Text)
        esp.GetText = function() return txt end
    else
        esp.GetText = function() return "Object" end
    end
    
    if options.Object and typeof(options.Object) == "Instance" then
        local obj = options.Object
        esp.GetPosition = function()
            if not obj or not obj.Parent then return nil end
            if obj:IsA("BasePart") then
                return obj.Position
            elseif obj:IsA("Model") then
                local primary = obj.PrimaryPart
                return primary and primary.Position
            end
            return nil
        end
    elseif type(options.Position) == "function" then
        esp.GetPosition = options.Position
    elseif options.Position and typeof(options.Position) == "Vector3" then
        local pos = options.Position
        esp.GetPosition = function() return pos end
    else
        esp.GetPosition = function() return nil end
    end
    
    if options.Animated ~= nil then esp.Settings.Animated = options.Animated end
    if options.Color1 then esp.Settings.Color1 = options.Color1 end
    if options.Color2 then esp.Settings.Color2 = options.Color2 end
    if options.StaticColor then esp.Settings.StaticColor = options.StaticColor end
    if options.YOffset then esp.Settings.YOffset = options.YOffset end
    if options.MaxDistance then esp.Settings.MaxDistance = options.MaxDistance end
    if options.Enabled ~= nil then esp.Enabled = options.Enabled end
    if options.Visible ~= nil then esp.Visible = options.Visible end
    
    customESPs[id] = esp
    return id
end

function Library.Custom:Remove(id)
    local esp = customESPs[id]
    if esp then
        esp:Cleanup()
        customESPs[id] = nil
    end
end

function Library.Custom:RemoveAll()
    for id, esp in pairs(customESPs) do
        esp:Cleanup()
        customESPs[id] = nil
    end
end

function Library.Custom:Get(id)
    return customESPs[id]
end

function Library.Custom:SetText(id, text)
    local esp = customESPs[id]
    if esp then
        if type(text) == "function" then
            esp.GetText = text
        else
            local txt = tostring(text)
            esp.GetText = function() return txt end
        end
    end
end

function Library.Custom:SetPosition(id, pos)
    local esp = customESPs[id]
    if esp then
        if type(pos) == "function" then
            esp.GetPosition = pos
        elseif typeof(pos) == "Vector3" then
            local v = pos
            esp.GetPosition = function() return v end
        end
    end
end

function Library.Custom:SetAnimated(id, state)
    local esp = customESPs[id]
    if esp then esp.Settings.Animated = state end
end

function Library.Custom:SetColors(id, color1, color2)
    local esp = customESPs[id]
    if esp then
        esp.Settings.Color1 = color1
        esp.Settings.Color2 = color2
    end
end

function Library.Custom:SetStaticColor(id, color)
    local esp = customESPs[id]
    if esp then esp.Settings.StaticColor = color end
end

function Library.Custom:SetEnabled(id, state)
    local esp = customESPs[id]
    if esp then esp.Enabled = state end
end

function Library.Custom:SetVisible(id, state)
    local esp = customESPs[id]
    if esp then esp.Visible = state end
end

return Library
