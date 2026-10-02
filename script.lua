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
local RobloxSettings = settings

local VirtualInput
pcall(function()
    VirtualInput = game:GetService("VirtualInputManager")
end)

do
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
    pcall(destroyOld, Players.LocalPlayer:FindFirstChildOfClass("PlayerGui"))
    pcall(destroyOld, hiddenGui())
end

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

local player = Players.LocalPlayer

local character = player.Character
local humanoidRootPart = character and character:FindFirstChild("HumanoidRootPart")
local humanoid = character and character:FindFirstChildOfClass("Humanoid")

--==============================================================================
-- 2. THEME, CONFIG, STATE
--==============================================================================

local VERSION = "v2.0"
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
    opacity = 1,
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
    flySpeed = 60,
    glideSink = 10,
    glideVel = Vector3.zero,
    antiPauseOn = false,
    renderOn = false,
    render = { keep = true, quality = true, fog = false },
    renderSaved = {},
    teleportOn = false,
    tpOrigin = "Center",
    tpOffset = 3,
    clickOn = false,
    clickInterval = 0.15,
    noclipOn = false,
    tourPending = false,
    reconnectOn = false,
    reconnectDelay = 5,
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
local persistNow
local syncers = {}
local showPage
local pages = {}
local ui = {}

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

local function setAntiPause(on)
    motion.antiPauseOn = on
    pcall(function()
        game:GetService("GuiService"):SetGameplayPausedNotificationEnabled(not on)
    end)
    if motion.pauseConn then
        motion.pauseConn:Disconnect()
        motion.pauseConn = nil
    end

    local function writeIntegrity(mode)
        local set = sethiddenproperty or set_hidden_property
        if not (set and pcall(set, workspace, "StreamingIntegrityMode", mode)) then
            pcall(function()
                workspace.StreamingIntegrityMode = mode
            end)
        end
    end

    if not on then
        if motion.integrity then
            writeIntegrity(motion.integrity)
            motion.integrity = nil
        end
        return
    end

    if motion.integrity == nil then
        local get = gethiddenproperty or get_hidden_property
        local ok, mode = pcall(function()
            return get and get(workspace, "StreamingIntegrityMode") or workspace.StreamingIntegrityMode
        end)
        motion.integrity = ok and mode or false
    end
    writeIntegrity(Enum.StreamingIntegrityMode.Disabled)

    local function resume()
        pcall(function()
            if player.GameplayPaused then
                player.GameplayPaused = false
            end
        end)
    end
    resume()
    pcall(function()
        motion.pauseConn = player:GetPropertyChangedSignal("GameplayPaused"):Connect(resume)
    end)
end

local function setRender(on)
    motion.renderOn = on
    local opt, saved = motion.render, motion.renderSaved

    local function enum(category, name)
        local ok, item = pcall(function()
            return Enum[category][name]
        end)
        return ok and item or nil
    end

    local function read(obj, prop)
        local get = gethiddenproperty or get_hidden_property
        local ok, value = pcall(function()
            if get then
                return (get(obj, prop))
            end
            return obj[prop]
        end)
        return ok and value or nil
    end

    local function write(obj, prop, value)
        local set = sethiddenproperty or set_hidden_property
        if not (set and pcall(set, obj, prop, value)) then
            pcall(function()
                obj[prop] = value
            end)
        end
    end

    local function apply(key, obj, prop, value, enabled)
        if not obj or value == nil then
            return
        end
        if on and enabled then
            if saved[key] == nil then
                saved[key] = read(obj, prop)
            end
            write(obj, prop, value)
        elseif saved[key] ~= nil then
            write(obj, prop, saved[key])
            saved[key] = nil
        end
    end

    local rendering, userSettings
    pcall(function()
        rendering = RobloxSettings().Rendering
    end)
    pcall(function()
        userSettings = UserSettings():GetService("UserGameSettings")
    end)
    local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")

    apply("streamOut", workspace, "StreamOutBehavior", enum("StreamOutBehavior", "LowMemory"), opt.keep)
    apply("targetRadius", workspace, "StreamingTargetRadius", 100000, opt.keep)
    apply("quality", rendering, "QualityLevel", enum("QualityLevel", "Level21"), opt.quality)
    apply("savedQuality", userSettings, "SavedQualityLevel", enum("SavedQualitySetting", "QualityLevel10"), opt.quality)
    apply("meshDetail", rendering, "MeshPartDetailLevel", enum("MeshPartDetailLevel", "Level04"), opt.quality)
    apply("fogEnd", Lighting, "FogEnd", 1e6, opt.fog)
    apply("fogStart", Lighting, "FogStart", 1e6, opt.fog)
    apply("haze", atmosphere, "Density", 0, opt.fog)
end

local function setAutoExec(on)
    local queue = queue_on_teleport or queueonteleport or queueteleport
        or (syn and syn.queue_on_teleport) or (fluxus and fluxus.queue_on_teleport)
    if not queue then
        return false
    end
    local store = (getgenv and getgenv()) or shared or motion
    if on and not store.HarukoQueued then
        store.HarukoQueued = pcall(queue, string.format(
            "repeat task.wait() until game:IsLoaded() loadstring(game:HttpGet(%q))()",
            "https://raw.githubusercontent.com/zhogoshi/haruko/main/script.lua"
        ))
    elseif not on and store.HarukoQueued then
        local clear = clear_queue_on_teleport or clearqueueonteleport
        if clear then
            pcall(clear)
        end
        store.HarukoQueued = false
    end
    return true
end

do
    local GuiService = game:GetService("GuiService")
    local TeleportService = game:GetService("TeleportService")
    local reconnecting = false

    local function isDisconnect()
        local ok, code = pcall(GuiService.GetErrorCode, GuiService)
        if ok and typeof(code) == "EnumItem" then
            return code.Value >= 256 and code.Value < 512
        end
        local okMsg, msg = pcall(GuiService.GetErrorMessage, GuiService)
        return okMsg and type(msg) == "string" and msg ~= ""
    end

    local function reconnect()
        if reconnecting or unloading or not motion.reconnectOn or not isDisconnect() then
            return
        end
        reconnecting = true
        local message, base
        local function show(text)
            if not (message and message.Parent) then
                local promptGui = CoreGui:FindFirstChild("RobloxPromptGui")
                message = promptGui and promptGui:FindFirstChild("ErrorMessage", true)
                base = message and message.Text
            end
            if message then
                message.Text = base .. "\n\n" .. text
            end
        end
        task.spawn(function()
            local sameServer = #Players:GetPlayers() > 1
            while motion.reconnectOn and not unloading do
                for left = math.floor(motion.reconnectDelay), 1, -1 do
                    if not motion.reconnectOn or unloading then
                        break
                    end
                    show(string.format("Reconnecting in %ds", left))
                    task.wait(1)
                end
                if not motion.reconnectOn or unloading then
                    break
                end
                show("Reconnecting...")
                pcall(persistNow)
                if sameServer then
                    pcall(TeleportService.TeleportToPlaceInstance, TeleportService, game.PlaceId, game.JobId, player)
                else
                    pcall(TeleportService.Teleport, TeleportService, game.PlaceId, player)
                end
                sameServer = false
                task.wait(10)
            end
            if message and message.Parent then
                message.Text = base
            end
            reconnecting = false
        end)
    end

    table.insert(connections, GuiService.ErrorMessageChanged:Connect(reconnect))
    motion.reconnectNow = reconnect
end

local function dropFlyBody()
    for _, key in ipairs({ "flyVel", "flyGyro" }) do
        if motion[key] then
            motion[key]:Destroy()
            motion[key] = nil
        end
    end
end

local function setFly(on)
    motion.flyOn = on
    motion.glideVel = Vector3.zero
    if not on then
        dropFlyBody()
    end
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
    dropFlyBody()
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
    elseif kind == "eye" then
        local lens = new("Frame", place(14, 8, 0, 0), box)
        lens.BackgroundTransparency = 1
        round(lens, 4 * k)
        table.insert(strokes, new("UIStroke", {
            Color = color,
            Thickness = math.max(1.5 * k, 1),
            ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        }, lens))
        dot(3.6, 0, 0)
    elseif kind == "clock" then
        ring(13, 0, 0, 6.5)
        bar(1.6, 4.6, 0, -1.9)
        bar(3.6, 1.6, 1.4, 0)
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
    DisplayOrder = 100,
}, CoreGui)

local HighlightFolder = new("Folder", { Name = "HarukoHighlights" }, CoreGui)

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
    AnchorPoint = Vector2.new(1, 1),
    Position = UDim2.new(1, -20, 1, -20),
    Size = UDim2.fromOffset(360, 360),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ZIndex = 40,
    Active = false,
}, ScreenGui)

local panels = setmetatable({ [MainFrame] = true }, { __mode = "k" })

local function applyOpacity()
    for gui in pairs(panels) do
        gui.BackgroundTransparency = 1 - settings.opacity
    end
