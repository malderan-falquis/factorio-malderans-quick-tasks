-- The core netting / expansion DFS. Walks each goal top-down consuming from ONE mutable inventory
-- pool, so each unit of stock is allocated to exactly one consumer (no double-counting). The computed
-- forest is cached module-locally per player (disposable, never stored).
local constants = require("scripts.constants")
local recipe_graph = require("scripts.recipe-graph")

local tree = {}

-- player_index -> array of forest entries (see build_forest)
local forests = {}

-- Total of each fluid across the force's storage tanks on the player's surface. Used both as fluid
-- "inventory" during a build and (by the control-stage change detector) to cheaply tell whether
-- fluid levels moved without rebuilding the whole tree.
function tree.scan_fluids(player)
  local totals = {}
  local tanks = player.surface.find_entities_filtered({ type = "storage-tank", force = player.force })
  for _, tank in pairs(tanks) do
    for name, amount in pairs(tank.get_fluid_contents()) do
      totals[name] = (totals[name] or 0) + amount
    end
  end
  return totals
end

-- Fluid stock comes from the tank scan (lazily, only if a fluid is actually encountered, or reused
-- from a scan the change detector already did). ctx.fluid_used records whether the tree depends on
-- fluids at all, so the detector can skip the scan entirely for item-only trees.
local function fluid_available(ctx, name)
  if not ctx.fluids then
    ctx.fluids = tree.scan_fluids(ctx.player)
  end
  ctx.fluid_used = true
  return ctx.fluids[name] or 0
end

