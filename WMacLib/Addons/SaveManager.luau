--[[
    SaveManager for WMacLib (Fluent-style addon)

    Saves / loads named configs (a json file per config) made of every flagged WMacLib element:
    Toggle, Slider, Input, Keybind, Dropdown, Colorpicker. Create the elements with a flag:
        section:Toggle({ Name = "Auto pick", Default = true }, "AutoPick")

    Usage
        local SaveManager = loadstring(game:HttpGet("<raw url of this file>"))()
        SaveManager:SetLibrary(WMacLib)
        SaveManager:SetWindow(Window)                       -- optional, used for notifications
        SaveManager:SetFolder("My Script/My Game")          -- <folder>/settings/<config>.json
        SaveManager:SetIgnoreIndexes({ "SomeFlag" })        -- flags that must never be saved
        SaveManager:BuildConfigSection(tab, "Right")        -- name box, config list, create / load / overwrite / delete / autoload
        SaveManager:LoadAutoloadConfig()                    -- call after every element was created

    Flags that start with "IM_" belong to the InterfaceManager and are ignored here (it keeps its own file).
    Extra stores: values that are not UI elements (a plain table) can be saved too:
        SaveManager:AddStore("Config", ConfigTable)         -- boolean / number / string values are kept
]]

local HttpService = game:GetService("HttpService")

local SaveManager = {}
SaveManager.Folder = "WMacLibSettings"
SaveManager.SubFolder = nil
SaveManager.Library = nil
SaveManager.Window = nil
SaveManager.Ignore = {}                 -- [flag] = true
SaveManager.IgnorePrefixes = { "IM_", "SM_" }
SaveManager.Stores = {}                 -- [name] = table

