--[[
    ╔══════════════════════════════════════════╗
    ║   RobloxCollab Plugin v2.0               ║
    ║   Совместная работа в Roblox Studio      ║
    ║   Красивый UI с анимациями и звуками     ║
    ╚══════════════════════════════════════════╝
]]

local HttpService = game:GetService("HttpService")
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local Selection = game:GetService("Selection")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Terrain = workspace.Terrain

-- ============== КОНФИГУРАЦИЯ ==============

local DEFAULT_SERVER = "http://localhost:3000"
local POLL_INTERVAL = 0.3
local HEARTBEAT_INTERVAL = 8
local MAX_OPS_PER_BATCH = 80

-- ============== ЦВЕТА ТЕМЫ ==============

local Theme = {
    bg = Color3.fromRGB(18, 18, 24),
    bgSecondary = Color3.fromRGB(25, 25, 35),
    bgTertiary = Color3.fromRGB(32, 32, 45),
    card = Color3.fromRGB(28, 28, 40),
    cardHover = Color3.fromRGB(35, 35, 50),
    accent = Color3.fromRGB(88, 101, 242),      -- Discord-like blue
    accentHover = Color3.fromRGB(108, 121, 255),
    success = Color3.fromRGB(87, 242, 135),
    successDark = Color3.fromRGB(40, 167, 69),
    danger = Color3.fromRGB(237, 66, 69),
    dangerDark = Color3.fromRGB(180, 40, 40),
    warning = Color3.fromRGB(254, 231, 92),
    warningDark = Color3.fromRGB(200, 160, 0),
    orange = Color3.fromRGB(255, 163, 71),
    text = Color3.fromRGB(220, 221, 225),
    textMuted = Color3.fromRGB(148, 155, 164),
    textDark = Color3.fromRGB(96, 100, 108),
    border = Color3.fromRGB(47, 49, 54),
    inputBg = Color3.fromRGB(30, 31, 40),
    shadow = Color3.fromRGB(0, 0, 0),
    online = Color3.fromRGB(35, 165, 90),
    gradient1 = Color3.fromRGB(88, 101, 242),
    gradient2 = Color3.fromRGB(155, 89, 182),
}

-- ============== СОСТОЯНИЕ ==============

local state = {
    connected = false,
    serverUrl = DEFAULT_SERVER,
    roomId = nil,
    userId = nil,
    username = "Player",
    isHost = false,
    trackedInstances = {},
    instanceById = {},
    pendingOperations = {},
    ignoreChanges = false,
    pollConnection = nil,
    heartbeatConnection = nil,
    lastPollTime = 0,
    opsReceived = 0,
    opsSent = 0,
}

-- ============== СОЗДАНИЕ ПЛАГИНА ==============

local toolbar = plugin:CreateToolbar("🔗 Collab Tools")
local mainButton = toolbar:CreateButton(
    "CollabPlugin",
    "Открыть панель совместной работы",
    "rbxassetid://6031071053",
    "🔗 Collab"
)

-- ============== ЗВУКИ ==============

local Sounds = {}

local function playSound(soundType)
    -- В Studio нет нормального воспроизведения звуков через UI,
    -- но мы можем использовать SoundService
    pcall(function()
        local sound = Instance.new("Sound")
        sound.Parent = game:GetService("SoundService")
        
        if soundType == "connect" then
            sound.SoundId = "rbxassetid://6042053626"
            sound.Volume = 0.3
        elseif soundType == "disconnect" then
            sound.SoundId = "rbxassetid://6042053626"
            sound.Volume = 0.3
            sound.PlaybackSpeed = 0.7
        elseif soundType == "message" then
            sound.SoundId = "rbxassetid://6042053626"
            sound.Volume = 0.15
            sound.PlaybackSpeed = 1.5
        elseif soundType == "click" then
            sound.SoundId = "rbxassetid://6042053626"
            sound.Volume = 0.1
            sound.PlaybackSpeed = 2
        elseif soundType == "error" then
            sound.SoundId = "rbxassetid://6042053626"
            sound.Volume = 0.2
            sound.PlaybackSpeed = 0.5
        elseif soundType == "notification" then
            sound.SoundId = "rbxassetid://6042053626"
            sound.Volume = 0.2
            sound.PlaybackSpeed = 1.2
        end
        
        sound:Play()
        game:GetService("Debris"):AddItem(sound, 3)
    end)
end

-- ============== АНИМАЦИИ ==============

local TWEEN_INFO_FAST = TweenInfo.new(0.2, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
local TWEEN_INFO_MEDIUM = TweenInfo.new(0.35, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
local TWEEN_INFO_SLOW = TweenInfo.new(0.5, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
local TWEEN_INFO_BOUNCE = TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local TWEEN_INFO_ELASTIC = TweenInfo.new(0.6, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out)
local TWEEN_INFO_SPRING = TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0, false, 0)

local function animateIn(element, delay)
    delay = delay or 0
    local originalPos = element.Position
    local originalSize = element.Size
    
    element.Position = UDim2.new(
        originalPos.X.Scale, originalPos.X.Offset,
        originalPos.Y.Scale, originalPos.Y.Offset + 20
    )
    element.BackgroundTransparency = 1
    
    if element:IsA("TextLabel") or element:IsA("TextButton") or element:IsA("TextBox") then
        element.TextTransparency = 1
    end
    
    task.delay(delay, function()
        local tween1 = TweenService:Create(element, TWEEN_INFO_MEDIUM, {
            Position = originalPos,
            BackgroundTransparency = element:GetAttribute("TargetBgTransparency") or 0
        })
        tween1:Play()
        
        if element:IsA("TextLabel") or element:IsA("TextButton") or element:IsA("TextBox") then
            local tween2 = TweenService:Create(element, TWEEN_INFO_MEDIUM, {
                TextTransparency = 0
            })
            tween2:Play()
        end
    end)
end

local function animateScale(element, targetScale, tweenInfo)
    tweenInfo = tweenInfo or TWEEN_INFO_FAST
    local tween = TweenService:Create(element, tweenInfo, { Size = targetScale })
    tween:Play()
    return tween
end

local function animateColor(element, property, targetColor, tweenInfo)
    tweenInfo = tweenInfo or TWEEN_INFO_FAST
    local tween = TweenService:Create(element, tweenInfo, { [property] = targetColor })
    tween:Play()
    return tween
end

local function pulseAnimation(element)
    task.spawn(function()
        while element and element.Parent do
            local tween1 = TweenService:Create(element, TweenInfo.new(1, Enum.EasingStyle.Sine), {
                BackgroundTransparency = 0.3
            })
            tween1:Play()
            tween1.Completed:Wait()
            
            if not element or not element.Parent then break end
            
            local tween2 = TweenService:Create(element, TweenInfo.new(1, Enum.EasingStyle.Sine), {
                BackgroundTransparency = 0.6
            })
            tween2:Play()
            tween2.Completed:Wait()
        end
    end)
end

local function shakeAnimation(element)
    local originalPos = element.Position
    task.spawn(function()
        for i = 1, 3 do
            element.Position = UDim2.new(
                originalPos.X.Scale, originalPos.X.Offset + 4,
                originalPos.Y.Scale, originalPos.Y.Offset
            )
            task.wait(0.05)
            element.Position = UDim2.new(
                originalPos.X.Scale, originalPos.X.Offset - 4,
                originalPos.Y.Scale, originalPos.Y.Offset
            )
            task.wait(0.05)
        end
        element.Position = originalPos
    end)
end

local function rippleEffect(button, x, y)
    local ripple = Instance.new("Frame")
    ripple.Size = UDim2.new(0, 0, 0, 0)
    ripple.Position = UDim2.new(0, x - button.AbsolutePosition.X, 0, y - button.AbsolutePosition.Y)
    ripple.AnchorPoint = Vector2.new(0.5, 0.5)
    ripple.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    ripple.BackgroundTransparency = 0.7
    ripple.BorderSizePixel = 0
    ripple.ZIndex = button.ZIndex + 1
    ripple.Parent = button
    
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(1, 0)
    corner.Parent = ripple
    
    local maxSize = math.max(button.AbsoluteSize.X, button.AbsoluteSize.Y) * 2
    
    local tween = TweenService:Create(ripple, TweenInfo.new(0.5, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
        Size = UDim2.new(0, maxSize, 0, maxSize),
        BackgroundTransparency = 1
    })
    tween:Play()
    tween.Completed:Connect(function()
        ripple:Destroy()
    end)
end

local function typewriterEffect(label, text, speed)
    speed = speed or 0.02
    task.spawn(function()
        label.Text = ""
        for i = 1, #text do
            if not label or not label.Parent then break end
            label.Text = string.sub(text, 1, i)
            task.wait(speed)
        end
    end)
end

local function glowPulse(element)
    task.spawn(function()
        while element and element.Parent do
            local stroke = element:FindFirstChildOfClass("UIStroke")
            if stroke then
                TweenService:Create(stroke, TweenInfo.new(1.5, Enum.EasingStyle.Sine), {
                    Transparency = 0.3
                }):Play()
                task.wait(1.5)
                if not element or not element.Parent then break end
                TweenService:Create(stroke, TweenInfo.new(1.5, Enum.EasingStyle.Sine), {
                    Transparency = 0.8
                }):Play()
                task.wait(1.5)
            else
                break
            end
        end
    end)
end

-- ============== UI КОМПОНЕНТЫ ==============

local function addCorner(parent, radius)
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, radius or 8)
    corner.Parent = parent
    return corner
end

local function addStroke(parent, color, thickness, transparency)
    local stroke = Instance.new("UIStroke")
    stroke.Color = color or Theme.border
    stroke.Thickness = thickness or 1
    stroke.Transparency = transparency or 0
    stroke.Parent = parent
    return stroke
end

local function addPadding(parent, t, b, l, r)
    local padding = Instance.new("UIPadding")
    padding.PaddingTop = UDim.new(0, t or 8)
    padding.PaddingBottom = UDim.new(0, b or t or 8)
    padding.PaddingLeft = UDim.new(0, l or t or 8)
    padding.PaddingRight = UDim.new(0, r or l or t or 8)
    padding.Parent = parent
    return padding
end

local function addGradient(parent, color1, color2, rotation)
    local gradient = Instance.new("UIGradient")
    gradient.Color = ColorSequence.new(color1, color2)
    gradient.Rotation = rotation or 45
    gradient.Parent = parent
    return gradient
end

local function addShadow(parent)
    local shadow = Instance.new("ImageLabel")
    shadow.Size = UDim2.new(1, 12, 1, 12)
    shadow.Position = UDim2.new(0, -6, 0, -2)
    shadow.BackgroundTransparency = 1
    shadow.Image = "rbxassetid://5554236805"
    shadow.ImageColor3 = Color3.fromRGB(0, 0, 0)
    shadow.ImageTransparency = 0.6
    shadow.ScaleType = Enum.ScaleType.Slice
    shadow.SliceCenter = Rect.new(23, 23, 277, 277)
    shadow.ZIndex = parent.ZIndex - 1
    shadow.Parent = parent
    return shadow
end

local function createStyledButton(text, parent, order, color, icon)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 0, 40)
    btn.BackgroundColor3 = color or Theme.accent
    btn.BorderSizePixel = 0
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.TextSize = 14
    btn.Font = Enum.Font.GothamBold
    btn.Text = (icon or "") .. " " .. text
    btn.LayoutOrder = order or 0
    btn.AutoButtonColor = false
    btn.Parent = parent
    
    addCorner(btn, 8)
    
    local originalColor = color or Theme.accent
    local hoverColor = Color3.new(
        math.min(originalColor.R + 0.08, 1),
        math.min(originalColor.G + 0.08, 1),
        math.min(originalColor.B + 0.08, 1)
    )
    local pressColor = Color3.new(
        math.max(originalColor.R - 0.05, 0),
        math.max(originalColor.G - 0.05, 0),
        math.max(originalColor.B - 0.05, 0)
    )
    
    btn.MouseEnter:Connect(function()
        animateColor(btn, "BackgroundColor3", hoverColor)
        animateScale(btn, UDim2.new(1, 0, 0, 42), TWEEN_INFO_FAST)
    end)
    
    btn.MouseLeave:Connect(function()
        animateColor(btn, "BackgroundColor3", originalColor)
        animateScale(btn, UDim2.new(1, 0, 0, 40), TWEEN_INFO_FAST)
    end)
    
    btn.MouseButton1Down:Connect(function()
        animateColor(btn, "BackgroundColor3", pressColor)
        animateScale(btn, UDim2.new(1, 0, 0, 38), TWEEN_INFO_FAST)
    end)
    
    btn.MouseButton1Up:Connect(function()
        animateColor(btn, "BackgroundColor3", hoverColor)
        animateScale(btn, UDim2.new(1, 0, 0, 42), TWEEN_INFO_FAST)
    end)
    
    btn.MouseButton1Click:Connect(function()
        playSound("click")
    end)
    
    return btn
