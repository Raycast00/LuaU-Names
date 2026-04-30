--[[
    Hologram ESP Library v3.1 - Text Glow Effect
    - Glow on the text itself (not outline)
    - Blur-like glow using multiple offset layers
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer

-- ===== SETTINGS =====
local SETTINGS = {
    Enabled = false,
    Visible = false,
    
    -- Text settings
    Font = Drawing.Fonts.UI,
    Size = 14,
    Outline = true,
    OutlineColor = Color3.fromRGB(0, 0, 0),
    
    -- Text Glow effect
    GlowEnabled = true,
    GlowIntensity = 4,          -- How many glow layers (1-8, more = smoother)
    GlowSpread = 1.5,           -- How far glow spreads (pixels between layers)
    GlowTransparency = 0.6,     -- Base transparency of glow layers
    GlowColor = nil,            -- nil = use text color, or set custom Color3
    
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
    self.CharTexts = {}          -- Main text (top layer)
    self.OutlineTexts = {}       -- Black outline
    self.GlowTexts = {}          -- Glow text layers (behind main text)
    self.Enabled = true
    self.Visible = true
    self.Settings = {}
    self.GetPosition = nil
    self.GetText = nil
    self.LastTextLength = 0
    return self
end

function ESP:Cleanup()
    for _, text in ipairs(self.CharTexts) do
        pcall(function() text:Remove() end)
    end
    for _, text in ipairs(self.OutlineTexts) do
        pcall(function() text:Remove() end)
    end
    for _, glowText in ipairs(self.GlowTexts) do
        pcall(function() glowText:Remove() end)
    end
    table.clear(self.CharTexts)
    table.clear(self.OutlineTexts)
    table.clear(self.GlowTexts)
    self.LastTextLength = 0
end

function ESP:EnsureCharCount(count, glowCount)
    glowCount = glowCount or 0
    
    -- Main characters
    while #self.CharTexts > count do
        pcall(function() table.remove(self.CharTexts):Remove() end)
    end
    while #self.CharTexts < count do
        local text = Drawing.new("Text")
        text.Font = SETTINGS.Font
        text.Size = SETTINGS.Size
        text.Outline = true
        text.OutlineColor = Color3.fromRGB(0, 0, 0)
        text.Center = true
        text.Visible = false
        text.ZIndex = 10  -- Top layer
        table.insert(self.CharTexts, text)
    end
    
    -- Outlines (thin black border around main text)
    while #self.OutlineTexts > count do
        pcall(function() table.remove(self.OutlineTexts):Remove() end)
    end
    while #self.OutlineTexts < count do
        local outline = Drawing.new("Text")
        outline.Font = SETTINGS.Font
        outline.Size = SETTINGS.Size + 2
        outline.Color = SETTINGS.OutlineColor
        outline.Transparency = 0.8
        outline.Outline = false
        outline.Center = true
        outline.Visible = false
        outline.ZIndex = 9  -- Behind main text
        table.insert(self.OutlineTexts, outline)
    end
    
    -- Glow text layers (rendered behind, offset in different directions)
    -- Each layer is a full copy of the text, slightly offset and transparent
    while #self.GlowTexts > glowCount do
        pcall(function() table.remove(self.GlowTexts):Remove() end)
    end
    while #self.GlowTexts < glowCount do
        local glow = Drawing.new("Text")
        glow.Font = SETTINGS.Font
        glow.Size = SETTINGS.Size
        glow.Outline = false
        glow.Center = true
        glow.Visible = false
        glow.ZIndex = 1  -- Far behind
        table.insert(self.GlowTexts, glow)
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
    
    local glowEnabled = self.Settings.GlowEnabled
    if glowEnabled == nil then glowEnabled = SETTINGS.GlowEnabled end
    
    local glowIntensity = glowEnabled and (self.Settings.GlowIntensity or SETTINGS.GlowIntensity) or 0
    glowIntensity = math.clamp(glowIntensity, 0, 8)
    
    local glowSpread = self.Settings.GlowSpread or SETTINGS.GlowSpread
    local glowTransparency = self.Settings.GlowTransparency or SETTINGS.GlowTransparency
    
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
    
    -- We only need 1 glow text object (we'll render glow per-character differently)
    self:EnsureCharCount(textLength, 0)  -- No extra glow text objects needed
    self.LastTextLength = textLength
    
    -- But we need glow objects for each character
    -- Actually, let's use a different approach: per-character glow layers
    while #self.GlowTexts < (textLength * glowIntensity) do
        local glow = Drawing.new("Text")
        glow.Font = SETTINGS.Font
        glow.Outline = false
        glow.Center = true
        glow.Visible = false
        glow.ZIndex = 1
        table.insert(self.GlowTexts, glow)
    end
    while #self.GlowTexts > (textLength * glowIntensity) do
        pcall(function() table.remove(self.GlowTexts):Remove() end)
    end
    
    local charWidth = SETTINGS.Size * 0.6
    local scale = math.clamp(1 - (distance / maxDistance), 0.3, 1)
    local finalSize = math.floor(SETTINGS.Size * scale)
    local finalCharWidth = charWidth * scale
    
    local totalWidth = finalCharWidth * textLength
    local startX = screenPos.X - totalWidth / 2 + finalCharWidth / 2
    
    local color1 = self.Settings.Color1 or SETTINGS.Color1
    local color2 = self.Settings.Color2 or SETTINGS.Color2
    local staticColor = self.Settings.StaticColor or SETTINGS.StaticColor
    local glowColor = self.Settings.GlowColor or SETTINGS.GlowColor
    
    local gradientPhase = (now * SETTINGS.GradientSpeed) % 1
    local isVisible = SETTINGS.Visible and SETTINGS.Enabled
    
    -- Calculate colors for each character
    local charColors = {}
    for i = 1, textLength do
        if animated then
            local normalizedPos = textLength > 1 and (i - 1) / (textLength - 1) or 0.5
            local gradientPos = (normalizedPos + gradientPhase) % 1
            charColors[i] = lerpColor(color1, color2, gradientPos)
        else
            charColors[i] = staticColor
        end
    end
    
    -- Hide all glow texts first
    for _, glow in ipairs(self.GlowTexts) do
        glow.Visible = false
    end
    
    -- Render glow layers (behind main text, offset in different directions)
    local glowIndex = 1
    for charIdx = 1, textLength do
        local char = displayText:sub(charIdx, charIdx)
        local charX = startX + (charIdx - 1) * finalCharWidth
        local charColor = glowColor or charColors[charIdx]
        
        -- Create glow for this character with multiple offset layers
        for layerIdx = 1, glowIntensity do
            if glowIndex <= #self.GlowTexts then
                local glow = self.GlowTexts[glowIndex]
                
                -- Calculate offset direction (spread out in circle pattern)
                local angle = (layerIdx - 1) * (math.pi * 2 / glowIntensity)
                local offsetX = math.cos(angle) * glowSpread * layerIdx * 0.5
                local offsetY = math.sin(angle) * glowSpread * layerIdx * 0.5
                
                -- More transparent the further out
                local layerAlpha = 1 - (layerIdx / glowIntensity) * glowTransparency
                
                glow.Position = Vector2.new(charX + offsetX, screenPos.Y + offsetY)
                glow.Text = char
                glow.Size = finalSize
                glow.Color = charColor
                glow.Transparency = 1 - layerAlpha
                glow.Visible = isVisible
                
                glowIndex = glowIndex + 1
            end
        end
    end
    
    -- Render outline
    for i = 1, textLength do
        if self.OutlineTexts[i] then
            local char = displayText:sub(i, i)
            local charX = startX + (i - 1) * finalCharWidth
            
            self.OutlineTexts[i].Position = Vector2.new(charX, screenPos.Y)
            self.OutlineTexts[i].Text = char
            self.OutlineTexts[i].Size = finalSize + 2
            self.OutlineTexts[i].Visible = isVisible
        end
    end
    
    -- Render main text (on top)
    for i = 1, textLength do
        if self.CharTexts[i] then
            local char = displayText:sub(i, i)
            local charX = startX + (i - 1) * finalCharWidth
            
            self.CharTexts[i].Position = Vector2.new(charX, screenPos.Y)
            self.CharTexts[i].Text = char
            self.CharTexts[i].Size = finalSize
            self.CharTexts[i].Color = charColors[i]
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
    for _, text in ipairs(self.GlowTexts) do
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

pcall(function()
    if script then
        script.Destroying:Connect(fullCleanup)
    end
end)

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

-- Text Glow API
function Library:SetGlowEnabled(state)
    SETTINGS.GlowEnabled = state
end

function Library:SetGlowIntensity(intensity)
    SETTINGS.GlowIntensity = math.clamp(intensity, 1, 8)
end

function Library:SetGlowSpread(spread)
    SETTINGS.GlowSpread = math.clamp(spread, 0.5, 5)
end

function Library:SetGlowTransparency(transparency)
    SETTINGS.GlowTransparency = math.clamp(transparency, 0, 1)
end

function Library:SetGlowColor(color)
    SETTINGS.GlowColor = color
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
    
    -- Glow settings
    if options.GlowEnabled ~= nil then esp.Settings.GlowEnabled = options.GlowEnabled end
    if options.GlowIntensity then esp.Settings.GlowIntensity = options.GlowIntensity end
    if options.GlowSpread then esp.Settings.GlowSpread = options.GlowSpread end
    if options.GlowColor then esp.Settings.GlowColor = options.GlowColor end
    
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

function Library.Custom:SetGlowEnabled(id, state)
    local esp = customESPs[id]
    if esp then esp.Settings.GlowEnabled = state end
end

function Library.Custom:SetGlowSettings(id, intensity, spread, color)
    local esp = customESPs[id]
    if esp then
        if intensity then esp.Settings.GlowIntensity = intensity end
        if spread then esp.Settings.GlowSpread = spread end
        if color then esp.Settings.GlowColor = color end
    end
end

return Library
