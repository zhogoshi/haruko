--==============================================================================
-- 1. SERVICES & CLEANUP
--==============================================================================

local CoreGui = game:GetService("CoreGui")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local Lighting = game:GetService("Lighting")

local VirtualInput
pcall(function()
    VirtualInput = game:GetService("VirtualInputManager")
end)

local GUI_NAMES = { "SpeedControlUI", "HarukoUI", "AdminHighlights", "HarukoHighlights" }

local function hiddenGui()
    local fn = gethui or get_hidden_gui or get_hui
    if type(fn) ~= "function" then
        return nil
    end
    local ok, gui = pcall(fn)
    if ok and typeof(gui) == "Instance" then
        return gui
    end
    return nil
end

local function destroyOld(parent)
    if not parent then
        return
    end
    for _, name in ipairs(GUI_NAMES) do
        local old = parent:FindFirstChild(name)
        if old then
            old:Destroy()
        end
    end
end

pcall(destroyOld, CoreGui)
pcall(destroyOld, hiddenGui())

for _, stepName in ipairs({ "AdminPanelBlur", "HarukoBlur" }) do
    pcall(function()
        RunService:UnbindFromRenderStep(stepName)
    end)
end
do
    for _, blurName in ipairs({ "AdminPanelBlur", "HarukoBlur" }) do
        local oldDof = Lighting:FindFirstChild(blurName)
        if oldDof then
            oldDof:Destroy()
        end
    end
    local cam = workspace.CurrentCamera
    if cam then
        for _, partName in ipairs({ "AdminPanelBlurPart", "HarukoBlurPart" }) do
            local oldPart = cam:FindFirstChild(partName)
            if oldPart then
                oldPart:Destroy()
            end
        end
    end
end

if not game:IsLoaded() then
    game.Loaded:Wait()
end

local player = Players.LocalPlayer
if not player then
    player = Players.PlayerAdded:Wait()
end
pcall(destroyOld, player:FindFirstChildOfClass("PlayerGui"))

local character = player.Character
local humanoidRootPart = character and character:FindFirstChild("HumanoidRootPart")
local humanoid = character and character:FindFirstChildOfClass("Humanoid")

local function protectGui(gui)
    local fn = protectgui or protect_gui or (syn and syn.protect_gui)
    if fn then
        pcall(fn, gui)
    end
end

local function mount(gui)
    protectGui(gui)
    local hidden = hiddenGui()
    if hidden then
        local ok = pcall(function()
            gui.Parent = hidden
        end)
        if ok and gui.Parent == hidden then
            return
        end
    end
    local ok = pcall(function()
        gui.Parent = CoreGui
    end)
    if ok and gui.Parent == CoreGui then
        return
    end
    local pg = player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui", 5)
    if pg then
        gui.Parent = pg
    else
        warn("[Haruko] Could not mount the UI")
    end
end

--==============================================================================
-- 2. THEME, CONFIG, STATE
--==============================================================================

local PRESET_FILE = "AdminPanel_Presets.json"
local VERSION = "v4"
local ACTIONS = { "Teleport", "Walk", "Glide" }
local ACTION_SET = { Teleport = true, Walk = true, Glide = true }
local TP_SET = { Start = true, Center = true, End = true }
local PAUSE_SET = { Before = true, After = true }

local WIN_W, WIN_H = 740, 520
local SIDEBAR_W = 164
local PAGE_W = WIN_W - SIDEBAR_W - 32
local PAGE_H = WIN_H - 78
local CORNER = 14

local T = {
    Accent = Color3.fromRGB(10, 132, 255),
    AccentHi = Color3.fromRGB(100, 175, 255),
    Text = Color3.fromRGB(245, 246, 250),
    Muted = Color3.fromRGB(150, 157, 176),
    Window = Color3.fromRGB(22, 24, 34),
    Dark = Color3.fromRGB(9, 10, 15),
    Menu = Color3.fromRGB(34, 37, 50),
    White = Color3.new(1, 1, 1),
    Success = Color3.fromRGB(48, 209, 88),
    Warning = Color3.fromRGB(255, 204, 0),
    Danger = Color3.fromRGB(255, 69, 58),
    DangerText = Color3.fromRGB(255, 120, 110),
}

local F = {
    Regular = Enum.Font.Gotham,
    Medium = Enum.Font.GothamMedium,
    Bold = Enum.Font.GothamBold,
}

local settings = {
    blur = true,
    blurStrength = 1,
    opacity = 0.86,
}

local D = {
    action = "Teleport",
    speed = 40,
    tp = { x = "Center", y = "End", z = "Center" },
    offset = 3,
}

local tour = { order = "Forward", loop = true, interval = 0.5 }

local NORMAL_SPEED = 16
local motion = {
    speedOn = false,
    speed = 300,
    flyOn = false,
    flyMode = "Default",
    flySpeed = 80,
    glideSink = 10,
    teleportOn = false,
    tpOrigin = "Center",
    tpOffset = 3,
    clickOn = false,
    clickInterval = 0.15,
    noclipOn = false,
    wish = nil,
    suppress = 0,
}

local savedPlatform
local collideState = {}
local unloading = false

local pickMode, pickKind, pickType = false, nil, "Part"
local xray, espOn = true, false
local touring = false
local moveToken = 0
local lastAddedItem

local function newList(name)
    return { name = name, items = {} }
end

local lists = { newList("Default") }
local activeList = 1

local function currentList()
    return lists[activeList]
end

local expanded = setmetatable({}, { __mode = "k" })
local connections = {}
local modUi = {}
local listening

local setPickMode
local refreshList, refreshESP, switchList
local goItem, cancelMovement, startTour, updateTourUI
local hoverHighlight

local function applyNoclip()
    if not character then
        return
    end
    for _, inst in ipairs(character:GetDescendants()) do
        if inst:IsA("BasePart") then
            if collideState[inst] == nil then
                collideState[inst] = inst.CanCollide
            end
            inst.CanCollide = false
        end
    end
end

local function restoreNoclip()
    for inst, was in pairs(collideState) do
        if inst.Parent then
            inst.CanCollide = was
        end
    end
    collideState = {}
end

local function setNoclip(on)
    motion.noclipOn = on
    if on then
        applyNoclip()
    else
        restoreNoclip()
    end
end

local function setFly(on)
    motion.flyOn = on
    local hum = humanoid
    if not hum or not hum.Parent then
        return
    end
    if on then
        if savedPlatform == nil then
            savedPlatform = hum.PlatformStand
        end
        hum.PlatformStand = true
    else
        local prev = savedPlatform
        savedPlatform = nil
        hum.PlatformStand = prev == true
    end
end

local function attachCharacter(char)
    if not char then
        return
    end
    character = char
    humanoidRootPart = char:WaitForChild("HumanoidRootPart", 8)
    humanoid = char:WaitForChild("Humanoid", 8)
    motion.wish = nil
    collideState = {}
    if motion.flyOn and humanoid then
        humanoid.PlatformStand = true
    end
end

if character and not (humanoidRootPart and humanoid) then
    task.spawn(attachCharacter, character)
end
table.insert(connections, player.CharacterAdded:Connect(attachCharacter))

--==============================================================================
-- 3. UI PRIMITIVES
--==============================================================================

local function new(class, props, parent)
    local obj = Instance.new(class)
    for k, v in pairs(props) do
        obj[k] = v
    end
    obj.Parent = parent
    return obj
end

local function round(obj, r)
    return new("UICorner", { CornerRadius = UDim.new(0, r) }, obj)
end

local function hairline(obj, transparency)
    return new("UIStroke", {
        Color = T.White,
        Thickness = 1,
        Transparency = transparency or 0.9,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, obj)
end

local function tween(obj, props, t, style)
    local tw = TweenService:Create(
        obj,
        TweenInfo.new(t or 0.18, style or Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
        props
    )
    tw:Play()
    return tw
end

local function label(parent, text, pos, size, o)
    o = o or {}
    return new("TextLabel", {
        BackgroundTransparency = 1,
        Position = pos,
        Size = size,
        AutomaticSize = o.autosize or Enum.AutomaticSize.None,
        Text = text,
        TextColor3 = o.color or T.Text,
        Font = o.font or F.Regular,
        TextSize = o.size or 13,
        TextXAlignment = o.align or Enum.TextXAlignment.Left,
        TextYAlignment = o.yalign or Enum.TextYAlignment.Center,
        TextWrapped = o.wrap or false,
        TextTruncate = o.truncate or Enum.TextTruncate.None,
        RichText = o.rich or false,
    }, parent)
end

local function escapeRich(s)
    return (tostring(s):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local function fmt(v)
    return string.format("%g", math.floor(v * 100 + 0.5) / 100)
end

local CHEVRON_POSE = {
    down = { { -2.0, 0.5, 42 }, { 2.0, 0.5, -42 } },
    right = { { 0.6, -1.7, -42 }, { 0.6, 1.7, 42 } },
    up = { { -2.0, -0.5, -42 }, { 2.0, -0.5, 42 } },
}

local function makeIcon(parent, kind, size, color)
    size = size or 16
    color = color or T.Text
    local k = size / 16
    local box = new("Frame", {
        Size = UDim2.fromOffset(size, size),
        BackgroundTransparency = 1,
        ClipsDescendants = true,
    }, parent)

    local fills, strokes = {}, {}
    local chevBars

    local function place(w, h, x, y, rot)
        return {
            Size = UDim2.fromOffset(w * k, h * k),
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.new(0.5, x * k, 0.5, y * k),
            Rotation = rot or 0,
            BorderSizePixel = 0,
        }
    end

    local function bar(w, h, x, y, rot)
        local props = place(w, h, x, y, rot)
        props.BackgroundColor3 = color
        local f = new("Frame", props, box)
        round(f, math.max(h * k / 2, 1))
        table.insert(fills, f)
        return f
    end

    local function dot(d, x, y)
        local props = place(d, d, x, y)
        props.BackgroundColor3 = color
        local f = new("Frame", props, box)
        round(f, d * k / 2)
        table.insert(fills, f)
    end

    local function ring(d, x, y, r)
        local props = place(d, d, x, y)
        props.BackgroundTransparency = 1
        local f = new("Frame", props, box)
        round(f, r * k)
        table.insert(strokes, new("UIStroke", {
            Color = color,
            Thickness = math.max(1.5 * k, 1),
            ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        }, f))
    end

    local function cell(x, y)
        local props = place(4.6, 4.6, x, y)
        props.BackgroundColor3 = color
        local f = new("Frame", props, box)
        round(f, 1.4)
        table.insert(fills, f)
    end

    if kind == "chevron" then
        chevBars = {
            bar(6, 1.6, -2.0, 0.5, 42),
            bar(6, 1.6, 2.0, 0.5, -42),
        }
    elseif kind == "plus" then
        bar(10, 2, 0, 0)
        bar(2, 10, 0, 0)
    elseif kind == "close" then
        bar(7.5, 1.7, 0, 0, 45)
        bar(7.5, 1.7, 0, 0, -45)
    elseif kind == "check" then
        bar(4.5, 1.7, -2.4, 1.0, 42)
        bar(8, 1.7, 1.5, -0.2, -48)
    elseif kind == "cube" then
        ring(12, 0, 0, 3)
        dot(4, 0, 0)
    elseif kind == "target" then
        ring(12, 0, 0, 6)
        dot(3.5, 0, 0)
    elseif kind == "lines" then
        bar(11, 1.8, 0, -4)
        bar(11, 1.8, 0, 0)
        bar(7, 1.8, -2, 4)
    elseif kind == "fast" then
        bar(5, 1.7, -3.2, -2, 40)
        bar(5, 1.7, -3.2, 2, -40)
        bar(5, 1.7, 2.2, -2, 40)
        bar(5, 1.7, 2.2, 2, -40)
    elseif kind == "sliders" then
        bar(11, 1.8, 0, -3.5)
        bar(11, 1.8, 0, 3.5)
        ring(5, -2.2, -3.5, 2.5)
        ring(5, 2.2, 3.5, 2.5)
    elseif kind == "gear" then
        ring(7.2, 0, 0, 3.4)
        for i = 0, 5 do
            local a = math.rad(i * 60 - 90)
            bar(2.2, 2.5, math.cos(a) * 5.2, math.sin(a) * 5.2, i * 60)
        end
    elseif kind == "grid" then
        cell(-3.1, -3.1)
        cell(3.1, -3.1)
        cell(-3.1, 3.1)
        cell(3.1, 3.1)
    elseif kind == "mark" then
        bar(2.2, 9, -3.2, 0)
        bar(2.2, 9, 3.2, 0)
        bar(4.6, 2.2, 0, 0)
    elseif kind == "fly" then
        bar(7, 1.7, -1.1, -0.3, -28)
        bar(7, 1.7, 1.1, 0.5, 28)
    elseif kind == "click" then
        ring(11, 0, 0, 5.5)
        dot(3.2, 0, 0)
    elseif kind == "noclip" then
        bar(6, 1.6, -2.2, -4.2)
        bar(6, 1.6, 2.2, 4.2)
        bar(1.6, 5, -4.2, -1.4)
        bar(1.6, 5, 4.2, 1.4)
    elseif kind == "info" then
        ring(11, 0, 0, 5.5)
        dot(2, 0, -2.6)
        bar(1.8, 4.2, 0, 1.6)
    elseif kind == "warn" then
        bar(1.8, 6.2, 0, -1.1)
        dot(2.2, 0, 3.5)
    end

    local api = { Frame = box }

    function api.SetColor(c, animate)
        for _, f in ipairs(fills) do
            if animate then
                tween(f, { BackgroundColor3 = c }, 0.15)
            else
                f.BackgroundColor3 = c
            end
        end
        for _, s in ipairs(strokes) do
            if animate then
                tween(s, { Color = c }, 0.15)
            else
                s.Color = c
            end
        end
    end

    function api.SetFacing(dir, animate)
        local pose = CHEVRON_POSE[dir]
        if not pose or not chevBars then
            return
        end
        for i, f in ipairs(chevBars) do
            local p = pose[i]
            local goalPos = UDim2.new(0.5, p[1] * k, 0.5, p[2] * k)
            if animate then
                tween(f, { Position = goalPos, Rotation = p[3] }, 0.2)
            else
                f.Position = goalPos
                f.Rotation = p[3]
            end
        end
    end

    return api
end

--==============================================================================
-- 4. LAYERS
--==============================================================================

local ScreenGui = new("ScreenGui", {
    Name = "HarukoUI",
    ResetOnSpawn = false,
    IgnoreGuiInset = true,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    DisplayOrder = 2147483647,
})
mount(ScreenGui)

local HighlightFolder = new("Folder", { Name = "HarukoHighlights" })
mount(HighlightFolder)

local MainFrame = new("CanvasGroup", {
    Name = "MainFrame",
    Size = UDim2.fromOffset(WIN_W, WIN_H),
    Position = UDim2.new(0.5, -WIN_W / 2, 0.5, -WIN_H / 2),
    BackgroundColor3 = T.Window,
    BackgroundTransparency = 1 - settings.opacity,
    BorderSizePixel = 0,
    Active = true,
    GroupTransparency = 0,
    Visible = true,
    ZIndex = 1,
}, ScreenGui)
round(MainFrame, CORNER)
hairline(MainFrame, 0.82)
local WinScale = new("UIScale", { Scale = 1 }, MainFrame)

do
    local sheen = new("Frame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = T.White,
        BorderSizePixel = 0,
    }, MainFrame)
    new("UIGradient", {
        Rotation = 90,
        Transparency = NumberSequence.new(0.93, 1),
    }, sheen)
end

local Overlay = new("Frame", {
    Name = "Overlay",
    Size = UDim2.fromScale(1, 1),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    Visible = false,
    ZIndex = 20,
    Active = false,
}, ScreenGui)

local OverlayCatcher = new("TextButton", {
    Size = UDim2.fromScale(1, 1),
    BackgroundTransparency = 1,
    Text = "",
    AutoButtonColor = false,
    ZIndex = 1,
}, Overlay)

local DialogHost = new("Frame", {
    Name = "DialogHost",
    Size = UDim2.fromScale(1, 1),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    Visible = false,
    ZIndex = 30,
    Active = false,
}, ScreenGui)

local ToastHost = new("Frame", {
    Name = "ToastHost",
    AnchorPoint = Vector2.new(0.5, 0),
    Position = UDim2.new(0.5, 0, 0, 56),
    Size = UDim2.fromOffset(340, 0),
    AutomaticSize = Enum.AutomaticSize.Y,
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ZIndex = 40,
    Active = false,
}, ScreenGui)

--==============================================================================
-- 5. WIDGETS
--==============================================================================

local Styles = {
    primary = { color = T.Accent, t = 0, text = T.Text },
    secondary = { color = T.White, t = 0.9, text = T.Text },
    danger = { color = T.Danger, t = 0.8, text = T.DangerText },
}
local BtnApi = setmetatable({}, { __mode = "k" })

local function btnText(btn, text)
    local api = BtnApi[btn]
    api.label.Text = text
    api.label.Visible = (text ~= "")
end

local function btnIcon(btn, kind)
    local api = BtnApi[btn]
    if api.icon then
        api.icon.Frame:Destroy()
        api.icon = nil
    end
    if kind then
        api.icon = makeIcon(api.row, kind, 14, Styles[api.style].text)
        api.icon.Frame.LayoutOrder = 1
    end
end

local function setButtonStyle(btn, style)
    local api = BtnApi[btn]
    local s = Styles[style]
    api.style, api.color, api.t = style, s.color, s.t
    tween(btn, { BackgroundColor3 = s.color, BackgroundTransparency = s.t }, 0.2)
    tween(api.label, { TextColor3 = s.text }, 0.2)
    if api.icon then
        api.icon.SetColor(s.text, true)
    end
end

local function button(parent, text, pos, size, style, iconKind)
    style = style or "secondary"
    local s = Styles[style]

    local btn = new("TextButton", {
        Position = pos,
        Size = size,
        BackgroundColor3 = s.color,
        BackgroundTransparency = s.t,
        Text = "",
        AutoButtonColor = false,
        BorderSizePixel = 0,
    }, parent)
    round(btn, 8)
    hairline(btn, 0.9)

    local row = new("Frame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
    }, btn)
    new("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        HorizontalAlignment = Enum.HorizontalAlignment.Center,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 6),
    }, row)

    local lbl = new("TextLabel", {
        BackgroundTransparency = 1,
        AutomaticSize = Enum.AutomaticSize.X,
        Size = UDim2.new(0, 0, 1, 0),
        Text = text,
        Visible = (text ~= ""),
        TextColor3 = s.text,
        Font = F.Medium,
        TextSize = 13,
        LayoutOrder = 2,
    }, row)

    local api = { label = lbl, row = row, style = style, color = s.color, t = s.t }
    BtnApi[btn] = api
    if iconKind then
        btnIcon(btn, iconKind)
    end

    local function paint(delta, lighten)
        if api.t == 0 then
            tween(btn, { BackgroundColor3 = api.color:Lerp(lighten and T.White or T.Dark, 0.12) }, 0.1)
        else
            tween(btn, { BackgroundTransparency = math.clamp(api.t + delta, 0, 1) }, 0.1)
        end
    end
    local function reset()
        tween(btn, { BackgroundColor3 = api.color, BackgroundTransparency = api.t }, 0.15)
    end

    btn.MouseEnter:Connect(function() paint(-0.06, true) end)
    btn.MouseLeave:Connect(reset)
    btn.MouseButton1Down:Connect(function() paint(-0.14, false) end)
    btn.MouseButton1Up:Connect(function() paint(-0.06, true) end)

    return btn
