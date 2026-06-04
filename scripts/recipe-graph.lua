-- Read-only queries over the recipe prototypes: which recipes produce a given item, a deterministic
-- "canonical" recipe pick, and the per-craft yield of a product. The producing-recipe index is a
-- module-local cache (derived from prototypes, never stored) built lazily and reset on config change.
local recipe_graph = {}

-- item/fluid name -> array of recipe names that produce it
local producing = nil
-- item -> cheapest recursive raw-material cost (memoized; derived from prototypes only)
local cost_memo = nil
-- item -> true while its cost is being computed, used to break cycles
local computing = nil

function recipe_graph.reset()
  producing = nil
  cost_memo = nil
  computing = nil
end

function recipe_graph.ensure()
  if producing then return end
  producing = {}
  cost_memo = {}
  computing = {}
  for name, recipe in pairs(prototypes.recipe) do
    for _, product in pairs(recipe.products) do
      local list = producing[product.name]
      if not list then
        list = {}
        producing[product.name] = list
      end
      list[#list + 1] = name
    end
  end
  for _, list in pairs(producing) do
    table.sort(list) -- deterministic candidate order (MP safety)
  end
end

-- Per-craft output amount of a single Product. Averages randomized output and weights by probability;
-- never returns <= 0 (guards the ceil(deficit / yield) divide).
function recipe_graph.product_amount(product)
  local amount = product.amount
  if not amount then
    local lo = product.amount_min or 1
    local hi = product.amount_max or lo
    amount = (lo + hi) / 2
  end
  amount = amount * (product.probability or 1)
  if amount and amount > 0 then return amount end
  return 1
end

-- Per-craft amount of `item` produced by `recipe`.
function recipe_graph.product_yield(recipe, item)
  for _, product in pairs(recipe.products) do
    if product.name == item then
      return recipe_graph.product_amount(product)
    end
  end
  return 1
end

-- The item/fluid a recipe is "for" (used as a goal's tracked product and display).
function recipe_graph.recipe_main_item(recipe)
  local main = recipe.main_product
  if main then return main.name end
  local first = recipe.products[1]
  if first then return first.name end
  return nil
end

-- A recipe is cyclic on the current path if any of its ingredients is already an ancestor (e.g. A is
-- made from B and B is made from A). Such recipes are skipped so a non-cyclic alternative can win.
local function uses_ancestor(recipe, visited)
  if not visited then return false end
  for _, ingredient in pairs(recipe.ingredients) do
    if visited[ingredient.name] then return true end
  end
  return false
end

local item_cost -- forward declaration (mutually recursive with recipe_raw_cost)

-- Total recursive raw-material cost of producing one `item` via `recipe`: each raw input counts as 1,
-- intermediates as the cheapest sum of their inputs, divided by this recipe's yield of the item. So a
-- byproduct recipe (little of the item out of expensive inputs) costs a lot, and a direct recipe from
-- near-raw inputs costs little.
local function recipe_raw_cost(recipe, item)
  local sum = 0
  for _, ingredient in pairs(recipe.ingredients) do
    sum = sum + item_cost(ingredient.name) * ingredient.amount
    if sum == math.huge then return math.huge end
  end
  return sum / recipe_graph.product_yield(recipe, item)
end

-- Cheapest cost to make one `item`, memoized. Raw resources cost 1. Cycles return huge (so reversible
-- or looping recipes never look cheap). Ignores tech -- it's a static graph metric; the enabled check
-- lives in select_recipe.
function item_cost(item)
  local cached = cost_memo[item]
  if cached ~= nil then return cached end
  if computing[item] then return math.huge end
  local candidates = producing[item]
  if not candidates then
    cost_memo[item] = 1
    return 1
  end
  computing[item] = true
  local best = math.huge
  for _, recipe_name in ipairs(candidates) do
    local recipe = prototypes.recipe[recipe_name]
    if recipe.allow_decomposition ~= false then
      local c = recipe_raw_cost(recipe, item)
      if c < best then best = c end
    end
  end
  computing[item] = nil
  cost_memo[item] = best
  return best
end

-- Deterministic, cost-aware recipe selection for an item. `override` forces a specific recipe (the
-- goal root uses the clicked recipe). Candidates are skipped when allow_decomposition == false (the
-- engine's flag for reversible/utility recipes -- barrels, boxing/unboxing, recycling) or when an
-- ingredient is already an ancestor on the path (`visited`, a backstop cycle guard). Among the rest we
-- prefer: researched recipes, then the cheapest (fewest raw materials), then fewest ingredients, then
-- alphabetical. Returns nil for a raw item or when every recipe is skipped.
function recipe_graph.select_recipe(item, force, override, visited)
  if override and prototypes.recipe[override] then
    return prototypes.recipe[override]
  end
  recipe_graph.ensure()
  local candidates = producing[item]
  if not candidates then return nil end
  local list = {}
  for _, recipe_name in ipairs(candidates) do
    local recipe = prototypes.recipe[recipe_name]
    if recipe.allow_decomposition ~= false and not uses_ancestor(recipe, visited) then
      local force_recipe = force.recipes[recipe_name]
      list[#list + 1] = {
        recipe = recipe,
        enabled = (force_recipe ~= nil and force_recipe.enabled) and 0 or 1,
        cost = recipe_raw_cost(recipe, item),
        ingredients = #recipe.ingredients,
        name = recipe_name,
      }
    end
  end
  if #list == 0 then return nil end
  table.sort(list, function(a, b)
    if a.enabled ~= b.enabled then return a.enabled < b.enabled end
    if a.cost ~= b.cost then return a.cost < b.cost end
    if a.ingredients ~= b.ingredients then return a.ingredients < b.ingredients end
    return a.name < b.name
  end)
  return list[1].recipe
end

return recipe_graph
