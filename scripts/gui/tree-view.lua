-- Renders the computed forest into the panel's list flow. Goal roots get reorder/delete controls;
-- component nodes are plain indented rows. Item icons use rich text ("[item=...]") so we never touch
-- sprite paths / sizing. Handler functions are passed in (registered in gui/index.lua).
local flib_gui = require("__flib__.gui")
local constants = require("scripts.constants")

local tree_view = {}

local CLICK = defines.events.on_gui_click
local CHECKED = defines.events.on_gui_checked_state_changed
local GREY = { 0.6, 0.6, 0.6 }
local GREEN = { 0.55, 0.9, 0.55 } -- can hand-craft now (ingredients in stock / hand-ready)
local YELLOW = { 0.95, 0.82, 0.4 } -- a machine can make it now (direct inputs in stock)

-- Font colour for an item's name label: grey when satisfied, green/yellow when buildable now.
local function name_color(node)
  if node.satisfied then return GREY end
  if node.craft_state == "hand" then return GREEN end
  if node.craft_state == "machine" then return YELLOW end
  return nil
end

-- Builds a style_mods table for a name label, or nil if nothing to override.
local function name_style(node, bold)
  local style = {}
  if bold then style.font = "default-bold" end
  local color = name_color(node)
  if color then style.font_color = color end
  return next(style) and style or nil
end

-- "have / total", floored to whole numbers (fluid tank contents and probability-weighted yields are
-- floats, which otherwise render as very long decimals).
local function have_need(node)
  return math.floor(node.from_stock) .. " / " .. math.floor(node.need)
end

local function icon_richtext(name, kind)
  -- kind: "item" | "fluid" | "virtual"
  if kind == "fluid" then return "[fluid=" .. name .. "]" end
  if kind == "virtual" then return "[virtual-signal=" .. name .. "]" end
  return "[item=" .. name .. "]"
end

local function localised_name(name, is_fluid)
  local proto = is_fluid and prototypes.fluid[name] or prototypes.item[name]
  return proto and proto.localised_name or name
end

-- Caption combining a rich-text icon and the (localised) prototype name.
local function node_caption(node)
  local kind = node.is_fluid and "fluid" or "item"
  return { "", icon_richtext(node.item, kind) .. "  ", localised_name(node.item, node.is_fluid) }
end

local function signal_richtext(icon)
  if not icon or not icon.name then return "" end
  local t = icon.type or "item"
  if t == "virtual" then return "[virtual-signal=" .. icon.name .. "]  " end
  if t == "fluid" then return "[fluid=" .. icon.name .. "]  " end
  return "[item=" .. icon.name .. "]  "
end