end

local function input(parent, pos, size, text, placeholder)
    local box = new("TextBox", {
        Position = pos,
        Size = size,
        BackgroundColor3 = T.White,
        BackgroundTransparency = 0.92,
        TextColor3 = T.Text,
        PlaceholderColor3 = T.Muted,
        Text = text or "",
        PlaceholderText = placeholder or "",
        Font = F.Medium,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        ClearTextOnFocus = false,
        BorderSizePixel = 0,
    }, parent)
    round(box, 8)
    local s = hairline(box, 0.88)
    new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, box)

    box.Focused:Connect(function()
        tween(s, { Color = T.Accent, Transparency = 0, Thickness = 1.5 }, 0.15)
        tween(box, { BackgroundTransparency = 0.86 }, 0.15)
    end)
    box.FocusLost:Connect(function()
        tween(s, { Color = T.White, Transparency = 0.88, Thickness = 1 }, 0.15)
        tween(box, { BackgroundTransparency = 0.92 }, 0.15)
    end)
    return box
end

local function card(parent, pos, size, title, subtitle)
    local f = new("Frame", {
        Position = pos,
        Size = size,
        BackgroundColor3 = T.White,
        BackgroundTransparency = 0.955,
        BorderSizePixel = 0,
    }, parent)
    round(f, 12)
    hairline(f, 0.92)

    if title then
        label(f, title, UDim2.fromOffset(14, 10), UDim2.new(1, -28, 0, 18), { font = F.Bold, size = 14 })
    end
    if subtitle then
        label(f, subtitle, UDim2.fromOffset(14, 29), UDim2.new(1, -28, 0, 14), { color = T.Muted, size = 12 })
    end
    return f
end

local function switch(parent, pos, initial, onChange)
    local state = initial

    local track = new("TextButton", {
        Position = pos,
        Size = UDim2.fromOffset(42, 24),
        Text = "",
        AutoButtonColor = false,
        BorderSizePixel = 0,
        ZIndex = 3,
    }, parent)
    round(track, 12)

    local knob = new("Frame", {
        Size = UDim2.fromOffset(20, 20),
        BackgroundColor3 = T.White,
        BorderSizePixel = 0,
    }, track)
    round(knob, 10)
    new("UIStroke", {
        Color = T.Dark, Transparency = 0.8, Thickness = 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, knob)

    local function render(animate)
        local goal = {
            BackgroundColor3 = state and T.Accent or T.White,
            BackgroundTransparency = state and 0 or 0.8,
        }
        local knobGoal = { Position = state and UDim2.new(1, -22, 0.5, -10) or UDim2.new(0, 2, 0.5, -10) }
        if animate then
            tween(track, goal, 0.2)
            tween(knob, knobGoal, 0.22)
        else
            for k, v in pairs(goal) do track[k] = v end
            for k, v in pairs(knobGoal) do knob[k] = v end
        end
    end
    render(false)

    track.Activated:Connect(function()
        state = not state
        render(true)
        onChange(state)
    end)

    return {
        Set = function(v)
            state = v
            render(true)
        end,
        Get = function()
            return state
        end,
    }
end

local function segmented(parent, pos, size, options, initial, onChange)
    local n = #options

    local container = new("Frame", {
        Position = pos,
        Size = size,
        BackgroundColor3 = T.White,
        BackgroundTransparency = 0.92,
        BorderSizePixel = 0,
    }, parent)
    round(container, 9)
    hairline(container, 0.9)

    local pill = new("Frame", {
        Size = UDim2.new(1 / n, -4, 1, -4),
        Position = UDim2.new(0, 2, 0, 2),
        BackgroundColor3 = T.Accent,
        BorderSizePixel = 0,
    }, container)
    round(pill, 7)

    local buttons = {}
    local function render(value, animate)
        local idx = table.find(options, value) or 1
        local goal = UDim2.new((idx - 1) / n, 2, 0, 2)
        if animate then
            tween(pill, { Position = goal }, 0.24)
        else
            pill.Position = goal
        end
        for opt, b in pairs(buttons) do
            local c = (opt == value) and T.Text or T.Muted
            if animate then
                tween(b, { TextColor3 = c }, 0.2)
            else
                b.TextColor3 = c
            end
        end
    end

    for i, opt in ipairs(options) do
        local b = new("TextButton", {
            Size = UDim2.new(1 / n, 0, 1, 0),
            Position = UDim2.new((i - 1) / n, 0, 0, 0),
            BackgroundTransparency = 1,
            Text = opt,
            TextColor3 = T.Muted,
            Font = F.Medium,
            TextSize = 13,
            AutoButtonColor = false,
            ZIndex = 2,
        }, container)
        buttons[opt] = b
        b.Activated:Connect(function()
            render(opt, true)
            onChange(opt)
        end)
    end

    render(initial, false)
    return { Set = function(v) render(v, true) end }
end

local function slider(parent, pos, width, min, max, initial, isLog, onChange)
    local track = new("Frame", {
        Position = pos,
        Size = UDim2.fromOffset(width, 4),
        BackgroundColor3 = T.White,
        BackgroundTransparency = 0.82,
        BorderSizePixel = 0,
    }, parent)
    round(track, 2)

    local fill = new("Frame", {
        Size = UDim2.new(0, 0, 1, 0),
        BackgroundColor3 = T.Accent,
        BorderSizePixel = 0,
    }, track)
    round(fill, 2)

    local knob = new("Frame", {
        Size = UDim2.fromOffset(16, 16),
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0, 0, 0.5, 0),
        BackgroundColor3 = T.White,
        BorderSizePixel = 0,
    }, track)
    round(knob, 8)
    new("UIStroke", {
        Color = T.Dark, Transparency = 0.75, Thickness = 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, knob)

    local hit = new("TextButton", {
        Position = UDim2.new(0, -8, 0.5, -12),
        Size = UDim2.new(1, 16, 0, 24),
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        ZIndex = 2,
    }, track)

    local function toValue(a)
        return isLog and min * (max / min) ^ a or min + (max - min) * a
    end
    local function toAlpha(v)
        v = math.clamp(v, min, max)
        return isLog and math.log(v / min) / math.log(max / min) or (v - min) / (max - min)
    end

    local function setAlpha(a, fire, animate)
        a = math.clamp(a, 0, 1)
        if animate then
            tween(fill, { Size = UDim2.new(a, 0, 1, 0) }, 0.2)
            tween(knob, { Position = UDim2.new(a, 0, 0.5, 0) }, 0.2)
        else
            fill.Size = UDim2.new(a, 0, 1, 0)
            knob.Position = UDim2.new(a, 0, 0.5, 0)
        end
        if fire then
            onChange(toValue(a))
        end
    end

    local dragging = false
    local function fromInput(inp)
        setAlpha((inp.Position.X - track.AbsolutePosition.X) / track.AbsoluteSize.X, true, false)
    end

    hit.InputBegan:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            tween(knob, { Size = UDim2.fromOffset(19, 19) }, 0.1)
            fromInput(inp)
        end
    end)
    table.insert(connections, UserInputService.InputChanged:Connect(function(inp)
        if dragging and (inp.UserInputType == Enum.UserInputType.MouseMovement
            or inp.UserInputType == Enum.UserInputType.Touch) then
            fromInput(inp)
        end
    end))
    table.insert(connections, UserInputService.InputEnded:Connect(function(inp)
        if dragging and (inp.UserInputType == Enum.UserInputType.MouseButton1
            or inp.UserInputType == Enum.UserInputType.Touch) then
            dragging = false
            tween(knob, { Size = UDim2.fromOffset(16, 16) }, 0.12)
        end
    end))

    setAlpha(toAlpha(initial), false, false)
    return { Set = function(v) setAlpha(toAlpha(v), false, true) end }
end

local activePopup

local function closeDropdown(instant)
    Overlay.Visible = false
    local p = activePopup
    activePopup = nil
    if not p then
        return
    end
    if instant or not p.Parent then
        p:Destroy()
        return
    end
    local stroke = p:FindFirstChildOfClass("UIStroke")
    tween(p, { BackgroundTransparency = 1 }, 0.12)
    if stroke then
        tween(stroke, { Transparency = 1 }, 0.12)
    end
    local sc = p:FindFirstChildOfClass("UIScale")
    if sc then
        tween(sc, { Scale = 0.96 }, 0.12)
    end
    task.delay(0.14, function()
        if p then
            p:Destroy()
        end
    end)
end

OverlayCatcher.Activated:Connect(function()
    closeDropdown(false)
end)