end

local function createStyledInput(placeholder, parent, order)
    local container = Instance.new("Frame")
    container.Size = UDim2.new(1, 0, 0, 38)
    container.BackgroundColor3 = Theme.inputBg
    container.BorderSizePixel = 0
    container.LayoutOrder = order or 0
    container.Parent = parent
    
    addCorner(container, 8)
    local stroke = addStroke(container, Theme.border, 1.5, 0.3)
    
    local input = Instance.new("TextBox")
    input.Size = UDim2.new(1, -16, 1, 0)
    input.Position = UDim2.new(0, 8, 0, 0)
    input.BackgroundTransparency = 1
    input.TextColor3 = Theme.text
    input.PlaceholderText = placeholder
    input.PlaceholderColor3 = Theme.textDark
    input.TextSize = 13
    input.Font = Enum.Font.Gotham
    input.ClearTextOnFocus = false
    input.TextXAlignment = Enum.TextXAlignment.Left
    input.Parent = container
    
    input.Focused:Connect(function()
        animateColor(stroke, "Color", Theme.accent, TWEEN_INFO_FAST)
        TweenService:Create(stroke, TWEEN_INFO_FAST, { Transparency = 0 }):Play()
    end)
    
    input.FocusLost:Connect(function()
        animateColor(stroke, "Color", Theme.border, TWEEN_INFO_FAST)
        TweenService:Create(stroke, TWEEN_INFO_FAST, { Transparency = 0.3 }):Play()
    end)
    
    return input, container
end

local function createSectionHeader(text, parent, order, icon)
    local header = Instance.new("TextLabel")
    header.Size = UDim2.new(1, 0, 0, 30)
    header.BackgroundTransparency = 1
    header.TextColor3 = Theme.textMuted
    header.TextSize = 12
    header.Font = Enum.Font.GothamBold
    header.Text = string.upper((icon or "") .. " " .. text)
    header.TextXAlignment = Enum.TextXAlignment.Left
    header.LayoutOrder = order or 0
    header.Parent = parent
    return header
end

local function createCard(parent, order, height)
    local card = Instance.new("Frame")
    card.Size = UDim2.new(1, 0, 0, height or 0)
    card.AutomaticSize = height == nil and Enum.AutomaticSize.Y or Enum.AutomaticSize.None
    card.BackgroundColor3 = Theme.card
    card.BorderSizePixel = 0
    card.LayoutOrder = order or 0
    card.Parent = parent
    
    addCorner(card, 10)
    addStroke(card, Theme.border, 1, 0.5)
    addPadding(card, 12)
    
    local layout = Instance.new("UIListLayout")
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Padding = UDim.new(0, 6)
    layout.Parent = card
    
    return card
end

local function createSpacer(parent, order, height)
    local spacer = Instance.new("Frame")
    spacer.Size = UDim2.new(1, 0, 0, height or 8)
    spacer.BackgroundTransparency = 1
    spacer.LayoutOrder = order or 0
    spacer.Parent = parent
    return spacer
end

local function createStatusDot(parent, online)
    local dot = Instance.new("Frame")
    dot.Size = UDim2.new(0, 10, 0, 10)
    dot.BackgroundColor3 = online and Theme.online or Theme.danger
    dot.BorderSizePixel = 0
    dot.Parent = parent
    
    addCorner(dot, 5)
    
    if online then
        pulseAnimation(dot)
    end
    
    return dot
end

-- ============== ГЛАВНЫЙ UI ==============