local function children_with_deficit(node, hide_completed)
  local out = {}
  for _, child in ipairs(node.children) do
    if (not hide_completed) or child.deficit > 0 then
      out[#out + 1] = child
    end
  end
  return out
end

-- def builders ------------------------------------------------------------------------------------

local function collapse_def(key, collapsed, h)
  return {
    type = "sprite-button",
    sprite = collapsed and "utility/expand" or "utility/collapse",
    style_mods = { width = 20, height = 20, padding = 0 },
    tags = { [constants.tag.node_key] = key },
    handler = { [CLICK] = h.toggle_collapse },
  }
end

local function spacer_def(width)
  return { type = "empty-widget", style_mods = { width = width or 20 } }
end

local function pusher_def()
  return { type = "empty-widget", style_mods = { horizontally_stretchable = true } }
end

local function reorder_def(dir, task_id, h)
  return {
    type = "button",
    caption = dir == "up" and "▲" or "▼",
    tooltip = dir == "up" and { "fqt.move-up" } or { "fqt.move-down" },
    style_mods = { width = 24, height = 24, padding = 0 },
    tags = { [constants.tag.task_id] = task_id, [constants.tag.dir] = dir },
    handler = { [CLICK] = h.move_task },
  }
end

local function tick_def()
  return {
    type = "sprite",
    sprite = "utility/check_mark_green",
    style_mods = { width = 20, height = 20, stretch_image_to_widget_size = true },
  }
end

local function delete_def(task_id, h)
  return {
    type = "sprite-button",
    sprite = "utility/trash",
    tooltip = { "fqt.delete" },
    style_mods = { width = 24, height = 24, padding = 2 },
    tags = { [constants.tag.task_id] = task_id },
    handler = { [CLICK] = h.delete_task },
  }
end

-- rendering ---------------------------------------------------------------------------------------

local function render_component(list, node, depth, ps, h)
  local kids = children_with_deficit(node, ps.hide_completed)
  local has_kids = #kids > 0
  local collapsed = ps.collapsed[node.key]

  local row = {
    type = "flow",
    direction = "horizontal",
    style_mods = { vertical_align = "center", horizontal_spacing = 4, left_margin = depth * 14 },
  }
  row[#row + 1] = has_kids and collapse_def(node.key, collapsed, h) or spacer_def()
  row[#row + 1] = { type = "label", caption = node_caption(node), style_mods = name_style(node, false) }
  row[#row + 1] = pusher_def()

  row[#row + 1] = {
    type = "label",
    caption = have_need(node),
    style_mods = node.satisfied and { font_color = GREY } or nil,
  }
  if node.truncated then
    row[#row + 1] = {
      type = "sprite-button",
      sprite = "utility/warning_icon",
      tooltip = { "fqt.truncated" },
      style_mods = { width = 20, height = 20, padding = 0 },
    }
  end

  flib_gui.add(list, row)

  if has_kids and not collapsed then
    for _, child in ipairs(kids) do
      render_component(list, child, depth + 1, ps, h)
    end
  end
end

local function render_goal(list, entry, ps, h)
  local node = entry.node
  local kids = children_with_deficit(node, ps.hide_completed)
  local has_kids = #kids > 0
  local collapsed = ps.collapsed[node.key]

  local row = {
    type = "flow",
    direction = "horizontal",
    style_mods = { vertical_align = "center", horizontal_spacing = 4 },
  }
  if node.built then
    row[#row + 1] = tick_def() -- actually in inventory (excludes queued)
  elseif has_kids then
    row[#row + 1] = collapse_def(node.key, collapsed, h)
  else
    row[#row + 1] = spacer_def()
  end
  row[#row + 1] = { type = "label", caption = node_caption(node), style_mods = name_style(node, true) }
  row[#row + 1] = {
    type = "label",
    caption = have_need(node),
    style_mods = { font_color = GREY },
  }
  row[#row + 1] = pusher_def()
  row[#row + 1] = reorder_def("up", entry.task_id, h)
  row[#row + 1] = reorder_def("down", entry.task_id, h)
  row[#row + 1] = delete_def(entry.task_id, h)

  flib_gui.add(list, row)

  if has_kids and not collapsed then
    for _, child in ipairs(kids) do
      render_component(list, child, 1, ps, h)
    end
  end
end

local function render_manual(list, task, ps, h)
  local key = "manual:" .. task.id
  local has_desc = task.description ~= nil and task.description ~= ""
  local collapsed = ps.collapsed[key]

  local row = {
    type = "flow",
    direction = "horizontal",
    style_mods = { vertical_align = "center", horizontal_spacing = 4 },
  }
  row[#row + 1] = has_desc and collapse_def(key, collapsed, h) or spacer_def()
  row[#row + 1] = {
    type = "checkbox",
    state = task.done or false,
    tags = { [constants.tag.task_id] = task.id },
    handler = { [CHECKED] = h.toggle_manual_done },
  }
  row[#row + 1] = {
    type = "label",
    caption = signal_richtext(task.icon) .. task.name,
    style_mods = task.done and { font_color = GREY } or nil,
  }
  row[#row + 1] = pusher_def()
  row[#row + 1] = {
    type = "sprite-button",
    sprite = "utility/rename_icon",
    tooltip = { "fqt.edit" },
    style_mods = { width = 24, height = 24, padding = 2 },
    tags = { [constants.tag.task_id] = task.id },
    handler = { [CLICK] = h.edit_manual },
  }
  row[#row + 1] = reorder_def("up", task.id, h)
  row[#row + 1] = reorder_def("down", task.id, h)
  row[#row + 1] = delete_def(task.id, h)

  flib_gui.add(list, row)

  if has_desc and not collapsed then
    local desc = list.add({ type = "label", caption = task.description })
    desc.style.single_line = false
    desc.style.left_margin = 28
    desc.style.maximal_width = 280
    desc.style.font = "default-semibold"
  end
end

local function render_missing(list, entry, h)
  flib_gui.add(list, {
    type = "flow",
    direction = "horizontal",
    style_mods = { vertical_align = "center", horizontal_spacing = 4 },
    {
      type = "sprite-button",
      sprite = "utility/warning_icon",
      tooltip = { "fqt.truncated" },
      style_mods = { width = 20, height = 20, padding = 0 },
    },
    { type = "label", caption = { "fqt.missing-recipe", entry.recipe }, style_mods = { font_color = GREY } },
    pusher_def(),
    delete_def(entry.task_id, h),
  })
end

function tree_view.render(list, forest, ps, h)
  list.clear()
  if #forest == 0 then
    local hint = list.add({ type = "label", caption = { "fqt.empty-hint" } })
    hint.style.single_line = false
    hint.style.maximal_width = 280
    return
  end
  for _, entry in ipairs(forest) do
    if entry.kind == "goal" then
      render_goal(list, entry, ps, h)
    elseif entry.kind == "missing" then
      render_missing(list, entry, h)
    else
      render_manual(list, entry.task, ps, h)
    end
  end
end

return tree_view