local function openDropdown(anchor, options, selected, onSelect)
    closeDropdown(true)

    local rowH, pad = 30, 5
    local h = math.min(#options, 7) * rowH + pad * 2
    local w = math.max(anchor.AbsoluteSize.X, 140)
    local view = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
    local absPos, absSize = anchor.AbsolutePosition, anchor.AbsoluteSize
    local below = absPos.Y + absSize.Y + 6 + h <= view.Y - 8
    local y = below and (absPos.Y + absSize.Y + 6) or (absPos.Y - 6)
    local x = math.clamp(absPos.X + absSize.X / 2, w / 2 + 8, math.max(view.X - w / 2 - 8, w / 2 + 8))

    local popup = new("Frame", {
        Name = "Popup",
        AnchorPoint = Vector2.new(0.5, below and 0 or 1),
        Position = UDim2.fromOffset(x, y),
        Size = UDim2.fromOffset(w, h),
        BackgroundColor3 = T.Menu,
        BackgroundTransparency = 0.62,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        ZIndex = 2,
    }, Overlay)
    round(popup, 10)
    hairline(popup, 0.72)
    local sc = new("UIScale", { Scale = 0.96 }, popup)

    local scroll = new("ScrollingFrame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 3,
        ScrollBarImageColor3 = T.Muted,
        CanvasSize = UDim2.new(),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
    }, popup)
    new("UIPadding", {
        PaddingTop = UDim.new(0, pad), PaddingBottom = UDim.new(0, pad),
        PaddingLeft = UDim.new(0, pad), PaddingRight = UDim.new(0, pad),
    }, scroll)
    new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }, scroll)

    for i, opt in ipairs(options) do
        local isSel = (i == selected)
        local item = new("TextButton", {
            Size = UDim2.new(1, 0, 0, rowH),
            BackgroundColor3 = T.Accent,
            BackgroundTransparency = isSel and 0.82 or 1,
            Text = "",
            AutoButtonColor = false,
            BorderSizePixel = 0,
            LayoutOrder = i,
        }, scroll)
        round(item, 6)

        label(item, opt, UDim2.fromOffset(10, 0), UDim2.new(1, -34, 1, 0), {
            font = isSel and F.Bold or F.Medium,
            truncate = Enum.TextTruncate.AtEnd,
        })

        if isSel then
            local ic = makeIcon(item, "check", 12, T.AccentHi)
            ic.Frame.Position = UDim2.new(1, -22, 0.5, -6)
        end

        item.MouseEnter:Connect(function()
            tween(item, { BackgroundTransparency = 0.78 }, 0.08)
        end)
        item.MouseLeave:Connect(function()
            tween(item, { BackgroundTransparency = isSel and 0.82 or 1 }, 0.12)
        end)
        item.Activated:Connect(function()
            closeDropdown(false)
            onSelect(opt, i)
        end)
    end

    activePopup = popup
    Overlay.Visible = true
    tween(popup, { BackgroundTransparency = 0.38 }, 0.16)
    tween(sc, { Scale = 1 }, 0.18)
end

local function dropdown(parent, pos, size, options, initial, onChange)
    local btn = new("TextButton", {
        Position = pos,
        Size = size,
        BackgroundColor3 = T.White,
        BackgroundTransparency = 0.92,
        Text = "",
        AutoButtonColor = false,
        BorderSizePixel = 0,
    }, parent)
    round(btn, 8)
    local st = hairline(btn, 0.88)

    local txt = label(btn, initial, UDim2.fromOffset(10, 0), UDim2.new(1, -28, 1, 0), {
        font = F.Medium,
        truncate = Enum.TextTruncate.AtEnd,
    })
    local chev = makeIcon(btn, "chevron", 10, T.Muted)
    chev.Frame.Position = UDim2.new(1, -18, 0.5, -5)

    local value = initial

    btn.MouseEnter:Connect(function()
        tween(btn, { BackgroundTransparency = 0.87 }, 0.12)
        tween(st, { Color = T.Accent, Transparency = 0.5 }, 0.12)
    end)
    btn.MouseLeave:Connect(function()
        tween(btn, { BackgroundTransparency = 0.92 }, 0.15)
        tween(st, { Color = T.White, Transparency = 0.88 }, 0.15)
    end)

    btn.Activated:Connect(function()
        openDropdown(btn, options, table.find(options, value), function(opt)
            value = opt
            txt.Text = opt
            onChange(opt)
        end)
    end)

    return {
        Button = btn,
        Set = function(v)
            value = v
            txt.Text = v
        end,
        Get = function()
            return value
        end,
    }
end

local TOAST_H, TOAST_GAP = 48, 8
local toasts = {}
local KIND = {
    info = { color = T.AccentHi, icon = "info" },
    success = { color = T.Success, icon = "check" },
    warn = { color = T.Warning, icon = "warn" },
    error = { color = T.Danger, icon = "close" },
}

local function layoutToasts()
    for i, item in ipairs(toasts) do
        if item.alive then
            tween(item.frame, { Position = UDim2.fromOffset(0, (i - 1) * (TOAST_H + TOAST_GAP)) }, 0.22)
        end
    end
end

local function dismiss(item)
    if not item.alive then
        return
    end
    item.alive = false
    local pos = item.frame.Position
    tween(item.frame, { GroupTransparency = 1, Position = pos - UDim2.fromOffset(0, 12) }, 0.2)
    local idx = table.find(toasts, item)
    if idx then
        table.remove(toasts, idx)
    end
    layoutToasts()
    task.delay(0.22, function()
        if item.frame then
            item.frame:Destroy()
        end
    end)
end

local function notify(text, kind)
    kind = KIND[kind] and kind or "info"
    local meta = KIND[kind]
    while #toasts >= 4 do
        dismiss(toasts[1])
    end

    local frame = new("CanvasGroup", {
        Size = UDim2.fromOffset(340, TOAST_H),
        BackgroundColor3 = T.Menu,
        BackgroundTransparency = 0.12,
        GroupTransparency = 1,
        BorderSizePixel = 0,
        Active = true,
    }, ToastHost)
    round(frame, 12)
    hairline(frame, 0.82)

    local accent = new("Frame", {
        Position = UDim2.fromOffset(8, 10),
        Size = UDim2.fromOffset(3, TOAST_H - 20),
        BackgroundColor3 = meta.color,
        BorderSizePixel = 0,
    }, frame)
    round(accent, 2)

    local ic = makeIcon(frame, meta.icon, 16, meta.color)
    ic.Frame.Position = UDim2.fromOffset(20, 16)
    label(frame, text, UDim2.fromOffset(44, 0), UDim2.new(1, -80, 1, 0), {
        font = F.Medium,
        size = 13,
        truncate = Enum.TextTruncate.AtEnd,
    })

    local item = { alive = true, frame = frame }
    local close = new("TextButton", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -8, 0.5, 0),
        Size = UDim2.fromOffset(22, 22),
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        ZIndex = 2,
    }, frame)
    local xic = makeIcon(close, "close", 10, T.Muted)
    xic.Frame.Position = UDim2.new(0.5, -5, 0.5, -5)
    close.Activated:Connect(function()
        dismiss(item)
    end)

    table.insert(toasts, item)
    local y = (#toasts - 1) * (TOAST_H + TOAST_GAP)
    frame.Position = UDim2.fromOffset(0, y - 14)
    tween(frame, { Position = UDim2.fromOffset(0, y), GroupTransparency = 0 }, 0.26)
    task.delay(4, function()
        dismiss(item)
    end)
end

local function setStatus(text, kind)
    notify(text, kind)
end

local dialogBusy = false
local dialogGen = 0
local dialogFinish = function() end

local Dimmer = new("TextButton", {
    Size = UDim2.fromScale(1, 1),
    BackgroundColor3 = Color3.new(0, 0, 0),
    BackgroundTransparency = 1,
    Text = "",
    AutoButtonColor = false,
    BorderSizePixel = 0,
    ZIndex = 1,
}, DialogHost)

local DialogCard = new("CanvasGroup", {
    AnchorPoint = Vector2.new(0.5, 0.5),
    Size = UDim2.fromOffset(348, 172),
    BackgroundColor3 = T.Window,
    BackgroundTransparency = 0.04,
    BorderSizePixel = 0,
    ZIndex = 2,
    Active = true,
}, DialogHost)
round(DialogCard, 14)
hairline(DialogCard, 0.8)
local DialogScale = new("UIScale", { Scale = 1 }, DialogCard)

local DialogTitle = label(DialogCard, "Confirm", UDim2.fromOffset(18, 16), UDim2.new(1, -36, 0, 22), {
    font = F.Bold,
    size = 16,
})
local DialogBody = label(DialogCard, "", UDim2.fromOffset(18, 42), UDim2.fromOffset(312, 68), {
    color = T.Muted,
    size = 13,
    wrap = true,
    yalign = Enum.TextYAlignment.Top,
})
local DialogCancel = button(DialogCard, "Cancel", UDim2.fromOffset(16, 124), UDim2.fromOffset(150, 32), "secondary")
local DialogConfirm = button(DialogCard, "Confirm", UDim2.fromOffset(182, 124), UDim2.fromOffset(150, 32), "danger")

local function confirm(opts)
    if dialogBusy then
        return false
    end
    closeDropdown(true)
    dialogBusy = true
    dialogGen += 1
    local gen = dialogGen
    local event = Instance.new("BindableEvent")

    DialogTitle.Text = opts.title or "Confirm"
    DialogBody.Text = opts.body or ""
    btnText(DialogConfirm, opts.confirmText or "Confirm")
    setButtonStyle(DialogConfirm, opts.danger and "danger" or "primary")

    local p, s = MainFrame.AbsolutePosition, MainFrame.AbsoluteSize
    DialogCard.Position = UDim2.fromOffset(p.X + s.X / 2, p.Y + s.Y / 2)
    DialogHost.Visible = true
    Dimmer.BackgroundTransparency = 1
    DialogCard.GroupTransparency = 1
    DialogScale.Scale = 0.96
    tween(Dimmer, { BackgroundTransparency = 0.45 }, 0.2)
    tween(DialogCard, { GroupTransparency = 0 }, 0.2)
    tween(DialogScale, { Scale = 1 }, 0.22)

    dialogFinish = function(value)
        if gen ~= dialogGen then
            return
        end
        dialogGen += 1
        tween(Dimmer, { BackgroundTransparency = 1 }, 0.16)
        tween(DialogCard, { GroupTransparency = 1 }, 0.16)
        tween(DialogScale, { Scale = 0.96 }, 0.16)
        task.delay(0.18, function()
            DialogHost.Visible = false
            dialogBusy = false
            event:Fire(value)
        end)
    end

    local value = event.Event:Wait()
    event:Destroy()
    return value
end

Dimmer.Activated:Connect(function()
    dialogFinish(false)
end)
DialogCancel.Activated:Connect(function()
    dialogFinish(false)
end)
DialogConfirm.Activated:Connect(function()
    dialogFinish(true)
end)

--==============================================================================
-- 6. SHELL
--==============================================================================

local Sidebar = new("Frame", {
    Name = "Sidebar",
    Size = UDim2.new(0, SIDEBAR_W, 1, 0),
    BackgroundColor3 = T.Dark,
    BackgroundTransparency = 0.55,
    BorderSizePixel = 0,
}, MainFrame)

new("Frame", {
    Size = UDim2.new(0, 1, 1, 0),
    Position = UDim2.new(1, -1, 0, 0),
    BackgroundColor3 = T.White,
    BackgroundTransparency = 0.92,
    BorderSizePixel = 0,
}, Sidebar)

local DragStrip = new("Frame", {
    Size = UDim2.new(1, 0, 0, 92),
    BackgroundTransparency = 1,
    Active = true,
}, Sidebar)

local function trafficLight(x, color)
    local b = new("TextButton", {
        Position = UDim2.fromOffset(x, 14),
        Size = UDim2.fromOffset(12, 12),
        BackgroundColor3 = color,
        Text = "",
        AutoButtonColor = false,
        BorderSizePixel = 0,
    }, Sidebar)
    round(b, 6)
    b.MouseEnter:Connect(function() tween(b, { BackgroundTransparency = 0.25 }, 0.1) end)
    b.MouseLeave:Connect(function() tween(b, { BackgroundTransparency = 0 }, 0.1) end)
    return b
end
local CloseDot = trafficLight(14, Color3.fromRGB(255, 95, 87))
local HideDot = trafficLight(32, Color3.fromRGB(254, 188, 46))
local CenterDot = trafficLight(50, Color3.fromRGB(40, 200, 64))

local logo = new("Frame", {
    Position = UDim2.fromOffset(14, 40),
    Size = UDim2.fromOffset(28, 28),
    BackgroundColor3 = T.Accent,
    BorderSizePixel = 0,
}, DragStrip)
round(logo, 8)
local mark = makeIcon(logo, "mark", 16, T.White)
mark.Frame.Position = UDim2.new(0.5, -8, 0.5, -8)

local TitleLabel = label(DragStrip, "Haruko", UDim2.fromOffset(50, 44), UDim2.fromOffset(0, 18), {
    font = F.Bold,
    size = 15,
    autosize = Enum.AutomaticSize.X,
    yalign = Enum.TextYAlignment.Top,
})
local VersionLabel = label(DragStrip, VERSION, UDim2.fromOffset(112, 44), UDim2.fromOffset(0, 18), {
    color = T.Muted,
    size = 11,
    autosize = Enum.AutomaticSize.X,
    yalign = Enum.TextYAlignment.Top,
})
local function placeVersion()
    local w = TitleLabel.TextBounds.X
    if w < 1 then
        w = TitleLabel.AbsoluteSize.X
    end
    VersionLabel.Position = UDim2.fromOffset(50 + w + 6, 44)
end
TitleLabel:GetPropertyChangedSignal("TextBounds"):Connect(placeVersion)
task.defer(placeVersion)

local TabList = new("Frame", {
    Position = UDim2.fromOffset(0, 100),
    Size = UDim2.new(1, 0, 1, -170),
    BackgroundTransparency = 1,
}, Sidebar)
new("UIListLayout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder }, TabList)
new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, TabList)

new("Frame", {
    Position = UDim2.new(0, 14, 1, -66),
    Size = UDim2.new(1, -28, 0, 1),
    BackgroundColor3 = T.White,
    BackgroundTransparency = 0.92,
    BorderSizePixel = 0,
}, Sidebar)

local FooterDot = new("Frame", {
    Position = UDim2.new(0, 16, 1, -50),
    Size = UDim2.fromOffset(8, 8),
    BackgroundColor3 = T.Muted,
    BorderSizePixel = 0,
}, Sidebar)
round(FooterDot, 4)
local FooterText = label(Sidebar, "Tour idle", UDim2.new(0, 32, 1, -56), UDim2.new(1, -40, 0, 20), {
    color = T.Muted,
    size = 12,
    font = F.Medium,
})
label(Sidebar, "RightShift: hide / show", UDim2.new(0, 16, 1, -34), UDim2.new(1, -24, 0, 24), {
    color = T.Muted,
    size = 11,
})

local Topbar = new("Frame", {
    Position = UDim2.fromOffset(SIDEBAR_W, 0),
    Size = UDim2.new(1, -SIDEBAR_W, 0, 56),
    BackgroundTransparency = 1,
    Active = true,
}, MainFrame)
local PageTitle = label(Topbar, "", UDim2.fromOffset(16, 10), UDim2.new(1, -32, 0, 22), { font = F.Bold, size = 18 })
local PageSubtitle = label(Topbar, "", UDim2.fromOffset(16, 33), UDim2.new(1, -32, 0, 16), { color = T.Muted, size = 12 })
new("Frame", {
    Position = UDim2.new(0, 16, 1, -1),
    Size = UDim2.new(1, -32, 0, 1),
    BackgroundColor3 = T.White,
    BackgroundTransparency = 0.92,
    BorderSizePixel = 0,
}, Topbar)

local Content = new("Frame", {
    Position = UDim2.fromOffset(SIDEBAR_W + 16, 62),
    Size = UDim2.fromOffset(PAGE_W, PAGE_H),
    BackgroundTransparency = 1,
    ClipsDescendants = true,
}, MainFrame)

local PAGE_INFO = {
    General = { "General", "Modules you can toggle and bind" },
    Objects = { "Objects", "Pick objects in the world and set an action for each" },
    Tour = { "Tour", "Defaults for new objects and the automatic tour" },
    Presets = { "Presets", "Back up or share your lists" },
    Settings = { "Settings", "Window material and background blur" },
}

local pages, tabs = {}, {}
local currentPage
local pageToken = 0

local function showPage(name, instant)
    if currentPage == name then
        return
    end
    closeDropdown(true)
    pageToken += 1
    local token = pageToken
    local prev = currentPage and pages[currentPage]
    currentPage = name

    for tabName, tab in pairs(tabs) do
        local active = (tabName == name)
        tween(tab.button, {
            BackgroundColor3 = T.Accent,
            BackgroundTransparency = active and 0.1 or 1,
        }, 0.2)
        tween(tab.text, { TextColor3 = active and T.Text or T.Muted }, 0.2)
        tab.icon.SetColor(active and T.Text or T.Muted, true)
    end

    PageTitle.Text = PAGE_INFO[name][1]
    PageSubtitle.Text = PAGE_INFO[name][2]

    local page = pages[name]
    if prev then
        tween(prev, { Position = UDim2.fromOffset(0, 8) }, 0.12)
        task.delay(0.13, function()
            if token == pageToken and prev ~= page then
                prev.Visible = false
                prev.Position = UDim2.fromOffset(0, 0)
            end
        end)
    end

    page.Visible = true
    if instant then
        page.Position = UDim2.fromOffset(0, 0)
    else
        page.Position = UDim2.fromOffset(0, 10)
        tween(page, { Position = UDim2.fromOffset(0, 0) }, 0.24)
    end
end

local function addPage(name, iconKind, order)
    local btn = new("TextButton", {
        Size = UDim2.new(1, 0, 0, 34),
        BackgroundColor3 = T.Accent,
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        BorderSizePixel = 0,
        LayoutOrder = order,
    }, TabList)
    round(btn, 8)

    local icon = makeIcon(btn, iconKind, 16, T.Muted)
    icon.Frame.Position = UDim2.new(0, 12, 0.5, -8)
    local text = label(btn, name, UDim2.fromOffset(38, 0), UDim2.new(1, -44, 1, 0), { font = F.Medium, color = T.Muted })
    tabs[name] = { button = btn, text = text, icon = icon }

    btn.MouseEnter:Connect(function()
        if currentPage ~= name then
            tween(btn, { BackgroundColor3 = T.White, BackgroundTransparency = 0.94 }, 0.12)
        end
    end)
    btn.MouseLeave:Connect(function()
        if currentPage ~= name then
            tween(btn, { BackgroundTransparency = 1 }, 0.15)
        else
            tween(btn, { BackgroundColor3 = T.Accent, BackgroundTransparency = 0.1 }, 0.15)
        end
    end)
    btn.Activated:Connect(function()
        btn.BackgroundColor3 = T.Accent
        showPage(name)
    end)

    local page = new("Frame", {
        Name = name,
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Visible = false,
    }, Content)
    pages[name] = page
    return page
end

local GeneralPage = addPage("General", "grid", 1)
local ObjectsPage = addPage("Objects", "cube", 2)
local TourPage = addPage("Tour", "target", 3)
local PresetsPage = addPage("Presets", "lines", 4)
local SettingsPage = addPage("Settings", "gear", 5)

--==============================================================================
-- 7. MODULES & GENERAL
--==============================================================================

local function keyLabel(code)
    if typeof(code) ~= "EnumItem" then
        return "None"
    end
    return code.Name:gsub("^Left", "L"):gsub("^Right", "R")
end

local function setTeleport(on)
    motion.teleportOn = on
    if on then
        if pickKind == "add" then
            setPickMode(false)
        end
        pickKind = "teleport"
        notify("Click an object to teleport", "info")
    else
        if pickKind == "teleport" then
            pickKind = nil
        end
        if hoverHighlight then
            hoverHighlight.Adornee = nil
        end
    end
end

local MOD_HEAD = 62
local colGap = 8
local colW = math.floor((PAGE_W - colGap - 12) / 2)

local GeneralScroll = new("ScrollingFrame", {
    Size = UDim2.fromScale(1, 1),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ScrollBarThickness = 3,
    ScrollBarImageColor3 = T.Accent,
    CanvasSize = UDim2.new(),
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
}, GeneralPage)

local moduleHolder = new("Frame", {
    Size = UDim2.new(1, -4, 0, 0),
    AutomaticSize = Enum.AutomaticSize.Y,
    BackgroundTransparency = 1,
}, GeneralScroll)
new("UIPadding", { PaddingBottom = UDim.new(0, 8) }, moduleHolder)

local function column(x)
    local f = new("Frame", {
        Position = UDim2.fromOffset(x, 0),
        Size = UDim2.fromOffset(colW, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
    }, moduleHolder)
    new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, f)
    return f
end

local leftCol = column(0)
local rightCol = column(colW + colGap)

local function buildModule(parent, order, def)
    local opened = false
    local bodyH = def.body or 0
    local cardFrame = new("Frame", {
        Size = UDim2.new(1, 0, 0, MOD_HEAD),
        BackgroundColor3 = T.White,
        BackgroundTransparency = 0.93,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        LayoutOrder = order,
    }, parent)
    round(cardFrame, 10)
    hairline(cardFrame, 0.92)

    local head = new("Frame", {
        Size = UDim2.new(1, 0, 0, MOD_HEAD),
        BackgroundTransparency = 1,
    }, cardFrame)

    local textX = 12
    local chev
    if bodyH > 0 then
        chev = makeIcon(head, "chevron", 12, T.Muted)
        chev.Frame.Position = UDim2.fromOffset(10, 25)
        chev.SetFacing("right", false)
        textX = 28
    end

    local icon = makeIcon(head, def.icon, 16, T.Text)
    icon.Frame.Position = UDim2.fromOffset(textX, 23)
    local nameX = textX + 22
    label(head, def.name, UDim2.fromOffset(nameX, 12), UDim2.new(1, -nameX - 118, 0, 18), {
        font = F.Bold,
        size = 13,
        truncate = Enum.TextTruncate.AtEnd,
    })
    label(head, def.desc, UDim2.fromOffset(nameX, 32), UDim2.new(1, -nameX - 118, 0, 16), {
        color = T.Muted,
        size = 11,
        truncate = Enum.TextTruncate.AtEnd,
    })

    if bodyH > 0 then
        local hit = new("TextButton", {
            Size = UDim2.new(1, -112, 1, 0),
            BackgroundTransparency = 1,
            Text = "",
            AutoButtonColor = false,
        }, head)
        hit.MouseEnter:Connect(function()
            tween(cardFrame, { BackgroundTransparency = 0.9 }, 0.12)
        end)
        hit.MouseLeave:Connect(function()
            tween(cardFrame, { BackgroundTransparency = 0.93 }, 0.15)
        end)
        hit.Activated:Connect(function()
            opened = not opened
            tween(cardFrame, { Size = UDim2.new(1, 0, 0, opened and (MOD_HEAD + bodyH) or MOD_HEAD) }, 0.24)
            chev.SetFacing(opened and "down" or "right", true)
        end)
    end

    local chip = new("TextButton", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -54, 0.5, 0),
        Size = UDim2.fromOffset(48, 22),
        BackgroundColor3 = T.White,
        BackgroundTransparency = 0.9,
        Text = "None",
        TextColor3 = T.Muted,
        Font = F.Medium,
        TextSize = 11,
        AutoButtonColor = false,
        TextTruncate = Enum.TextTruncate.AtEnd,
        ZIndex = 4,
        BorderSizePixel = 0,
    }, head)
    round(chip, 6)

    local sw = switch(head, UDim2.new(1, -46, 0.5, -12), false, function(on)
        def.onToggle(on)
    end)

    chip.Activated:Connect(function()
        if listening == def.id then
            listening = nil
            chip.Text = keyLabel(modUi[def.id].bind)
            chip.TextColor3 = T.Muted
            return
        end
        if listening and modUi[listening] then
            local prev = modUi[listening]
            prev.chip.Text = keyLabel(prev.bind)
            prev.chip.TextColor3 = T.Muted
        end
        listening = def.id
        chip.Text = "..."
        chip.TextColor3 = T.AccentHi
    end)

    if bodyH > 0 then
        local body = new("Frame", {
            Position = UDim2.fromOffset(0, MOD_HEAD),
            Size = UDim2.new(1, 0, 0, bodyH),
            BackgroundTransparency = 1,
        }, cardFrame)
        def.build(body)
    end

    modUi[def.id] = { bind = nil, chip = chip, switch = sw, onToggle = def.onToggle }