local function createWidget()
    local widgetInfo = DockWidgetPluginGuiInfo.new(
        Enum.InitialDockState.Right,
        false, false, 380, 700, 320, 500
    )
    
    local widget = plugin:CreateDockWidgetPluginGui("CollabWidgetV2", widgetInfo)
    widget.Title = "🔗 RobloxCollab"
    state.widget = widget
    
    -- Основной скроллинг
    local scrollFrame = Instance.new("ScrollingFrame")
    scrollFrame.Size = UDim2.new(1, 0, 1, 0)
    scrollFrame.BackgroundColor3 = Theme.bg
    scrollFrame.BorderSizePixel = 0
    scrollFrame.ScrollBarThickness = 4
    scrollFrame.ScrollBarImageColor3 = Theme.textDark
    scrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
    scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
    scrollFrame.Parent = widget
    
    local mainLayout = Instance.new("UIListLayout")
    mainLayout.SortOrder = Enum.SortOrder.LayoutOrder
    mainLayout.Padding = UDim.new(0, 6)
    mainLayout.Parent = scrollFrame
    
    addPadding(scrollFrame, 12, 12, 12, 12)
    
    -- ══════════ HEADER ══════════
    
    local headerFrame = Instance.new("Frame")
    headerFrame.Size = UDim2.new(1, 0, 0, 70)
    headerFrame.BackgroundColor3 = Theme.accent
    headerFrame.BorderSizePixel = 0
    headerFrame.LayoutOrder = 1
    headerFrame.Parent = scrollFrame
    
    addCorner(headerFrame, 12)
    addGradient(headerFrame, Theme.gradient1, Theme.gradient2, 135)
    
    local headerTitle = Instance.new("TextLabel")
    headerTitle.Size = UDim2.new(1, 0, 0, 30)
    headerTitle.Position = UDim2.new(0, 15, 0, 12)
    headerTitle.BackgroundTransparency = 1
    headerTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
    headerTitle.TextSize = 20
    headerTitle.Font = Enum.Font.GothamBlack
    headerTitle.Text = "🔗 RobloxCollab"
    headerTitle.TextXAlignment = Enum.TextXAlignment.Left
    headerTitle.Parent = headerFrame
    
    local headerSub = Instance.new("TextLabel")
    headerSub.Size = UDim2.new(1, 0, 0, 18)
    headerSub.Position = UDim2.new(0, 15, 0, 42)
    headerSub.BackgroundTransparency = 1
    headerSub.TextColor3 = Color3.new(1, 1, 1)
    headerSub.TextTransparency = 0.3
    headerSub.TextSize = 12
    headerSub.Font = Enum.Font.Gotham
    headerSub.Text = "Совместная работа в Studio"
    headerSub.TextXAlignment = Enum.TextXAlignment.Left
    headerSub.Parent = headerFrame
    
    -- ══════════ STATUS BAR ══════════
    
    local statusCard = createCard(scrollFrame, 2)
    
    local statusRow = Instance.new("Frame")
    statusRow.Size = UDim2.new(1, 0, 0, 20)
    statusRow.BackgroundTransparency = 1
    statusRow.LayoutOrder = 1
    statusRow.Parent = statusCard
    
    local statusDot = Instance.new("Frame")
    statusDot.Size = UDim2.new(0, 10, 0, 10)
    statusDot.Position = UDim2.new(0, 0, 0, 5)
    statusDot.BackgroundColor3 = Theme.danger
    statusDot.BorderSizePixel = 0
    statusDot.Parent = statusRow
    addCorner(statusDot, 5)
    
    local statusLabel = Instance.new("TextLabel")
    statusLabel.Size = UDim2.new(1, -18, 1, 0)
    statusLabel.Position = UDim2.new(0, 18, 0, 0)
    statusLabel.BackgroundTransparency = 1
    statusLabel.TextColor3 = Theme.danger
    statusLabel.TextSize = 13
    statusLabel.Font = Enum.Font.GothamBold
    statusLabel.Text = "Отключено"
    statusLabel.TextXAlignment = Enum.TextXAlignment.Left
    statusLabel.Parent = statusRow
    state.statusLabel = statusLabel
    state.statusDot = statusDot
    
    local statsLabel = Instance.new("TextLabel")
    statsLabel.Size = UDim2.new(1, 0, 0, 16)
    statsLabel.BackgroundTransparency = 1
    statsLabel.TextColor3 = Theme.textDark
    statsLabel.TextSize = 11
    statsLabel.Font = Enum.Font.Gotham
    statsLabel.Text = ""
    statsLabel.TextXAlignment = Enum.TextXAlignment.Left
    statsLabel.LayoutOrder = 2
    statsLabel.Parent = statusCard
    state.statsLabel = statsLabel
    
    -- ══════════ CONNECTION SETTINGS ══════════
    
    local settingsCard = createCard(scrollFrame, 3)
    
    createSectionHeader("Настройки подключения", settingsCard, 1, "⚙️")
    
    local serverLabel = Instance.new("TextLabel")
    serverLabel.Size = UDim2.new(1, 0, 0, 16)
    serverLabel.BackgroundTransparency = 1
    serverLabel.TextColor3 = Theme.textMuted
    serverLabel.TextSize = 11
    serverLabel.Font = Enum.Font.Gotham
    serverLabel.Text = "URL сервера"
    serverLabel.TextXAlignment = Enum.TextXAlignment.Left
    serverLabel.LayoutOrder = 2
    serverLabel.Parent = settingsCard
    
    local serverInput = createStyledInput("http://localhost:3000", settingsCard, 3)
    serverInput.Text = DEFAULT_SERVER
    
    local usernameLabel = Instance.new("TextLabel")
    usernameLabel.Size = UDim2.new(1, 0, 0, 16)
    usernameLabel.BackgroundTransparency = 1
    usernameLabel.TextColor3 = Theme.textMuted
    usernameLabel.TextSize = 11
    usernameLabel.Font = Enum.Font.Gotham
    usernameLabel.Text = "Ваше имя"
    usernameLabel.TextXAlignment = Enum.TextXAlignment.Left
    usernameLabel.LayoutOrder = 4
    usernameLabel.Parent = settingsCard
    
    local usernameInput = createStyledInput("Введите имя...", settingsCard, 5)
    usernameInput.Text = "Player_" .. math.random(1000, 9999)
    
    -- ══════════ CREATE ROOM ══════════
    
    local createCard2 = createCard(scrollFrame, 4)
    
    createSectionHeader("Создать комнату", createCard2, 1, "🏠")
    
    local roomNameLabel = Instance.new("TextLabel")
    roomNameLabel.Size = UDim2.new(1, 0, 0, 16)
    roomNameLabel.BackgroundTransparency = 1
    roomNameLabel.TextColor3 = Theme.textMuted
    roomNameLabel.TextSize = 11
    roomNameLabel.Font = Enum.Font.Gotham
    roomNameLabel.Text = "Название комнаты"
    roomNameLabel.TextXAlignment = Enum.TextXAlignment.Left
    roomNameLabel.LayoutOrder = 2
    roomNameLabel.Parent = createCard2
    
    local roomNameInput = createStyledInput("Моя комната", createCard2, 3)
    
    local roomPwLabel = Instance.new("TextLabel")
    roomPwLabel.Size = UDim2.new(1, 0, 0, 16)
    roomPwLabel.BackgroundTransparency = 1
    roomPwLabel.TextColor3 = Theme.textMuted
    roomPwLabel.TextSize = 11
    roomPwLabel.Font = Enum.Font.Gotham
    roomPwLabel.Text = "Пароль (необязательно)"
    roomPwLabel.TextXAlignment = Enum.TextXAlignment.Left
    roomPwLabel.LayoutOrder = 4
    roomPwLabel.Parent = createCard2
    
    local roomPasswordInput = createStyledInput("Пароль...", createCard2, 5)
    
    local createRoomBtn = createStyledButton("Создать комнату", createCard2, 6, Theme.successDark, "🏠")
    
    -- ══════════ JOIN ROOM ══════════
    
    local joinCard = createCard(scrollFrame, 5)
    
    createSectionHeader("Присоединиться", joinCard, 1, "🚪")
    
    local joinIdLabel = Instance.new("TextLabel")
    joinIdLabel.Size = UDim2.new(1, 0, 0, 16)
    joinIdLabel.BackgroundTransparency = 1
    joinIdLabel.TextColor3 = Theme.textMuted
    joinIdLabel.TextSize = 11
    joinIdLabel.Font = Enum.Font.Gotham
    joinIdLabel.Text = "Код комнаты"
    joinIdLabel.TextXAlignment = Enum.TextXAlignment.Left
    joinIdLabel.LayoutOrder = 2
    joinIdLabel.Parent = joinCard
    
    local joinRoomIdInput = createStyledInput("Например: AB12CD34", joinCard, 3)
    
    local joinPwLabel = Instance.new("TextLabel")
    joinPwLabel.Size = UDim2.new(1, 0, 0, 16)
    joinPwLabel.BackgroundTransparency = 1
    joinPwLabel.TextColor3 = Theme.textMuted
    joinPwLabel.TextSize = 11
    joinPwLabel.Font = Enum.Font.Gotham
    joinPwLabel.Text = "Пароль (если есть)"
    joinPwLabel.TextXAlignment = Enum.TextXAlignment.Left
    joinPwLabel.LayoutOrder = 4
    joinPwLabel.Parent = joinCard
    
    local joinPasswordInput = createStyledInput("Пароль...", joinCard, 5)
    
    local joinRoomBtn = createStyledButton("Присоединиться", joinCard, 6, Theme.accent, "🚪")
    
    -- ══════════ CONNECTED PANEL (hidden by default) ══════════
    
    local connectedCard = createCard(scrollFrame, 6)
    connectedCard.Visible = false
    
    local roomInfoLabel = Instance.new("TextLabel")
    roomInfoLabel.Size = UDim2.new(1, 0, 0, 22)
    roomInfoLabel.BackgroundTransparency = 1
    roomInfoLabel.TextColor3 = Theme.text
    roomInfoLabel.TextSize = 16
    roomInfoLabel.Font = Enum.Font.GothamBlack
    roomInfoLabel.Text = "Комната: ---"
    roomInfoLabel.TextXAlignment = Enum.TextXAlignment.Left
    roomInfoLabel.LayoutOrder = 1
    roomInfoLabel.Parent = connectedCard
    
    -- Room ID (копируемый)
    local roomIdDisplay = Instance.new("TextButton")
    roomIdDisplay.Size = UDim2.new(1, 0, 0, 36)
    roomIdDisplay.BackgroundColor3 = Theme.bgSecondary
    roomIdDisplay.BorderSizePixel = 0
    roomIdDisplay.TextColor3 = Theme.accent
    roomIdDisplay.TextSize = 18
    roomIdDisplay.Font = Enum.Font.Code
    roomIdDisplay.Text = "AB12CD34"
    roomIdDisplay.LayoutOrder = 2
    roomIdDisplay.AutoButtonColor = false
    roomIdDisplay.Parent = connectedCard
    addCorner(roomIdDisplay, 6)
    addStroke(roomIdDisplay, Theme.accent, 1, 0.5)
    
    local copyHint = Instance.new("TextLabel")
    copyHint.Size = UDim2.new(1, 0, 0, 14)
    copyHint.BackgroundTransparency = 1
    copyHint.TextColor3 = Theme.textDark
    copyHint.TextSize = 10
    copyHint.Font = Enum.Font.Gotham
    copyHint.Text = "Нажми чтобы скопировать код"
    copyHint.TextXAlignment = Enum.TextXAlignment.Center
    copyHint.LayoutOrder = 3
    copyHint.Parent = connectedCard
    
    roomIdDisplay.MouseButton1Click:Connect(function()
        -- В Studio нельзя напрямую копировать в буфер, но покажем анимацию
        playSound("click")
        local originalText = roomIdDisplay.Text
        roomIdDisplay.Text = "✅ Скопировано!"
        roomIdDisplay.TextColor3 = Theme.success
        task.delay(1.5, function()
            if roomIdDisplay and roomIdDisplay.Parent then
                roomIdDisplay.Text = originalText
                roomIdDisplay.TextColor3 = Theme.accent
            end
        end)
    end)
    
    createSpacer(connectedCard, 4, 4)
    
    -- Users list
    state.usersLabel = Instance.new("TextLabel")
    state.usersLabel.Size = UDim2.new(1, 0, 0, 20)
    state.usersLabel.BackgroundTransparency = 1
    state.usersLabel.TextColor3 = Theme.textMuted
    state.usersLabel.TextSize = 12
    state.usersLabel.Font = Enum.Font.Gotham
    state.usersLabel.Text = "👥 Участники: ---"
    state.usersLabel.TextXAlignment = Enum.TextXAlignment.Left
    state.usersLabel.TextWrapped = true
    state.usersLabel.AutomaticSize = Enum.AutomaticSize.Y
    state.usersLabel.LayoutOrder = 5
    state.usersLabel.Parent = connectedCard
    
    createSpacer(connectedCard, 6, 6)
    
    -- Action Buttons
    local syncBtn = createStyledButton("Загрузить сцену на сервер", connectedCard, 7, Theme.warningDark, "📤")
    local downloadBtn = createStyledButton("Скачать сцену с сервера", connectedCard, 8, Color3.fromRGB(70, 80, 140), "📥")
    
    createSpacer(connectedCard, 9, 4)
    
    local terrainUpBtn = createStyledButton("Загрузить Terrain", connectedCard, 10, Color3.fromRGB(60, 120, 80), "🏔️")
    local terrainDownBtn = createStyledButton("Скачать Terrain", connectedCard, 11, Color3.fromRGB(80, 100, 60), "⬇️")
    
    createSpacer(connectedCard, 12, 4)
    
    local disconnectBtn = createStyledButton("Отключиться", connectedCard, 13, Theme.dangerDark, "❌")
    
    -- ══════════ CHAT ══════════
    
    local chatCard = createCard(scrollFrame, 7)
    chatCard.Visible = false
    
    createSectionHeader("Чат", chatCard, 1, "💬")
    
    local chatScroll = Instance.new("ScrollingFrame")
    chatScroll.Size = UDim2.new(1, 0, 0, 180)
    chatScroll.BackgroundColor3 = Theme.bg
    chatScroll.BorderSizePixel = 0
    chatScroll.ScrollBarThickness = 3
    chatScroll.ScrollBarImageColor3 = Theme.textDark
    chatScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    chatScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    chatScroll.LayoutOrder = 2
    chatScroll.Parent = chatCard
    addCorner(chatScroll, 6)
    state.chatFrame = chatScroll
    
    local chatListLayout = Instance.new("UIListLayout")
    chatListLayout.SortOrder = Enum.SortOrder.LayoutOrder
    chatListLayout.Padding = UDim.new(0, 3)
    chatListLayout.Parent = chatScroll
    
    addPadding(chatScroll, 6, 6, 8, 8)
    
    createSpacer(chatCard, 3, 4)
    
    -- Chat input row
    local chatInputRow = Instance.new("Frame")
    chatInputRow.Size = UDim2.new(1, 0, 0, 38)
    chatInputRow.BackgroundTransparency = 1
    chatInputRow.LayoutOrder = 4
    chatInputRow.Parent = chatCard
    
    local chatInput, chatInputContainer = createStyledInput("Сообщение...", chatInputRow, 0)
    chatInputContainer.Size = UDim2.new(1, -50, 0, 38)
    state.chatInput = chatInput
    
    local chatSendBtn = Instance.new("TextButton")
    chatSendBtn.Size = UDim2.new(0, 44, 0, 38)
    chatSendBtn.Position = UDim2.new(1, -44, 0, 0)
    chatSendBtn.BackgroundColor3 = Theme.accent
    chatSendBtn.BorderSizePixel = 0
    chatSendBtn.TextColor3 = Color3.new(1, 1, 1)
    chatSendBtn.TextSize = 18
    chatSendBtn.Font = Enum.Font.GothamBold
    chatSendBtn.Text = "➤"
    chatSendBtn.AutoButtonColor = false
    chatSendBtn.Parent = chatInputRow
    addCorner(chatSendBtn, 8)
    
    chatSendBtn.MouseEnter:Connect(function()
        animateColor(chatSendBtn, "BackgroundColor3", Theme.accentHover)
    end)
    chatSendBtn.MouseLeave:Connect(function()
        animateColor(chatSendBtn, "BackgroundColor3", Theme.accent)
    end)
    
    -- ══════════ NOTIFICATION TOAST ══════════
    
    local toastFrame = Instance.new("Frame")
    toastFrame.Size = UDim2.new(1, -24, 0, 44)
    toastFrame.Position = UDim2.new(0, 12, 0, -60)
    toastFrame.BackgroundColor3 = Theme.card
    toastFrame.BorderSizePixel = 0
    toastFrame.ZIndex = 100
    toastFrame.Parent = widget
    addCorner(toastFrame, 10)
    addStroke(toastFrame, Theme.accent, 1, 0.3)
    
    local toastLabel = Instance.new("TextLabel")
    toastLabel.Size = UDim2.new(1, -20, 1, 0)
    toastLabel.Position = UDim2.new(0, 10, 0, 0)
    toastLabel.BackgroundTransparency = 1
    toastLabel.TextColor3 = Theme.text
    toastLabel.TextSize = 12
    toastLabel.Font = Enum.Font.GothamBold
    toastLabel.Text = ""
    toastLabel.TextXAlignment = Enum.TextXAlignment.Left
    toastLabel.ZIndex = 101
    toastLabel.Parent = toastFrame
    
    local function showToast(text, color, duration)
        toastLabel.Text = text
        if color then
            local stroke = toastFrame:FindFirstChildOfClass("UIStroke")
            if stroke then stroke.Color = color end
        end
        
        local tweenIn = TweenService:Create(toastFrame, TWEEN_INFO_BOUNCE, {
            Position = UDim2.new(0, 12, 0, 12)
        })
        tweenIn:Play()
        playSound("notification")
        
        task.delay(duration or 3, function()
            local tweenOut = TweenService:Create(toastFrame, TWEEN_INFO_FAST, {
                Position = UDim2.new(0, 12, 0, -60)
            })
            tweenOut:Play()
        end)
    end
    
    -- ══════════ ОБРАБОТЧИКИ СОБЫТИЙ ══════════
    
    local function setConnectedUI(connected, roomId, roomName)
        -- Анимация переключения
        if connected then
            -- Скрываем настройки
            TweenService:Create(settingsCard, TWEEN_INFO_FAST, { BackgroundTransparency = 1 }):Play()
            TweenService:Create(createCard2, TWEEN_INFO_FAST, { BackgroundTransparency = 1 }):Play()
            TweenService:Create(joinCard, TWEEN_INFO_FAST, { BackgroundTransparency = 1 }):Play()
            
            task.delay(0.2, function()
                settingsCard.Visible = false
                createCard2.Visible = false
                joinCard.Visible = false
                
                connectedCard.Visible = true
                chatCard.Visible = true
                
                connectedCard.BackgroundTransparency = 1
                chatCard.BackgroundTransparency = 1
                
                roomInfoLabel.Text = "🏠 " .. (roomName or roomId)
                roomIdDisplay.Text = roomId
                
                TweenService:Create(connectedCard, TWEEN_INFO_MEDIUM, { BackgroundTransparency = 0 }):Play()
                task.delay(0.1, function()
                    TweenService:Create(chatCard, TWEEN_INFO_MEDIUM, { BackgroundTransparency = 0 }):Play()
                end)
            end)
            
            state.statusLabel.Text = "Подключено"
            state.statusLabel.TextColor3 = Theme.success
            state.statusDot.BackgroundColor3 = Theme.online
            pulseAnimation(state.statusDot)
            
        else
            TweenService:Create(connectedCard, TWEEN_INFO_FAST, { BackgroundTransparency = 1 }):Play()
            TweenService:Create(chatCard, TWEEN_INFO_FAST, { BackgroundTransparency = 1 }):Play()
            
            task.delay(0.2, function()
                connectedCard.Visible = false
                chatCard.Visible = false
                
                settingsCard.Visible = true
                createCard2.Visible = true
                joinCard.Visible = true
                
                settingsCard.BackgroundTransparency = 1
                createCard2.BackgroundTransparency = 1
                joinCard.BackgroundTransparency = 1
                
                TweenService:Create(settingsCard, TWEEN_INFO_MEDIUM, { BackgroundTransparency = 0 }):Play()
                task.delay(0.08, function()
                    TweenService:Create(createCard2, TWEEN_INFO_MEDIUM, { BackgroundTransparency = 0 }):Play()
                end)
                task.delay(0.16, function()
                    TweenService:Create(joinCard, TWEEN_INFO_MEDIUM, { BackgroundTransparency = 0 }):Play()
                end)
            end)
            
            state.statusLabel.Text = "Отключено"
            state.statusLabel.TextColor3 = Theme.danger
            state.statusDot.BackgroundColor3 = Theme.danger
            state.statsLabel.Text = ""
        end
    end
    
    -- CREATE ROOM
    createRoomBtn.MouseButton1Click:Connect(function()
        state.serverUrl = serverInput.Text
        state.username = usernameInput.Text
        
        createRoomBtn.Text = "⏳ Создаём..."
        
        local success, result = pcall(function()
            return HttpService:RequestAsync({
                Url = state.serverUrl .. "/api/rooms/create",
                Method = "POST",
                Headers = { ["Content-Type"] = "application/json" },
                Body = HttpService:JSONEncode({
                    roomName = roomNameInput.Text ~= "" and roomNameInput.Text or "Моя комната",
                    password = roomPasswordInput.Text ~= "" and roomPasswordInput.Text or nil,
                    username = state.username
                })
            })
        end)
        
        if success and result.StatusCode == 200 then
            local data = HttpService:JSONDecode(result.Body)
            state.roomId = data.roomId
            state.userId = data.userId
            state.isHost = true
            state.connected = true
            
            playSound("connect")
            setConnectedUI(true, data.roomId, roomNameInput.Text)
            showToast("✅ Комната создана! Код: " .. data.roomId, Theme.success)
            
            startSync()
            startTracking()
            
            warn("[Collab] Room created: " .. data.roomId)
        else
            playSound("error")
            shakeAnimation(createRoomBtn.Parent)
            showToast("❌ Ошибка создания комнаты", Theme.danger)
        end
        
        createRoomBtn.Text = "🏠 Создать комнату"
    end)
    
    -- JOIN ROOM
    joinRoomBtn.MouseButton1Click:Connect(function()
        state.serverUrl = serverInput.Text
        state.username = usernameInput.Text
        
        if joinRoomIdInput.Text == "" then
            shakeAnimation(joinRoomIdInput.Parent)
            showToast("⚠️ Введите код комнаты", Theme.warning)
            return
        end
        
        joinRoomBtn.Text = "⏳ Подключаемся..."
        
        local success, result = pcall(function()
            return HttpService:RequestAsync({
                Url = state.serverUrl .. "/api/rooms/join",
                Method = "POST",
                Headers = { ["Content-Type"] = "application/json" },
                Body = HttpService:JSONEncode({
                    roomId = joinRoomIdInput.Text,
                    password = joinPasswordInput.Text ~= "" and joinPasswordInput.Text or nil,
                    username = state.username
                })
            })
        end)
        
        if success and result.StatusCode == 200 then
            local data = HttpService:JSONDecode(result.Body)
            state.roomId = data.roomId
            state.userId = data.userId
            state.isHost = false
            state.connected = true
            
            playSound("connect")
            setConnectedUI(true, data.roomId, data.roomName)
            showToast("✅ Вы присоединились к " .. data.roomName, Theme.success)
            
            startSync()
            startTracking()
        else
            playSound("error")
            shakeAnimation(joinRoomBtn.Parent)
            local errMsg = "Ошибка"
            if result and result.Body then
                pcall(function() errMsg = HttpService:JSONDecode(result.Body).error or errMsg end)
            end
            showToast("❌ " .. errMsg, Theme.danger)
        end
        
        joinRoomBtn.Text = "🚪 Присоединиться"
    end)
    
    -- DISCONNECT
    disconnectBtn.MouseButton1Click:Connect(function()
        playSound("disconnect")
        disconnect()
        setConnectedUI(false)
        showToast("👋 Вы отключились", Theme.textMuted)
    end)
    
    -- UPLOAD SNAPSHOT
    syncBtn.MouseButton1Click:Connect(function()
        syncBtn.Text = "⏳ Загрузка..."
        task.defer(function()
            uploadSnapshot()
            syncBtn.Text = "📤 Загрузить сцену на сервер"
            showToast("📤 Сцена загружена на сервер!", Theme.success)
        end)
    end)
    
    -- DOWNLOAD SNAPSHOT
    downloadBtn.MouseButton1Click:Connect(function()
        downloadBtn.Text = "⏳ Скачивание..."
        task.defer(function()
            downloadSnapshot()
            downloadBtn.Text = "📥 Скачать сцену с сервера"
            showToast("📥 Сцена загружена!", Theme.success)
        end)
    end)
    
    -- TERRAIN UPLOAD
    terrainUpBtn.MouseButton1Click:Connect(function()
        terrainUpBtn.Text = "⏳ Загрузка terrain..."
        task.defer(function()
            uploadTerrain()
            terrainUpBtn.Text = "🏔️ Загрузить Terrain"
            showToast("🏔️ Terrain загружен!", Theme.success)
        end)
    end)
    
    -- TERRAIN DOWNLOAD
    terrainDownBtn.MouseButton1Click:Connect(function()
        terrainDownBtn.Text = "⏳ Скачивание terrain..."
        task.defer(function()
            downloadTerrain()
            terrainDownBtn.Text = "⬇️ Скачать Terrain"
            showToast("🏔️ Terrain загружен!", Theme.success)
        end)
    end)
    
    -- CHAT SEND
    local function doSendChat()
        if state.chatInput.Text ~= "" and state.connected then
            sendChat(state.chatInput.Text)
            state.chatInput.Text = ""
        end
    end
    
    chatSendBtn.MouseButton1Click:Connect(function()
        playSound("message")
        doSendChat()
    end)
    
    state.chatInput.FocusLost:Connect(function(enterPressed)
        if enterPressed then
            playSound("message")
            doSendChat()
        end
    end)
    
    -- Анимация появления карточек при открытии
    task.defer(function()
        task.wait(0.1)
        for _, child in ipairs(scrollFrame:GetChildren()) do
            if child:IsA("Frame") and child.LayoutOrder > 0 then
                animateIn(child, child.LayoutOrder * 0.06)
            end
        end
    end)
    
    state.showToast = showToast
    
    return widget