------------------------------------------------------------------ helpers
local function colorToHex(c)
    return string.format("#%02X%02X%02X", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end

local function hexToColor(hex)
    return Color3.fromRGB(tonumber(hex:sub(2, 3), 16) or 0, tonumber(hex:sub(4, 5), 16) or 0, tonumber(hex:sub(6, 7), 16) or 0)
end

local function fsAvailable()
    return writefile and readfile and isfile and isfolder and makefolder and listfiles and true or false
end

------------------------------------------------------------------ element parsers
-- Save returns a json-able table, Load applies it again. The option objects expose State / Value / Text / Bind / Color / Alpha.
SaveManager.Parser = {
    Toggle = {
        Save = function(flag, option) return { type = "Toggle", flag = flag, state = option.State == true } end,
        Load = function(flag, data, lib)
            local option = lib.Options[flag]
            if option and data.state ~= nil then option:UpdateState(data.state) end
        end,
    },
    Slider = {
        Save = function(flag, option) return { type = "Slider", flag = flag, value = tonumber(option.Value) } end,
        Load = function(flag, data, lib)
            local option = lib.Options[flag]
            if option and data.value ~= nil then option:UpdateValue(data.value) end
        end,
    },
    Input = {
        Save = function(flag, option)
            -- the Text field is only filled once the user typed something, GetInput also covers the default text
            local text = option.Text
            if text == nil and option.GetInput then pcall(function() text = option:GetInput() end) end
            return { type = "Input", flag = flag, text = text }
        end,
        Load = function(flag, data, lib)
            local option = lib.Options[flag]
            if option and type(data.text) == "string" then option:UpdateText(data.text) end
        end,
    },
    Keybind = {
        Save = function(flag, option)
            local bind = option.Bind
            if bind == nil and option.GetBind then pcall(function() bind = option:GetBind() end) end
            return { type = "Keybind", flag = flag, bind = typeof(bind) == "EnumItem" and bind.Name or nil }
        end,
        Load = function(flag, data, lib)
            local option = lib.Options[flag]
            if option and data.bind and Enum.KeyCode[data.bind] then option:Bind(Enum.KeyCode[data.bind]) end
        end,
    },
    Dropdown = {
        Save = function(flag, option) return { type = "Dropdown", flag = flag, value = option.Value } end,
        Load = function(flag, data, lib)
            local option = lib.Options[flag]
            if option and data.value ~= nil then option:UpdateSelection(data.value) end
        end,
    },
    Colorpicker = {
        Save = function(flag, option)
            return { type = "Colorpicker", flag = flag, color = colorToHex(option.Color), alpha = option.Alpha }
        end,
        Load = function(flag, data, lib)
            local option = lib.Options[flag]
            if option and data.color then
                option:SetColor(hexToColor(data.color))
                if data.alpha ~= nil then option:SetAlpha(data.alpha) end
            end
        end,
    },
}

------------------------------------------------------------------ setup
function SaveManager:SetLibrary(library) self.Library = library end
function SaveManager:SetWindow(window) self.Window = window end

function SaveManager:SetIgnoreIndexes(list)
    for _, flag in ipairs(list) do self.Ignore[flag] = true end
end

function SaveManager:AddStore(name, tbl)
    self.Stores[name] = tbl
end

function SaveManager:SettingsPath()
    local path = self.Folder
    if self.SubFolder then path = path .. "/" .. self.SubFolder end
    return path .. "/settings"
end

function SaveManager:BuildFolderTree()
    if not fsAvailable() then return false end
    local path = ""
    for part in self:SettingsPath():gmatch("[^/\\]+") do   -- one level at a time, so nested folders work
        path = path == "" and part or (path .. "/" .. part)
        if not isfolder(path) then makefolder(path) end
    end
    return true
end

function SaveManager:SetFolder(folder)
    self.Folder = folder
    self:BuildFolderTree()
end

function SaveManager:SetSubFolder(sub)
    self.SubFolder = sub
    self:BuildFolderTree()
end

function SaveManager:IsIgnored(flag)
    if self.Ignore[flag] then return true end
    for _, prefix in ipairs(self.IgnorePrefixes) do
        if flag:sub(1, #prefix) == prefix then return true end
    end
    return false
end

function SaveManager:Notify(text)
    local window = self.Window
    if window and window.Notify then
        pcall(function() window:Notify({ Title = "Config", Description = text, Lifetime = 4 }) end)
    end
end

------------------------------------------------------------------ save / load / delete
function SaveManager:Save(name)
    if not fsAvailable() then return false, "file functions are not available" end
    if not name or name:gsub("%s", "") == "" then return false, "config name is empty" end
    if not self.Library then return false, "call SetLibrary first" end
    self:BuildFolderTree()

    local data = { objects = {}, stores = {} }
    for flag, option in pairs(self.Library.Options) do
        local parser = self.Parser[option.Class]
        if parser and not self:IsIgnored(flag) and not option.IgnoreConfig then
            table.insert(data.objects, parser.Save(flag, option))
        end
    end
    for storeName, tbl in pairs(self.Stores) do
        local copy = {}
        for k, v in pairs(tbl) do
            local t = type(v)
            if t == "boolean" or t == "number" or t == "string" then copy[k] = v end
        end
        data.stores[storeName] = copy
    end

    local ok, encoded = pcall(HttpService.JSONEncode, HttpService, data)
    if not ok then return false, "could not encode the config" end
    local written, err = pcall(writefile, self:SettingsPath() .. "/" .. name .. ".json", encoded)
    if not written then return false, tostring(err) end
    return true
end

function SaveManager:Load(name)
    if not fsAvailable() then return false, "file functions are not available" end
    if not name or name == "" then return false, "no config selected" end
    if not self.Library then return false, "call SetLibrary first" end

    local file = self:SettingsPath() .. "/" .. name .. ".json"
    if not isfile(file) then return false, "config does not exist" end
    local ok, decoded = pcall(function() return HttpService:JSONDecode(readfile(file)) end)
    if not ok then return false, "could not decode the config" end

    for storeName, saved in pairs(decoded.stores or {}) do
        local tbl = self.Stores[storeName]
        if tbl then
            for k, v in pairs(saved) do
                if tbl[k] ~= nil and type(tbl[k]) == type(v) then tbl[k] = v end
            end
        end
    end
    for _, object in ipairs(decoded.objects or {}) do
        local parser = self.Parser[object.type]
        if parser and not self:IsIgnored(object.flag) then
            task.spawn(function() pcall(parser.Load, object.flag, object, self.Library) end)
        end
    end
    return true
end

function SaveManager:Delete(name)
    if not fsAvailable() or not delfile then return false, "file functions are not available" end
    if not name or name == "" then return false, "no config selected" end
    local file = self:SettingsPath() .. "/" .. name .. ".json"
    if not isfile(file) then return false, "config does not exist" end
    local ok, err = pcall(delfile, file)
    if not ok then return false, tostring(err) end
    if self:GetAutoloadConfig() == name then pcall(delfile, self:SettingsPath() .. "/autoload.txt") end
    return true
end

function SaveManager:RefreshConfigList()
    if not fsAvailable() then return {} end
    self:BuildFolderTree()
    local out = {}
    for _, file in ipairs(listfiles(self:SettingsPath())) do
        local name = file:match("([^/\\]+)%.json$")
        if name then table.insert(out, name) end
    end
    table.sort(out)
    return out
end

------------------------------------------------------------------ autoload
function SaveManager:SetAutoloadConfig(name)
    if not fsAvailable() then return false end
    self:BuildFolderTree()
    return pcall(writefile, self:SettingsPath() .. "/autoload.txt", name)
end

function SaveManager:GetAutoloadConfig()
    if not fsAvailable() then return nil end
    local file = self:SettingsPath() .. "/autoload.txt"
    if isfile(file) then return readfile(file) end
    return nil
end

function SaveManager:LoadAutoloadConfig()
    local name = self:GetAutoloadConfig()
    if not name or name == "" then return false, "no autoload config" end
    local ok, err = self:Load(name)
    self:Notify(ok and string.format("autoloaded config %q", name) or ("autoload failed: " .. tostring(err)))
    return ok, err
end

------------------------------------------------------------------ ui
-- name box + config list + buttons, added to `tab` as a section on the given side
function SaveManager:BuildConfigSection(tab, side)
    assert(self.Library, "SaveManager:SetLibrary must be called before BuildConfigSection")
    local section = tab:Section({ Side = side or "Right" })
    section:Header({ Text = "Configuration" })

    local nameBox = section:Input({
        Name = "Config name",
        Placeholder = "my config",
        Default = "",
    }, "SM_ConfigName")

    local list = section:Dropdown({
        Name = "Config list",
        Options = self:RefreshConfigList(),
        Multi = false,
        Required = false,
    }, "SM_ConfigList")

    local function selected()
        local value = list.Value
        if type(value) == "table" then value = next(value) end
        return value
    end

    local function refreshList(select)
        list:ClearOptions()
        list:InsertOptions(self:RefreshConfigList())
        if select then list:UpdateSelection(select) end
    end

    local autoloadLabel
    local function refreshAutoload()
        local name = self:GetAutoloadConfig()
        if autoloadLabel then
            local text = "autoload config: " .. (name or "none")
            for _, method in ipairs({ "UpdateName", "SetName" }) do
                if autoloadLabel[method] and pcall(autoloadLabel[method], autoloadLabel, text) then return end
            end
        end
    end

    section:Button({
        Name = "Create config",
        Callback = function()
            local name = nameBox:GetInput()
            local ok, err = self:Save(name)
            self:Notify(ok and string.format("created config %q", name) or ("could not create: " .. tostring(err)))
            if ok then refreshList(name) end
        end,
    })
    section:Button({
        Name = "Load config",
        Callback = function()
            local name = selected()
            local ok, err = self:Load(name)
            self:Notify(ok and string.format("loaded config %q", tostring(name)) or ("could not load: " .. tostring(err)))
        end,
    })
    section:Button({
        Name = "Overwrite config",
        Callback = function()
            local name = selected()
            local ok, err = self:Save(name)
            self:Notify(ok and string.format("overwrote config %q", tostring(name)) or ("could not overwrite: " .. tostring(err)))
        end,
    })
    section:Button({
        Name = "Delete config",
        Callback = function()
            local name = selected()
            local ok, err = self:Delete(name)
            self:Notify(ok and string.format("deleted config %q", tostring(name)) or ("could not delete: " .. tostring(err)))
            if ok then refreshList() refreshAutoload() end
        end,
    })
    section:Button({
        Name = "Refresh list",
        Callback = function() refreshList() end,
    })
    section:Button({
        Name = "Set as autoload",
        Callback = function()
            local name = selected()
            if not name then self:Notify("select a config first") return end
            if self:SetAutoloadConfig(name) then
                self:Notify(string.format("%q will load automatically", name))
                refreshAutoload()
            end
        end,
    })
    autoloadLabel = section:SubLabel({ Text = "autoload config: " .. (self:GetAutoloadConfig() or "none") })

    return section
end

return SaveManager
