local constants = require("scripts.constants")

data:extend({
  -- Minimum ticks between panel recalculations (per-user, so it can't desync MP). This is the hard
  -- rate cap: at most one change-check + rebuild per this many ticks, regardless of how often the
  -- underlying inventory/fluids/queue change. Default 15 = up to ~4 updates/sec; lower (toward 5) for
  -- near-realtime, raise it to cut overhead on huge trees.
  {
    type = "int-setting",
    name = constants.setting.recompute_interval,
    setting_type = "runtime-per-user",
    default_value = 15,
    minimum_value = 5,
    maximum_value = 300,
    order = "a",
  },
  -- When a crafting goal is fully satisfied, drop it from the list. Off = keep it shown with a tick.
  {
    type = "bool-setting",
    name = constants.setting.auto_remove,
    setting_type = "runtime-per-user",
    default_value = true,
    order = "c",
  },
  -- Hard guard against recipe cycles / pathological breakdown depth (global so the tree is identical
  -- for everyone in MP).
  {
    type = "int-setting",
    name = constants.setting.max_tree_depth,
    setting_type = "runtime-global",
    default_value = 25,
    minimum_value = 3,
    maximum_value = 100,
    order = "b",
  },
})