end

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
    tween(p, { GroupTransparency = 1 }, 0.12)
    local sc = p:FindFirstChildOfClass("UIScale")
    if sc then
        tween(sc, { Scale = 0.97 }, 0.12)
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
    local below = absPos.Y + absSize.Y + 4 + h <= view.Y - 8
    local y = below and (absPos.Y + absSize.Y + 4) or (absPos.Y - 4)
    local x = math.clamp(absPos.X, 8, math.max(view.X - w - 8, 8))

    local popup = new("CanvasGroup", {
        Name = "Popup",
        AnchorPoint = Vector2.new(0, below and 0 or 1),
        Position = UDim2.fromOffset(x, y),
        Size = UDim2.fromOffset(w, h),
        BackgroundColor3 = T.Menu,
        BackgroundTransparency = 0,
        GroupTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = 2,
    }, Overlay)
    round(popup, 10)
    hairline(popup, 0.8)
    local sc = new("UIScale", { Scale = 0.97 }, popup)

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
    tween(popup, { GroupTransparency = 0 }, 0.14)
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

local notify

do
    local TOAST_W, TOAST_H, TOAST_GAP, TOAST_LIFE = 360, 68, 10, 4.5
    local OFFSCREEN = TOAST_W + 40
    local toasts = {}
    local KIND = {
        info = { color = T.AccentHi, icon = "info", title = "Info" },
        success = { color = T.Success, icon = "check", title = "Done" },
        warn = { color = T.Warning, icon = "warn", title = "Heads up" },
        error = { color = T.Danger, icon = "close", title = "Error" },
    }

    local function slotY(i)
        return -(#toasts - i) * (TOAST_H + TOAST_GAP)
    end

    local function layoutToasts()
        for i, item in ipairs(toasts) do
            tween(item.frame, { Position = UDim2.new(0, 0, 1, slotY(i)) }, 0.3)
        end
    end

    local function dismiss(item)
        if not item.alive then
            return
        end
        item.alive = false
        local idx = table.find(toasts, item)
        if idx then
            table.remove(toasts, idx)
        end
        local y = item.frame.Position.Y.Offset
        tween(item.frame, { Position = UDim2.new(0, OFFSCREEN, 1, y), GroupTransparency = 1 }, 0.28, Enum.EasingStyle.Quart)
        layoutToasts()
        task.delay(0.3, function()
            item.frame:Destroy()
        end)
    end

    function notify(text, kind)
        kind = KIND[kind] and kind or "info"
        local meta = KIND[kind]
        while #toasts >= 4 do
            dismiss(toasts[1])
        end

        local frame = new("CanvasGroup", {
            AnchorPoint = Vector2.new(0, 1),
            Size = UDim2.fromOffset(TOAST_W, TOAST_H),
            BackgroundColor3 = T.Window,
            BackgroundTransparency = 1 - settings.opacity,
            GroupTransparency = 1,
            BorderSizePixel = 0,
            Active = true,
        }, ToastHost)
        round(frame, 12)
        panels[frame] = true
        new("UIStroke", {
            Color = meta.color,
            Transparency = 0.55,
            Thickness = 1,
            ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        }, frame)

        local badge = new("Frame", {
            Position = UDim2.fromOffset(14, 16),
            Size = UDim2.fromOffset(32, 32),
            BackgroundColor3 = meta.color,
            BackgroundTransparency = 0.82,
            BorderSizePixel = 0,
        }, frame)
        round(badge, 16)
        local ic = makeIcon(badge, meta.icon, 16, meta.color)
        ic.Frame.Position = UDim2.new(0.5, -8, 0.5, -8)

        label(frame, meta.title, UDim2.fromOffset(58, 14), UDim2.new(1, -110, 0, 18), {
            font = F.Bold,
            size = 14,
            color = meta.color,
        })
        label(frame, text, UDim2.fromOffset(58, 33), UDim2.new(1, -110, 0, 18), {
            font = F.Medium,
            size = 13,
            truncate = Enum.TextTruncate.AtEnd,
        })

        local item = { alive = true, frame = frame }
        local close = new("TextButton", {
            AnchorPoint = Vector2.new(1, 0),
            Position = UDim2.new(1, -12, 0, 12),
            Size = UDim2.fromOffset(28, 28),
            BackgroundColor3 = T.White,
            BackgroundTransparency = 0.92,
            Text = "",
            AutoButtonColor = false,
            BorderSizePixel = 0,
            ZIndex = 2,
        }, frame)
        round(close, 8)
        local xic = makeIcon(close, "close", 14, T.Text)
        xic.Frame.Position = UDim2.new(0.5, -7, 0.5, -7)
        close.MouseEnter:Connect(function()
            tween(close, { BackgroundTransparency = 0.8 }, 0.1)
        end)
        close.MouseLeave:Connect(function()
            tween(close, { BackgroundTransparency = 0.92 }, 0.12)
        end)
        close.Activated:Connect(function()
            dismiss(item)
        end)

        local bar = new("Frame", {
            AnchorPoint = Vector2.new(0, 1),
            Position = UDim2.fromScale(0, 1),
            Size = UDim2.new(1, 0, 0, 3),
            BackgroundColor3 = meta.color,
            BackgroundTransparency = 0.2,
            BorderSizePixel = 0,
        }, frame)
        tween(bar, { Size = UDim2.new(0, 0, 0, 3) }, TOAST_LIFE, Enum.EasingStyle.Linear)

        table.insert(toasts, item)
        frame.Position = UDim2.new(0, OFFSCREEN, 1, 0)
        tween(frame, { GroupTransparency = 0 }, 0.3)
        layoutToasts()
        task.delay(TOAST_LIFE, function()
            dismiss(item)
        end)
    end
end

local function setStatus(text, kind)
    notify(text, kind)
end

local dialogBusy = false
local dialogFinish = function() end
local confirm

do
    local dialogGen = 0

    local Dimmer = new("TextButton", {
        BackgroundColor3 = Color3.new(0, 0, 0),
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        BorderSizePixel = 0,
        ZIndex = 1,
    }, DialogHost)
    round(Dimmer, CORNER)

    local DialogCard = new("CanvasGroup", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Size = UDim2.fromOffset(348, 172),
        BackgroundColor3 = T.Window,
        BackgroundTransparency = 1 - settings.opacity,
        BorderSizePixel = 0,
        ZIndex = 2,
        Active = true,
    }, DialogHost)
    round(DialogCard, 14)
    panels[DialogCard] = true
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

    function confirm(opts)
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
        Dimmer.Position = UDim2.fromOffset(p.X, p.Y)
        Dimmer.Size = UDim2.fromOffset(s.X, s.Y)
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
end

--==============================================================================
-- 6. SHELL
--==============================================================================