-- Ingredients the hand-crafting queue has sequestered from inventory, per item: net consumed minus
-- produced across all queued crafts. These are added back to availability so materials committed to a
-- queued craft still count (they shouldn't reappear as a fresh deficit). The queue's OUTPUTS are
-- deliberately NOT counted -- an item isn't "had" until it's actually built and back in inventory.
-- (Intermediates that feed other queued crafts net to zero: produced and consumed within the queue.)
local function queued_reserved(player)
  local queue = player.crafting_queue
  if not queue then return {} end
  local produced, consumed = {}, {}
  for _, entry in pairs(queue) do
    local recipe = prototypes.recipe[entry.recipe]
    if recipe then
      for _, product in pairs(recipe.products) do
        produced[product.name] = (produced[product.name] or 0) + recipe_graph.product_amount(product) * entry.count
      end
      for _, ingredient in pairs(recipe.ingredients) do
        consumed[ingredient.name] = (consumed[ingredient.name] or 0) + ingredient.amount * entry.count
      end
    end
  end
  local reserved = {}
  for name, amount in pairs(consumed) do
    local net = amount - (produced[name] or 0)
    if net >= 1 then reserved[name] = math.floor(net) end
  end
  return reserved
end

-- Item stock = main inventory plus whatever is held in the cursor (the cursor leaves the main
-- inventory, so without this a held stack reads as missing). Only call for valid item names.
local function inventory_count(ctx, item)
  local count = (ctx.inv and ctx.inv.get_item_count(item)) or 0
  if item == ctx.cursor_name then count = count + ctx.cursor_count end
  return count
end

-- A recipe is hand-craftable if the character's crafting categories include it and it has no fluid
-- ingredients (the player can't hand-craft with fluids).
local function is_hand_craftable(ctx, recipe)
  if not ctx.hand_categories[recipe.category] then return false end
  for _, ingredient in pairs(recipe.ingredients) do
    if ingredient.type == "fluid" then return false end
  end
  return true
end

-- ctx carries the per-build shared state: { force, inv, max_depth, player, pool, fluids }.
-- `forced` is the exact recipe to use for the goal's product, applied ONLY at the root (depth 0) so
-- the clicked recipe wins there; deeper nodes (including the same item recurring in the subtree) fall
-- back to per-node `overrides` then the select_recipe heuristic.
local function expand(ctx, item, need, visited, depth, path, overrides, forced)
  need = math.ceil(need)
  local is_fluid = prototypes.fluid[item] ~= nil
  local node = {
    children = {},
    craft_state = nil, -- nil | "hand" (green) | "machine" (yellow); set after children expand
    crafts = 0,
    deficit = 0,
    depth = depth, -- 0 at a goal root, increasing toward raw components
    from_stock = 0,
    is_fluid = is_fluid,
    is_raw = false,
    item = item,
    key = path,
    need = need,
    recipe = nil,
    satisfied = false,
    truncated = false,
  }

  -- 1. allocate from the running pool: items from the main inventory, fluids from storage tanks.
  --    get_item_count errors on non-item names (e.g. fluids), so it is only called for real items.
  local avail = ctx.pool[item]
  if avail == nil then
    if is_fluid then
      avail = fluid_available(ctx, item)
    elseif prototypes.item[item] then
      avail = inventory_count(ctx, item)
    else
      avail = 0
    end
    avail = avail + (ctx.queued[item] or 0) -- add back ingredients the queue sequestered (not outputs)
    ctx.pool[item] = avail
  end
  local take = math.min(need, avail)
  ctx.pool[item] = avail - take
  node.from_stock = take
  node.deficit = need - take

  if node.deficit <= 0 then
    node.satisfied = true
    return node
  end

  -- 2. depth guard (hard backstop; cycles are normally avoided by cycle-aware recipe selection below)
  if visited[item] or depth >= ctx.max_depth then
    node.truncated = true
    return node
  end

  -- 3. choose a recipe and recurse on the remaining deficit. Selection is cycle-aware: it skips any
  --    recipe whose ingredient is already an ancestor on this path, preferring a non-cyclic
  --    alternative. nil means no recipe (a raw resource) OR every recipe would cycle (e.g. a fluid
  --    that only interconverts, like oxygen <-> compressed oxygen) -- either way it's a base input you
  --    produce/pipe, shown as a clean leaf. The root bypasses the filter via the forced recipe.
  local override = overrides[item]
  if depth == 0 and forced then override = forced end
  local recipe = recipe_graph.select_recipe(item, ctx.force, override, visited)
  if recipe == nil then
    node.is_raw = true
    return node
  end
  node.recipe = recipe.name
  local crafts = math.ceil(node.deficit / recipe_graph.product_yield(recipe, item))
  node.crafts = crafts

  local visited2 = {}
  for key in pairs(visited) do visited2[key] = true end
  visited2[item] = true

  for _, ingredient in pairs(recipe.ingredients) do
    node.children[#node.children + 1] = expand(
      ctx,
      ingredient.name,
      crafts * ingredient.amount,
      visited2,
      depth + 1,
      path .. "/" .. ingredient.name,
      overrides,
      forced
    )
  end

  -- Readiness: can the remaining deficit be obtained right now? Hand-craftable + every ingredient
  -- either in stock or itself hand-ready => "hand" (green: hand-build it, sub-parts auto-queue).
  -- Machine-only but all direct ingredients in stock => "machine" (yellow: a machine can make it now).
  local hand = is_hand_craftable(ctx, recipe)
  local all_satisfied, all_hand_ready = true, true
  for _, child in ipairs(node.children) do
    if not child.satisfied then
      all_satisfied = false
      if child.craft_state ~= "hand" then all_hand_ready = false end
    end
  end
  if hand and all_hand_ready then
    node.craft_state = "hand"
  elseif not hand and all_satisfied then
    node.craft_state = "machine"
  end

  return node
end

-- Builds the render forest for a player from their tasks. Goals are netted top-down in list order
-- (= allocation priority); manual tasks pass through unchanged. Returns, and caches, an array of:
--   { task_id, kind = "goal",  node, target }
--   { task_id, kind = "manual", task }
function tree.build_forest(player, prescanned_fluids)
  local ps = storage.players[player.index]
  if not ps then return {} end
  recipe_graph.ensure()

  local cursor = player.cursor_stack
  local cursor_valid = cursor ~= nil and cursor.valid_for_read
  local ctx = {
    cursor_count = cursor_valid and cursor.count or 0,
    cursor_name = cursor_valid and cursor.name or nil,
    force = player.force,
    fluid_used = false,
    fluids = prescanned_fluids, -- reuse the change detector's scan if given, else scan lazily
    hand_categories = (player.character and player.character.prototype.crafting_categories) or {},
    inv = player.get_main_inventory(),
    max_depth = settings.global[constants.setting.max_tree_depth].value,
    player = player,
    pool = {},
    queued = queued_reserved(player),
  }

  local forest = {}
  for _, task in ipairs(ps.tasks) do
    if task.kind == "goal" then
      local recipe = prototypes.recipe[task.recipe]
      if recipe then
        local need = task.target * recipe_graph.product_yield(recipe, task.item)
        local node = expand(ctx, task.item, need, {}, 0, tostring(task.id), task.recipe_overrides or {}, task.recipe)
        node.is_goal = true
        -- "built" = the product is actually in inventory (get_item_count excludes the crafting queue),
        -- so auto-remove / the done tick fire only on real completion, not on merely queued crafts.
        node.built = prototypes.item[task.item] ~= nil
          and inventory_count(ctx, task.item) >= node.need
        forest[#forest + 1] = { task_id = task.id, kind = "goal", node = node, target = task.target }
      else
        -- The recipe was removed (e.g. a mod was disabled). Surface a deletable placeholder so the
        -- goal can't become an undeletable zombie.
        forest[#forest + 1] = { task_id = task.id, kind = "missing", recipe = task.recipe }
      end
    else
      forest[#forest + 1] = { task_id = task.id, kind = "manual", task = task }
    end
  end

  ps.uses_fluids = ctx.fluid_used
  forests[player.index] = forest
  return forest
end

function tree.get_forest(player_index)
  return forests[player_index]
end

-- Flatten a forest into a "what to make next" list: each needed item with its total deficit, deepest
-- depth, readiness and whether it's a top-level goal. Ordered so the most immediately actionable
-- things come first -- buildable top-level goals, then other buildable (green/yellow) items, then the
-- rest -- and within each band the lowest-level (deepest) sub-components first (bottom-up make order).
-- Capped to `limit`. Deterministic (full sort + name tiebreak) for MP safety.
local CRAFT_PRIORITY = { hand = 2, machine = 1 }

function tree.aggregate_needs(forest, limit)
  local totals = {}
  local function walk(node, is_goal)
    if node.deficit > 0 then
      local entry = totals[node.item]
      if not entry then
        entry = { item = node.item, deficit = 0, depth = 0, is_fluid = node.is_fluid, is_goal = false }
        totals[node.item] = entry
      end
      entry.deficit = entry.deficit + node.deficit
      if node.depth > entry.depth then entry.depth = node.depth end
      if is_goal then entry.is_goal = true end
      if (CRAFT_PRIORITY[node.craft_state] or 0) > (CRAFT_PRIORITY[entry.craft_state] or 0) then
        entry.craft_state = node.craft_state
      end
    end
    for _, child in ipairs(node.children) do
      walk(child, false)
    end
  end
  local built = {}
  for _, entry in ipairs(forest) do
    if entry.kind == "goal" then
      if entry.node.built then
        -- kept (auto-remove off) completed goal: show as a tick, not a count
        built[#built + 1] = { item = entry.node.item, is_fluid = entry.node.is_fluid, built = true }
      else
        walk(entry.node, true)
      end
    end
  end

  local list = {}
  for _, entry in pairs(totals) do
    list[#list + 1] = entry
  end
  table.sort(list, function(a, b)
    local a_goal = (a.is_goal and a.craft_state) and 0 or 1
    local b_goal = (b.is_goal and b.craft_state) and 0 or 1
    if a_goal ~= b_goal then return a_goal < b_goal end
    local a_build = a.craft_state and 0 or 1
    local b_build = b.craft_state and 0 or 1
    if a_build ~= b_build then return a_build < b_build end
    if a.depth ~= b.depth then return a.depth > b.depth end -- deepest (lowest sub-component) first
    if a.deficit ~= b.deficit then return a.deficit > b.deficit end
    return a.item < b.item
  end)
  while #list > limit do
    table.remove(list)
  end

  -- Built (kept) goals always shown, at the top, as ticks; needs fill the rest up to the limit.
  table.sort(built, function(a, b) return a.item < b.item end)
  for _, entry in ipairs(list) do
    built[#built + 1] = entry
  end
  return built
end

function tree.forget(player_index)
  forests[player_index] = nil
end

return tree
