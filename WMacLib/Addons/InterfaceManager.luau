--[[
    InterfaceManager for WMacLib (Fluent-style addon)

    Interface settings for the window: theme (built-in + a custom theme you build with colour pickers), acrylic blur,
    UI scale, menu keybind, user info (show / hide / redact), notifications and an optional gradient title.
    Everything is saved to <folder>/interface.json and applied again on the next start.

    Usage
        local InterfaceManager = loadstring(game:HttpGet("<raw url of this file>"))()
        InterfaceManager:SetLibrary(WMacLib)
        InterfaceManager:SetWindow(Window)
        InterfaceManager:SetFolder("My Script/My Game")
        InterfaceManager:BuildInterfaceSection(tab, "Left")     -- adds the controls (call after SaveManager:SetFolder if you use both)
        -- InterfaceManager:ApplySettings() is called for you at the end of BuildInterfaceSection

    Window functions used: SetAcrylicBlurState, SetScale, SetKeybind, SetUserInfoState, SetNotificationsState and
    (customized WMacLib only) SetTitleGradient. Missing ones are skipped.
    All control flags start with "IM_" so SaveManager leaves them out of its configs.
]]

local HttpService = game:GetService("HttpService")

local InterfaceManager = {}
InterfaceManager.Folder = "WMacLibSettings"
InterfaceManager.Library = nil
InterfaceManager.Window = nil
InterfaceManager.CustomThemeName = "Custom"

local THEME_KEYS = { "Accent", "Background", "Surface", "Outline", "Text", "Placeholder", "Button", "Icon" }

InterfaceManager.Settings = {
    Theme = "Dark",
    Acrylic = true,
    Scale = 1,
    MenuKeybind = "RightControl",
    UserInfo = "Show",          -- "Show" | "Hide" | "Redact"
    Notifications = true,
    TitleGradient = false,
    TitleColorA = "#49E685",
    TitleColorB = "#6496FF",
    Custom = nil,               -- { Accent = "#18181B", ... } filled from the Dark theme on first use
}

