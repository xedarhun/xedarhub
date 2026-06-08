local _version = "1.6.64-fix"
local WindUI = loadstring(game:HttpGet("https://github.com/Footagesus/WindUI/releases/download/" .. _version .. "/main.lua"))()
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local Event = game:GetService("ReplicatedStorage").REPLICATEDSTORAGE.Mechanics.Weapon

-- === Config System ===
local CONFIG_FOLDER = "OwnerPanel"
local CONFIG_EXT = ".json"

local function ensureFolder()
    if not isfolder(CONFIG_FOLDER) then makefolder(CONFIG_FOLDER) end
end

local function getConfigList()
    ensureFolder()
    local files = listfiles(CONFIG_FOLDER)
    local configs = {}
    for _, path in ipairs(files) do
        local name = path:match("([^/\\]+)%.json$")
        if name and name ~= "autoload" then table.insert(configs, name) end
    end
    if #configs == 0 then table.insert(configs, "(none)") end
    return configs
end

local function saveConfig(name, data)
    ensureFolder()
    local ok = pcall(function()
        writefile(CONFIG_FOLDER .. "/" .. name .. CONFIG_EXT, HttpService:JSONEncode(data))
    end)
    return ok
end

local function loadConfigData(name)
    local path = CONFIG_FOLDER .. "/" .. name .. CONFIG_EXT
    if not isfile(path) then return nil end
    local ok, result = pcall(function() return HttpService:JSONDecode(readfile(path)) end)
    if ok then return result end
    return nil
end

local function deleteConfigFile(name)
    local path = CONFIG_FOLDER .. "/" .. name .. CONFIG_EXT
    if isfile(path) then pcall(function() delfile(path) end) end
end

local function getAutoLoad()
    ensureFolder()
    local path = CONFIG_FOLDER .. "/autoload.json"
    if not isfile(path) then return "" end
    local ok, result = pcall(function() return HttpService:JSONDecode(readfile(path)) end)
    if ok and result and result.name then return result.name end
    return ""
end

local function setAutoLoad(name)
    ensureFolder()
    pcall(function()
        writefile(CONFIG_FOLDER .. "/autoload.json", HttpService:JSONEncode({ name = name }))
    end)
end

-- === State ===
local enabled      = false
local notifEnabled = true
local AVOID_RADIUS = 20
local jumpEnabled  = false
local jumpPower    = 55.7
local wasJumping   = false
-- Keybind state: these store the active key strings so configs can save/restore them.
-- WindUI's Keybind element tracks the active key internally; we mirror it here.
local aimKey  = "F"
local jumpKey = "G"

-- Forward declarations so applyConfig can reference UI elements created later
local enableToggle, notifToggle, jumpToggle, avoidSlider
local aimKeybind, jumpKeybind
local selectDropdown, autoDropdown

local function getCurrentConfig()
    return {
        enabled      = enabled,
        notifEnabled = notifEnabled,
        avoidRadius  = AVOID_RADIUS,
        jumpEnabled  = jumpEnabled,
        jumpPower    = jumpPower,
        -- Read directly from the element at save time so we always get the current key,
        -- even if the user rebound it without us catching a change event.
        aimKey       = (aimKeybind  and aimKeybind.Value)  or aimKey,
        jumpKey      = (jumpKeybind and jumpKeybind.Value) or jumpKey,
    }
end

local function applyConfig(data)
    if not data then return end
    if data.avoidRadius  ~= nil then AVOID_RADIUS = data.avoidRadius;  if avoidSlider  then avoidSlider:Set(AVOID_RADIUS)  end end
    if data.jumpPower    ~= nil then jumpPower    = data.jumpPower                                                              end
    if data.enabled      ~= nil then enabled      = data.enabled;      if enableToggle  then enableToggle:Set(enabled)      end end
    if data.jumpEnabled  ~= nil then jumpEnabled  = data.jumpEnabled;  if jumpToggle    then jumpToggle:Set(jumpEnabled)    end end
    if data.notifEnabled ~= nil then notifEnabled = data.notifEnabled; if notifToggle   then notifToggle:Set(notifEnabled)  end end
    -- Restore keybinds: update our mirror variable and tell the element to display the new key
    if data.aimKey  ~= nil then aimKey  = data.aimKey;  if aimKeybind  then aimKeybind:Set(aimKey)   end end
    if data.jumpKey ~= nil then jumpKey = data.jumpKey; if jumpKeybind then jumpKeybind:Set(jumpKey)  end end
