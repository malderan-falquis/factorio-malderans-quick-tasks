-- Creating / incrementing crafting goals. A goal's identity is the EXACT recipe the player clicked
-- (items can have several recipes under overhaul mods), so re-clicking the same recipe bumps its
-- target rather than adding a duplicate.
local recipe_graph = require("scripts.recipe-graph")
local storage_mod = require("scripts.storage")

local goals = {}

function goals.add_or_increment(ps, recipe_name, amount)
  local recipe = prototypes.recipe[recipe_name]
  if not recipe then return false end

  for _, task in ipairs(ps.tasks) do
    if task.kind == "goal" and task.recipe == recipe_name then
      task.target = task.target + amount
      return true
    end
  end

  local item = recipe_graph.recipe_main_item(recipe)
  if not item then return false end

  ps.tasks[#ps.tasks + 1] = {
    id = storage_mod.next_id(ps),
    item = item,
    kind = "goal",
    recipe = recipe_name,
    recipe_overrides = {},
    target = amount,
  }
  return true
end

return goals
