-- Panel lifecycle (build / destroy / open / close / toggle / refresh) and every GUI event handler.
-- Handlers live in gui.handlers and are registered once via flib_gui.add_handlers in control.lua;
-- tree-view and manual-form receive this same table so their def-attached handlers resolve.
local flib_gui = require("__flib__.gui")
local constants = require("scripts.constants")
local manual_form = require("scripts.gui.manual-form")
local manual_tasks = require("scripts.manual-tasks")
local storage_mod = require("scripts.storage")
local tree = require("scripts.tree")
local tree_view = require("scripts.gui.tree-view")

local gui = {}
local handlers = {}
gui.handlers = handlers

local CLICK = defines.events.on_gui_click
local CHECKED = defines.events.on_gui_checked_state_changed

local MINI_GREEN = { 0.55, 0.9, 0.55 }
local MINI_YELLOW = { 0.95, 0.82, 0.4 }

local function mini_color(craft_state)
  if craft_state == "hand" then return MINI_GREEN end
  if craft_state == "machine" then return MINI_YELLOW end
  return nil
end

local function get_panel(player)
  local panel = player.gui.left[constants.gui.panel]
  if panel and panel.valid then return panel end
  return nil
end

function gui.destroy(player)
  local panel = get_panel(player)
  if panel then panel.destroy() end
end

-- Builds the forest and, when the auto-remove setting is on, deletes any goal that is now fully
-- satisfied before returning a forest without it. With the setting off, satisfied goals remain (and
-- render with a green tick).
local function build_pruned_forest(player, prescanned_fluids)
  local forest = tree.build_forest(player, prescanned_fluids)
  local setting = settings.get_player_settings(player)[constants.setting.auto_remove]
  local auto_remove = (setting == nil) or setting.value -- default on if the setting isn't registered yet
  if not auto_remove then
    return forest
  end
  local ps = storage.players[player.index]
  local removed = false
  for _, entry in ipairs(forest) do
    if entry.kind == "goal" and entry.node.built then -- built = in inventory, NOT just queued
      storage_mod.remove_task(ps, entry.task_id)
      removed = true
    end
  end
  if removed then
    return tree.build_forest(player, prescanned_fluids)
  end
  return forest
end

function gui.refresh_list(player, prescanned_fluids)
  local panel = get_panel(player)
  if not panel then return end
  local scroll = panel[constants.gui.scroll]
  local list = scroll and scroll[constants.gui.list]
  if not (list and list.valid) then return end
  local ps = storage.players[player.index]
  if not ps then return end
  tree_view.render(list, build_pruned_forest(player, prescanned_fluids), ps, handlers)
end

function gui.build(player)
  gui.destroy(player)
  local ps = storage.players[player.index]
  -- Cap the scroll height to (roughly) the visible screen so the panel never grows taller than the
  -- left GUI area. Otherwise the game wraps player.gui.left in its OWN scroll pane, producing a second
  -- (outer) scrollbar alongside our inner one. display_resolution is in physical px; divide by
  -- display_scale for logical px, then leave headroom for the toolbar, our header and margins.
  local logical_height = player.display_resolution.height / player.display_scale
  local scroll_max = math.max(200, math.floor(logical_height - 240))
  flib_gui.add(player.gui.left, {
    type = "frame",
    name = constants.gui.panel,
    direction = "vertical",
    style_mods = { minimal_width = 300 },
    {
      type = "flow",
      direction = "horizontal",
      style_mods = { vertical_align = "center", horizontal_spacing = 8 },
      { type = "label", style = "frame_title", caption = { "fqt.panel-title" } },
      { type = "empty-widget", style_mods = { horizontally_stretchable = true } },
      {
        type = "checkbox",
        state = not ps.hide_completed,
        caption = { "fqt.show-completed" },
        handler = { [CHECKED] = handlers.toggle_hide_completed },
      },
      {
        type = "button",
        caption = { "fqt.add-task" },
        style_mods = { height = 24, top_padding = 0, bottom_padding = 0 },
        handler = { [CLICK] = handlers.open_add_form },
      },
      {
        type = "sprite-button",
        style = "frame_action_button",
        sprite = "utility/close",
        tooltip = { "fqt.close" },
        handler = { [CLICK] = handlers.close_panel },
      },
    },
    {
      type = "scroll-pane",
      name = constants.gui.scroll,
      vertical_scroll_policy = "auto",
      horizontal_scroll_policy = "never",
      style_mods = { maximal_height = scroll_max, minimal_width = 290 },
      { type = "flow", name = constants.gui.list, direction = "vertical", style_mods = { vertical_spacing = 2 } },
    },
  })
  gui.refresh_list(player)