end

local moduleSpecs = {
    {
        id = "speed",
        name = "Speed",
        desc = "Boost horizontal movement",
        icon = "fast",
        body = 78,
        onToggle = function(on)
            motion.speedOn = on
        end,
        build = function(body)
            label(body, "Studs / s", UDim2.fromOffset(12, 10), UDim2.fromOffset(120, 20), { font = F.Medium, size = 12 })
            local box = input(body, UDim2.new(1, -72, 0, 6), UDim2.fromOffset(60, 26), tostring(motion.speed), "300")
            box.TextXAlignment = Enum.TextXAlignment.Center
            local sl = slider(body, UDim2.fromOffset(12, 48), colW - 24, 16, 500, motion.speed, false, function(v)
                motion.speed = math.floor(v + 0.5)
                box.Text = tostring(motion.speed)
            end)
            box.FocusLost:Connect(function()
                local v = tonumber(box.Text)
                if v and v > 0 then
                    motion.speed = math.clamp(math.floor(v + 0.5), 16, 500)
                    sl.Set(motion.speed)
                end
                box.Text = tostring(motion.speed)
            end)
        end,
    },
    {
        id = "fly",
        name = "Fly",
        desc = "Hover, or glide downward",
        icon = "fly",
        body = 156,
        onToggle = function(on)
            setFly(on)
        end,
        build = function(body)
            label(body, "Mode", UDim2.fromOffset(12, 4), UDim2.fromOffset(80, 16), { color = T.Muted, size = 12 })
            segmented(body, UDim2.fromOffset(12, 22), UDim2.fromOffset(colW - 24, 28), { "Default", "Glide" }, motion.flyMode, function(v)
                motion.flyMode = v
            end)
            label(body, "Speed", UDim2.fromOffset(12, 58), UDim2.fromOffset(80, 16), { font = F.Medium, size = 12 })
            local speedRead = label(body, tostring(motion.flySpeed), UDim2.new(1, -72, 0, 58), UDim2.fromOffset(60, 16), {
                color = T.Muted,
                size = 12,
                align = Enum.TextXAlignment.Right,
            })
            slider(body, UDim2.fromOffset(12, 80), colW - 24, 16, 300, motion.flySpeed, false, function(v)
                motion.flySpeed = math.floor(v + 0.5)
                speedRead.Text = tostring(motion.flySpeed)
            end)
            label(body, "Sink", UDim2.fromOffset(12, 100), UDim2.fromOffset(80, 16), { font = F.Medium, size = 12 })
            local sinkRead = label(body, tostring(motion.glideSink), UDim2.new(1, -72, 0, 100), UDim2.fromOffset(60, 16), {
                color = T.Muted,
                size = 12,
                align = Enum.TextXAlignment.Right,
            })
            slider(body, UDim2.fromOffset(12, 122), colW - 24, 2, 60, motion.glideSink, false, function(v)
                motion.glideSink = math.floor(v + 0.5)
                sinkRead.Text = tostring(motion.glideSink)
            end)
        end,
    },
    {
        id = "teleport",
        name = "Teleport",
        desc = "Click a world object once",
        icon = "target",
        body = 128,
        onToggle = function(on)
            setTeleport(on)
        end,
        build = function(body)
            label(body, "Origin", UDim2.fromOffset(12, 6), UDim2.fromOffset(120, 16), { color = T.Muted, size = 12 })
            dropdown(body, UDim2.fromOffset(12, 24), UDim2.fromOffset(colW - 24, 28), { "Start", "Center", "End" }, motion.tpOrigin, function(v)
                motion.tpOrigin = v
            end)
            label(body, "Offset", UDim2.fromOffset(12, 60), UDim2.fromOffset(80, 16), { color = T.Muted, size = 12 })
            local box = input(body, UDim2.new(1, -84, 0, 56), UDim2.fromOffset(72, 26), fmt(motion.tpOffset), "3")
            box.TextXAlignment = Enum.TextXAlignment.Center
            box.FocusLost:Connect(function()
                local v = tonumber(box.Text)
                if v then
                    motion.tpOffset = v
                end
                box.Text = fmt(motion.tpOffset)
            end)
            label(body, "Arms a world click, then turns off.", UDim2.fromOffset(12, 92), UDim2.new(1, -24, 0, 28), {
                color = T.Muted,
                size = 11,
                wrap = true,
            })
        end,
    },
    {
        id = "click",
        name = "Click",
        desc = "Repeat a click off this window",
        icon = "click",
        body = 96,
        onToggle = function(on)
            motion.clickOn = on
        end,
        build = function(body)
            label(body, "Interval", UDim2.fromOffset(12, 8), UDim2.fromOffset(80, 16), { font = F.Medium, size = 12 })
            local read = label(body, fmt(motion.clickInterval) .. "s", UDim2.new(1, -72, 0, 8), UDim2.fromOffset(60, 16), {
                color = T.Muted,
                size = 12,
                align = Enum.TextXAlignment.Right,
            })
            slider(body, UDim2.fromOffset(12, 36), colW - 24, 0.05, 1, motion.clickInterval, true, function(v)
                motion.clickInterval = math.floor(v * 100 + 0.5) / 100
                read.Text = fmt(motion.clickInterval) .. "s"
            end)
            label(body, "Clicks the bottom-left corner, outside this window.", UDim2.fromOffset(12, 58), UDim2.new(1, -24, 0, 32), {
                color = T.Muted,
                size = 11,
                wrap = true,
            })
        end,
    },
    {
        id = "noclip",
        name = "Noclip",
        desc = "Walk through parts",
        icon = "noclip",
        body = 0,
        onToggle = function(on)
            setNoclip(on)
        end,
    },
}

