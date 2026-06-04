-- Free-form manual tasks (name + optional icon + optional description + manual checkbox).
local storage_mod = require("scripts.storage")

local manual_tasks = {}

function manual_tasks.add(ps, fields)
  local id = storage_mod.next_id(ps)
  ps.tasks[#ps.tasks + 1] = {
    description = fields.description,
    done = false,
    icon = fields.icon,
    id = id,
    kind = "manual",
    name = fields.name,
  }
  return id
end

function manual_tasks.update(ps, id, fields)
  local task = storage_mod.find_task(ps, id)
  if not task or task.kind ~= "manual" then return end
  task.description = fields.description
  task.icon = fields.icon
  task.name = fields.name
end

function manual_tasks.set_done(ps, id, done)
  local task = storage_mod.find_task(ps, id)
  if task and task.kind == "manual" then
    task.done = done
  end
end

return manual_tasks
