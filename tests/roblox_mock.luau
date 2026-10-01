local env = (function()
    local NUMBERS = { X = 0, Z = 0, Magnitude = 0, Scale = 1, Offset = 0, Width = 0, Height = 0 }
    local magic
    local meta = {}

    meta.__index = function(t, k)
        if NUMBERS[k] ~= nil then
            return NUMBERS[k]
        end
        local props = rawget(t, "__props")
        if props and props[k] ~= nil then
            return props[k]
        end
        return magic(tostring(k))
    end
    meta.__newindex = function(t, k, v)
        rawget(t, "__props")[k] = v
    end
    meta.__call = function()
        return magic("call")
    end
    for _, op in ipairs({ "__add", "__sub", "__mul", "__div", "__unm", "__mod", "__pow", "__idiv" }) do
        meta[op] = function()
            return magic("op")
        end
    end
    meta.__lt = function()
        return false
    end
    meta.__le = function()
        return true
    end
    meta.__len = function()
        return 0
    end
    meta.__concat = function()
        return "magic"
    end
    meta.__iter = function()
        return next, {}
    end
    meta.__tostring = function(t)
        return "magic:" .. rawget(t, "__name")
    end

    function magic(name)
        return setmetatable({ __name = name, __props = {} }, meta)
    end

    local function instance(class)
        local o = magic(class)
        local p = rawget(o, "__props")
        p.ClassName = class
        p.Name = class
        p.FindFirstChild = function() return nil end
        p.FindFirstChildOfClass = function() return nil end
        p.GetChildren = function() return {} end
        p.GetDescendants = function() return {} end
        p.IsA = function() return false end
        return o
    end

    local function constructor()
        return setmetatable({ zero = magic("zero"), one = magic("one"), yAxis = magic("yAxis") }, {
            __index = function()
                return function()
                    return magic("value")
                end
            end,
        })
    end

    local stored, nextId = {}, 0
    local function copy(v)
        if type(v) ~= "table" then
            return v
        end
        local out = {}
        for k, x in pairs(v) do
            out[k] = copy(x)
        end
        return out
    end

    local services = {}
    local game = instance("DataModel")
    rawget(game, "__props").GetService = function(_, name)
        services[name] = services[name] or instance(name)
        return services[name]
    end
    local http = game:GetService("HttpService")
    rawget(http, "__props").JSONEncode = function(_, value)
        nextId += 1
        local key = "json#" .. nextId
        stored[key] = copy(value)
        return key
    end
    rawget(http, "__props").JSONDecode = function(_, text)
        assert(stored[text], "invalid json: " .. tostring(text))
        return copy(stored[text])
    end
    local player = instance("Player")
    rawget(game:GetService("Players"), "__props").LocalPlayer = player

    local workspace = instance("Workspace")
    rawget(workspace, "__props").CurrentCamera = nil

    local files = {}

    return setmetatable({
        __files = files,
        game = game,
        workspace = workspace,
        Enum = magic("Enum"),
        Instance = { new = instance },
        UDim2 = constructor(),
        UDim = constructor(),
        Vector2 = constructor(),
        Vector3 = constructor(),
        Color3 = constructor(),
        CFrame = constructor(),
        TweenInfo = constructor(),
        NumberSequence = constructor(),
        RaycastParams = constructor(),
        settings = function() return magic("RenderSettings") end,
        UserSettings = function() return magic("UserSettings") end,
        typeof = function(v)
            return type(v) == "table" and "Instance" or type(v)
        end,
        warn = function(...)
            error("warn: " .. table.concat({ ... }, " "))
        end,
        task = {
            spawn = function(f, ...)
                local ok, err = pcall(f, ...)
                if not ok and not tostring(err):find("mock wait", 1, true) then
                    error(err, 0)
                end
            end,
            defer = function(f, ...)
                f(...)
            end,
            delay = function() end,
            wait = function()
                error("mock wait")
            end,
        },
        writefile = function(path, text)
            files[path] = text
        end,
        readfile = function(path)
            return files[path]
        end,
        isfile = function(path)
            return files[path] ~= nil
        end,
        isfolder = function()
            return true
        end,
        makefolder = function() end,
        delfile = function(path)
            files[path] = nil
        end,
        listfiles = function(dir)
            local out = {}
            for path in pairs(files) do
                if path:sub(1, #dir + 1) == dir .. "/" then
                    table.insert(out, path)
                end
            end
            return out
        end,
    }, { __index = _G })
end)()