for i, def in ipairs(moduleSpecs) do
    local col = (i % 2 == 1) and leftCol or rightCol
    buildModule(col, math.ceil(i / 2), def)
end

--==============================================================================
-- 8. OBJECTS, TOUR, PRESETS, SETTINGS
--==============================================================================

local AddBtn = button(ObjectsPage, "Add", UDim2.fromOffset(0, 0), UDim2.fromOffset(104, 34), "primary", "plus")
segmented(ObjectsPage, UDim2.fromOffset(112, 0), UDim2.fromOffset(128, 34), { "Part", "Model" }, pickType, function(v)
    pickType = v
end)
label(ObjectsPage, "X-ray", UDim2.fromOffset(258, 0), UDim2.fromOffset(40, 34), { color = T.Muted, size = 12 })
switch(ObjectsPage, UDim2.fromOffset(298, 5), xray, function(v)
    xray = v
end)
label(ObjectsPage, "Show saved", UDim2.new(1, -140, 0, 0), UDim2.fromOffset(90, 34), {
    color = T.Muted,
    size = 12,
    align = Enum.TextXAlignment.Right,
})
switch(ObjectsPage, UDim2.new(1, -42, 0, 5), false, function(v)
    espOn = v
    refreshESP()
end)

local HintLabel = label(ObjectsPage, "Press Add, then click an object in the world.",
    UDim2.fromOffset(2, 40), UDim2.fromOffset(400, 16), { color = T.Muted, size = 12 })
local CountLabel = label(ObjectsPage, "0 objects", UDim2.new(1, -140, 0, 40), UDim2.fromOffset(140, 16), {
    color = T.Muted,
    size = 12,
    align = Enum.TextXAlignment.Right,
})

local ListCard = card(ObjectsPage, UDim2.fromOffset(0, 62), UDim2.fromOffset(PAGE_W, PAGE_H - 62))
local ListNameBox = input(ListCard, UDim2.fromOffset(12, 12), UDim2.fromOffset(236, 32), "", "List name")
ListNameBox.Font = F.Bold
local ListArrow = button(ListCard, "", UDim2.fromOffset(254, 12), UDim2.fromOffset(32, 32), "secondary", "chevron")
local NewListBtn = button(ListCard, "New list", UDim2.fromOffset(294, 12), UDim2.fromOffset(120, 32), "secondary", "plus")
local DelListBtn = button(ListCard, "Delete", UDim2.fromOffset(422, 12), UDim2.fromOffset(110, 32), "danger", "close")

local ListScroll = new("ScrollingFrame", {
    Position = UDim2.fromOffset(12, 56),
    Size = UDim2.new(1, -24, 1, -68),
    BackgroundColor3 = T.Dark,
    BackgroundTransparency = 0.6,
    BorderSizePixel = 0,
    ScrollBarThickness = 3,
    ScrollBarImageColor3 = T.Accent,
    CanvasSize = UDim2.new(),
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
}, ListCard)
round(ListScroll, 10)
hairline(ListScroll, 0.94)
new("UIListLayout", { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }, ListScroll)
new("UIPadding", {
    PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6),
    PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 9),
}, ListScroll)

local EmptyLabel = label(ListScroll, "This list is empty.\nPress Add and click an object in the world.",
    UDim2.new(), UDim2.new(1, 0, 0, 70),
    { color = T.Muted, size = 13, wrap = true, align = Enum.TextXAlignment.Center })

local DefaultsCard = card(TourPage, UDim2.fromOffset(0, 0), UDim2.fromOffset(PAGE_W, 176),
    "New object defaults", "Applied to objects you add. Every object can override them.")
local col3 = (PAGE_W - 24 - 16) / 3

label(DefaultsCard, "Action", UDim2.fromOffset(12, 50), UDim2.fromOffset(150, 14), { color = T.Muted, size = 12 })
dropdown(DefaultsCard, UDim2.fromOffset(12, 66), UDim2.fromOffset(col3, 32), ACTIONS, D.action, function(v)
    D.action = v
end)
label(DefaultsCard, "Speed (studs/s)", UDim2.fromOffset(12 + col3 + 8, 50), UDim2.fromOffset(150, 14), { color = T.Muted, size = 12 })
local DefSpeedBox = input(DefaultsCard, UDim2.fromOffset(12 + col3 + 8, 66), UDim2.fromOffset(100, 32), fmt(D.speed), "40")
label(DefaultsCard, "Offset (studs)", UDim2.fromOffset(12 + col3 + 116, 50), UDim2.fromOffset(150, 14), { color = T.Muted, size = 12 })
local DefOffsetBox = input(DefaultsCard, UDim2.fromOffset(12 + col3 + 116, 66), UDim2.fromOffset(100, 32), fmt(D.offset), "3")
local ApplyAllBtn = button(DefaultsCard, "Apply to all", UDim2.fromOffset(PAGE_W - 144, 66), UDim2.fromOffset(132, 32), "secondary")

for i, axis in ipairs({ "x", "y", "z" }) do
    local x = 12 + (i - 1) * (col3 + 8)
    label(DefaultsCard, axis:upper() .. " axis" .. (axis == "y" and " (height)" or ""),
        UDim2.fromOffset(x, 108), UDim2.fromOffset(150, 14), { color = T.Muted, size = 12 })
    dropdown(DefaultsCard, UDim2.fromOffset(x, 124), UDim2.fromOffset(col3, 32),
        { "Start", "Center", "End" }, D.tp[axis], function(v)
            D.tp[axis] = v
        end)
end

local TourCard = card(TourPage, UDim2.fromOffset(0, 186), UDim2.fromOffset(PAGE_W, PAGE_H - 186),
    "Auto tour", "Runs each object's own action in order")
label(TourCard, "Order", UDim2.fromOffset(12, 50), UDim2.fromOffset(150, 14), { color = T.Muted, size = 12 })
dropdown(TourCard, UDim2.fromOffset(12, 66), UDim2.fromOffset(220, 32),
    { "Forward", "Reverse", "Ping-pong", "Random" }, tour.order, function(v)
        tour.order = v
    end)
label(TourCard, "Loop forever", UDim2.fromOffset(252, 66), UDim2.fromOffset(120, 32), { font = F.Medium })
switch(TourCard, UDim2.fromOffset(PAGE_W - 54, 70), tour.loop, function(v)
    tour.loop = v
end)
label(TourCard, "Default pause between steps", UDim2.fromOffset(12, 110), UDim2.fromOffset(280, 20), { font = F.Medium })
label(TourCard, "sec", UDim2.new(1, -52, 0, 108), UDim2.fromOffset(40, 24), {
    color = T.Muted,
    size = 12,
    align = Enum.TextXAlignment.Right,
})
local IntervalBox = input(TourCard, UDim2.new(1, -128, 0, 108), UDim2.fromOffset(72, 24), fmt(tour.interval), "0.5")
IntervalBox.TextXAlignment = Enum.TextXAlignment.Center
local IntervalSlider = slider(TourCard, UDim2.fromOffset(14, 148), PAGE_W - 28, 0.05, 5, tour.interval, true, function(v)
    tour.interval = math.floor(v * 100 + 0.5) / 100
    IntervalBox.Text = fmt(tour.interval)
end)
local TourProgress = label(TourCard, "Idle", UDim2.fromOffset(14, 168), UDim2.fromOffset(PAGE_W - 28, 16), {
    color = T.Muted,
    size = 12,
    truncate = Enum.TextTruncate.AtEnd,
})
local StartBtn = button(TourCard, "Start tour", UDim2.fromOffset(12, PAGE_H - 186 - 48), UDim2.fromOffset(PAGE_W - 24, 36), "primary")
BtnApi[StartBtn].label.Font = F.Bold

local exportScope = "Current list"
local ExportCard = card(PresetsPage, UDim2.fromOffset(0, 0), UDim2.fromOffset(PAGE_W, 136),
    "Export", "Copy your lists as JSON or save them to a file")
segmented(ExportCard, UDim2.fromOffset(12, 52), UDim2.fromOffset(240, 30), { "Current list", "All lists" }, exportScope, function(v)
    exportScope = v
end)
local halfW = (PAGE_W - 24 - 8) / 2
local CopyBtn = button(ExportCard, "Copy to clipboard", UDim2.fromOffset(12, 92), UDim2.fromOffset(halfW, 34), "primary")
local SaveBtn = button(ExportCard, "Save to file", UDim2.fromOffset(20 + halfW, 92), UDim2.fromOffset(halfW, 34), "secondary")

local ImportCard = card(PresetsPage, UDim2.fromOffset(0, 146), UDim2.fromOffset(PAGE_W, 170),
    "Import", "Imported lists are added next to your existing ones")
local PasteBtn = button(ImportCard, "Paste from clipboard", UDim2.fromOffset(12, 52), UDim2.fromOffset(halfW, 34), "primary")
local LoadBtn = button(ImportCard, "Load from file", UDim2.fromOffset(20 + halfW, 52), UDim2.fromOffset(halfW, 34), "secondary")
label(ImportCard, "Or paste JSON manually", UDim2.fromOffset(12, 98), UDim2.fromOffset(300, 14), { color = T.Muted, size = 12 })
local JsonBox = input(ImportCard, UDim2.fromOffset(12, 118), UDim2.fromOffset(PAGE_W - 24 - 96, 34), "", "Paste preset JSON here")
JsonBox.TextTruncate = Enum.TextTruncate.AtEnd
local ImportTextBtn = button(ImportCard, "Import", UDim2.fromOffset(PAGE_W - 100, 118), UDim2.fromOffset(88, 34), "secondary")

local CapsLabel = label(PresetsPage, "", UDim2.fromOffset(2, 326), UDim2.fromOffset(PAGE_W, 16), { color = T.Muted, size = 12 })
label(PresetsPage, "Objects are saved by their path in the game plus a fallback position, so a preset works in the same game across sessions.",
    UDim2.fromOffset(2, 346), UDim2.fromOffset(PAGE_W, 32), { color = T.Muted, size = 12, wrap = true })

local AppearanceCard = card(SettingsPage, UDim2.fromOffset(0, 0), UDim2.fromOffset(PAGE_W, 216),
    "Appearance", "Frosted glass window")
label(AppearanceCard, "Background blur", UDim2.fromOffset(14, 54), UDim2.fromOffset(250, 24), { font = F.Medium })
switch(AppearanceCard, UDim2.new(1, -56, 0, 54), settings.blur, function(v)
    settings.blur = v
end)
label(AppearanceCard, "Blur strength", UDim2.fromOffset(14, 96), UDim2.fromOffset(200, 20), { font = F.Medium })
local BlurValue = label(AppearanceCard, "100%", UDim2.new(1, -74, 0, 96), UDim2.fromOffset(60, 20), {
    color = T.Muted,
    size = 12,
    align = Enum.TextXAlignment.Right,
})
slider(AppearanceCard, UDim2.fromOffset(14, 128), PAGE_W - 28, 0.1, 1, settings.blurStrength, false, function(v)
    settings.blurStrength = v
    BlurValue.Text = string.format("%d%%", math.floor(v * 100 + 0.5))
end)
label(AppearanceCard, "Window opacity", UDim2.fromOffset(14, 148), UDim2.fromOffset(200, 20), { font = F.Medium })
local OpacityValue = label(AppearanceCard, "86%", UDim2.new(1, -74, 0, 148), UDim2.fromOffset(60, 20), {
    color = T.Muted,
    size = 12,
    align = Enum.TextXAlignment.Right,
})
slider(AppearanceCard, UDim2.fromOffset(14, 180), PAGE_W - 28, 0.5, 1, settings.opacity, false, function(v)
    settings.opacity = v
    OpacityValue.Text = string.format("%d%%", math.floor(v * 100 + 0.5))
    MainFrame.BackgroundTransparency = 1 - v
end)
label(SettingsPage, "Blur is a depth-of-field pass plus a glass pane fitted to this window. The panel draws above other interfaces. Turn blur off if it looks wrong. The frosted window stays.",
    UDim2.fromOffset(2, 226), UDim2.fromOffset(PAGE_W, 48), { color = T.Muted, size = 12, wrap = true })

--==============================================================================
-- 9. WORLD HELPERS & PICKER
--==============================================================================

local function getPath(obj)
    local path, cur = {}, obj
    while cur and cur ~= game do
        table.insert(path, 1, cur.Name)
        cur = cur.Parent
    end
    return path
end

local function resolvePath(path)
    local cur = game
    for _, name in ipairs(path) do
        cur = cur:FindFirstChild(name)
        if not cur then
            return nil
        end
    end
    return cur
end

local function getBounds(obj)
    local cf, size
    if obj:IsA("BasePart") then
        cf, size = obj.CFrame, obj.Size
    elseif obj:IsA("Model") then
        local ok, boxCf, boxSize = pcall(obj.GetBoundingBox, obj)
        if not ok then
            return nil
        end
        cf, size = boxCf, boxSize
    else
        return nil
    end

    local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector
    local half = Vector3.new(
        (math.abs(r.X) * size.X + math.abs(u.X) * size.Y + math.abs(l.X) * size.Z) / 2,
        (math.abs(r.Y) * size.X + math.abs(u.Y) * size.Y + math.abs(l.Y) * size.Z) / 2,
        (math.abs(r.Z) * size.X + math.abs(u.Z) * size.Y + math.abs(l.Z) * size.Z) / 2
    )
    return cf.Position, half
end

local function axisValue(mode, center, half)
    if mode == "Start" then
        return center - half
    elseif mode == "End" then
        return center + half
    end
    return center
end

