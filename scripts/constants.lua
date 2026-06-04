-- Shared, stage-agnostic constants. Safe to require from data, settings and control stages
-- (contains only plain strings/numbers, no stage-specific API calls).
local constants = {}

constants.mod_name = "malderans-quick-tasks"

-- How often (ticks) the change-detector is evaluated. This is only the granularity at which the
-- per-user recompute interval is honoured -- the actual rebuild rate is capped by that interval, not
-- by this. Kept small (cheap tick comparison per open panel) so the interval setting is respected
-- closely, and so the setting's minimum can be low for near-realtime updates.
constants.recompute_base_interval = 5

-- How many crafts the "+5" recipe-grab adds.
constants.goal_5_amount = 5

constants.input = {
  add_goal_1 = "fqt-add-goal-1",
  add_goal_5 = "fqt-add-goal-5",
  toggle_panel = "fqt-toggle-panel",
}

constants.setting = {
  auto_remove = "fqt-auto-remove-completed",
  max_tree_depth = "fqt-max-tree-depth",
  recompute_interval = "fqt-recompute-interval",
}

constants.gui = {
  form = "fqt_form",
  form_desc = "fqt_form_desc",
  form_icon = "fqt_form_icon",
  form_name = "fqt_form_name",
  list = "fqt_list",
  mini = "fqt_mini",
  panel = "fqt_panel",
  scroll = "fqt_scroll",
}

-- How many items the closed-panel HUD overlay shows.
constants.mini_item_count = 10

constants.tag = {
  dir = "fqt_dir",
  node_key = "fqt_node_key",
  task_id = "fqt_task_id",
}

return constants