end

-- === Window ===
local Window = WindUI:CreateWindow({
    Title     = "Owner Panel",
    Icon      = "shield",
    Author    = "Formless Auto-Aim",
    ToggleKey = Enum.KeyCode.RightControl,
})

local FormlessTab = Window:Tab({ Title = "Formless",  Icon = "target"    })
local MovementTab = Window:Tab({ Title = "Movement",  Icon = "footprints" })
local ConfigTab   = Window:Tab({ Title = "Configs",   Icon = "save"      })

local SettingsSection    = FormlessTab:Section({ Title = "Settings"  })
local AvoidSection       = FormlessTab:Section({ Title = "Avoidance" })
local KeybindSection     = FormlessTab:Section({ Title = "Keybinds"  })
local JumpSection        = MovementTab:Section({ Title = "Jump Power" })
local JumpKeybindSection = MovementTab:Section({ Title = "Keybinds"  })
local ConfigSection      = ConfigTab:Section({  Title = "Config Manager" })

local function notify(title, content, icon, duration)
    if not notifEnabled then return end
    WindUI:Notify({ Title = title, Content = content, Icon = icon, Duration = duration or 2 })
end

-- === Goals ===
local goalA = Workspace.Map_Events.SIDE_A.Goal2.Net
local goalB = Workspace.Map_Events.SIDE_B.NetHitbox1
local selectedGoal = goalA

local function getGoalCFAndSize(goal)
    if goal:IsA("BasePart") then return goal.CFrame, goal.Size
    else return goal:GetBoundingBox() end
end

local function updateSelectedGoal()
    local character = Players.LocalPlayer.Character
    local hrp = character and character:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local cfA = getGoalCFAndSize(goalA)
    local cfB = getGoalCFAndSize(goalB)
    local distA = (hrp.Position - cfA.Position).Magnitude
    local distB = (hrp.Position - cfB.Position).Magnitude
    local newGoal = distA < distB and goalA or goalB
    if newGoal ~= selectedGoal then
        selectedGoal = newGoal
        notify("Auto Goal", "Switched to " .. (newGoal == goalA and "Side A" or "Side B"), "map-pin", 2)
    end
end

-- === Settings ===
enableToggle = SettingsSection:Toggle({
    Title    = "Enable Auto-Aim",
    Value    = false,
    Callback = function(state)
        enabled = state
        notify("Auto-Aim", enabled and "Enabled!" or "Disabled.", enabled and "check" or "x", 2)
    end,
})

notifToggle = SettingsSection:Toggle({
    Title    = "Enable Notifications",
    Value    = true,
    Callback = function(state) notifEnabled = state end,
})

-- === Avoidance ===
avoidSlider = AvoidSection:Slider({
    Title    = "Player Avoid Radius",
    Value    = { Min = 1, Max = 50, Default = AVOID_RADIUS },
    Callback = function(val) AVOID_RADIUS = val end,
})

-- === Keybinds (Formless) ===
-- NOTE: WindUI Keybind callbacks fire only on keypress with no arguments.
-- We read the current key back from the element via :GetValue() after the user
-- rebinds, using a Changed listener so aimKey stays in sync for config saving.
aimKeybind = KeybindSection:Keybind({
    Title    = "Toggle Auto-Aim",
    Value    = aimKey,
    Callback = function()
        enabled = not enabled
        if enableToggle then enableToggle:Set(enabled) end
        notify("Auto-Aim", enabled and "Enabled!" or "Disabled.", enabled and "check" or "x", 2)
    end,
})


-- === Jump ===
jumpToggle = JumpSection:Toggle({
    Title    = "Enable Jump Power",
    Value    = false,
    Callback = function(state)
        jumpEnabled = state
        notify("Jump Power", jumpEnabled and "Enabled! " .. jumpPower .. " studs" or "Disabled.", jumpEnabled and "check" or "x", 2)
    end,
})

JumpSection:Input({
    Title       = "Jump Power (studs)",
    Placeholder = "Enter jump power (default: 55.7)",
    Callback    = function(text)
        local num = tonumber(text)
        if num then
            jumpPower = num
            notify("Jump Power", "Set to " .. jumpPower .. " studs", "check", 2)
        else
            notify("Invalid Input", "Please enter a valid number!", "alert-circle", 2)
        end
    end,
})