do
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

    ui.DragStrip = new("Frame", {
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
    ui.CloseDot = trafficLight(14, Color3.fromRGB(255, 95, 87))
    ui.HideDot = trafficLight(32, Color3.fromRGB(254, 188, 46))
    ui.CenterDot = trafficLight(50, Color3.fromRGB(40, 200, 64))

    local logo = new("Frame", {
        Position = UDim2.fromOffset(14, 40),
        Size = UDim2.fromOffset(28, 28),
        BackgroundColor3 = T.Accent,
        BorderSizePixel = 0,
    }, ui.DragStrip)
    round(logo, 8)
    local mark = makeIcon(logo, "mark", 16, T.White)
    mark.Frame.Position = UDim2.new(0.5, -8, 0.5, -8)

    local TitleLabel = label(ui.DragStrip, "Haruko", UDim2.fromOffset(50, 44), UDim2.fromOffset(0, 18), {
        font = F.Bold,
        size = 15,
        autosize = Enum.AutomaticSize.X,
        yalign = Enum.TextYAlignment.Top,
    })
    local VersionLabel = label(ui.DragStrip, VERSION, UDim2.fromOffset(112, 44), UDim2.fromOffset(0, 18), {
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

    ui.FooterDot = new("Frame", {
        Position = UDim2.new(0, 16, 1, -50),
        Size = UDim2.fromOffset(8, 8),
        BackgroundColor3 = T.Muted,
        BorderSizePixel = 0,
    }, Sidebar)
    round(ui.FooterDot, 4)
    ui.FooterText = label(Sidebar, "Tour idle", UDim2.new(0, 32, 1, -56), UDim2.new(1, -40, 0, 20), {
        color = T.Muted,
        size = 12,
        font = F.Medium,
    })
    label(Sidebar, "RightShift: hide / show", UDim2.new(0, 16, 1, -34), UDim2.new(1, -24, 0, 24), {
        color = T.Muted,
        size = 11,
    })

    ui.Topbar = new("Frame", {
        Position = UDim2.fromOffset(SIDEBAR_W, 0),
        Size = UDim2.new(1, -SIDEBAR_W, 0, 56),
        BackgroundTransparency = 1,
        Active = true,
    }, MainFrame)
    local PageTitle = label(ui.Topbar, "", UDim2.fromOffset(16, 10), UDim2.new(1, -32, 0, 22), { font = F.Bold, size = 18 })
    local PageSubtitle = label(ui.Topbar, "", UDim2.fromOffset(16, 33), UDim2.new(1, -32, 0, 16), { color = T.Muted, size = 12 })
    new("Frame", {
        Position = UDim2.new(0, 16, 1, -1),
        Size = UDim2.new(1, -32, 0, 1),
        BackgroundColor3 = T.White,
        BackgroundTransparency = 0.92,
        BorderSizePixel = 0,
    }, ui.Topbar)

    local Content = new("Frame", {
        Position = UDim2.fromOffset(SIDEBAR_W + 16, 62),
        Size = UDim2.fromOffset(PAGE_W, PAGE_H),
        BackgroundTransparency = 1,
        ClipsDescendants = true,
    }, MainFrame)

    local PAGE_INFO = {
        General = { "General", "Modules you can toggle and bind" },
        Objects = { "Objects", "Pick objects in the world and set an action for each" },
        Settings = { "Settings", "Appearance, configs and locations" },
    }

    local tabs = {}
    local currentPage
    local pageToken = 0

    function showPage(name, instant)
        if currentPage == name then
            return
        end
        closeDropdown(true)
        pageToken += 1
        local token = pageToken
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
        for _, other in pairs(pages) do
            if other ~= page and other.Visible then
                tween(other, { Position = UDim2.fromOffset(0, 8), GroupTransparency = 1 }, instant and 0 or 0.14)
                task.delay(instant and 0 or 0.15, function()
                    if token == pageToken then
                        other.Visible = false
                        other.Position = UDim2.fromOffset(0, 0)
                    end
                end)
            end
        end

        page.Visible = true
        if instant then
            page.Position = UDim2.fromOffset(0, 0)
            page.GroupTransparency = 0
            return
        end
        PageTitle.TextTransparency, PageSubtitle.TextTransparency = 1, 1
        tween(PageTitle, { TextTransparency = 0 }, 0.25)
        tween(PageSubtitle, { TextTransparency = 0 }, 0.3)
        page.Position = UDim2.fromOffset(0, 12)
        page.GroupTransparency = 1
        tween(page, { Position = UDim2.fromOffset(0, 0), GroupTransparency = 0 }, 0.28)
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

        local page = new("CanvasGroup", {
            Name = name,
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
            GroupTransparency = 1,
            Visible = false,
        }, Content)
        pages[name] = page
        return page
    end

    addPage("General", "grid", 1)
    addPage("Objects", "cube", 2)
    addPage("Settings", "gear", 3)
end

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

do
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
    }, pages.General)

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
        local edge = hairline(cardFrame, 0.92)

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
        chip.MouseEnter:Connect(function()
            tween(chip, { BackgroundTransparency = 0.82 }, 0.1)
        end)
        chip.MouseLeave:Connect(function()
            tween(chip, { BackgroundTransparency = 0.9 }, 0.12)
        end)

        local function paint(on)
            icon.SetColor(on and T.AccentHi or T.Text, true)
            tween(edge, { Color = on and T.Accent or T.White, Transparency = on and 0.45 or 0.92 }, 0.2)
        end
        local function toggle(on)
            paint(on)
            def.onToggle(on)
        end
        local sw = switch(head, UDim2.new(1, -46, 0.5, -12), false, toggle)

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
            notify("Press a key. Backspace unbinds, Esc cancels", "info")
        end)

        if bodyH > 0 then
            local body = new("Frame", {
                Position = UDim2.fromOffset(0, MOD_HEAD),
                Size = UDim2.new(1, 0, 0, bodyH),
                BackgroundTransparency = 1,
            }, cardFrame)
            def.build(body)
        end

        modUi[def.id] = {
            name = def.name,
            persist = def.persist,
            bind = nil,
            chip = chip,
            switch = sw,
            onToggle = toggle,
            paint = paint,
        }
    end

    local moduleSpecs = {
        {
            id = "speed",
            name = "Speed",
            desc = "Boost horizontal movement",
            icon = "fast",
            body = 78,
            persist = true,
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
                table.insert(syncers, function()
                    sl.Set(motion.speed)
                    box.Text = tostring(motion.speed)
                end)
            end,
        },
        {
            id = "fly",
            name = "Fly",
            desc = "Classic flight, or a gliding dive",
            icon = "fly",
            body = 184,
            onToggle = function(on)
                setFly(on)
            end,
            build = function(body)
                label(body, "Mode", UDim2.fromOffset(12, 4), UDim2.fromOffset(80, 16), { color = T.Muted, size = 12 })
                local mode = segmented(body, UDim2.fromOffset(12, 22), UDim2.fromOffset(colW - 24, 28), { "Default", "Glide" }, motion.flyMode, function(v)
                    motion.flyMode = v
                end)
                label(body, "Speed", UDim2.fromOffset(12, 58), UDim2.fromOffset(80, 16), { font = F.Medium, size = 12 })
                local speedRead = label(body, tostring(motion.flySpeed), UDim2.new(1, -72, 0, 58), UDim2.fromOffset(60, 16), {
                    color = T.Muted,
                    size = 12,
                    align = Enum.TextXAlignment.Right,
                })
                local speedSl = slider(body, UDim2.fromOffset(12, 80), colW - 24, 16, 300, motion.flySpeed, false, function(v)
                    motion.flySpeed = math.floor(v + 0.5)
                    speedRead.Text = tostring(motion.flySpeed)
                end)
                label(body, "Sink", UDim2.fromOffset(12, 100), UDim2.fromOffset(80, 16), { font = F.Medium, size = 12 })
                local sinkRead = label(body, tostring(motion.glideSink), UDim2.new(1, -72, 0, 100), UDim2.fromOffset(60, 16), {
                    color = T.Muted,
                    size = 12,
                    align = Enum.TextXAlignment.Right,
                })
                local sinkSl = slider(body, UDim2.fromOffset(12, 122), colW - 24, 2, 60, motion.glideSink, false, function(v)
                    motion.glideSink = math.floor(v + 0.5)
                    sinkRead.Text = tostring(motion.glideSink)
                end)
                label(body, "WASD to move, Space / E up, Ctrl / Q down. Glide keeps momentum and sinks unless you climb.",
                    UDim2.fromOffset(12, 140), UDim2.new(1, -24, 0, 34), { color = T.Muted, size = 11, wrap = true })
                table.insert(syncers, function()
                    mode.Set(motion.flyMode)
                    speedSl.Set(motion.flySpeed)
                    speedRead.Text = tostring(motion.flySpeed)
                    sinkSl.Set(motion.glideSink)
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
                local origin = dropdown(body, UDim2.fromOffset(12, 24), UDim2.fromOffset(colW - 24, 28), { "Start", "Center", "End" }, motion.tpOrigin, function(v)
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
                table.insert(syncers, function()
                    origin.Set(motion.tpOrigin)
                    box.Text = fmt(motion.tpOffset)
                end)
            end,
        },
        {
            id = "click",
            name = "Click",
            desc = "Repeat a click off this window",
            icon = "click",
            body = 96,
            persist = true,
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
                local sl = slider(body, UDim2.fromOffset(12, 36), colW - 24, 0.05, 1, motion.clickInterval, true, function(v)
                    motion.clickInterval = math.floor(v * 100 + 0.5) / 100
                    read.Text = fmt(motion.clickInterval) .. "s"
                end)
                table.insert(syncers, function()
                    sl.Set(motion.clickInterval)
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
            persist = true,
            onToggle = function(on)
                setNoclip(on)
            end,
        },
        {
            id = "antiload",
            name = "Anti Loading",
            desc = "Skip Gameplay paused screens",
            icon = "clock",
            body = 0,
            persist = true,
            onToggle = function(on)
                setAntiPause(on)
            end,
        },
        {
            id = "render",
            name = "Render Distance",
            desc = "Keep far content and draw farther",
            icon = "eye",
            body = 142,
            persist = true,
            onToggle = function(on)
                setRender(on)
            end,
            build = function(body)
                local rows = {
                    { "keep", "Keep loaded", "Far parts stop unloading" },
                    { "quality", "Max draw distance", "Highest graphics level" },
                    { "fog", "Remove fog", "Clear fog and haze" },
                }
                for i, row in ipairs(rows) do
                    local key, y = row[1], 4 + (i - 1) * 34
                    label(body, row[2], UDim2.fromOffset(12, y), UDim2.new(1, -70, 0, 16), { font = F.Medium, size = 12 })
                    label(body, row[3], UDim2.fromOffset(12, y + 16), UDim2.new(1, -70, 0, 14), { color = T.Muted, size = 11 })
                    local sw = switch(body, UDim2.new(1, -54, 0, y + 4), motion.render[key], function(v)
                        motion.render[key] = v
                        if motion.renderOn then
                            setRender(true)
                        end
                    end)
                    table.insert(syncers, function()
                        sw.Set(motion.render[key])
                    end)
                end
                label(body, "The server decides how far content streams. This keeps what already arrived.",
                    UDim2.fromOffset(12, 106), UDim2.new(1, -24, 0, 30), { color = T.Muted, size = 11, wrap = true })
            end,
        },
        {
            id = "tour",
            name = "Auto Tour",
            desc = "Run the current list",
            icon = "lines",
            body = 392,
            persist = true,
            onToggle = function(on)
                if not on then
                    cancelMovement((touring or motion.tourPending) and "Tour stopped" or nil)
                    return
                end
                if touring or motion.tourPending then
                    return
                end
                motion.tourPending = true
                task.spawn(function()
                    local waited = false
                    while motion.tourPending and not (humanoidRootPart and humanoidRootPart.Parent) do
                        waited = true
                        task.wait(0.5)
                    end
                    if waited then
                        task.wait(2)
                    end
                    if motion.tourPending then
                        motion.tourPending = false
                        startTour()
                        updateTourUI()
                    end
                end)
            end,
            build = function(body)
                local w = colW - 24
                local muted = { color = T.Muted, size = 12 }
                label(body, "Order", UDim2.fromOffset(12, 4), UDim2.fromOffset(w, 16), muted)
                local orderDd = dropdown(body, UDim2.fromOffset(12, 22), UDim2.fromOffset(w, 28),
                    { "Forward", "Reverse", "Ping-pong", "Random" }, tour.order, function(v)
                        tour.order = v
                    end)
                label(body, "Loop forever", UDim2.fromOffset(12, 62), UDim2.fromOffset(w - 50, 20), { font = F.Medium, size = 12 })
                local loopSw = switch(body, UDim2.new(1, -54, 0, 60), tour.loop, function(v)
                    tour.loop = v
                end)
                label(body, "Pause, sec", UDim2.fromOffset(12, 96), UDim2.fromOffset(w - 70, 20), { font = F.Medium, size = 12 })
                ui.IntervalBox = input(body, UDim2.new(1, -72, 0, 94), UDim2.fromOffset(60, 24), fmt(tour.interval), "0.5")
                ui.IntervalBox.TextXAlignment = Enum.TextXAlignment.Center
                ui.IntervalSlider = slider(body, UDim2.fromOffset(12, 130), w, 0.05, 5, tour.interval, true, function(v)
                    tour.interval = math.floor(v * 100 + 0.5) / 100
                    ui.IntervalBox.Text = fmt(tour.interval)
                end)
                ui.TourProgress = label(body, "Idle", UDim2.fromOffset(12, 146), UDim2.fromOffset(w, 16), {
                    color = T.Muted,
                    size = 11,
                    truncate = Enum.TextTruncate.AtEnd,
                })

                label(body, "New object defaults", UDim2.fromOffset(12, 174), UDim2.fromOffset(w, 18), { font = F.Bold, size = 12 })
                label(body, "Action", UDim2.fromOffset(12, 196), UDim2.fromOffset(w, 16), muted)
                local defAction = dropdown(body, UDim2.fromOffset(12, 214), UDim2.fromOffset(w, 28), ACTIONS, D.action, function(v)
                    D.action = v
                end)
                local half = (w - 8) / 2
                label(body, "Speed", UDim2.fromOffset(12, 250), UDim2.fromOffset(half, 16), muted)
                label(body, "Offset", UDim2.fromOffset(20 + half, 250), UDim2.fromOffset(half, 16), muted)
                ui.DefSpeedBox = input(body, UDim2.fromOffset(12, 268), UDim2.fromOffset(half, 28), fmt(D.speed), "40")
                ui.DefOffsetBox = input(body, UDim2.fromOffset(20 + half, 268), UDim2.fromOffset(half, 28), fmt(D.offset), "3")

                local third = (w - 16) / 3
                local axisDds = {}
                for i, axis in ipairs({ "x", "y", "z" }) do
                    local x = 12 + (i - 1) * (third + 8)
                    label(body, axis:upper() .. " axis", UDim2.fromOffset(x, 304), UDim2.fromOffset(third, 16), muted)
                    axisDds[axis] = dropdown(body, UDim2.fromOffset(x, 322), UDim2.fromOffset(third, 28),
                        { "Start", "Center", "End" }, D.tp[axis], function(v)
                            D.tp[axis] = v
                        end)
                end
                ui.ApplyAllBtn = button(body, "Apply to all objects", UDim2.fromOffset(12, 358), UDim2.fromOffset(w, 28), "secondary")

                table.insert(syncers, function()
                    orderDd.Set(tour.order)
                    loopSw.Set(tour.loop)
                    ui.IntervalSlider.Set(tour.interval)
                    ui.IntervalBox.Text = fmt(tour.interval)
                    defAction.Set(D.action)
                    ui.DefSpeedBox.Text = fmt(D.speed)
                    ui.DefOffsetBox.Text = fmt(D.offset)
                    for axis, dd in pairs(axisDds) do
                        dd.Set(D.tp[axis])
                    end
                end)
            end,
        },
        {
            id = "autoexec",
            name = "Auto Execute",
            desc = "Reload Haruko after a rejoin",
            icon = "gear",
            body = 66,
            persist = true,
            onToggle = function(on)
                if not setAutoExec(on) and on then
                    notify("This executor has no queue_on_teleport", "error")
                    task.defer(function()
                        modUi.autoexec.switch.Set(false)
                        modUi.autoexec.paint(false)
                    end)
                end
            end,
            build = function(body)
                label(body, "Server restarts and updates move you to a new server without a prompt. This queues Haruko to load there.",
                    UDim2.fromOffset(12, 4), UDim2.new(1, -24, 0, 54), { color = T.Muted, size = 11, wrap = true })
            end,
        },
        {
            id = "reconnect",
            name = "Auto Reconnect",
            desc = "Rejoin after a kick or disconnect",
            icon = "info",
            body = 96,
            persist = true,
            onToggle = function(on)
                motion.reconnectOn = on
                if on then
                    motion.reconnectNow()
                end
            end,
            build = function(body)
                label(body, "Delay", UDim2.fromOffset(12, 8), UDim2.fromOffset(80, 16), { font = F.Medium, size = 12 })
                local read = label(body, motion.reconnectDelay .. "s", UDim2.new(1, -72, 0, 8), UDim2.fromOffset(60, 16), {
                    color = T.Muted,
                    size = 12,
                    align = Enum.TextXAlignment.Right,
                })
                local sl = slider(body, UDim2.fromOffset(12, 36), colW - 24, 1, 60, motion.reconnectDelay, true, function(v)
                    motion.reconnectDelay = math.floor(v + 0.5)
                    read.Text = motion.reconnectDelay .. "s"
                end)
                table.insert(syncers, function()
                    sl.Set(motion.reconnectDelay)
                    read.Text = motion.reconnectDelay .. "s"
                end)
                label(body, "Tries the same server first. Pair with Auto Execute to reload Haruko.",
                    UDim2.fromOffset(12, 56), UDim2.new(1, -24, 0, 32), { color = T.Muted, size = 11, wrap = true })
            end,
        },
    }

    for i, def in ipairs(moduleSpecs) do
        local col = (i % 2 == 1) and leftCol or rightCol
        buildModule(col, math.ceil(i / 2), def)
    end
end

--==============================================================================
-- 8. OBJECTS, TOUR, SETTINGS
--==============================================================================

do
    ui.AddBtn = button(pages.Objects, "Add", UDim2.fromOffset(0, 0), UDim2.fromOffset(104, 34), "primary", "plus")
    segmented(pages.Objects, UDim2.fromOffset(112, 0), UDim2.fromOffset(128, 34), { "Part", "Model" }, pickType, function(v)
        pickType = v
    end)
    label(pages.Objects, "X-ray", UDim2.fromOffset(258, 0), UDim2.fromOffset(40, 34), { color = T.Muted, size = 12 })
    switch(pages.Objects, UDim2.fromOffset(298, 5), xray, function(v)
        xray = v
    end)
    label(pages.Objects, "Show saved", UDim2.new(1, -140, 0, 0), UDim2.fromOffset(90, 34), {
        color = T.Muted,
        size = 12,
        align = Enum.TextXAlignment.Right,
    })
    switch(pages.Objects, UDim2.new(1, -42, 0, 5), false, function(v)
        espOn = v
        refreshESP()
    end)

    ui.HintLabel = label(pages.Objects, "Press Add, then click an object in the world.",
        UDim2.fromOffset(2, 40), UDim2.fromOffset(400, 16), { color = T.Muted, size = 12 })
    ui.CountLabel = label(pages.Objects, "0 objects", UDim2.new(1, -140, 0, 40), UDim2.fromOffset(140, 16), {
        color = T.Muted,
        size = 12,
        align = Enum.TextXAlignment.Right,
    })

    local ListCard = card(pages.Objects, UDim2.fromOffset(0, 62), UDim2.fromOffset(PAGE_W, PAGE_H - 62))
    ui.ListNameBox = input(ListCard, UDim2.fromOffset(12, 12), UDim2.fromOffset(236, 32), "", "List name")
    ui.ListNameBox.Font = F.Bold
    ui.ListArrow = button(ListCard, "", UDim2.fromOffset(254, 12), UDim2.fromOffset(32, 32), "secondary", "chevron")
    ui.NewListBtn = button(ListCard, "New list", UDim2.fromOffset(294, 12), UDim2.fromOffset(120, 32), "secondary", "plus")
    ui.DelListBtn = button(ListCard, "Delete", UDim2.fromOffset(422, 12), UDim2.fromOffset(110, 32), "danger", "close")

    ui.ListScroll = new("ScrollingFrame", {
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
    round(ui.ListScroll, 10)
    hairline(ui.ListScroll, 0.94)
    new("UIListLayout", { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }, ui.ListScroll)
    new("UIPadding", {
        PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6),
        PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 9),
    }, ui.ListScroll)

    ui.EmptyLabel = label(ui.ListScroll, "This list is empty.\nPress Add and click an object in the world.",
        UDim2.new(), UDim2.new(1, 0, 0, 70),
        { color = T.Muted, size = 13, wrap = true, align = Enum.TextXAlignment.Center })

    ui.SettingsScroll = new("ScrollingFrame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 3,
        ScrollBarImageColor3 = T.Accent,
        CanvasSize = UDim2.new(),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
    }, pages.Settings)
    ui.SettingsW = PAGE_W - 10

    local SW = ui.SettingsW
    local AppearanceCard = card(ui.SettingsScroll, UDim2.fromOffset(0, 0), UDim2.fromOffset(SW, 112),
        "Appearance", "Applies to the window, notifications and dialogs")
    local function percent(v)
        return string.format("%d%%", math.floor(v * 100 + 0.5))
    end
    label(AppearanceCard, "Opacity", UDim2.fromOffset(14, 54), UDim2.fromOffset(200, 20), { font = F.Medium })
    local OpacityValue = label(AppearanceCard, percent(settings.opacity), UDim2.new(1, -74, 0, 54), UDim2.fromOffset(60, 20), {
        color = T.Muted,
        size = 12,
        align = Enum.TextXAlignment.Right,
    })
    local opacitySl = slider(AppearanceCard, UDim2.fromOffset(14, 86), SW - 28, 0.5, 1, settings.opacity, false, function(v)
        settings.opacity = v
        OpacityValue.Text = percent(v)
        applyOpacity()
    end)

    table.insert(syncers, function()
        opacitySl.Set(settings.opacity)
        OpacityValue.Text = percent(settings.opacity)
    end)
end

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
                modUi.teleport.paint(false)
            end
            if pickKind == "teleport" then
                pickKind = nil
            end
        end
        pickKind = "add"
        btnText(ui.AddBtn, "Cancel")
        btnIcon(ui.AddBtn, "close")
        setButtonStyle(ui.AddBtn, "danger")
        ui.HintLabel.Text = xray and "Click an object. X-ray skips invisible and zero-size parts."
            or "Click an object in the world."
    else
        if pickKind == "add" then
            pickKind = nil
        end
        btnText(ui.AddBtn, "Add")
        btnIcon(ui.AddBtn, "plus")
        setButtonStyle(ui.AddBtn, "primary")
        ui.HintLabel.Text = "Press Add, then click an object in the world."
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
    }, ui.ListScroll)
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
    if ui.ListNameBox.Text ~= list.name then
        ui.ListNameBox.Text = list.name
    end
    ui.CountLabel.Text = string.format("%d object%s", #list.items, #list.items == 1 and "" or "s")

    for _, child in ipairs(ui.ListScroll:GetChildren()) do
        if child:IsA("Frame") then
            child:Destroy()
        end
    end

    ui.EmptyLabel.Visible = (#list.items == 0)
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
    local mod = modUi.tour
    local on = touring or motion.tourPending
    if mod and mod.switch.Get() ~= on then
        mod.switch.Set(on)
        mod.paint(on)
    end
    if touring then
        ui.FooterText.Text = "Tour running"
        tween(ui.FooterText, { TextColor3 = T.Success }, 0.2)
        tween(ui.FooterDot, { BackgroundColor3 = T.Success }, 0.2)
    else
        ui.FooterText.Text = motion.tourPending and "Tour waiting" or "Tour idle"
        tween(ui.FooterText, { TextColor3 = T.Muted }, 0.2)
        tween(ui.FooterDot, { BackgroundColor3 = T.Muted }, 0.2)
        ui.TourProgress.Text = "Idle"
    end
end

function cancelMovement(message)
    moveToken += 1
    motion.wish = nil
    touring = false
    motion.tourPending = false
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
            ui.TourProgress.Text = string.format("%d/%d  %s  -  %s", index, n, item.name, item.action)
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

do
    local function axis(pos, neg, alt)
        local down = UserInputService:IsKeyDown(pos) or (alt and UserInputService:IsKeyDown(alt))
        return (down and 1 or 0) - (UserInputService:IsKeyDown(neg) and 1 or 0)
    end

    local function flyInput()
        if UserInputService:GetFocusedTextBox() then
            return 0, 0, 0
        end
        local K = Enum.KeyCode
        local up = axis(K.Space, K.LeftControl, K.E)
        if UserInputService:IsKeyDown(K.Q) then
            up -= 1
        end
        return axis(K.W, K.S), axis(K.D, K.A), math.clamp(up, -1, 1)
    end

    local function flyBody(hrp)
        if motion.flyVel and motion.flyVel.Parent == hrp then
            return motion.flyVel, motion.flyGyro
        end
        dropFlyBody()
        motion.flyVel = new("BodyVelocity", {
            Name = "HarukoFly",
            MaxForce = Vector3.one * 9e9,
            P = 9e4,
            Velocity = Vector3.zero,
        }, hrp)
        motion.flyGyro = new("BodyGyro", {
            Name = "HarukoFlyGyro",
            MaxTorque = Vector3.one * 9e9,
            P = 9e4,
            D = 600,
            CFrame = hrp.CFrame,
        }, hrp)
        return motion.flyVel, motion.flyGyro
    end

    local function stepFly(dt, hrp, hum, wish)
        local cam = workspace.CurrentCamera
        if not cam then
            return
        end
        local bv, gyro = flyBody(hrp)
        local cf = cam.CFrame
        local f, r, u = flyInput()
        local move = cf.LookVector * f + cf.RightVector * r
        if wish then
            local flat = Vector3.new(wish.point.X - hrp.Position.X, 0, wish.point.Z - hrp.Position.Z)
            move = flat.Magnitude > 0.05 and flat.Unit or Vector3.zero
        elseif move.Magnitude < 0.01 then
            local md = hum.MoveDirection
            move = Vector3.new(md.X, 0, md.Z)
        end
        move += Vector3.yAxis * u
        local speed = wish and wish.speed or motion.flySpeed
        local target = move.Magnitude > 0.01 and move.Unit * speed or Vector3.zero

        local flatLook = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
        if flatLook.Magnitude < 0.01 then
            flatLook = Vector3.new(hrp.CFrame.LookVector.X, 0, hrp.CFrame.LookVector.Z)
        end
        local facing = CFrame.lookAt(Vector3.zero, flatLook.Unit)

        if motion.flyMode == "Glide" then
            if u <= 0 then
                target += Vector3.new(0, -motion.glideSink, 0)
            end
            motion.glideVel = motion.glideVel:Lerp(target, 1 - math.exp(-2.5 * dt))
            bv.Velocity = motion.glideVel
            local horiz = Vector3.new(motion.glideVel.X, 0, motion.glideVel.Z)
            if horiz.Magnitude > 2 then
                facing = CFrame.lookAt(Vector3.zero, horiz.Unit)
            end
            local pitch = math.clamp(motion.glideVel.Y / math.max(speed, 1), -0.6, 0.4)
            gyro.CFrame = CFrame.new(hrp.Position) * facing * CFrame.Angles(pitch, 0, -r * 0.45)
        else
            bv.Velocity = target
            gyro.CFrame = CFrame.new(hrp.Position) * facing * CFrame.Angles(-math.rad(18) * f, 0, -math.rad(10) * r)
        end
    end

    local function stepMotion(dt)
        if unloading then
            return
        end
        if motion.noclipOn then
            applyNoclip()
        end
        if motion.suppress > 0 then
            if motion.flyVel then
                motion.flyVel.Velocity = Vector3.zero
            end
            return
        end

        local hrp, hum = humanoidRootPart, humanoid
        if not hrp or not hum or not hrp.Parent or not hrp:IsDescendantOf(workspace) then
            return
        end

        local wish = motion.wish
        if motion.flyOn then
            if not hum.PlatformStand then
                hum.PlatformStand = true
            end
            stepFly(dt, hrp, hum, wish)
            return
        end
        if not motion.speedOn and not wish then
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
            end
            speed = motion.speed
        end

        -- Wish speed wins over the Speed module so the two do not stack.
        -- Ground steps add (speed - walk speed) because the humanoid still moves at WalkSpeed.

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
end

--==============================================================================
-- 11. PRESETS, INPUT, WINDOW
--==============================================================================

ui.AddBtn.Activated:Connect(function()
    setPickMode(not pickMode)
end)

ui.ListArrow.Activated:Connect(function()
    local names = {}
    for i, l in ipairs(lists) do
        names[i] = string.format("%s  (%d)", l.name, #l.items)
    end
    openDropdown(ui.ListNameBox, names, activeList, function(_, idx)
        switchList(idx)
    end)
end)

ui.ListNameBox.FocusLost:Connect(function()
    local text = ui.ListNameBox.Text:gsub("^%s+", ""):gsub("%s+$", "")
    if text ~= "" then
        currentList().name = text
    end
    ui.ListNameBox.Text = currentList().name
end)

ui.NewListBtn.Activated:Connect(function()
    table.insert(lists, newList("List " .. (#lists + 1)))
    switchList(#lists)
    setStatus("New list created", "success")
end)

ui.DelListBtn.Activated:Connect(function()
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

ui.DefSpeedBox.FocusLost:Connect(function()
    local v = tonumber(ui.DefSpeedBox.Text)
    if v and v > 0 then
        D.speed = v
    end
    ui.DefSpeedBox.Text = fmt(D.speed)
end)

ui.DefOffsetBox.FocusLost:Connect(function()
    local v = tonumber(ui.DefOffsetBox.Text)
    if v then
        D.offset = v
    end
    ui.DefOffsetBox.Text = fmt(D.offset)
end)

ui.ApplyAllBtn.Activated:Connect(function()
    local list = currentList()
    for _, it in ipairs(list.items) do
        it.action, it.speed, it.offset = D.action, D.speed, D.offset
        it.tp = { x = D.tp.x, y = D.tp.y, z = D.tp.z }
    end
    refreshList()
    setStatus(string.format("Applied defaults to %d object(s)", #list.items), "success")
end)

ui.IntervalBox.FocusLost:Connect(function()
    local v = tonumber(ui.IntervalBox.Text)
    if v then
        tour.interval = math.clamp(v, 0.02, 60)
        ui.IntervalSlider.Set(tour.interval)
    end
    ui.IntervalBox.Text = fmt(tour.interval)
end)

local function setupStorage()
    local ROOT = "Haruko"
    local CONFIG_DIR = ROOT .. "/configs"
    local LOCATIONS_DIR = ROOT .. "/locations"
    local LEGACY_LOCATIONS = ROOT .. "/locations.json"
    local LEGACY_PRESETS = "AdminPanel_Presets.json"
    local META_FILE = ROOT .. "/settings.json"
    local canFiles = (writefile and readfile and isfile) and true or false
    local meta = { autoload = nil, autosave = true, configs = {}, lists = {} }
    local activeConfig, lastConfig
    local writtenLists = {}

    local function decode(text)
        local ok, data = pcall(function()
            return HttpService:JSONDecode(text)
        end)
        return ok and type(data) == "table" and data or nil
    end

    local function ensureFolders()
        if not (canFiles and isfolder and makefolder) then
            return
        end
        for _, dir in ipairs({ ROOT, CONFIG_DIR, LOCATIONS_DIR }) do
            pcall(function()
                if not isfolder(dir) then
                    makefolder(dir)
                end
            end)
        end
    end

    local function readText(path)
        if not canFiles then
            return nil
        end
        local ok, text = pcall(function()
            return isfile(path) and readfile(path) or nil
        end)
        return ok and text or nil
    end

    local function writeText(path, text)
        return canFiles and (pcall(writefile, path, text))
    end

    local function configPath(name)
        return CONFIG_DIR .. "/" .. name .. ".json"
    end

    local function locationPath(name)
        return LOCATIONS_DIR .. "/" .. name .. ".json"
    end

    local function listJson(dir, fallback)
        if not (canFiles and listfiles) then
            return fallback
        end
        local ok, paths = pcall(listfiles, dir)
        if not ok or type(paths) ~= "table" then
            return fallback
        end
        local names = {}
        for _, path in ipairs(paths) do
            local name = tostring(path):match("([^/\\]+)%.json$")
            if name then
                table.insert(names, name)
            end
        end
        table.sort(names)
        return names
    end

    local function cleanName(text)
        local name = tostring(text or ""):gsub("[^%w%s%-_]", ""):gsub("^%s+", ""):gsub("%s+$", "")
        return name:sub(1, 32)
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

    local function parseLists(data)
        local out = {}
        if type(data) == "table" and type(data.lists) ~= "table" and type(data.items) == "table" then
            data = { lists = { data } }
        end
        if type(data) ~= "table" or type(data.lists) ~= "table" then
            return out
        end
        for _, l in ipairs(data.lists) do
            if type(l) == "table" and type(l.name) == "string" and type(l.items) == "table" then
                local list = newList(l.name)
                for _, raw in ipairs(l.items) do
                    local item = normalizeItem(raw, l.tp, l.offset)
                    if item then
                        table.insert(list.items, item)
                    end
                end
                table.insert(out, list)
            end
        end
        return out
    end

    local function encodeLists(source)
        local out = {}
        for _, l in ipairs(source) do
            table.insert(out, { name = l.name, items = l.items })
        end
        return HttpService:JSONEncode({ version = 4, lists = out })
    end

    local function listNameTaken(name)
        for _, l in ipairs(lists) do
            if l.name == name then
                return true
            end
        end
        return false
    end

    local function importLists(text)
        local parsed = parseLists(decode(text))
        if #parsed == 0 then
            return false, "No valid lists found in that text"
        end
        local objects = 0
        for _, list in ipairs(parsed) do
            local base, k = list.name, 1
            while listNameTaken(list.name) do
                k += 1
                list.name = string.format("%s (%d)", base, k)
            end
            table.insert(lists, list)
            objects += #list.items
        end
        switchList(#lists)
        return true, string.format("Imported %d list(s), %d object(s)", #parsed, objects)
    end

    local function num(v, lo, hi, fallback)
        return type(v) == "number" and math.clamp(v, lo, hi) or fallback
    end

    local function oneOf(v, options, fallback)
        return table.find(options, v) and v or fallback
    end

    local function bool(v, fallback)
        if type(v) == "boolean" then
            return v
        end
        return fallback
    end

    local function keyFromName(name)
        if type(name) ~= "string" then
            return nil
        end
        local ok, code = pcall(function()
            return Enum.KeyCode[name]
        end)
        if ok and code and code ~= Enum.KeyCode.RightShift then
            return code
        end
        return nil
    end

    local function snapshot(name)
        local mods = {}
        for id, mod in pairs(modUi) do
            mods[id] = {
                on = mod.persist and mod.switch.Get() or nil,
                bind = mod.bind and mod.bind.Name or nil,
            }
        end
        return {
            version = 2,
            name = name,
            settings = { opacity = settings.opacity },
            modules = mods,
            motion = {
                speed = motion.speed,
                flyMode = motion.flyMode,
                flySpeed = motion.flySpeed,
                glideSink = motion.glideSink,
                tpOrigin = motion.tpOrigin,
                tpOffset = motion.tpOffset,
                clickInterval = motion.clickInterval,
                reconnectDelay = motion.reconnectDelay,
                render = motion.render,
            },
            defaults = { action = D.action, speed = D.speed, offset = D.offset, tp = D.tp },
            tour = { order = tour.order, loop = tour.loop, interval = tour.interval, list = currentList().name },
        }
    end

    local function applyConfig(cfg)
        local s = type(cfg.settings) == "table" and cfg.settings or {}
        local m = type(cfg.motion) == "table" and cfg.motion or {}
        local d = type(cfg.defaults) == "table" and cfg.defaults or {}
        local t = type(cfg.tour) == "table" and cfg.tour or {}
        local mods = type(cfg.modules) == "table" and cfg.modules or {}

        settings.opacity = num(s.opacity, 0.5, 1, settings.opacity)

        motion.speed = num(m.speed, 16, 500, motion.speed)
        motion.flyMode = oneOf(m.flyMode, { "Default", "Glide" }, motion.flyMode)
        motion.flySpeed = num(m.flySpeed, 16, 300, motion.flySpeed)
        motion.glideSink = num(m.glideSink, 2, 60, motion.glideSink)
        motion.tpOrigin = oneOf(m.tpOrigin, { "Start", "Center", "End" }, motion.tpOrigin)
        motion.tpOffset = num(m.tpOffset, -1000, 1000, motion.tpOffset)
        motion.clickInterval = num(m.clickInterval, 0.05, 1, motion.clickInterval)
        motion.reconnectDelay = math.floor(num(m.reconnectDelay, 1, 60, motion.reconnectDelay))
        if type(m.render) == "table" then
            for key, value in pairs(motion.render) do
                motion.render[key] = bool(m.render[key], value)
            end
        end

        D.action = oneOf(d.action, ACTIONS, D.action)
        D.speed = num(d.speed, 1, 1000, D.speed)
        D.offset = num(d.offset, -1000, 1000, D.offset)
        if type(d.tp) == "table" then
            for _, axis in ipairs({ "x", "y", "z" }) do
                if TP_SET[d.tp[axis]] then
                    D.tp[axis] = d.tp[axis]
                end
            end
        end

        tour.order = oneOf(t.order, { "Forward", "Reverse", "Ping-pong", "Random" }, tour.order)
        tour.loop = bool(t.loop, tour.loop)
        tour.interval = num(t.interval, 0.02, 60, tour.interval)
        for i, list in ipairs(lists) do
            if list.name == t.list and i ~= activeList then
                switchList(i)
                break
            end
        end

        for _, sync in ipairs(syncers) do
            sync()
        end
        applyOpacity()

        for id, mod in pairs(modUi) do
            local saved = type(mods[id]) == "table" and mods[id] or {}
            mod.bind = keyFromName(saved.bind)
            mod.chip.Text = keyLabel(mod.bind)
            if mod.persist then
                local want = saved.on == true
                if mod.switch.Get() ~= want then
                    mod.switch.Set(want)
                    mod.onToggle(want)
                end
            end
        end
        if motion.renderOn then
            setRender(true)
        end
    end

    local function saveMeta()
        writeText(META_FILE, HttpService:JSONEncode(meta))
    end

    local function addToIndex(name)
        if not table.find(meta.configs, name) then
            table.insert(meta.configs, name)
        end
    end

    local function saveConfig(name)
        local json = HttpService:JSONEncode(snapshot(name))
        if not writeText(configPath(name), json) then
            return false
        end
        addToIndex(name)
        activeConfig, lastConfig = name, json
        saveMeta()
        return true
    end

    local function loadConfig(name)
        local data = decode(readText(configPath(name)) or "")
        if not data then
            return false
        end
        applyConfig(data)
        activeConfig = name
        lastConfig = HttpService:JSONEncode(snapshot(name))
        return true
    end

    local function deleteConfig(name)
        if delfile then
            pcall(delfile, configPath(name))
        end
        local i = table.find(meta.configs, name)
        if i then
            table.remove(meta.configs, i)
        end
        if meta.autoload == name then
            meta.autoload = nil
        end
        if activeConfig == name then
            activeConfig = nil
        end
        saveMeta()
    end

    local function refreshIndex()
        meta.configs = listJson(CONFIG_DIR, meta.configs)
    end

    local function saveLocations()
        local used, desired, files = {}, {}, {}
        for i, list in ipairs(lists) do
            local base = cleanName(list.name)
            base = base ~= "" and base or "List"
            local name, k = base, 1
            while used[name] do
                k += 1
                name = base .. " " .. k
            end
            used[name] = true
            table.insert(files, name)
            desired[name] = HttpService:JSONEncode({ version = 4, order = i, name = list.name, items = list.items })
        end
        for name, json in pairs(desired) do
            if writtenLists[name] ~= json and writeText(locationPath(name), json) then
                writtenLists[name] = json
            end
        end
        for name in pairs(writtenLists) do
            if not desired[name] then
                if delfile then
                    pcall(delfile, locationPath(name))
                end
                writtenLists[name] = nil
            end
        end
        if table.concat(files, "\n") ~= table.concat(meta.lists, "\n") then
            meta.lists = files
            saveMeta()
        end
    end

    local function loadLocations()
        local found = {}
        for _, name in ipairs(listJson(LOCATIONS_DIR, meta.lists)) do
            local text = readText(locationPath(name))
            local data = decode(text or "")
            local list = parseLists(data)[1]
            if list then
                writtenLists[name] = text
                table.insert(found, { list = list, order = tonumber(data.order) or math.huge })
            end
        end
        table.sort(found, function(a, b)
            return a.order < b.order
        end)
        local out = {}
        for _, entry in ipairs(found) do
            table.insert(out, entry.list)
        end
        if #out == 0 then
            out = parseLists(decode(readText(LEGACY_LOCATIONS) or ""))
            if #out > 0 and delfile then
                task.defer(function()
                    saveLocations()
                    pcall(delfile, LEGACY_LOCATIONS)
                end)
            end
        end
        if #out == 0 then
            out = parseLists(decode(readText(LEGACY_PRESETS) or ""))
        end
        return out
    end

    function persistNow()
        if not canFiles then
            return
        end
        saveLocations()
        if meta.autosave and activeConfig then
            local json = HttpService:JSONEncode(snapshot(activeConfig))
            if json ~= lastConfig and writeText(configPath(activeConfig), json) then
                lastConfig = json
            end
        end
    end

    local SW = ui.SettingsW
    local ConfigCard = card(ui.SettingsScroll, UDim2.fromOffset(0, 124), UDim2.fromOffset(SW, 300),
        "Configs", "Modules, binds, appearance and tour. Locations are stored apart.")
    local nameBox = input(ConfigCard, UDim2.fromOffset(12, 52), UDim2.fromOffset(SW - 140, 32), "", "Config name")
    local saveBtn = button(ConfigCard, "Save", UDim2.fromOffset(SW - 116, 52), UDim2.fromOffset(104, 32), "primary", "check")

    local ShareCard = card(ui.SettingsScroll, UDim2.fromOffset(0, 436), UDim2.fromOffset(SW, 236),
        "Share", "Select the text and press Ctrl+C, or paste with Ctrl+V and press Import")
    local shareBox = input(ShareCard, UDim2.fromOffset(12, 52), UDim2.fromOffset(SW - 24, 124), "", "Config or location text")
    shareBox.MultiLine = true
    shareBox.TextWrapped = true
    shareBox.TextYAlignment = Enum.TextYAlignment.Top
    shareBox.TextXAlignment = Enum.TextXAlignment.Left
    shareBox.Font = Enum.Font.Code
    shareBox.TextSize = 12
    shareBox.ClipsDescendants = true
    local sharePad = shareBox:FindFirstChildOfClass("UIPadding")
    if sharePad then
        sharePad.PaddingTop = UDim.new(0, 8)
        sharePad.PaddingBottom = UDim.new(0, 8)
    end
    local shareW = (SW - 24 - 24) / 4
    local importBtn = button(ShareCard, "Import", UDim2.fromOffset(12, 188), UDim2.fromOffset(shareW, 34), "primary", "plus")
    local listBtn = button(ShareCard, "Current list", UDim2.fromOffset(20 + shareW, 188), UDim2.fromOffset(shareW, 34), "secondary")
    local allBtn = button(ShareCard, "All lists", UDim2.fromOffset(28 + shareW * 2, 188), UDim2.fromOffset(shareW, 34), "secondary")
    local clearBtn = button(ShareCard, "Clear", UDim2.fromOffset(36 + shareW * 3, 188), UDim2.fromOffset(shareW, 34), "secondary")

    local function share(text, what)
        shareBox.Text = text
        ui.SettingsScroll.CanvasPosition = Vector2.new(0, ShareCard.Position.Y.Offset)
        notify(what .. " is in the Share box. Select it and press Ctrl+C", "success")
    end

    local configList = new("ScrollingFrame", {
        Position = UDim2.fromOffset(12, 94),
        Size = UDim2.new(1, -24, 0, 150),
        BackgroundColor3 = T.Dark,
        BackgroundTransparency = 0.6,
        BorderSizePixel = 0,
        ScrollBarThickness = 3,
        ScrollBarImageColor3 = T.Accent,
        CanvasSize = UDim2.new(),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
    }, ConfigCard)
    round(configList, 10)
    hairline(configList, 0.94)
    new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, configList)
    new("UIPadding", {
        PaddingTop = UDim.new(0, 5), PaddingBottom = UDim.new(0, 5),
        PaddingLeft = UDim.new(0, 5), PaddingRight = UDim.new(0, 8),
    }, configList)

    label(ConfigCard, "Auto-save active config", UDim2.fromOffset(14, 254), UDim2.fromOffset(260, 20), { font = F.Medium })
    label(ConfigCard, "Changes are written every few seconds", UDim2.fromOffset(14, 272), UDim2.fromOffset(300, 16), {
        color = T.Muted,
        size = 11,
    })
    local autosaveSw = switch(ConfigCard, UDim2.new(1, -56, 0, 258), meta.autosave, function(v)
        meta.autosave = v
        saveMeta()
    end)

    local renderConfigs

    local function configRow(name, order)
        local active = name == activeConfig
        local isAuto = name == meta.autoload
        local row = new("Frame", {
            Size = UDim2.new(1, 0, 0, 40),
            BackgroundColor3 = active and T.Accent or T.White,
            BackgroundTransparency = active and 0.84 or 0.95,
            BorderSizePixel = 0,
            LayoutOrder = order,
        }, configList)
        round(row, 8)
        label(row, name, UDim2.fromOffset(12, 0), UDim2.new(1, -246, 1, 0), {
            font = active and F.Bold or F.Medium,
            truncate = Enum.TextTruncate.AtEnd,
        })

        local auto = button(row, "Autoload", UDim2.new(1, -234, 0.5, -14), UDim2.fromOffset(84, 28), isAuto and "primary" or "secondary")
        local load = button(row, "Load", UDim2.new(1, -146, 0.5, -14), UDim2.fromOffset(64, 28), "secondary")
        local copy = button(row, "", UDim2.new(1, -78, 0.5, -14), UDim2.fromOffset(34, 28), "secondary", "lines")
        local del = button(row, "", UDim2.new(1, -40, 0.5, -14), UDim2.fromOffset(34, 28), "danger", "close")

        auto.Activated:Connect(function()
            meta.autoload = (not isAuto) and name or nil
            saveMeta()
            renderConfigs()
            notify(isAuto and "Nothing loads on start" or (name .. " loads on start"), "info")
        end)
        load.Activated:Connect(function()
            if loadConfig(name) then
                notify("Loaded " .. name, "success")
            else
                notify("Couldn't read " .. name, "error")
            end
            renderConfigs()
        end)
        copy.Activated:Connect(function()
            local data = decode(readText(configPath(name)) or "")
            if data then
                data.name = name
                share(HttpService:JSONEncode(data), name)
            else
                notify("Couldn't read " .. name, "error")
            end
        end)
        del.Activated:Connect(function()
            task.spawn(function()
                local ok = confirm({
                    title = "Delete config",
                    body = "Delete " .. name .. "? Your locations stay untouched.",
                    confirmText = "Delete",
                    danger = true,
                })
                if ok then
                    deleteConfig(name)
                    renderConfigs()
                    notify("Deleted " .. name, "warn")
                end
            end)
        end)
    end

    function renderConfigs()
        refreshIndex()
        for _, child in ipairs(configList:GetChildren()) do
            if child:IsA("GuiObject") then
                child:Destroy()
            end
        end
        if #meta.configs == 0 then
            label(configList, canFiles and "No configs yet. Name one above and press Save."
                or "This executor can't write files, so configs are unavailable.",
                UDim2.new(), UDim2.new(1, 0, 0, 60), {
                    color = T.Muted,
                    size = 12,
                    wrap = true,
                    align = Enum.TextXAlignment.Center,
                })
            return
        end
        for i, name in ipairs(meta.configs) do
            configRow(name, i)
        end
    end

    local function uniqueConfigName(base)
        local name, k = base, 1
        while table.find(meta.configs, name) do
            k += 1
            name = string.format("%s %d", base, k)
        end
        return name
    end

    saveBtn.Activated:Connect(function()
        if not canFiles then
            notify("This executor can't write files", "error")
            return
        end
        local name = cleanName(nameBox.Text)
        if name == "" then
            name = activeConfig
        end
        if not name then
            notify("Type a config name first", "warn")
            return
        end
        if saveConfig(name) then
            if not meta.autoload then
                meta.autoload = name
                saveMeta()
            end
            nameBox.Text = ""
            renderConfigs()
            notify("Saved " .. name, "success")
        else
            notify("Failed to write the config", "error")
        end
    end)

    local function importConfig(data)
        if not canFiles then
            notify("This executor can't write files", "error")
            return
        end
        local base = cleanName(nameBox.Text)
        base = base ~= "" and base or cleanName(data.name)
        local name = uniqueConfigName(base ~= "" and base or "Imported")
        data.name = name
        if writeText(configPath(name), HttpService:JSONEncode(data)) then
            addToIndex(name)
            saveMeta()
            nameBox.Text = ""
            shareBox.Text = ""
            renderConfigs()
            notify("Imported " .. name .. ". Press Load to apply it", "success")
        else
            notify("Failed to write the config", "error")
        end
    end

    importBtn.Activated:Connect(function()
        local text = shareBox.Text
        local data = decode(text)
        if not data then
            notify("Paste a Haruko config or location list first", "warn")
        elseif type(data.settings) == "table" or type(data.modules) == "table" or type(data.motion) == "table" then
            importConfig(data)
        else
            local ok, msg = importLists(text)
            if ok then
                shareBox.Text = ""
            end
            notify(msg, ok and "success" or "error")
        end
    end)
    listBtn.Activated:Connect(function()
        share(encodeLists({ currentList() }), "Current list")
    end)
    allBtn.Activated:Connect(function()
        share(encodeLists(lists), string.format("%d list(s)", #lists))
    end)
    clearBtn.Activated:Connect(function()
        shareBox.Text = ""
    end)

    label(ui.SettingsScroll, canFiles
        and "workspace/Haruko keeps one file per config in configs/ and one per list in locations/. Drop files there and they load on the next start."
        or "This executor can't write files, so nothing is saved between sessions.",
        UDim2.fromOffset(2, 684), UDim2.fromOffset(SW, 32), { color = T.Muted, size = 12, wrap = true })

    ensureFolders()
    local stored = decode(readText(META_FILE) or "") or decode(readText(ROOT .. "/meta.json") or "")
    if stored then
        meta.autoload = type(stored.autoload) == "string" and stored.autoload or nil
        meta.autosave = stored.autosave ~= false
        for _, key in ipairs({ "configs", "lists" }) do
            for _, name in ipairs(type(stored[key]) == "table" and stored[key] or {}) do
                if type(name) == "string" and not table.find(meta[key], name) then
                    table.insert(meta[key], name)
                end
            end
        end
    end
    refreshIndex()

    local savedLists = loadLocations()
    if #savedLists > 0 then
        lists = savedLists
        activeList = 1
    end

    if meta.autoload and table.find(meta.configs, meta.autoload) and loadConfig(meta.autoload) then
        task.defer(notify, "Loaded config " .. meta.autoload, "info")
    elseif canFiles and #meta.configs == 0 and saveConfig("Default") then
        meta.autoload = "Default"
        saveMeta()
    end
    autosaveSw.Set(meta.autosave)
    renderConfigs()

    table.insert(connections, player.OnTeleport:Connect(function(state)
        if state == Enum.TeleportState.Started then
            pcall(persistNow)
        end
    end))

    task.spawn(function()
        while not unloading do
            task.wait(3)
            if not unloading then
                pcall(persistNow)
            end
        end
    end)
end
setupStorage()

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
    if unloading then
        return
    end
    pcall(persistNow)
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
    if motion.antiPauseOn then
        setAntiPause(false)
    end
    if motion.renderOn then
        setRender(false)
    end
    if humanoid and humanoid.Parent then
        humanoid.WalkSpeed = NORMAL_SPEED
    end
    cancelMovement()
    hideWindow(function()
        for _, c in ipairs(connections) do
            c:Disconnect()
        end
        HighlightFolder:Destroy()
        ScreenGui:Destroy()
    end)
end
ScreenGui.Destroying:Connect(unload)

local function clearListen(restore)
    if not listening or not modUi[listening] then
        listening = nil
        return
    end
    local mod = modUi[listening]
    listening = nil
    if restore then
        mod.chip.Text = keyLabel(mod.bind)
        mod.chip.TextColor3 = T.Muted
    end
end

table.insert(connections, UserInputService.InputBegan:Connect(function(inp, gameProcessed)
    if dialogBusy and inp.KeyCode == Enum.KeyCode.Escape then
        dialogFinish(false)
        return
    end

    if listening and inp.UserInputType == Enum.UserInputType.Keyboard and not UserInputService:GetFocusedTextBox() then
        local code = inp.KeyCode
        local mod = modUi[listening]
        if code == Enum.KeyCode.Escape then
            clearListen(true)
            return
        elseif code == Enum.KeyCode.Backspace then
            mod.bind = nil
            clearListen(true)
            notify(mod.name .. " unbound", "info")
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
            mod.bind = code
            clearListen(true)
            notify(mod.name .. " bound to " .. keyLabel(code), "success")
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
        for _, mod in pairs(modUi) do
            if mod.bind and mod.bind == inp.KeyCode then
                local nextOn = not mod.switch.Get()
                mod.switch.Set(nextOn)
                mod.onToggle(nextOn)
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
                modUi.teleport.paint(false)
            end
            setTeleport(false)
        else
            setStatus("Can't teleport there", "error")
        end
    end
end))

ui.HideDot.Activated:Connect(function()
    if dialogBusy then
        return
    end
    hideWindow()
    notify("RightShift to show", "info")
end)

ui.CenterDot.Activated:Connect(function()
    tween(MainFrame, { Position = UDim2.new(0.5, -WIN_W / 2, 0.5, -WIN_H / 2) }, 0.35)
end)

ui.CloseDot.Activated:Connect(function()
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
bindDrag(ui.Topbar)
bindDrag(ui.DragStrip)

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