end

-- ============== СЕРИАЛИЗАЦИЯ ==============

local SERIALIZABLE_PROPERTIES = {
    BasePart = {"Name","Position","Size","Orientation","Color","Material","Transparency","Anchored","CanCollide","CastShadow","Reflectance"},
    Part = {"Name","Position","Size","Orientation","Color","Material","Transparency","Anchored","CanCollide","CastShadow","Reflectance","Shape"},
    MeshPart = {"Name","Position","Size","Orientation","Color","Material","Transparency","Anchored","CanCollide","MeshId","TextureID"},
    SpawnLocation = {"Name","Position","Size","Orientation","Color","Material","Transparency","Anchored","CanCollide","Duration","Enabled","Neutral","TeamColor"},
    Model = {"Name","PrimaryPart"},
    Folder = {"Name"},
    Script = {"Name","Source","Disabled"},
    LocalScript = {"Name","Source","Disabled"},
    ModuleScript = {"Name","Source"},
    StringValue = {"Name","Value"},IntValue = {"Name","Value"},NumberValue = {"Name","Value"},
    BoolValue = {"Name","Value"},ObjectValue = {"Name"},Color3Value = {"Name","Value"},
    Vector3Value = {"Name","Value"},CFrameValue = {"Name","Value"},
    PointLight = {"Name","Brightness","Color","Range","Shadows","Enabled"},
    SpotLight = {"Name","Brightness","Color","Range","Shadows","Enabled","Angle","Face"},
    SurfaceLight = {"Name","Brightness","Color","Range","Shadows","Enabled","Angle","Face"},
    Decal = {"Name","Texture","Transparency","Face","Color3"},
    Texture = {"Name","Texture","Transparency","Face","StudsPerTileU","StudsPerTileV"},
    SurfaceGui = {"Name","Enabled","Face"},
    BillboardGui = {"Name","Enabled","Size","StudsOffset"},
    TextLabel = {"Name","Text","TextColor3","TextSize","BackgroundColor3","Size","Position","BackgroundTransparency","TextWrapped","Font"},
    TextButton = {"Name","Text","TextColor3","TextSize","BackgroundColor3","Size","Position","BackgroundTransparency"},
    Frame = {"Name","BackgroundColor3","Size","Position","BackgroundTransparency"},
    ImageLabel = {"Name","Image","Size","Position","ImageColor3"},
    ScrollingFrame = {"Name","Size","Position","CanvasSize","ScrollBarThickness"},
    Sound = {"Name","SoundId","Volume","Looped","PlaybackSpeed"},
    ParticleEmitter = {"Name","Texture","Rate","Lifetime","Speed","Enabled","Color","Size"},
    Beam = {"Name","Enabled","Width0","Width1","Color","Texture"},
    Trail = {"Name","Enabled","Lifetime","Color","WidthScale"},
    Attachment = {"Name","Position","Orientation"},
    WeldConstraint = {"Name"},Weld = {"Name"},
    Motor6D = {"Name"},
    Camera = {"Name","FieldOfView","CameraType"},
    RemoteEvent = {"Name"},RemoteFunction = {"Name"},
    BindableEvent = {"Name"},BindableFunction = {"Name"},
    UnionOperation = {"Name","Position","Size","Orientation","Color","Material","Transparency","Anchored","CanCollide"},
    NegateOperation = {"Name","Position","Size","Orientation","Color","Material","Transparency","Anchored","CanCollide"},
    TrussPart = {"Name","Position","Size","Orientation","Color","Material","Transparency","Anchored","CanCollide"},
    WedgePart = {"Name","Position","Size","Orientation","Color","Material","Transparency","Anchored","CanCollide"},
    CornerWedgePart = {"Name","Position","Size","Orientation","Color","Material","Transparency","Anchored","CanCollide"},
    Seat = {"Name","Position","Size","Orientation","Color","Material","Transparency","Anchored","CanCollide"},
    VehicleSeat = {"Name","Position","Size","Orientation","Color","Material","Transparency","Anchored","CanCollide","MaxSpeed","Torque"},
    Humanoid = {"Name","Health","MaxHealth","WalkSpeed","JumpPower","JumpHeight","HipHeight"},
    UICorner = {"Name","CornerRadius"},
    UIStroke = {"Name","Color","Thickness","Transparency"},
    UIPadding = {"Name","PaddingTop","PaddingBottom","PaddingLeft","PaddingRight"},
    UIListLayout = {"Name","SortOrder","Padding","FillDirection","HorizontalAlignment","VerticalAlignment"},
    UIGridLayout = {"Name","CellSize","CellPadding","SortOrder"},
    UIAspectRatioConstraint = {"Name","AspectRatio"},
    UISizeConstraint = {"Name","MinSize","MaxSize"},
    UIScale = {"Name","Scale"},
    UIGradient = {"Name","Color","Rotation","Transparency"},
    Atmosphere = {"Name","Density","Offset","Color","Decay","Glare","Haze"},
    Sky = {"Name","SkyboxBk","SkyboxDn","SkyboxFt","SkyboxLf","SkyboxRt","SkyboxUp","SunAngularSize","MoonAngularSize"},
    Lighting = {},
    ScreenGui = {"Name","Enabled","IgnoreGuiInset","ZIndexBehavior"},
    SurfaceAppearance = {"Name","ColorMap","NormalMap","MetalnessMap","RoughnessMap"},
    Highlight = {"Name","FillColor","FillTransparency","OutlineColor","OutlineTransparency","Enabled"},
    ProximityPrompt = {"Name","ActionText","HoldDuration","MaxActivationDistance","ObjectText","RequiresLineOfSight"},
}

