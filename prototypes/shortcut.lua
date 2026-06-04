local constants = require("scripts.constants")

-- The shortcut shares its name with the toggle custom-input so associated_control_input can surface
-- the keybind in the tooltip, and so on_lua_shortcut / the custom-input both resolve to the same name.
data:extend({
  {
    type = "shortcut",
    name = constants.input.toggle_panel,
    action = "lua",
    localised_name = { "shortcut-name.fqt-toggle-panel" },
    associated_control_input = constants.input.toggle_panel,
    toggleable = true,
    icon = "__malderans-quick-tasks__/graphics/shortcut-x32.png",
    icon_size = 32,
    small_icon = "__malderans-quick-tasks__/graphics/shortcut-x24.png",
    small_icon_size = 24,
  },
})