end

-- Closed-panel HUD: a backgroundless, click-through list of the top cumulative needs across all
-- goals, overlaid on the game. Rebuilt (cheaply, <= mini_item_count labels) on the throttled poll.
function gui.destroy_mini(player)
  local mini = player.gui.left[constants.gui.mini]
  if mini and mini.valid then mini.destroy() end
end

function gui.refresh_mini(player, prescanned_fluids)
  local ps = storage.players[player.index]
  if not ps then return end
  gui.destroy_mini(player)
  local needs = tree.aggregate_needs(build_pruned_forest(player, prescanned_fluids), constants.mini_item_count)
  if #needs == 0 then return end

  local mini = player.gui.left.add({ type = "flow", name = constants.gui.mini, direction = "vertical" })
  mini.ignored_by_interaction = true -- overlay must not eat clicks meant for the game
  mini.style.vertical_spacing = 4
  mini.style.padding = 8
  for _, need in ipairs(needs) do
    local row = mini.add({ type = "flow", direction = "horizontal" })
    row.ignored_by_interaction = true
    row.style.vertical_align = "center"
    row.style.horizontal_spacing = 8

    local path = (need.is_fluid and "fluid/" or "item/") .. need.item
    if not helpers.is_valid_sprite_path(path) then path = "utility/questionmark" end
    local icon = row.add({ type = "sprite", sprite = path })
    icon.ignored_by_interaction = true
    icon.style.width = 32
    icon.style.height = 32
    icon.style.stretch_image_to_widget_size = true

    if need.built then
      -- completed goal kept on screen: green tick instead of a count
      local tick = row.add({ type = "sprite", sprite = "utility/check_mark_green" })
      tick.ignored_by_interaction = true
      tick.style.width = 28
      tick.style.height = 28
      tick.style.stretch_image_to_widget_size = true
    else
      local label = row.add({ type = "label", caption = math.floor(need.deficit) })
      label.ignored_by_interaction = true
      label.style.font = "default-large-bold"
      local color = mini_color(need.craft_state)
      if color then label.style.font_color = color end
    end
  end
end

function gui.open(player)
  local ps = storage.players[player.index]
  ps.panel_open = true
  gui.destroy_mini(player)
  gui.build(player)
  player.set_shortcut_toggled(constants.input.toggle_panel, true)
end

function gui.close(player)
  local ps = storage.players[player.index]
  ps.panel_open = false
  gui.destroy(player)
  manual_form.close(player)
  player.set_shortcut_toggled(constants.input.toggle_panel, false)
  gui.refresh_mini(player)
end

function gui.toggle(player)
  local ps = storage.players[player.index]
  if ps.panel_open then gui.close(player) else gui.open(player) end
end

-- handlers ----------------------------------------------------------------------------------------

local function player_of(e)
  return game.get_player(e.player_index)
end

function handlers.close_panel(e)
  gui.close(player_of(e))
end

function handlers.toggle_hide_completed(e)
  local ps = storage.players[e.player_index]
  ps.hide_completed = not e.element.state
  gui.refresh_list(player_of(e))
end

function handlers.toggle_collapse(e)
  local ps = storage.players[e.player_index]
  local key = e.element.tags[constants.tag.node_key]
  ps.collapsed[key] = (not ps.collapsed[key]) or nil
  gui.refresh_list(player_of(e))
end

function handlers.move_task(e)
  local ps = storage.players[e.player_index]
  storage_mod.move_task(ps, e.element.tags[constants.tag.task_id], e.element.tags[constants.tag.dir])
  gui.refresh_list(player_of(e))
end

function handlers.delete_task(e)
  local ps = storage.players[e.player_index]
  storage_mod.remove_task(ps, e.element.tags[constants.tag.task_id])
  gui.refresh_list(player_of(e))
end

function handlers.toggle_manual_done(e)
  local ps = storage.players[e.player_index]
  manual_tasks.set_done(ps, e.element.tags[constants.tag.task_id], e.element.state)
  gui.refresh_list(player_of(e))
end

function handlers.open_add_form(e)
  manual_form.open(player_of(e), nil, handlers)
end

function handlers.edit_manual(e)
  manual_form.open(player_of(e), e.element.tags[constants.tag.task_id], handlers)
end

function handlers.save_manual(e)
  local player = player_of(e)
  if manual_form.save(player) then
    manual_form.close(player)
    gui.refresh_list(player)
  end
end

function handlers.cancel_manual(e)
  manual_form.close(player_of(e))
end

return gui