local function serializeValue(value)
    local t = typeof(value)
    if t == "string" or t == "number" or t == "boolean" then
        return {type=t, value=value}
    elseif t == "Vector3" then
        return {type="Vector3", value={value.X, value.Y, value.Z}}
    elseif t == "CFrame" then
        return {type="CFrame", value={value:GetComponents()}}
    elseif t == "Color3" then
        return {type="Color3", value={value.R, value.G, value.B}}
    elseif t == "BrickColor" then
        return {type="BrickColor", value=value.Name}
    elseif t == "UDim2" then
        return {type="UDim2", value={value.X.Scale, value.X.Offset, value.Y.Scale, value.Y.Offset}}
    elseif t == "UDim" then
        return {type="UDim", value={value.Scale, value.Offset}}
    elseif t == "Vector2" then
        return {type="Vector2", value={value.X, value.Y}}
    elseif t == "EnumItem" then
        return {type="EnumItem", value=tostring(value)}
    elseif t == "NumberRange" then
        return {type="NumberRange", value={value.Min, value.Max}}
    elseif t == "NumberSequence" then
        local kps = {}
        for _, kp in ipairs(value.Keypoints) do table.insert(kps, {kp.Time, kp.Value, kp.Envelope}) end
        return {type="NumberSequence", value=kps}
    elseif t == "ColorSequence" then
        local kps = {}
        for _, kp in ipairs(value.Keypoints) do table.insert(kps, {kp.Time, kp.Value.R, kp.Value.G, kp.Value.B}) end
        return {type="ColorSequence", value=kps}
    elseif t == "Rect" then
        return {type="Rect", value={value.Min.X, value.Min.Y, value.Max.X, value.Max.Y}}
    elseif t == "Font" then
        return {type="EnumItem", value=tostring(value)}
    else
        return {type="string", value=tostring(value)}
    end