local function computeTarget(item)
    if item.origin == "Custom" then
        local c = item.custom
        return Vector3.new(c[1], c[2], c[3])
    end

    local center, half
    local obj = resolvePath(item.path)
    if obj then
        center, half = getBounds(obj)
    end
    if not center and item.pos then
        center = Vector3.new(item.pos[1], item.pos[2], item.pos[3])
        local h = item.half or { 0, 0, 0 }
        half = Vector3.new(h[1] or 0, h[2] or 0, h[3] or 0)
    end
    if not center then
        return nil
    end

    return Vector3.new(
        axisValue(item.tp.x, center.X, half.X),
        axisValue(item.tp.y, center.Y, half.Y),
        axisValue(item.tp.z, center.Z, half.Z)
    ) + Vector3.new(0, item.offset, 0)
end

local function newItem(obj)
    local center, half = getBounds(obj)
    center = center or Vector3.zero
    half = half or Vector3.zero
    return {
        name = obj.Name,
        class = obj.ClassName,
        path = getPath(obj),
        pos = { center.X, center.Y, center.Z },
        half = { half.X, half.Y, half.Z },
        action = D.action,
        speed = D.speed,
        pause = nil,
        pauseWhen = "After",
        origin = "Object",
        tp = { x = D.tp.x, y = D.tp.y, z = D.tp.z },
        offset = D.offset,
        custom = { center.X, center.Y, center.Z },
    }
end

local function makeHighlight(fill, outline, fillTransparency)
    return new("Highlight", {
        FillColor = fill,
        OutlineColor = outline,
        FillTransparency = fillTransparency,
        OutlineTransparency = 0,
        DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
    }, HighlightFolder)
end

local function tryHighlight(fill, outline, transparency)
    local ok, h = pcall(makeHighlight, fill, outline, transparency)
    if ok then
        return h
    end
    return nil
end

hoverHighlight = tryHighlight(T.Accent, T.AccentHi, 0.55)
local previewHighlight = tryHighlight(T.Warning, T.Warning, 0.5)
local espHighlights = {}

function refreshESP()
    for _, h in ipairs(espHighlights) do
        h:Destroy()
    end
    espHighlights = {}
    if not espOn then
        return
    end

    local count = 0
    for _, item in ipairs(currentList().items) do
        if count >= 28 then
            -- Roblox draws about 31 Highlights at once.
            break
        end
        local obj = resolvePath(item.path)
        if obj then
            local h = makeHighlight(T.Success, T.Success, 0.7)
            h.Adornee = obj
            table.insert(espHighlights, h)
            count += 1
        end
    end
end

function setPickMode(on)
    if pickMode == on then
        return
    end
    pickMode = on
    if on then
        if motion.teleportOn then
            motion.teleportOn = false
            if modUi.teleport then
                modUi.teleport.switch.Set(false)
            end
            if pickKind == "teleport" then
                pickKind = nil
            end
        end
        pickKind = "add"
        btnText(AddBtn, "Cancel")
        btnIcon(AddBtn, "close")
        setButtonStyle(AddBtn, "danger")
        HintLabel.Text = xray and "Click an object. X-ray skips invisible and zero-size parts."
            or "Click an object in the world."
    else
        if pickKind == "add" then
            pickKind = nil
        end
        btnText(AddBtn, "Add")
        btnIcon(AddBtn, "plus")
        setButtonStyle(AddBtn, "primary")
        HintLabel.Text = "Press Add, then click an object in the world."
        if not pickKind and hoverHighlight then
            hoverHighlight.Adornee = nil
        end
    end
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function isGhost(part)
    if part.Transparency >= 0.9 then
        return true
    end
    local s = part.Size
    return s.Magnitude < 0.25 or math.min(s.X, s.Y, s.Z) < 0.01
end

local function isOverMainFrame(mousePos)
    if not MainFrame.Visible or MainFrame.GroupTransparency > 0.9 then
        return false
    end
    local pos, size = MainFrame.AbsolutePosition, MainFrame.AbsoluteSize
    return mousePos.X >= pos.X and mousePos.X <= pos.X + size.X
        and mousePos.Y >= pos.Y and mousePos.Y <= pos.Y + size.Y
end

local function getTargetUnderMouse()
    local camera = workspace.CurrentCamera
    if not camera then
        return nil
    end

    local mousePos = UserInputService:GetMouseLocation()
    if isOverMainFrame(mousePos) then
        return nil
    end

    local ray = camera:ViewportPointToRay(mousePos.X, mousePos.Y)
    local ignore = { character }
    for _ = 1, 40 do
        rayParams.FilterDescendantsInstances = ignore
        local result = workspace:Raycast(ray.Origin, ray.Direction * 2000, rayParams)
        if not result then
            return nil
        end
        local inst = result.Instance
        if inst:IsA("Terrain") then
            return nil
        end
        if xray and isGhost(inst) then
            table.insert(ignore, inst)
        elseif pickType == "Model" then
            return inst:FindFirstAncestorOfClass("Model") or inst
        else
            return inst
        end
    end
    return nil
end

local function addObjectToList(obj)
    local list = currentList()
    local key = table.concat(getPath(obj), "/")
    for _, item in ipairs(list.items) do
        if table.concat(item.path, "/") == key then
            setStatus("Already in the list: " .. obj.Name, "warn")
            return false
        end
    end

    local item = newItem(obj)
    table.insert(list.items, item)
    lastAddedItem = item
    refreshList()
    refreshESP()
    setStatus("Added: " .. obj.Name, "success")
    return true
end

table.insert(connections, RunService.RenderStepped:Connect(function()
    if pickKind and hoverHighlight then
        hoverHighlight.Adornee = getTargetUnderMouse()
    end
end))

local HEAD_H, BODY_H = 40, 120

local function buildRow(list, item, index, isNew)
    item.pauseWhen = PAUSE_SET[item.pauseWhen] and item.pauseWhen or "After"
    local open = expanded[item] == true
    local targetH = open and (HEAD_H + BODY_H) or HEAD_H

    local row = new("Frame", {
        Size = UDim2.new(1, 0, 0, isNew and 0 or targetH),
        BackgroundColor3 = T.White,
        BackgroundTransparency = isNew and 1 or 0.93,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        LayoutOrder = index,
    }, ListScroll)
    round(row, 10)
    if isNew then
        tween(row, { Size = UDim2.new(1, 0, 0, targetH), BackgroundTransparency = 0.93 }, 0.3)
    end

    local head = new("TextButton", {
        Size = UDim2.new(1, 0, 0, HEAD_H),
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
    }, row)

    local chev = makeIcon(head, "chevron", 12, T.Muted)
    chev.Frame.Position = UDim2.new(0, 12, 0.5, -6)
    chev.SetFacing(open and "down" or "right", false)

    local chip = new("TextLabel", {
        Position = UDim2.new(0, 32, 0.5, -11),
        Size = UDim2.fromOffset(24, 22),
        BackgroundColor3 = T.Accent,
        BackgroundTransparency = 0.8,
        Text = tostring(index),
        TextColor3 = T.AccentHi,
        Font = F.Bold,
        TextSize = 12,
        BorderSizePixel = 0,
    }, head)
    round(chip, 6)

    label(head, string.format('%s  <font color="rgb(150,157,176)" size="11">%s</font>',
        escapeRich(item.name), escapeRich(item.class or "?")),
        UDim2.fromOffset(64, 0), UDim2.new(1, -330, 1, 0),
        { font = F.Medium, rich = true, truncate = Enum.TextTruncate.AtEnd })

    local summary = label(head, "", UDim2.new(1, -258, 0, 0), UDim2.fromOffset(104, HEAD_H), {
        color = T.Muted,
        size = 12,
        align = Enum.TextXAlignment.Right,
    })

    local function refreshSummary()
        summary.Text = (item.action == "Teleport") and "Teleport"
            or string.format("%s  %s/s", item.action, fmt(item.speed))
    end
    refreshSummary()

    local function mini(text, xFromRight, w, style, iconKind)
        return button(head, text, UDim2.new(1, xFromRight, 0.5, -12), UDim2.fromOffset(w, 24), style, iconKind)
    end
    local upBtn = mini("", -146, 26, "secondary", "chevron")
    local downBtn = mini("", -116, 26, "secondary", "chevron")
    local goBtn = mini("Go", -86, 46, "secondary")
    local delBtn = mini("", -34, 26, "danger", "close")
    BtnApi[upBtn].icon.SetFacing("up")

    local body = new("Frame", {
        Position = UDim2.fromOffset(0, HEAD_H),
        Size = UDim2.new(1, 0, 0, BODY_H),
        BackgroundTransparency = 1,
    }, row)

    local function cap(text, x, y)
        label(body, text, UDim2.fromOffset(x, y), UDim2.fromOffset(140, 14), { color = T.Muted, size = 12 })
    end
    cap("Action", 12, 6)
    cap("Speed", 122, 6)
    cap("Pause (s)", 196, 6)
    cap("When", 262, 6)
    cap("Origin", 360, 6)

    local SpeedBoxI
    local function updateSpeedState()
        local active = item.action ~= "Teleport"
        SpeedBoxI.TextEditable = active
        tween(SpeedBoxI, { TextTransparency = active and 0 or 0.65 }, 0.2)
    end

    dropdown(body, UDim2.fromOffset(12, 22), UDim2.fromOffset(104, 30), ACTIONS, item.action, function(v)
        item.action = v
        refreshSummary()
        updateSpeedState()
    end)
    SpeedBoxI = input(body, UDim2.fromOffset(122, 22), UDim2.fromOffset(68, 30), fmt(item.speed), "40")
    SpeedBoxI.FocusLost:Connect(function()
        local v = tonumber(SpeedBoxI.Text)
        if v and v > 0 then
            item.speed = v
        end
        SpeedBoxI.Text = fmt(item.speed)
        refreshSummary()
    end)
    updateSpeedState()

    local PauseBox = input(body, UDim2.fromOffset(196, 22), UDim2.fromOffset(60, 30),
        item.pause and fmt(item.pause) or "", "off")
    PauseBox.FocusLost:Connect(function()
        local v = tonumber(PauseBox.Text)
        item.pause = (v and v > 0) and v or nil
        PauseBox.Text = item.pause and fmt(item.pause) or ""
    end)
    dropdown(body, UDim2.fromOffset(262, 22), UDim2.fromOffset(92, 30), { "Before", "After" }, item.pauseWhen, function(v)
        item.pauseWhen = v
    end)

    local objGroup = new("Frame", {
        Position = UDim2.fromOffset(12, 58),
        Size = UDim2.fromOffset(483, 50),
        BackgroundTransparency = 1,
    }, body)
    local customGroup = new("Frame", {
        Position = UDim2.fromOffset(12, 58),
        Size = UDim2.fromOffset(483, 50),
        BackgroundTransparency = 1,
    }, body)

    for i, axis in ipairs({ "x", "y", "z" }) do
        local x = (i - 1) * 120
        label(objGroup, axis:upper() .. (axis == "y" and " height" or " axis"),
            UDim2.fromOffset(x, 0), UDim2.fromOffset(112, 14), { color = T.Muted, size = 12 })
        dropdown(objGroup, UDim2.fromOffset(x, 16), UDim2.fromOffset(112, 30),
            { "Start", "Center", "End" }, item.tp[axis], function(v)
                item.tp[axis] = v
            end)
        label(customGroup, axis:upper(), UDim2.fromOffset(x, 0), UDim2.fromOffset(112, 14), { color = T.Muted, size = 12 })
    end

    label(objGroup, "Offset", UDim2.fromOffset(360, 0), UDim2.fromOffset(112, 14), { color = T.Muted, size = 12 })
    local offBox = input(objGroup, UDim2.fromOffset(360, 16), UDim2.fromOffset(112, 30), fmt(item.offset), "3")
    offBox.FocusLost:Connect(function()
        local v = tonumber(offBox.Text)
        if v then
            item.offset = v
        end
        offBox.Text = fmt(item.offset)
    end)

    local customBoxes = {}
    for i = 1, 3 do
        local box = input(customGroup, UDim2.fromOffset((i - 1) * 120, 16), UDim2.fromOffset(112, 30), fmt(item.custom[i]), "0")
        customBoxes[i] = box
        box.FocusLost:Connect(function()
            local v = tonumber(box.Text)
            if v then
                item.custom[i] = v
            end
            box.Text = fmt(item.custom[i])
        end)
    end

    local useBtn = button(customGroup, "Use my position", UDim2.fromOffset(360, 16), UDim2.fromOffset(123, 30), "secondary")
    useBtn.Activated:Connect(function()
        if humanoidRootPart and humanoidRootPart.Parent then
            local p = humanoidRootPart.Position
            item.custom = { p.X, p.Y, p.Z }
            for i = 1, 3 do
                customBoxes[i].Text = fmt(item.custom[i])
            end
            setStatus("Origin set to your position", "success")
        end
    end)

    local function showOrigin(mode)
        objGroup.Visible = (mode == "Object")
        customGroup.Visible = (mode == "Custom")
    end
    showOrigin(item.origin)
    segmented(body, UDim2.fromOffset(360, 22), UDim2.fromOffset(132, 30), { "Object", "Custom" }, item.origin, function(v)
        item.origin = v
        showOrigin(v)
    end)

    head.Activated:Connect(function()
        local v = not (expanded[item] == true)
        expanded[item] = v
        tween(row, { Size = UDim2.new(1, 0, 0, v and (HEAD_H + BODY_H) or HEAD_H) }, 0.3)
        chev.SetFacing(v and "down" or "right", true)
    end)
    head.MouseEnter:Connect(function()
        if previewHighlight then
            previewHighlight.Adornee = resolvePath(item.path)
        end
        tween(row, { BackgroundTransparency = 0.9 }, 0.12)
    end)
    head.MouseLeave:Connect(function()
        if previewHighlight then
            previewHighlight.Adornee = nil
        end
        tween(row, { BackgroundTransparency = 0.93 }, 0.15)
    end)
    goBtn.Activated:Connect(function()
        goItem(item)
    end)
    upBtn.Activated:Connect(function()
        local i = table.find(list.items, item)
        if i and i > 1 then
            list.items[i], list.items[i - 1] = list.items[i - 1], list.items[i]
            refreshList()
        end
    end)
    downBtn.Activated:Connect(function()
        local i = table.find(list.items, item)
        if i and i < #list.items then
            list.items[i], list.items[i + 1] = list.items[i + 1], list.items[i]
            refreshList()
        end
    end)
    delBtn.Activated:Connect(function()
        task.spawn(function()
            local ok = confirm({
                title = "Remove object",
                body = "Remove " .. item.name .. " from this list?",
                confirmText = "Remove",
                danger = true,
            })
            if not ok or not row.Parent then
                return
            end
            tween(row, { Size = UDim2.new(1, 0, 0, 0), BackgroundTransparency = 1 }, 0.22)
            task.delay(0.22, function()
                local i = table.find(list.items, item)
                if i then
                    table.remove(list.items, i)
                end
                refreshList()
                refreshESP()
            end)
        end)
    end)
