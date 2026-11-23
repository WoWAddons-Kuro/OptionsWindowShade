-- OptionsWindowShade: string table. English only for now; every user-visible string
-- goes through L[] so a locale can be added later without touching Core.lua.
local ADDON, NS = ...

local L = setmetatable({}, { __index = function(t, k) rawset(t, k, k) return k end })
NS.L = L

L["Shade window"] = "Shade window"
L["Unshade window"] = "Unshade window"
L["Unlock window"] = "Unlock window"
L["Lock window"] = "Lock window"
L["Drag the title bar to move it."] = "Drag the title bar to move it."
L["Keybind: %s"] = "Keybind: %s"
L["Keybind: none"] = "Keybind: none"
L["Open the Options window first."] = "Open the Options window first."
L["Usage: /ows shade | lock | help"] = "Usage: /ows shade | lock | help"

-- Globals the client reads for Bindings.xml (the Keybindings category shows these).
BINDING_HEADER_OPTIONSWINDOWSHADE = "Options Window Shade"
BINDING_NAME_OPTIONSWINDOWSHADE_TOGGLE_SHADE = "Shade / unshade the Options window"
BINDING_NAME_OPTIONSWINDOWSHADE_TOGGLE_LOCK = "Lock / unlock the Options window"