end

local function deserializeValue(data)
    if not data or not data.type then return nil end
    local t, v = data.type, data.value
    if t == "string" then return v
    elseif t == "number" then return tonumber(v)
    elseif t == "boolean" then return v
    elseif t == "Vector3" then return Vector3.new(v[1],v[2],v[3])
    elseif t == "CFrame" then return CFrame.new(unpack(v))
    elseif t == "Color3" then return Color3.new(v[1],v[2],v[3])
    elseif t == "BrickColor" then return BrickColor.new(v)
    elseif t == "UDim2" then return UDim2.new(v[1],v[2],v[3],v[4])
    elseif t == "UDim" then return UDim.new(v[1],v[2])
    elseif t == "Vector2" then return Vector2.new(v[1],v[2])
    elseif t == "EnumItem" then
        local parts = string.split(v, ".")
        if #parts == 3 then
            local ok, result = pcall(function() return Enum[parts[2]][parts[3]] end)
            if ok then return result end
        end
        return nil
    elseif t == "NumberRange" then return NumberRange.new(v[1],v[2])
    elseif t == "NumberSequence" then
        local kps = {}
        for _, kp in ipairs(v) do table.insert(kps, NumberSequenceKeypoint.new(kp[1],kp[2],kp[3])) end
        return NumberSequence.new(kps)
    elseif t == "ColorSequence" then
        local kps = {}
        for _, kp in ipairs(v) do table.insert(kps, ColorSequenceKeypoint.new(kp[1], Color3.new(kp[2],kp[3],kp[4]))) end
        return ColorSequence.new(kps)
    elseif t == "Rect" then return Rect.new(v[1],v[2],v[3],v[4])
    end
    return nil
end

local function getInstanceSyncId(inst)
    local tag = inst:FindFirstChild("__SyncId")
    return tag and tag.Value or nil
end

local function setInstanceSyncId(inst, syncId)
    local tag = inst:FindFirstChild("__SyncId")
    if not tag then
        tag = Instance.new("StringValue")
        tag.Name = "__SyncId"
        tag.Parent = inst
    end
    tag.Value = syncId
end

local function getOrCreateSyncId(inst)
    local existing = getInstanceSyncId(inst)
    if existing then return existing end
    local syncId = HttpService:GenerateGUID(false)
    setInstanceSyncId(inst, syncId)
    return syncId
end

local function getFullPath(inst)
    local parts = {}
    local current = inst
    while current and current ~= game do
        table.insert(parts, 1, current.Name)
        current = current.Parent
    end
    return table.concat(parts, ".")
end

local function getPropsForClass(className)
    if SERIALIZABLE_PROPERTIES[className] then return SERIALIZABLE_PROPERTIES[className] end
    for base, props in pairs(SERIALIZABLE_PROPERTIES) do
        local ok, result = pcall(function()
            local test = Instance.new(className)
            local is = test:IsA(base)
            test:Destroy()
            return is
        end)
        if ok and result then return props end
    end
    return {"Name"}
end

local function serializeInstance(inst)
    local className = inst.ClassName
    local props = getPropsForClass(className)
    local serializedProps = {}
    for _, propName in ipairs(props) do
        local ok, value = pcall(function() return inst[propName] end)
        if ok and value ~= nil then
            -- Пропускаем ObjectValue-подобные (Instance references)
            if typeof(value) ~= "Instance" then
                serializedProps[propName] = serializeValue(value)
            end
        end
    end
    local syncId = getOrCreateSyncId(inst)
    local parentSyncId = nil
    if inst.Parent and inst.Parent ~= game then
        parentSyncId = getInstanceSyncId(inst.Parent) or getOrCreateSyncId(inst.Parent)
    end
    return {
        syncId = syncId,
        className = className,
        properties = serializedProps,
        parentSyncId = parentSyncId,
        parentPath = inst.Parent and getFullPath(inst.Parent) or nil,
    }
end

local function serializeTree(inst)
    local result = {}
    local function recurse(obj)
        if obj.Name == "__SyncId" then return end
        if obj:IsA("Camera") and obj == workspace.CurrentCamera then return end
        if obj:IsA("Terrain") then return end -- Terrain отдельно
        table.insert(result, serializeInstance(obj))
        for _, child in ipairs(obj:GetChildren()) do
            recurse(child)
        end
    end
    recurse(inst)
    return result
end

-- ============== HTTP ==============

local function httpRequest(endpoint, body)
    local success, result = pcall(function()
        return HttpService:RequestAsync({
            Url = state.serverUrl .. endpoint,
            Method = "POST",
            Headers = {["Content-Type"] = "application/json"},
            Body = HttpService:JSONEncode(body)
        })
    end)
    if success and result.StatusCode == 200 then
        return true, HttpService:JSONDecode(result.Body)
    end
    return false, result
end

-- ============== TERRAIN ==============