-- === Keybinds (Jump) ===
jumpKeybind = JumpKeybindSection:Keybind({
    Title    = "Toggle Jump Power",
    Value    = jumpKey,
    Callback = function()
        jumpEnabled = not jumpEnabled
        if jumpToggle then jumpToggle:Set(jumpEnabled) end
        notify("Jump Power", jumpEnabled and "Enabled! " .. jumpPower .. " studs" or "Disabled.", jumpEnabled and "check" or "x", 2)
    end,
})


-- === Config UI ===
local configNameInput = ""
local selectedConfig  = ""
local autoLoadName    = getAutoLoad()

-- Refreshes both dropdowns with the current file list.
-- Called after every save/delete so new configs appear immediately.
local function refreshDropdowns()
    local list = getConfigList()
    if selectDropdown then selectDropdown:Refresh(list, list[1]) end
    if autoDropdown   then
        local autoDefault = (autoLoadName ~= "" and autoLoadName) or list[1]
        autoDropdown:Refresh(list, autoDefault)
    end
    selectedConfig = ""
end

ConfigSection:Input({
    Title       = "Config Name",
    Placeholder = "Enter config name...",
    Callback    = function(text)
        configNameInput = text:match("^%s*(.-)%s*$") or ""
    end,
})

ConfigSection:Button({
    Title    = "💾 Save Config",
    Callback = function()
        if configNameInput == "" then
            notify("Config", "Enter a name first!", "alert-circle", 3)
            return
        end
        local ok = saveConfig(configNameInput, getCurrentConfig())
        notify("Config", ok and "Saved: " .. configNameInput or "Save failed!", ok and "check" or "x", 2)
        if ok then refreshDropdowns() end
    end,
})

local configList = getConfigList()
selectDropdown = ConfigSection:Dropdown({
    Title    = "Select Config",
    Values   = configList,
    Value    = configList[1],
    Callback = function(option)
        selectedConfig = option ~= "(none)" and option or ""
    end,
})

ConfigSection:Button({
    Title    = "📂 Load Config",
    Callback = function()
        if selectedConfig == "" then
            notify("Config", "Select a config first!", "alert-circle", 3)
            return
        end
        local data = loadConfigData(selectedConfig)
        if data then
            applyConfig(data)
            notify("Config", "Loaded: " .. selectedConfig, "check", 2)
        else
            notify("Config", "Failed to load!", "x", 2)
        end
    end,
})

ConfigSection:Button({
    Title    = "✏️ Overwrite Config",
    Callback = function()
        if selectedConfig == "" then
            notify("Config", "Select a config first!", "alert-circle", 3)
            return
        end
        local ok = saveConfig(selectedConfig, getCurrentConfig())
        notify("Config", ok and "Overwritten: " .. selectedConfig or "Failed!", ok and "check" or "x", 2)
    end,
})

ConfigSection:Button({
    Title    = "🗑️ Delete Config",
    Callback = function()
        if selectedConfig == "" then
            notify("Config", "Select a config first!", "alert-circle", 3)
            return
        end
        deleteConfigFile(selectedConfig)
        notify("Config", "Deleted: " .. selectedConfig, "trash", 2)
        refreshDropdowns()
    end,
})

local autoList = getConfigList()
autoDropdown = ConfigSection:Dropdown({
    Title    = "Auto-Load Config",
    Values   = autoList,
    Value    = (autoLoadName ~= "" and autoLoadName) or autoList[1],
    Callback = function(option)
        if option ~= "(none)" then
            autoLoadName = option
            setAutoLoad(option)
            notify("Config", "Auto-load set to: " .. option, "clock", 2)
        else
            autoLoadName = ""
            setAutoLoad("")
        end
    end,
})

-- === Auto-load on startup ===
task.defer(function()
    local name = getAutoLoad()
    if name and name ~= "" then
        local data = loadConfigData(name)
        if data then
            applyConfig(data)
            WindUI:Notify({ Title = "Config", Content = "Auto-loaded: " .. name, Icon = "check", Duration = 3 })
        end
    end
end)