------------------------------------------------------------------ helpers
local function colorToHex(c)
    return string.format("#%02X%02X%02X", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end

local function hexToColor(hex)
    return Color3.fromRGB(tonumber(hex:sub(2, 3), 16) or 0, tonumber(hex:sub(4, 5), 16) or 0, tonumber(hex:sub(6, 7), 16) or 0)
end

local function fsAvailable()
    return writefile and readfile and isfile and isfolder and makefolder and true or false
end

local function firstValue(v)
    if type(v) == "table" then return next(v) end
    return v
end

------------------------------------------------------------------ setup
function InterfaceManager:SetLibrary(library) self.Library = library end
function InterfaceManager:SetWindow(window) self.Window = window end

function InterfaceManager:SetFolder(folder)
    self.Folder = folder
    if fsAvailable() then
        local path = ""
        for part in folder:gmatch("[^/\\]+") do
            path = path == "" and part or (path .. "/" .. part)
            if not isfolder(path) then makefolder(path) end
        end
    end
    self:LoadSettings()
end

function InterfaceManager:SettingsFile()
    return self.Folder .. "/interface.json"
end

function InterfaceManager:SaveSettings()
    if not fsAvailable() then return false end
    local ok = pcall(function()
        writefile(self:SettingsFile(), HttpService:JSONEncode(self.Settings))
    end)
    return ok
end

function InterfaceManager:LoadSettings()
    if not (fsAvailable() and isfile(self:SettingsFile())) then return false end
    local ok, decoded = pcall(function() return HttpService:JSONDecode(readfile(self:SettingsFile())) end)
    if not ok or type(decoded) ~= "table" then return false end
    for key, value in pairs(decoded) do
        local current = self.Settings[key]
        if key == "Custom" and type(value) == "table" then
            self.Settings.Custom = value
        elseif current ~= nil and type(current) == type(value) then
            self.Settings[key] = value
        end
    end
    return true
end

------------------------------------------------------------------ themes
-- the custom theme starts as a copy of the Dark theme
function InterfaceManager:EnsureCustom()
    if self.Settings.Custom then return end
    local base = self.Library and self.Library.Themes and self.Library.Themes.Dark or {}
    local custom = {}
    for _, key in ipairs(THEME_KEYS) do
        custom[key] = colorToHex(base[key] or Color3.fromRGB(128, 128, 128))
    end
    self.Settings.Custom = custom
end

function InterfaceManager:RegisterCustomTheme()
    self:EnsureCustom()
    local theme = { Name = self.CustomThemeName }
    for _, key in ipairs(THEME_KEYS) do
        theme[key] = hexToColor(self.Settings.Custom[key] or "#808080")
    end
    self.Library:AddTheme(theme)
end

function InterfaceManager:GetThemeNames()
    local names = {}
    for _, name in ipairs(self.Library:GetThemes()) do
        if name ~= self.CustomThemeName then table.insert(names, name) end
    end
    table.sort(names)
    table.insert(names, self.CustomThemeName)
    return names
end

function InterfaceManager:SetTheme(name)
    if name == self.CustomThemeName then self:RegisterCustomTheme() end
    if self.Library.Themes[name] then
        self.Settings.Theme = name
        self.Library:SetTheme(name)
        self:SaveSettings()
        return true
    end
    return false
end

------------------------------------------------------------------ apply everything to the window
function InterfaceManager:ApplySettings()
    local lib, window, s = self.Library, self.Window, self.Settings
    assert(lib, "InterfaceManager:SetLibrary must be called first")

    self:RegisterCustomTheme()
    if lib.Themes[s.Theme] then lib:SetTheme(s.Theme) end

    if window then
        local function try(method, ...)
            if window[method] then pcall(window[method], window, ...) end
        end
        try("SetAcrylicBlurState", s.Acrylic)
        try("SetScale", s.Scale)
        if Enum.KeyCode[s.MenuKeybind] then try("SetKeybind", Enum.KeyCode[s.MenuKeybind]) end
        try("SetUserInfoState", s.UserInfo == "Hide" and false or (s.UserInfo == "Redact" and "redact" or true))
        try("SetNotificationsState", s.Notifications)
        if s.TitleGradient then
            try("SetTitleGradient", { hexToColor(s.TitleColorA), hexToColor(s.TitleColorB) })
        else
            try("SetTitleGradient", nil)
        end
    end
end

------------------------------------------------------------------ ui
function InterfaceManager:BuildInterfaceSection(tab, side)
    assert(self.Library, "InterfaceManager:SetLibrary must be called before BuildInterfaceSection")
    local lib, window, s = self.Library, self.Window, self.Settings
    self:EnsureCustom()
    self:RegisterCustomTheme()

    local section = tab:Section({ Side = side or "Left" })
    section:Header({ Text = "Interface" })

    -- theme ---------------------------------------------------------------
    local themeNames = self:GetThemeNames()
    local themeIndex = table.find(themeNames, s.Theme) or 1
    local pickers = {}
    local syncing = false          -- true while the colour pickers are filled from a theme (their callbacks must not fire)

    local function syncPickersFromTheme(name)
        local theme = lib.Themes[name]
        if not theme then return end
        syncing = true
        for _, key in ipairs(THEME_KEYS) do
            if pickers[key] and theme[key] then pcall(pickers[key].SetColor, pickers[key], theme[key]) end
        end
        syncing = false
    end

    local themeDropdown = section:Dropdown({
        Name = "Theme",
        Options = themeNames,
        Default = themeIndex,
        Multi = false,
        Required = true,
        Callback = function(value)
            local name = firstValue(value)
            if name and self:SetTheme(name) then syncPickersFromTheme(name) end
        end,
    }, "IM_Theme")

    -- window -------------------------------------------------------------
    section:Toggle({
        Name = "Acrylic blur",
        Default = s.Acrylic,
        Callback = function(value)
            s.Acrylic = value
            if window and window.SetAcrylicBlurState then window:SetAcrylicBlurState(value) end
            self:SaveSettings()
        end,
    }, "IM_Acrylic")

    section:Slider({
        Name = "UI scale",
        Default = s.Scale,
        Minimum = 0.6,
        Maximum = 1.6,
        Precision = 2,
        DisplayMethod = "Value",
        Callback = function(value)
            s.Scale = value
            if window and window.SetScale then window:SetScale(value) end
        end,
        onInputComplete = function() self:SaveSettings() end,
    }, "IM_Scale")

    section:Keybind({
        Name = "Menu keybind",
        Default = Enum.KeyCode[s.MenuKeybind] or Enum.KeyCode.RightControl,
        onBinded = function(key)    -- onBinded fires when a new key is picked (Callback fires on every press of the key)
            if typeof(key) == "EnumItem" then
                s.MenuKeybind = key.Name
                if window and window.SetKeybind then window:SetKeybind(key) end
                self:SaveSettings()
            end
        end,
    }, "IM_Keybind")

    section:Dropdown({
        Name = "User info",
        Options = { "Show", "Hide", "Redact" },
        Default = table.find({ "Show", "Hide", "Redact" }, s.UserInfo) or 1,
        Multi = false,
        Required = true,
        Callback = function(value)
            local choice = firstValue(value)
            if not choice then return end
            s.UserInfo = choice
            if window and window.SetUserInfoState then
                window:SetUserInfoState(choice == "Hide" and false or (choice == "Redact" and "redact" or true))
            end
            self:SaveSettings()
        end,
    }, "IM_UserInfo")

    section:Toggle({
        Name = "Notifications",
        Default = s.Notifications,
        Callback = function(value)
            s.Notifications = value
            if window and window.SetNotificationsState then window:SetNotificationsState(value) end
            self:SaveSettings()
        end,
    }, "IM_Notifications")

    -- title gradient (customized WMacLib) --------------------------------
    section:Divider()
    section:Header({ Text = "Title gradient" })
    local function applyTitle()
        if window and window.SetTitleGradient then
            if s.TitleGradient then
                window:SetTitleGradient({ hexToColor(s.TitleColorA), hexToColor(s.TitleColorB) })
            else
                window:SetTitleGradient(nil)
            end
        end
        self:SaveSettings()
    end
    section:Toggle({
        Name = "Gradient title",
        Default = s.TitleGradient,
        Callback = function(value) s.TitleGradient = value applyTitle() end,
    }, "IM_TitleGradient")
    section:Colorpicker({
        Name = "Title color 1",
        Default = hexToColor(s.TitleColorA),
        Callback = function(color) s.TitleColorA = colorToHex(color) applyTitle() end,
    }, "IM_TitleColorA")
    section:Colorpicker({
        Name = "Title color 2",
        Default = hexToColor(s.TitleColorB),
        Callback = function(color) s.TitleColorB = colorToHex(color) applyTitle() end,
    }, "IM_TitleColorB")

    -- custom theme -------------------------------------------------------
    local custom = tab:Section({ Side = side == "Left" and "Right" or "Left" })
    custom:Header({ Text = "Custom theme" })
    custom:SubLabel({ Text = "Change any colour and the Custom theme is applied right away." })

    local function onColor(key)
        return function(color)
            if syncing then return end
            s.Custom[key] = colorToHex(color)
            self:RegisterCustomTheme()
            self:SetTheme(self.CustomThemeName)
            pcall(themeDropdown.UpdateSelection, themeDropdown, self.CustomThemeName)
        end
    end

    local currentTheme = lib.Themes[s.Theme] or lib.Themes.Dark or {}
    for _, key in ipairs(THEME_KEYS) do
        local start = (s.Theme == self.CustomThemeName and s.Custom[key] and hexToColor(s.Custom[key])) or currentTheme[key] or Color3.fromRGB(128, 128, 128)
        pickers[key] = custom:Colorpicker({
            Name = key,
            Default = start,
            Callback = onColor(key),
        }, "IM_Color_" .. key)
    end

    custom:Divider()
    custom:Button({
        Name = "Reset custom colors (Dark)",
        Callback = function()
            local dark = lib.Themes.Dark or {}
            for _, key in ipairs(THEME_KEYS) do
                s.Custom[key] = colorToHex(dark[key] or Color3.fromRGB(128, 128, 128))
            end
            self:RegisterCustomTheme()
            syncPickersFromTheme(self.CustomThemeName)
            if s.Theme == self.CustomThemeName then lib:SetTheme(self.CustomThemeName) end
            self:SaveSettings()
        end,
    })

    -- share a theme as text: "#RRGGBB,#RRGGBB,..." in the order of THEME_KEYS
    local codeInput = custom:Input({ Name = "Theme code", Placeholder = "paste a theme code", Default = "" }, "IM_ThemeCode")
    custom:Button({
        Name = "Copy theme code",
        Callback = function()
            local parts = {}
            for _, key in ipairs(THEME_KEYS) do table.insert(parts, s.Custom[key]) end
            local code = table.concat(parts, ",")
            if setclipboard then pcall(setclipboard, code) end
            if codeInput.UpdateText then pcall(codeInput.UpdateText, codeInput, code) end
        end,
    })
    custom:Button({
        Name = "Import theme code",
        Callback = function()
            local code = codeInput:GetInput() or ""
            local hexes = {}
            for hex in code:gmatch("#%x%x%x%x%x%x") do table.insert(hexes, hex) end
            if #hexes ~= #THEME_KEYS then
                if window and window.Notify then window:Notify({ Title = "Theme", Description = "expected " .. #THEME_KEYS .. " colours like #RRGGBB", Lifetime = 4 }) end
                return
            end
            for i, key in ipairs(THEME_KEYS) do s.Custom[key] = hexes[i] end
            self:RegisterCustomTheme()
            self:SetTheme(self.CustomThemeName)
            syncPickersFromTheme(self.CustomThemeName)
            pcall(themeDropdown.UpdateSelection, themeDropdown, self.CustomThemeName)
        end,
    })

    self:ApplySettings()
    return section, custom
end

return InterfaceManager