function uploadTerrain()
    if not state.connected then return end
    
    local region = workspace.Terrain:FindFirstChildOfClass("TerrainRegion")
    
    -- Читаем terrain данные через ReadVoxels
    local CHUNK = 64
    local terrainSize = workspace.Terrain:FindFirstChild("MaxExtents")
    
    -- Простой подход: сериализуем материалы и occupancy в регионе
    local minPos = Vector3.new(-512, -512, -512)
    local maxPos = Vector3.new(512, 512, 512)
    
    -- Разбиваем на чанки и отправляем
    local chunks = {}
    local chunkCount = 0
    
    for x = minPos.X, maxPos.X - CHUNK, CHUNK do
        for y = minPos.Y, maxPos.Y - CHUNK, CHUNK do
            for z = minPos.Z, maxPos.Z - CHUNK, CHUNK do
                local region3 = Region3.new(
                    Vector3.new(x, y, z),
                    Vector3.new(x + CHUNK, y + CHUNK, z + CHUNK)
                ):ExpandToGrid(4)
                
                local ok, materials, occupancy = pcall(function()
                    return workspace.Terrain:ReadVoxels(region3, 4)
                end)
                
                if ok then
                    -- Проверяем есть ли что-то кроме воздуха
                    local hasContent = false
                    for xi, xSlice in ipairs(materials) do
                        for yi, ySlice in ipairs(xSlice) do
                            for zi, mat in ipairs(ySlice) do
                                if mat ~= Enum.Material.Air then
                                    hasContent = true
                                    break
                                end
                            end
                            if hasContent then break end
                        end
                        if hasContent then break end
                    end
                    
                    if hasContent then
                        local matData = {}
                        local occData = {}
                        for xi, xSlice in ipairs(materials) do
                            matData[xi] = {}
                            occData[xi] = {}
                            for yi, ySlice in ipairs(xSlice) do
                                matData[xi][yi] = {}
                                occData[xi][yi] = {}
                                for zi, mat in ipairs(ySlice) do
                                    matData[xi][yi][zi] = mat.Name
                                    occData[xi][yi][zi] = occupancy[xi][yi][zi]
                                end
                            end
                        end
                        
                        local key = x .. "_" .. y .. "_" .. z
                        chunks[key] = {
                            position = {x, y, z},
                            size = CHUNK,
                            materials = matData,
                            occupancy = occData
                        }
                        chunkCount = chunkCount + 1
                    end
                end
            end
        end
        task.wait() -- Не блокируем Studio
    end
    
    if chunkCount > 0 then
        httpRequest("/api/terrain/upload", {
            roomId = state.roomId,
            data = chunks
        })
        warn("[Collab] Terrain uploaded: " .. chunkCount .. " chunks")
    else
        warn("[Collab] No terrain data to upload")
    end
end

function downloadTerrain()
    if not state.connected then return end
    
    local ok, result = httpRequest("/api/terrain/download", {
        roomId = state.roomId
    })
    
    if not ok or not result.hasData then
        warn("[Collab] No terrain data available")
        return
    end
    
    state.ignoreChanges = true
    
    local chunks = result.data
    local count = 0
    
    for key, chunk in pairs(chunks) do
        local pos = chunk.position
        local size = chunk.size
        
        local region3 = Region3.new(
            Vector3.new(pos[1], pos[2], pos[3]),
            Vector3.new(pos[1] + size, pos[2] + size, pos[3] + size)
        ):ExpandToGrid(4)
        
        -- Восстанавливаем 3D массивы
        local materials = {}
        local occupancy = {}
        
        for xi, xSlice in pairs(chunk.materials) do
            local xIdx = tonumber(xi)
            materials[xIdx] = {}
            occupancy[xIdx] = {}
            for yi, ySlice in pairs(xSlice) do
                local yIdx = tonumber(yi)
                materials[xIdx][yIdx] = {}
                occupancy[xIdx][yIdx] = {}
                for zi, matName in pairs(ySlice) do
                    local zIdx = tonumber(zi)
                    materials[xIdx][yIdx][zIdx] = Enum.Material[matName] or Enum.Material.Air
                    occupancy[xIdx][yIdx][zIdx] = chunk.occupancy[xi][yi][zi]
                end
            end
        end
        
        pcall(function()
            workspace.Terrain:WriteVoxels(region3, 4, materials, occupancy)
        end)
        
        count = count + 1
        if count % 10 == 0 then task.wait() end
    end
    
    state.ignoreChanges = false
    warn("[Collab] Terrain downloaded: " .. count .. " chunks")
end

-- ============== TRACKING ==============

local changeConnections = {}
local descendantAddedConn = nil
local descendantRemovingConn = nil

local function findInstanceByPath(path)
    local parts = string.split(path, ".")
    local current = game
    for _, part in ipairs(parts) do
        current = current:FindFirstChild(part)
        if not current then return nil end
    end
    return current
end

local function findInstanceBySyncId(syncId)
    if state.instanceById[syncId] then
        local inst = state.instanceById[syncId]
        if inst.Parent then return inst end
        state.instanceById[syncId] = nil
    end
    local function search(parent)
        for _, child in ipairs(parent:GetChildren()) do
            local tag = child:FindFirstChild("__SyncId")
            if tag and tag.Value == syncId then
                state.instanceById[syncId] = child
                return child
            end
            local r = search(child)
            if r then return r end
        end
        return nil
    end
    for _, svc in ipairs({workspace, game:GetService("ReplicatedStorage"),
        game:GetService("ServerScriptService"), game:GetService("ServerStorage"),
        game:GetService("StarterGui"), game:GetService("StarterPack"), game:GetService("StarterPlayer")}) do
        local r = search(svc)
        if r then return r end
    end
    return nil
end

local function onPropertyChanged(inst, propName)
    if state.ignoreChanges or not state.connected then return end
    local syncId = getInstanceSyncId(inst) or getOrCreateSyncId(inst)
    local ok, value = pcall(function() return inst[propName] end)
    if ok and typeof(value) ~= "Instance" then
        table.insert(state.pendingOperations, {
            type = "update",
            data = {
                syncId = syncId,
                className = inst.ClassName,
                properties = { [propName] = serializeValue(value) },
                path = getFullPath(inst)
            }
        })
        state.opsSent = state.opsSent + 1
    end
end

local function trackInstance(inst)
    if inst.Name == "__SyncId" then return end
    if state.trackedInstances[inst] then return end
    local syncId = getOrCreateSyncId(inst)
    state.instanceById[syncId] = inst
    state.trackedInstances[inst] = true
    local props = getPropsForClass(inst.ClassName)
    local connections = {}
    for _, propName in ipairs(props) do
        local ok, conn = pcall(function()
            return inst:GetPropertyChangedSignal(propName):Connect(function()
                onPropertyChanged(inst, propName)
            end)
        end)
        if ok and conn then table.insert(connections, conn) end
    end
    changeConnections[inst] = connections
end

local function untrackInstance(inst)
    state.trackedInstances[inst] = nil
    if changeConnections[inst] then
        for _, conn in ipairs(changeConnections[inst]) do conn:Disconnect() end
        changeConnections[inst] = nil
    end
    local syncId = getInstanceSyncId(inst)
    if syncId then state.instanceById[syncId] = nil end
end

function startTracking()
    local services = {workspace, game:GetService("ReplicatedStorage"),
        game:GetService("ServerScriptService"), game:GetService("ServerStorage"),
        game:GetService("StarterGui"), game:GetService("StarterPack")}
    for _, svc in ipairs(services) do
        for _, desc in ipairs(svc:GetDescendants()) do
            pcall(function() trackInstance(desc) end)
        end
    end
    
    -- Отслеживаем все сервисы
    for _, svc in ipairs(services) do
        svc.DescendantAdded:Connect(function(desc)
            if state.ignoreChanges or desc.Name == "__SyncId" then return end
            task.defer(function()
                trackInstance(desc)
                if state.connected then
                    table.insert(state.pendingOperations, {
                        type = "create",
                        data = serializeInstance(desc)
                    })
                    state.opsSent = state.opsSent + 1
                end
            end)
        end)
        
        svc.DescendantRemoving:Connect(function(desc)
            if state.ignoreChanges or desc.Name == "__SyncId" then return end
            local syncId = getInstanceSyncId(desc)
            if syncId and state.connected then
                table.insert(state.pendingOperations, {
                    type = "delete",
                    data = { syncId = syncId, path = getFullPath(desc) }
                })
                state.opsSent = state.opsSent + 1
            end
            untrackInstance(desc)
        end)
    end
end

-- ============== APPLY OPERATIONS ==============

local function applyOperation(op)
    state.ignoreChanges = true
    pcall(function()
        if op.type == "create" then
            local data = op.data
            local existing = findInstanceBySyncId(data.syncId)
            if existing then
                for pn, pd in pairs(data.properties or {}) do
                    local val = deserializeValue(pd)
                    if val ~= nil then pcall(function() existing[pn] = val end) end
                end
            else
                local ok2, newInst = pcall(function() return Instance.new(data.className) end)
                if ok2 and newInst then
                    setInstanceSyncId(newInst, data.syncId)
                    if data.properties and data.properties["Name"] then
                        local name = deserializeValue(data.properties["Name"])
                        if name then pcall(function() newInst.Name = name end) end
                    end
                    for pn, pd in pairs(data.properties or {}) do
                        if pn ~= "Name" then
                            local val = deserializeValue(pd)
                            if val ~= nil then pcall(function() newInst[pn] = val end) end
                        end
                    end
                    local parent = nil
                    if data.parentSyncId then parent = findInstanceBySyncId(data.parentSyncId) end
                    if not parent and data.parentPath then parent = findInstanceByPath(data.parentPath) end
                    if not parent then parent = workspace end
                    pcall(function() newInst.Parent = parent end)
                    trackInstance(newInst)
                end
            end
        elseif op.type == "update" then
            local data = op.data
            local inst = findInstanceBySyncId(data.syncId) or (data.path and findInstanceByPath(data.path))
            if inst then
                for pn, pd in pairs(data.properties or {}) do
                    local val = deserializeValue(pd)
                    if val ~= nil then pcall(function() inst[pn] = val end) end
                end
            end
        elseif op.type == "delete" then
            local data = op.data
            local inst = findInstanceBySyncId(data.syncId) or (data.path and findInstanceByPath(data.path))
            if inst then untrackInstance(inst); inst:Destroy() end
        elseif op.type == "reparent" then
            local data = op.data
            local inst = findInstanceBySyncId(data.syncId)
            local newParent = data.newParentSyncId and findInstanceBySyncId(data.newParentSyncId)
            if not newParent and data.newParentPath then newParent = findInstanceByPath(data.newParentPath) end
            if inst and newParent then inst.Parent = newParent end
        end
    end)
    state.ignoreChanges = false
    state.opsReceived = state.opsReceived + 1
