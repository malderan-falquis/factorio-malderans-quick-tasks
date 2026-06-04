local flib_gui = require("__flib__.gui")
local constants = require("scripts.constants")
local goals = require("scripts.goals")
local gui = require("scripts.gui.index")
local recipe_graph = require("scripts.recipe-graph")
local storage_mod = require("scripts.storage")
local tree = require("scripts.tree")

-- lifecycle ---------------------------------------------------------------------------------------

script.on_init(function()
  storage_mod.init()
  for index in pairs(game.players) do
    storage_mod.init_player(index)
  end
end)

script.on_configuration_changed(function()
  storage_mod.migrate()
  recipe_graph.reset() -- prototypes may have changed; rebuilt lazily on next tree compute
end)

script.on_event(defines.events.on_player_created, function(e)
  storage_mod.init_player(e.player_index)
end)

script.on_event(defines.events.on_player_removed, function(e)
  if storage.players then storage.players[e.player_index] = nil end
  tree.forget(e.player_index)
end)

-- recipe-grab -------------------------------------------------------------------------------------

-- The crafting menu reports the hovered slot via selected_prototype. We accept a recipe directly, and
-- also an item (resolving its canonical recipe) so the feature works whichever the engine reports.
local function resolve_recipe_name(selected, player)
  if not selected then return nil end
  if selected.base_type == "recipe" then return selected.name end
  if selected.base_type == "item" then
    local recipe = recipe_graph.select_recipe(selected.name, player.force, nil)
    if recipe then return recipe.name end
  end
  return nil
end

local function add_goal(amount)
  return function(e)
    local player = game.get_player(e.player_index)
    if not player then return end
    local recipe_name = resolve_recipe_name(e.selected_prototype, player)
    if not recipe_name then return end
    local ps = storage.players and storage.players[e.player_index]
    if not ps then return end
    if goals.add_or_increment(ps, recipe_name, amount) then
      if ps.panel_open then
        gui.refresh_list(player)
      else
        gui.refresh_mini(player) -- update the HUD overlay only; don't force the panel open
      end
    end
  end
end

script.on_event(constants.input.add_goal_1, add_goal(1))
script.on_event(constants.input.add_goal_5, add_goal(constants.goal_5_amount))

-- toggle ------------------------------------------------------------------------------------------

local function toggle(player_index)
  local player = game.get_player(player_index)
  if player then gui.toggle(player) end
end

script.on_event(constants.input.toggle_panel, function(e)
  toggle(e.player_index)
end)

script.on_event(defines.events.on_lua_shortcut, function(e)
  if e.prototype_name == constants.input.toggle_panel then
    toggle(e.player_index)
  end
end)

-- Live tracking. The expensive work is the recursive tree build + GUI rebuild, so we avoid it unless
-- an input actually changed. Inventory and research fire events (cheap dirty flag); the crafting
-- queue and fluid tanks have no events, so we poll them with cheap checks each interval -- a queue
-- signature and (only when the tree uses fluids) a tank scan, both far lighter than a full rebuild.

-- Flag for recompute whenever the panel is open OR there are tasks driving the HUD overlay; otherwise
-- a closed-panel HUD would miss inventory/cursor changes and only update when a fluid/queue change
-- happened to be detected.
local function mark_dirty(player_index)
  local ps = storage.players and storage.players[player_index]
  if ps and (ps.panel_open or next(ps.tasks)) then ps.dirty = true end
end

script.on_event(defines.events.on_player_main_inventory_changed, function(e)
  mark_dirty(e.player_index)
end)

-- Picking a stack to the cursor (and grabbing from a chest into the cursor) may not fire the
-- inventory-changed event, but the held items still count, so refresh on cursor changes too.
script.on_event(defines.events.on_player_cursor_stack_changed, function(e)
  mark_dirty(e.player_index)
end)

script.on_event(defines.events.on_research_finished, function()
  if not storage.players then return end
  for _, ps in pairs(storage.players) do
    ps.dirty = true -- newly unlocked recipes can change the breakdown
  end
end)

-- Cheap fingerprint of the hand-crafting queue (size + per-entry counts), which changes as crafts are
-- queued, cancelled, or progress.
local function queue_signature(player)
  local queue = player.crafting_queue
  if not queue then return 0 end
  local sig = #queue
  for _, entry in pairs(queue) do
    sig = sig * 31 + entry.count
  end
  return sig
end

local function fluids_differ(a, b)
  if a == b then return false end -- both nil
  if not a or not b then return true end
  for name, amount in pairs(a) do
    if b[name] ~= amount then return true end
  end
  for name in pairs(b) do
    if a[name] == nil then return true end
  end
  return false
end

script.on_nth_tick(constants.recompute_base_interval, function(e)
  if not storage.players then return end
  for index, ps in pairs(storage.players) do
    -- Poll while the full panel is open OR while there are tasks to drive the closed-panel HUD.
    if ps.panel_open or next(ps.tasks) then
      local player = game.get_player(index)
      if player and player.connected then
        local interval = settings.get_player_settings(player)[constants.setting.recompute_interval].value
        if e.tick - (ps.last_recompute_tick or 0) >= interval then
          ps.last_recompute_tick = e.tick
          local qsig = queue_signature(player)
          local fluids = ps.uses_fluids and tree.scan_fluids(player) or nil
          if ps.dirty or qsig ~= ps.last_qsig or fluids_differ(fluids, ps.last_fluids) then
            ps.dirty = false
            ps.last_qsig = qsig
            ps.last_fluids = fluids
            if ps.panel_open then
              gui.refresh_list(player, fluids)
            else
              gui.refresh_mini(player, fluids)
            end
          end
        end
      end
    end
  end
end)

-- GUI events --------------------------------------------------------------------------------------

flib_gui.add_handlers(gui.handlers)
flib_gui.handle_events()
