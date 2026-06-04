-- Owns the shape of `storage` and per-player task helpers. Tasks (goals + manual) share one ordered
-- array per player so reorder/delete work uniformly across both kinds.
local storage_mod = {}

local function default_player()
  return {
    collapsed = {},
    dirty = true, -- event-driven (inventory/research) "needs recompute" flag
    editing_task_id = nil,
    hide_completed = true,
    last_fluids = nil, -- last tank scan, for change detection
    last_qsig = nil, -- last crafting-queue signature, for change detection
    last_recompute_tick = 0,
    next_task_id = 1,
    panel_open = false,
    tasks = {},
    uses_fluids = false, -- did the last build reference any fluid? gates the change-detector scan
  }
end

function storage_mod.init()
  storage.players = storage.players or {}
end

function storage_mod.init_player(index)
  if not storage.players[index] then
    storage.players[index] = default_player()
  end
end

-- Ensures every existing player has state and every state has all current fields. Runs on
-- on_configuration_changed, which (unlike on_init) fires when the mod is added to a running save.
function storage_mod.migrate()
  storage.players = storage.players or {}
  for index in pairs(game.players) do
    storage_mod.init_player(index)
    local ps = storage.players[index]
    ps.collapsed = ps.collapsed or {}
    ps.tasks = ps.tasks or {}
    ps.next_task_id = ps.next_task_id or 1
    ps.last_recompute_tick = ps.last_recompute_tick or 0
    if ps.hide_completed == nil then ps.hide_completed = true end
    if ps.panel_open == nil then ps.panel_open = false end
    if ps.uses_fluids == nil then ps.uses_fluids = false end
    ps.dirty = true
  end
end

function storage_mod.next_id(ps)
  local id = ps.next_task_id
  ps.next_task_id = id + 1
  return id
end

function storage_mod.find_task(ps, id)
  for _, task in ipairs(ps.tasks) do
    if task.id == id then return task end
  end
  return nil
end

function storage_mod.remove_task(ps, id)
  for i, task in ipairs(ps.tasks) do
    if task.id == id then
      table.remove(ps.tasks, i)
      return
    end
  end
end

function storage_mod.move_task(ps, id, dir)
  for i, task in ipairs(ps.tasks) do
    if task.id == id then
      local j = (dir == "up") and (i - 1) or (i + 1)
      if j >= 1 and j <= #ps.tasks then
        ps.tasks[i], ps.tasks[j] = ps.tasks[j], ps.tasks[i]
      end
      return
    end
  end
end

return storage_mod