end

-- ============== SNAPSHOT ==============

function uploadSnapshot()
    if not state.connected then return end
    local sceneData = {}
    local services = {
        {service = workspace, name = "Workspace"},
        {service = game:GetService("ReplicatedStorage"), name = "ReplicatedStorage"},
        {service = game:GetService("ServerScriptService"), name = "ServerScriptService"},
        {service = game:GetService("ServerStorage"), name = "ServerStorage"},
        {service = game:GetService("StarterGui"), name = "StarterGui"},
        {service = game:GetService("StarterPack"), name = "StarterPack"},
    }
    for _, svc in ipairs(services) do
        sceneData[svc.name] = serializeTree(svc.service)
    end
    httpRequest("/api/snapshot/upload", {roomId = state.roomId, userId = state.userId, data = sceneData})
    addChatMessage("SYSTEM", "📸 Снапшот загружен " .. state.username)
    warn("[Collab] Snapshot uploaded")
end

function downloadSnapshot()
    if not state.connected then return end
    local ok, result = httpRequest("/api/snapshot/download", {roomId = state.roomId})
    if not ok or not result.hasSnapshot then
        warn("[Collab] No snapshot available")
        addChatMessage("SYSTEM", "❌ Снапшот не найден")
        return
    end
    state.ignoreChanges = true
    for serviceName, tree in pairs(result.data) do
        local service = nil
        pcall(function()
            if serviceName == "Workspace" then service = workspace
            else service = game:GetService(serviceName) end
        end)
        if service then
            for _, itemData in ipairs(tree) do
                local existing = findInstanceBySyncId(itemData.syncId)
                if existing then
                    for pn, pd in pairs(itemData.properties or {}) do
                        local val = deserializeValue(pd)
                        if val ~= nil then pcall(function() existing[pn] = val end) end
                    end
                else
                    local ok2, newInst = pcall(function() return Instance.new(itemData.className) end)
                    if ok2 and newInst then
                        setInstanceSyncId(newInst, itemData.syncId)
                        for pn, pd in pairs(itemData.properties or {}) do
                            local val = deserializeValue(pd)
                            if val ~= nil then pcall(function() newInst[pn] = val end) end
                        end
                        local parent = nil
                        if itemData.parentSyncId then parent = findInstanceBySyncId(itemData.parentSyncId) end
                        if not parent and itemData.parentPath then parent = findInstanceByPath(itemData.parentPath) end
                        if not parent then parent = service end
                        pcall(function() newInst.Parent = parent end)
                        trackInstance(newInst)
                    end
                end
            end
        end
    end
    state.ignoreChanges = false
    addChatMessage("SYSTEM", "📸 Снапшот загружен " .. state.username)
    warn("[Collab] Snapshot applied")
end

-- ============== CHAT ==============

local lastChatTimestamp = 0
local chatMsgCount = 0

function addChatMessage(username, message)
    if not state.chatFrame then return end
    
    local msgFrame = Instance.new("Frame")
    msgFrame.Size = UDim2.new(1, 0, 0, 0)
    msgFrame.AutomaticSize = Enum.AutomaticSize.Y
    msgFrame.BackgroundColor3 = Theme.bgTertiary
    msgFrame.BackgroundTransparency = 0.5
    msgFrame.BorderSizePixel = 0
    msgFrame.LayoutOrder = chatMsgCount
    msgFrame.Parent = state.chatFrame
    addCorner(msgFrame, 6)
    addPadding(msgFrame, 4, 4, 6, 6)
    
    local isSystem = username == "SYSTEM"
    
    if not isSystem then
        local nameLabel = Instance.new("TextLabel")
        nameLabel.Size = UDim2.new(1, 0, 0, 14)
        nameLabel.BackgroundTransparency = 1
        nameLabel.TextColor3 = Theme.accent
        nameLabel.TextSize = 11
        nameLabel.Font = Enum.Font.GothamBold
        nameLabel.Text = username
        nameLabel.TextXAlignment = Enum.TextXAlignment.Left
        nameLabel.Parent = msgFrame
    end
    
    local msgLabel = Instance.new("TextLabel")
    msgLabel.Size = UDim2.new(1, 0, 0, 0)
    msgLabel.AutomaticSize = Enum.AutomaticSize.Y
    msgLabel.BackgroundTransparency = 1
    msgLabel.TextColor3 = isSystem and Theme.textDark or Theme.text
    msgLabel.TextSize = isSystem and 11 or 12
    msgLabel.Font = isSystem and Enum.Font.GothamItalic or Enum.Font.Gotham
    msgLabel.Text = message
    msgLabel.TextWrapped = true
    msgLabel.TextXAlignment = Enum.TextXAlignment.Left
    msgLabel.Parent = msgFrame
    
    if not isSystem then
        local layout = Instance.new("UIListLayout")
        layout.SortOrder = Enum.SortOrder.LayoutOrder
        layout.Padding = UDim.new(0, 2)
        layout.Parent = msgFrame
    end
    
    chatMsgCount = chatMsgCount + 1
    
    -- Анимация появления
    msgFrame.BackgroundTransparency = 1
    if not isSystem then
        msgLabel.TextTransparency = 1
    end
    TweenService:Create(msgFrame, TWEEN_INFO_FAST, {BackgroundTransparency = 0.5}):Play()
    if not isSystem then
        TweenService:Create(msgLabel, TWEEN_INFO_FAST, {TextTransparency = 0}):Play()
    end
    
    -- Прокрутка вниз
    task.defer(function()
        if state.chatFrame then
            state.chatFrame.CanvasPosition = Vector2.new(0, state.chatFrame.AbsoluteCanvasSize.Y)
        end
    end)
    
    -- Ограничиваем
    local children = state.chatFrame:GetChildren()
    local count = 0
    for _, child in ipairs(children) do
        if child:IsA("Frame") then count = count + 1 end
    end
    if count > 150 then
        for _, child in ipairs(children) do
            if child:IsA("Frame") then child:Destroy(); break end
        end
    end
end

function sendChat(message)
    if not state.connected then return end
    httpRequest("/api/chat/send", {
        roomId = state.roomId,
        username = state.username,
        message = message
    })
    addChatMessage(state.username, message)
end

-- ============== SYNC LOOP ==============

function startSync()
    -- Poll loop
    state.pollConnection = task.spawn(function()
        while state.connected do
            -- Отправка
            if #state.pendingOperations > 0 then
                local batch = {}
                for i = 1, math.min(#state.pendingOperations, MAX_OPS_PER_BATCH) do
                    table.insert(batch, table.remove(state.pendingOperations, 1))
                end
                pcall(function()
                    httpRequest("/api/operations/push", {
                        roomId = state.roomId,
                        userId = state.userId,
                        username = state.username,
                        operations = batch
                    })
                end)
            end
            
            -- Получение
            local ok, data
            pcall(function()
                ok, data = httpRequest("/api/operations/pull", {
                    roomId = state.roomId,
                    userId = state.userId
                })
            end)
            
            if ok and data then
                if data.operations then
                    for _, op in ipairs(data.operations) do
                        applyOperation(op)
                    end
                end
                if data.chatMessages then
                    for _, msg in ipairs(data.chatMessages) do
                        if msg.timestamp > lastChatTimestamp and msg.username ~= state.username then
                            addChatMessage(msg.username, msg.message)
                            lastChatTimestamp = msg.timestamp
                            if msg.username ~= "SYSTEM" then
                                playSound("message")
                            end
                        end
                    end
                end
            end
            
            -- Обновить статистику
            if state.statsLabel then
                state.statsLabel.Text = string.format(
                    "📊 Отправлено: %d | Получено: %d | Буфер: %d",
                    state.opsSent, state.opsReceived, #state.pendingOperations
                )
            end
            
            task.wait(POLL_INTERVAL)
        end
    end)
    
    -- Heartbeat
    state.heartbeatConnection = task.spawn(function()
        while state.connected do
            local ok, data
            pcall(function()
                ok, data = httpRequest("/api/rooms/heartbeat", {
                    roomId = state.roomId,
                    userId = state.userId
                })
            end)
            if ok and data and state.usersLabel then
                local userList = {}
                if data.users then
                    for _, u in ipairs(data.users) do
                        if u.online then
                            table.insert(userList, "🟢 " .. u.username)
                        end
                    end
                end
                state.usersLabel.Text = "👥 Участники (" .. #userList .. "): " .. table.concat(userList, ", ")
            end
            task.wait(HEARTBEAT_INTERVAL)
        end
    end)
end

function disconnect()
    state.connected = false
    pcall(function()
        httpRequest("/api/rooms/leave", {
            roomId = state.roomId,
            userId = state.userId,
            username = state.username
        })
    end)
    state.roomId = nil
    state.userId = nil
    state.pendingOperations = {}
    state.opsSent = 0
    state.opsReceived = 0
    for inst, _ in pairs(state.trackedInstances) do untrackInstance(inst) end
    state.trackedInstances = {}
    state.instanceById = {}
    warn("[Collab] Disconnected")
end

-- ============== INIT ==============

local widget = createWidget()

mainButton.Click:Connect(function()
    widget.Enabled = not widget.Enabled
end)

plugin.Unloading:Connect(function()
    disconnect()
end)

warn("═══════════════════════════════════════")
warn("  🔗 RobloxCollab Plugin v2.0 loaded!")
warn("  Click the toolbar button to open")
warn("═══════════════════════════════════════")