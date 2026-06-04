local constants = require("scripts.constants")

-- Recipe-grab binds carry the hovered prototype via include_selected_prototype. consuming = "none"
-- so we never fight vanilla controls. Defaults avoid vanilla quick-craft (plain / SHIFT / CONTROL +
-- left-click on recipe slots) by using the combined CONTROL+SHIFT modifier; RMB is unused by vanilla
-- crafting. All three are rebindable in the Controls menu.
data:extend({
  {
    type = "custom-input",
    name = constants.input.add_goal_1,
    key_sequence = "CONTROL + SHIFT + mouse-button-1",
    include_selected_prototype = true,
    consuming = "none",
  },
  {
    type = "custom-input",
    name = constants.input.add_goal_5,
    key_sequence = "CONTROL + SHIFT + mouse-button-2",
    include_selected_prototype = true,
    consuming = "none",
  },
  {
    type = "custom-input",
    name = constants.input.toggle_panel,
    key_sequence = "CONTROL + SHIFT + T",
    action = "lua",
  },
})