-- === Sliding detection ===
local isSliding = false
RunService.Heartbeat:Connect(function()
    local character = Players.LocalPlayer.Character
    local hum = character and character:FindFirstChildOfClass("Humanoid")
    if not hum then isSliding = false return end
    local state = hum:GetState()
    isSliding = (state == Enum.HumanoidStateType.PlatformStanding)
        or (state == Enum.HumanoidStateType.Running and hum.WalkSpeed <= 0)
end)

-- === Jump Loop ===
RunService.Heartbeat:Connect(function()
    if not jumpEnabled then wasJumping = false return end
    if isSliding then wasJumping = false return end
    local character = Players.LocalPlayer.Character
    if not character then return end
    local hrp = character:FindFirstChild("HumanoidRootPart")
    local hum = character:FindFirstChildOfClass("Humanoid")
    if not hrp or not hum then return end
    local state = hum:GetState()
    local jumping = (state == Enum.HumanoidStateType.Jumping) or (state == Enum.HumanoidStateType.Freefall)
    if jumping and not wasJumping then
        local vel = hrp.AssemblyLinearVelocity
        hrp.AssemblyLinearVelocity = Vector3.new(vel.X, jumpPower, vel.Z)
        wasJumping = true
    elseif not jumping then
        wasJumping = false
    end
end)

-- === Formless Logic ===
local cachedDirection = Vector3.new(0, 0, -1)
local cachedOffsetX   = 0
local cachedHalfX     = 1
local cachedRightVec  = Vector3.new(1, 0, 0)

local function getNearestPlayerToGoal(goalPos)
    local nearest, nearestDist = nil, math.huge
    local localPlayer = Players.LocalPlayer
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= localPlayer and player.Character then
            local hrp      = player.Character:FindFirstChild("HumanoidRootPart")
            local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
            if hrp and humanoid and humanoid.Health > 0 then
                local dist = (hrp.Position - goalPos).Magnitude
                if dist < nearestDist then nearestDist = dist; nearest = hrp end
            end
        end
    end
    return nearest, nearestDist
end

local timeSinceLastCheck = 0
RunService.Heartbeat:Connect(function(dt)
    timeSinceLastCheck += dt
    if timeSinceLastCheck >= 2 then
        timeSinceLastCheck = 0
        updateSelectedGoal()
    end
    if not selectedGoal then return end
    local goalCF, goalSize = getGoalCFAndSize(selectedGoal)
    local goalPos  = goalCF.Position
    cachedHalfX    = goalSize.X / 2
    cachedRightVec = goalCF.RightVector
    local nearestPlayer, nearestDist = getNearestPlayerToGoal(goalPos)
    if nearestPlayer and nearestDist < AVOID_RADIUS then
        local playerSide = (nearestPlayer.Position - goalPos):Dot(cachedRightVec)
        cachedOffsetX = (playerSide > 0 and -1 or 1) * (math.random(50, 100) / 100) * cachedHalfX
    else
        cachedOffsetX = (math.random() * 2 - 1) * cachedHalfX
    end
end)

RunService.RenderStepped:Connect(function()
    local character = Players.LocalPlayer.Character
    local hrp = character and character:FindFirstChild("HumanoidRootPart")
    local cam = Workspace.CurrentCamera
    if not (hrp and selectedGoal and cam) then return end
    local goalCF    = getGoalCFAndSize(selectedGoal)
    local goalPos   = goalCF.Position
    local targetPos = goalPos + cachedRightVec * cachedOffsetX
    local away      = (hrp.Position - targetPos).Unit
    local camY      = cam.CFrame.LookVector.Y
    cachedDirection = Vector3.new(away.X, camY, away.Z).Unit
end)

-- === Auto-Aim Hook ===
local originalNamecall
originalNamecall = hookmetamethod(game, "__namecall", function(self, ...)
    local method = getnamecallmethod()
    if method == "InvokeServer" and self == Event then
        local args = { ... }
        if enabled and args[1] == "WEAPON1" and args[2] == "BIG BANG DRIVE" then
            args[3] = cachedDirection
            return originalNamecall(self, table.unpack(args))
        end
        return originalNamecall(self, ...)
    end
    return originalNamecall(self, ...)
end)

WindUI:Notify({ Title = "Owner Panel", Content = "Loaded! Press Right Control to toggle.", Icon = "check", Duration = 3 })
print("[Formless] GUI loaded!")