end

function refreshList()
    closeDropdown(true)
    local list = currentList()
    if ListNameBox.Text ~= list.name then
        ListNameBox.Text = list.name
    end
    CountLabel.Text = string.format("%d object%s", #list.items, #list.items == 1 and "" or "s")

    for _, child in ipairs(ListScroll:GetChildren()) do
        if child:IsA("Frame") then
            child:Destroy()
        end
    end

    EmptyLabel.Visible = (#list.items == 0)
    if previewHighlight then
        previewHighlight.Adornee = nil
    end
    for index, item in ipairs(list.items) do
        buildRow(list, item, index, item == lastAddedItem)
    end
    lastAddedItem = nil
end

function switchList(index)
    if index < 1 then
        index = #lists
    elseif index > #lists then
        index = 1
    end
    activeList = index
    refreshList()
    refreshESP()
end

--==============================================================================
-- 10. MOTION, ACTIONS, TOUR
--==============================================================================

local function teleportTo(pos)
    local hrp = humanoidRootPart
    if not hrp or not hrp.Parent then
        return false
    end
    hrp.AssemblyLinearVelocity = Vector3.zero
    hrp.CFrame = CFrame.new(pos) * (hrp.CFrame - hrp.CFrame.Position)
    return true
end

local function glideTo(pos, speed, token)
    local hrp = humanoidRootPart
    if not hrp or not hrp.Parent then
        return false
    end
    motion.suppress += 1
    local startPos = hrp.Position
    local duration = math.max((pos - startPos).Magnitude / math.max(speed, 1), 0.05)
    local t, ok = 0, true
    while t < duration do
        if token ~= moveToken or not hrp.Parent then
            ok = false
            break
        end
        t += RunService.Heartbeat:Wait()
        local a = math.min(t / duration, 1)
        if hrp.Parent then
            hrp.AssemblyLinearVelocity = Vector3.zero
            hrp.CFrame = CFrame.new(startPos:Lerp(pos, a)) * (hrp.CFrame - hrp.CFrame.Position)
        end
    end
    motion.suppress = math.max(motion.suppress - 1, 0)
    return ok and token == moveToken
end

local function walkTo(pos, speed, token)
    local hrp, hum = humanoidRootPart, humanoid
    if not hrp or not hum or not hrp.Parent or not hum.Parent then
        return false
    end
    speed = math.max(speed, 1)
    local wishId = {}
    motion.wish = { point = pos, speed = speed, id = wishId }

    local function flatDist()
        local p = hrp.Position
        return Vector3.new(pos.X - p.X, 0, pos.Z - p.Z).Magnitude
    end

    local timeout = flatDist() / speed * 2 + 6
    local startT, lastCheck, lastPos = os.clock(), os.clock(), hrp.Position
    hum:MoveTo(pos)

    while token == moveToken and hrp.Parent and hum.Parent do
        if flatDist() < 3.5 then
            break
        end
        local now = os.clock()
        if now - startT > timeout then
            break
        end
        local flat = Vector3.new(pos.X - hrp.Position.X, 0, pos.Z - hrp.Position.Z)
        if flat.Magnitude > 0.05 then
            hum:Move(flat.Unit, false)
        end
        if now - lastCheck > 1 then
            -- MoveTo expires after 8 seconds. Jump if the character is stuck.
            if (hrp.Position - lastPos).Magnitude < 1 then
                hum.Jump = true
            end
            lastPos, lastCheck = hrp.Position, now
            hum:MoveTo(pos)
        end
        RunService.Heartbeat:Wait()
    end

    if motion.wish and motion.wish.id == wishId then
        motion.wish = nil
    end
    if hum.Parent and hrp.Parent then
        hum:MoveTo(hrp.Position)
    end
    return token == moveToken
end

local function runAction(item, token)
    local pos = computeTarget(item)
    if not pos or not humanoidRootPart or not humanoidRootPart.Parent then
        return false
    end
    if item.action == "Walk" then
        return walkTo(pos, item.speed, token)
    elseif item.action == "Glide" then
        return glideTo(pos, item.speed, token)
    end
    return teleportTo(pos)
end

local function waitFor(seconds, token)
    local t = 0
    while t < seconds do
        if token ~= moveToken then
            return false
        end
        t += RunService.Heartbeat:Wait()
    end
    return token == moveToken
end

local function perform(item, token, withTourGap)
    if (item.pause or 0) > 0 and item.pauseWhen == "Before" then
        if not waitFor(item.pause, token) then
            return "cancel"
        end
    end
    if token ~= moveToken then
        return "cancel"
    end
    local ok = runAction(item, token)
    if token ~= moveToken then
        return "cancel"
    end
    if not ok then
        return "fail"
    end

    local gap = 0
    if withTourGap then
        if item.pauseWhen == "After" and (item.pause or 0) > 0 then
            gap = item.pause
        else
            gap = tour.interval
        end
    elseif item.pauseWhen == "After" and (item.pause or 0) > 0 then
        gap = item.pause
    end
    if gap > 0 and not waitFor(gap, token) then
        return "cancel"
    end
    return "ok"
end

function updateTourUI()
    if touring then
        btnText(StartBtn, "Stop tour")
        setButtonStyle(StartBtn, "danger")
        FooterText.Text = "Tour running"
        tween(FooterText, { TextColor3 = T.Success }, 0.2)
        tween(FooterDot, { BackgroundColor3 = T.Success }, 0.2)
    else
        btnText(StartBtn, "Start tour")
        setButtonStyle(StartBtn, "primary")
        FooterText.Text = "Tour idle"
        tween(FooterText, { TextColor3 = T.Muted }, 0.2)
        tween(FooterDot, { BackgroundColor3 = T.Muted }, 0.2)
        TourProgress.Text = "Idle"
    end
end

function cancelMovement(message)
    moveToken += 1
    motion.wish = nil
    touring = false
    updateTourUI()
    if message then
        setStatus(message, "info")
    end
end

function goItem(item)
    cancelMovement()
    local token = moveToken
    task.spawn(function()
        local result = perform(item, token, false)
        if token ~= moveToken then
            return
        end
        if result == "ok" then
            setStatus("Done: " .. item.name, "success")
        elseif result == "fail" then
            setStatus("Can't reach " .. item.name, "error")
        end
    end)
end

function startTour()
    local list = currentList()
    if #list.items == 0 then
        setStatus("Add some objects to the list first", "warn")
        return
    end

    cancelMovement()
    touring = true
    local token = moveToken
    updateTourUI()

    task.spawn(function()
        local index, dir, steps, fails = 0, 1, 0, 0
        local startCount = #list.items
        local limit = (tour.order == "Ping-pong") and math.max(startCount * 2 - 2, 1) or startCount
        if tour.order == "Reverse" then
            index = startCount + 1
        end

        while token == moveToken do
            local n = #list.items
            if n == 0 then
                break
            end

            if tour.order == "Forward" then
                index = index % n + 1
            elseif tour.order == "Reverse" then
                index = math.min(index, n + 1) - 1
                if index < 1 then
                    index = n
                end
            elseif tour.order == "Ping-pong" then
                if n == 1 then
                    index = 1
                else
                    index += dir
                    if index > n then
                        dir, index = -1, n - 1
                    elseif index < 1 then
                        dir, index = 1, 2
                    end
                end
            elseif n == 1 then
                index = 1
            else
                local r
                repeat
                    r = math.random(n)
                until r ~= index
                index = r
            end

            local item = list.items[index]
            TourProgress.Text = string.format("%d/%d  %s  -  %s", index, n, item.name, item.action)
            local result = perform(item, token, true)
            if result == "cancel" or token ~= moveToken then
                break
            end
            if result == "ok" then
                fails = 0
            else
                fails += 1
                if fails >= n then
                    cancelMovement("Tour stopped: no reachable objects")
                    break
                end
                task.wait()
            end

            steps += 1
            if not tour.loop and steps >= limit then
                break
            end
        end

        if token == moveToken then
            touring = false
            updateTourUI()
            setStatus("Tour finished", "success")
        end
    end)
end

local function cameraFlat()
    local cam = workspace.CurrentCamera
    if not cam then
        return Vector3.zero
    end
    local cf = cam.CFrame
    local look = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
    local right = Vector3.new(cf.RightVector.X, 0, cf.RightVector.Z)
    look = (look.Magnitude > 0.01) and look.Unit or Vector3.zero
    right = (right.Magnitude > 0.01) and right.Unit or Vector3.zero
    local dir = Vector3.zero
    if UserInputService:IsKeyDown(Enum.KeyCode.W) then
        dir += look
    end
    if UserInputService:IsKeyDown(Enum.KeyCode.S) then
        dir -= look
    end
    if UserInputService:IsKeyDown(Enum.KeyCode.D) then
        dir += right
    end
    if UserInputService:IsKeyDown(Enum.KeyCode.A) then
        dir -= right
    end
    if dir.Magnitude > 0.05 then
        return dir.Unit
    end
    return Vector3.zero
end

local function stepMotion(dt)
    if unloading then
        return
    end
    if motion.noclipOn then
        applyNoclip()
    end
    if motion.suppress > 0 then
        return
    end

    local hrp, hum = humanoidRootPart, humanoid
    if not hrp or not hum or not hrp.Parent or not hrp:IsDescendantOf(workspace) then
        return
    end

    local wish = motion.wish
    local flying = motion.flyOn
    if not flying and not motion.speedOn and not wish then
        return
    end

    local dir = Vector3.zero
    local speed
    if wish then
        local flat = Vector3.new(wish.point.X - hrp.Position.X, 0, wish.point.Z - hrp.Position.Z)
        if flat.Magnitude > 0.05 then
            dir = flat.Unit
        end
        speed = wish.speed
    else
        local md = hum.MoveDirection
        local flat = Vector3.new(md.X, 0, md.Z)
        if flat.Magnitude > 0.05 then
            dir = flat.Unit
        elseif flying then
            dir = cameraFlat()
        end
        speed = flying and motion.flySpeed or motion.speed
    end

    -- Wish speed wins over the Speed module so the two do not stack.
    -- Ground steps add (speed - walk speed) because the humanoid still moves at WalkSpeed.
    if flying then
        local drop = (motion.flyMode == "Glide") and (-motion.glideSink * dt) or 0
        hrp.AssemblyLinearVelocity = Vector3.zero
        local step = dir * speed * dt
        hrp.CFrame = hrp.CFrame + Vector3.new(step.X, drop, step.Z)
        return
    end

    local vel = hrp.AssemblyLinearVelocity
    hrp.AssemblyLinearVelocity = Vector3.new(0, vel.Y, 0)
    if dir.Magnitude > 0 then
        local boost = math.max(speed - NORMAL_SPEED, 0)
        local step = dir * boost * dt
        hrp.CFrame = hrp.CFrame + Vector3.new(step.X, 0, step.Z)
    end
end

local function clickCorner()
    local cam = workspace.CurrentCamera
    local vp = cam and cam.ViewportSize or Vector2.new(1920, 1080)
    local x, y = 6, math.max(vp.Y - 6, 6)
    if isOverMainFrame(Vector2.new(x, y)) then
        return
    end
    local sent = false
    if VirtualInput then
        sent = pcall(function()
            VirtualInput:SendMouseButtonEvent(x, y, 0, true, game, 0)
            VirtualInput:SendMouseButtonEvent(x, y, 0, false, game, 0)
        end)
    end
    if not sent and type(mouse1click) == "function" then
        pcall(mouse1click, x, y)
    end
end

local clickAcc = 0
table.insert(connections, RunService.Heartbeat:Connect(function(dt)
    stepMotion(dt)
    if not motion.clickOn then
        clickAcc = 0
        return
    end
    clickAcc += dt
    if clickAcc < motion.clickInterval then
        return
    end
    clickAcc = 0
    clickCorner()
end))

--==============================================================================
-- 11. PRESETS, INPUT, WINDOW
--==============================================================================

AddBtn.Activated:Connect(function()
    setPickMode(not pickMode)
end)

ListArrow.Activated:Connect(function()
    local names = {}
    for i, l in ipairs(lists) do
        names[i] = string.format("%s  (%d)", l.name, #l.items)
    end
    openDropdown(ListNameBox, names, activeList, function(_, idx)
        switchList(idx)
    end)
end)

ListNameBox.FocusLost:Connect(function()
    local text = ListNameBox.Text:gsub("^%s+", ""):gsub("%s+$", "")
    if text ~= "" then
        currentList().name = text
    end
    ListNameBox.Text = currentList().name
end)

NewListBtn.Activated:Connect(function()
    table.insert(lists, newList("List " .. (#lists + 1)))
    switchList(#lists)
    setStatus("New list created", "success")
end)

DelListBtn.Activated:Connect(function()
    task.spawn(function()
        local only = #lists <= 1
        local name = currentList().name
        local ok = confirm({
            title = only and "Clear list" or "Delete list",
            body = only and "This is your only list. Remove every object in it?"
                or ("Delete " .. name .. " and its objects?"),
            confirmText = only and "Clear" or "Delete",
            danger = true,
        })
        if not ok then
            return
        end
        if #lists <= 1 then
            lists[1] = newList("Default")
            activeList = 1
            refreshList()
            refreshESP()
            setStatus("List cleared", "warn")
            return
        end
        table.remove(lists, activeList)
        switchList(math.min(activeList, #lists))
        setStatus("List deleted", "warn")
    end)
end)

DefSpeedBox.FocusLost:Connect(function()
    local v = tonumber(DefSpeedBox.Text)
    if v and v > 0 then
        D.speed = v
    end
    DefSpeedBox.Text = fmt(D.speed)
end)

DefOffsetBox.FocusLost:Connect(function()
    local v = tonumber(DefOffsetBox.Text)
    if v then
        D.offset = v
    end
    DefOffsetBox.Text = fmt(D.offset)
end)

ApplyAllBtn.Activated:Connect(function()
    local list = currentList()
    for _, it in ipairs(list.items) do
        it.action, it.speed, it.offset = D.action, D.speed, D.offset
        it.tp = { x = D.tp.x, y = D.tp.y, z = D.tp.z }
    end
    refreshList()
    setStatus(string.format("Applied defaults to %d object(s)", #list.items), "success")
end)

IntervalBox.FocusLost:Connect(function()
    local v = tonumber(IntervalBox.Text)
    if v then
        tour.interval = math.clamp(v, 0.02, 60)
        IntervalSlider.Set(tour.interval)
    end
    IntervalBox.Text = fmt(tour.interval)
end)

StartBtn.Activated:Connect(function()
    if touring then
        cancelMovement("Tour stopped")
    else
        startTour()
    end
end)

local function getClipWriter()
    return setclipboard or toclipboard or set_clipboard
        or (syn and syn.write_clipboard) or (Clipboard and Clipboard.set)
end

local function getClipReader()
    return getclipboard or get_clipboard
        or (syn and syn.get_clipboard) or (Clipboard and Clipboard.get)
end

local function clipWrite(text)
    local fn = getClipWriter()
    return fn ~= nil and (pcall(fn, text))
end

local function clipRead()
    local fn = getClipReader()
    if not fn then
        return nil
    end
    local ok, result = pcall(fn)
    if ok and type(result) == "string" and result ~= "" then
        return result
    end
    return nil
end

local function yesNo(v)
    return v and "yes" or "no"
end

CapsLabel.Text = string.format("Clipboard copy: %s   |   Clipboard paste: %s   |   Files: %s",
    yesNo(getClipWriter() ~= nil), yesNo(getClipReader() ~= nil), yesNo(writefile ~= nil and readfile ~= nil))

local function buildExportJson()
    local source = (exportScope == "All lists") and lists or { currentList() }
    local out = {}
    for _, l in ipairs(source) do
        table.insert(out, { name = l.name, items = l.items })
    end
    return HttpService:JSONEncode({ version = 4, lists = out }), #out
end

local function validVec3(t)
    return type(t) == "table" and type(t[1]) == "number" and type(t[2]) == "number" and type(t[3]) == "number"
end

-- v2 presets stored tp and offset on the list. v3+ store them on each item.
local function normalizeItem(raw, fallbackTp, fallbackOffset)
    if type(raw) ~= "table" or type(raw.name) ~= "string" or type(raw.path) ~= "table" or #raw.path == 0 then
        return nil
    end
    for _, part in ipairs(raw.path) do
        if type(part) ~= "string" then
            return nil
        end
    end

    local tp = type(raw.tp) == "table" and raw.tp or fallbackTp
    local pause = (type(raw.pause) == "number" and raw.pause > 0) and raw.pause or nil
    local pauseWhen = PAUSE_SET[raw.pauseWhen] and raw.pauseWhen or "After"
    if not pause and type(raw.wait) == "number" and raw.wait > 0 then
        pause = raw.wait
        pauseWhen = "After"
    end

    return {
        name = raw.name,
        class = type(raw.class) == "string" and raw.class or "?",
        path = raw.path,
        pos = validVec3(raw.pos) and raw.pos or nil,
        half = validVec3(raw.half) and raw.half or nil,
        action = ACTION_SET[raw.action] and raw.action or "Teleport",
        speed = (type(raw.speed) == "number" and raw.speed > 0) and raw.speed or D.speed,
        pause = pause,
        pauseWhen = pauseWhen,
        origin = (raw.origin == "Custom") and "Custom" or "Object",
        tp = {
            x = TP_SET[tp and tp.x] and tp.x or "Center",
            y = TP_SET[tp and tp.y] and tp.y or "End",
            z = TP_SET[tp and tp.z] and tp.z or "Center",
        },
        offset = type(raw.offset) == "number" and raw.offset
            or (type(fallbackOffset) == "number" and fallbackOffset or 3),
        custom = validVec3(raw.custom) and { raw.custom[1], raw.custom[2], raw.custom[3] } or { 0, 0, 0 },
    }
end

local function nameTaken(name)
    for _, l in ipairs(lists) do
        if l.name == name then
            return true
        end
    end
    return false
end

local function importJson(text)
    local ok, data = pcall(function()
        return HttpService:JSONDecode(text)
    end)
    if not ok or type(data) ~= "table" or type(data.lists) ~= "table" then
        return false, "That doesn't look like a valid preset"
    end

    local importedLists, importedItems = 0, 0
    for _, l in ipairs(data.lists) do
        if type(l) == "table" and type(l.name) == "string" and type(l.items) == "table" then
            local name, k = l.name, 1
            while nameTaken(name) do
                k += 1
                name = string.format("%s (%d)", l.name, k)
            end

            local list = newList(name)
            for _, raw in ipairs(l.items) do
                local item = normalizeItem(raw, l.tp, l.offset)
                if item then
                    table.insert(list.items, item)
                end
            end
            table.insert(lists, list)
            importedLists += 1
            importedItems += #list.items
        end
    end

    if importedLists == 0 then
        return false, "No valid lists found in that preset"
    end
    switchList(#lists)
    return true, string.format("Imported %d list(s), %d object(s)", importedLists, importedItems)
end

CopyBtn.Activated:Connect(function()
    local json, count = buildExportJson()
    if clipWrite(json) then
        setStatus(string.format("Copied %d list(s) to clipboard", count), "success")
    else
        JsonBox.Text = json
        setStatus("Clipboard not supported. JSON is in the field below.", "warn")
    end
end)

SaveBtn.Activated:Connect(function()
    if not writefile then
        setStatus("File writing is not available", "error")
        return
    end
    local json, count = buildExportJson()
    if pcall(writefile, PRESET_FILE, json) then
        setStatus(string.format("Saved %d list(s) to workspace/%s", count, PRESET_FILE), "success")
    else
        setStatus("Failed to write the file", "error")
    end
end)

PasteBtn.Activated:Connect(function()
    local text = clipRead()
    if not text then
        setStatus("Can't read the clipboard. Paste JSON into the field and press Import.", "warn")
        return
    end
    local ok, msg = importJson(text)
    setStatus(msg .. (ok and " from clipboard" or ""), ok and "success" or "error")
end)

LoadBtn.Activated:Connect(function()
    if not (readfile and isfile) then
        setStatus("File reading is not available", "error")
        return
    end
    if not isfile(PRESET_FILE) then
        setStatus("File not found: workspace/" .. PRESET_FILE, "warn")
        return
    end
    local ok, text = pcall(readfile, PRESET_FILE)
    if not ok then
        setStatus("Failed to read the file", "error")
        return
    end
    local success, msg = importJson(text)
    setStatus(msg .. (success and " from file" or ""), success and "success" or "error")
end)

ImportTextBtn.Activated:Connect(function()
    if JsonBox.Text == "" then
        setStatus("Paste JSON into the field first", "warn")
        return
    end
    local ok, msg = importJson(JsonBox.Text)
    setStatus(msg, ok and "success" or "error")
    if ok then
        JsonBox.Text = ""
    end
end)

local DOF
pcall(function()
    DOF = new("DepthOfFieldEffect", {
        Name = "HarukoBlur",
        Enabled = settings.blur,
        FarIntensity = 0,
        NearIntensity = settings.blurStrength,
        FocusDistance = 51.6,
        InFocusRadius = 50,
    }, Lighting)
end)

local blurPart = new("Part", {
    Name = "HarukoBlurPart",
    Anchored = true,
    CanCollide = false,
    CanQuery = false,
    CanTouch = false,
    CastShadow = false,
    Locked = true,
    Material = Enum.Material.Glass,
    Color = T.Dark,
    Transparency = 0.98,
    Size = Vector3.new(1, 1, 0.01),
})

local function updateBlur()
    local cam = workspace.CurrentCamera
    local shown = settings.blur and cam and MainFrame.Visible and MainFrame.GroupTransparency < 0.6
    if DOF then
        DOF.Enabled = settings.blur and MainFrame.Visible
        DOF.NearIntensity = settings.blurStrength
    end
    if not shown then
        blurPart.Parent = nil
        return
    end
    if blurPart.Parent ~= cam then
        blurPart.Parent = cam
    end

    -- ViewportPointToRay uses the same pixels as the GUI. ViewportSize centering sits above the window.
    local pos, size = MainFrame.AbsolutePosition, MainFrame.AbsoluteSize
    local x0, y0 = pos.X + CORNER, pos.Y + CORNER
    local x1, y1 = pos.X + size.X - CORNER, pos.Y + size.Y - CORNER
    local cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    local depth = 0.25
    local function at(x, y)
        return cam:ViewportPointToRay(x, y, depth).Origin
    end
    local mid = cam:ViewportPointToRay(cx, cy, depth)
    local width = math.max((at(x1, cy) - at(x0, cy)).Magnitude, 0.05)
    local height = math.max((at(cx, y1) - at(cx, y0)).Magnitude, 0.05)
    blurPart.Size = Vector3.new(width, height, 0.01)
    blurPart.CFrame = CFrame.lookAt(mid.Origin, mid.Origin + mid.Direction)
end

RunService:BindToRenderStep("HarukoBlur", Enum.RenderPriority.Camera.Value + 1, updateBlur)

local windowShown = false

local function showWindow()
    windowShown = true
    MainFrame.Visible = true
    tween(MainFrame, { GroupTransparency = 0 }, 0.28)
    tween(WinScale, { Scale = 1 }, 0.34)
end

local function hideWindow(thenCall)
    windowShown = false
    closeDropdown(true)
    tween(MainFrame, { GroupTransparency = 1 }, 0.2)
    tween(WinScale, { Scale = 0.95 }, 0.22)
    task.delay(0.22, function()
        if not windowShown then
            MainFrame.Visible = false
        end
        if thenCall then
            thenCall()
        end
    end)
end

local function unload()
    unloading = true
    motion.speedOn = false
    motion.clickOn = false
    motion.teleportOn = false
    motion.wish = nil
    pickKind = nil
    if motion.flyOn then
        setFly(false)
    end
    if motion.noclipOn then
        setNoclip(false)
    end
    if humanoid and humanoid.Parent then
        humanoid.WalkSpeed = NORMAL_SPEED
    end
    cancelMovement()
    hideWindow(function()
        for _, c in ipairs(connections) do
            c:Disconnect()
        end
        pcall(function()
            RunService:UnbindFromRenderStep("HarukoBlur")
        end)
        if DOF then
            DOF:Destroy()
        end
        blurPart:Destroy()
        HighlightFolder:Destroy()
        ScreenGui:Destroy()
    end)
end

local function clearListen(restore)
    if not listening or not modUi[listening] then
        listening = nil
        return
    end
    local ui = modUi[listening]
    listening = nil
    if restore then
        ui.chip.Text = keyLabel(ui.bind)
        ui.chip.TextColor3 = T.Muted
    end
end

table.insert(connections, UserInputService.InputBegan:Connect(function(inp, gameProcessed)
    if dialogBusy and inp.KeyCode == Enum.KeyCode.Escape then
        dialogFinish(false)
        return
    end

    if listening and inp.UserInputType == Enum.UserInputType.Keyboard and not UserInputService:GetFocusedTextBox() then
        local code = inp.KeyCode
        local ui = modUi[listening]
        if code == Enum.KeyCode.Escape then
            ui.bind = nil
            clearListen(true)
            return
        elseif code == Enum.KeyCode.RightShift then
            clearListen(true)
            notify("RightShift hides the panel", "warn")
        elseif code ~= Enum.KeyCode.Unknown then
            for id, other in pairs(modUi) do
                if id ~= listening and other.bind == code then
                    other.bind = nil
                    other.chip.Text = "None"
                end
            end
            ui.bind = code
            clearListen(true)
            return
        end
    end

    if gameProcessed or dialogBusy then
        return
    end

    if inp.KeyCode == Enum.KeyCode.RightShift then
        if windowShown then
            hideWindow()
        else
            showWindow()
        end
        return
    end

    if inp.UserInputType == Enum.UserInputType.Keyboard and not UserInputService:GetFocusedTextBox() then
        for _, ui in pairs(modUi) do
            if ui.bind and ui.bind == inp.KeyCode then
                local nextOn = not ui.switch.Get()
                ui.switch.Set(nextOn)
                ui.onToggle(nextOn)
            end
        end
    end

    if pickKind and inp.UserInputType == Enum.UserInputType.MouseButton1 then
        local target = getTargetUnderMouse()
        if not target then
            return
        end
        if pickKind == "add" then
            if addObjectToList(target) then
                setPickMode(false)
            end
            return
        end
        local center, half = getBounds(target)
        if not center then
            setStatus("Can't teleport there", "error")
            return
        end
        local mode = motion.tpOrigin
        local pos = Vector3.new(
            axisValue(mode, center.X, half.X),
            axisValue(mode, center.Y, half.Y),
            axisValue(mode, center.Z, half.Z)
        ) + Vector3.new(0, motion.tpOffset, 0)
        if teleportTo(pos) then
            setStatus("Teleported to " .. target.Name, "success")
            if modUi.teleport then
                modUi.teleport.switch.Set(false)
            end
            setTeleport(false)
        else
            setStatus("Can't teleport there", "error")
        end
    end
end))

HideDot.Activated:Connect(function()
    if dialogBusy then
        return
    end
    hideWindow()
    notify("RightShift to show", "info")
end)

CenterDot.Activated:Connect(function()
    tween(MainFrame, { Position = UDim2.new(0.5, -WIN_W / 2, 0.5, -WIN_H / 2) }, 0.35)
end)

CloseDot.Activated:Connect(function()
    task.spawn(function()
        local ok = confirm({
            title = "Close Haruko",
            body = "Unload the panel and stop every module?",
            confirmText = "Close",
            danger = true,
        })
        if ok then
            unload()
        end
    end)
end)

local dragging = false
local dragInput, dragStart, startPos

local function bindDrag(handle)
    handle.InputBegan:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = inp.Position
            startPos = MainFrame.Position
            inp.Changed:Connect(function()
                if inp.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)
    handle.InputChanged:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseMovement or inp.UserInputType == Enum.UserInputType.Touch then
            dragInput = inp
        end
    end)
end
bindDrag(Topbar)
bindDrag(DragStrip)

table.insert(connections, UserInputService.InputChanged:Connect(function(inp)
    if inp == dragInput and dragging then
        local delta = inp.Position - dragStart
        MainFrame.Position = UDim2.new(
            startPos.X.Scale, startPos.X.Offset + delta.X,
            startPos.Y.Scale, startPos.Y.Offset + delta.Y
        )
    end
end))

local okBoot, bootErr = pcall(function()
    refreshList()
    updateTourUI()
    showPage("General", true)
    showWindow()
end)
if not okBoot then
    warn("[Haruko] " .. tostring(bootErr))
    MainFrame.Visible = true
    MainFrame.GroupTransparency = 0
    WinScale.Scale = 1
end
