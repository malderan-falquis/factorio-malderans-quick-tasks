-- The add/edit form for manual tasks, shown as a centered modal frame on player.gui.screen. Handler
-- functions are passed in from gui/index.lua (so this module doesn't depend on it).
local flib_gui = require("__flib__.gui")
local constants = require("scripts.constants")
local manual_tasks = require("scripts.manual-tasks")
local storage_mod = require("scripts.storage")

local manual_form = {}

local CLICK = defines.events.on_gui_click

-- Recursively find a descendant element by name (form fields are nested inside flows).
local function find_by_name(element, name)
  if element.name == name then return element end
  for _, child in pairs(element.children) do
    local found = find_by_name(child, name)
    if found then return found end
  end
  return nil
end

local function trim(text)
  return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

function manual_form.close(player)
  -- Destroying the opened frame auto-clears player.opened and raises on_gui_closed, which re-enters
  -- this function via cancel_manual. By the time it does, the frame is gone, so the guard makes the
  -- reentrant call a no-op (no double-destroy).
  local form = player.gui.screen[constants.gui.form]
  if form and form.valid then
    form.destroy()
  end
  local ps = storage.players[player.index]
  if ps then ps.editing_task_id = nil end
end

function manual_form.open(player, task_id, h)
  manual_form.close(player)
  local ps = storage.players[player.index]
  ps.editing_task_id = task_id
  local task = task_id and storage_mod.find_task(ps, task_id) or nil

  local elems = flib_gui.add(player.gui.screen, {
    type = "frame",
    name = constants.gui.form,
    direction = "vertical",
    caption = task and { "fqt.edit-task" } or { "fqt.new-task" },
    handler = { [defines.events.on_gui_closed] = h.cancel_manual },
    {
      type = "flow",
      direction = "vertical",
      style_mods = { padding = 8, vertical_spacing = 8 },
      {
        type = "flow",
        direction = "horizontal",
        style_mods = { vertical_align = "center", horizontal_spacing = 8 },
        { type = "label", caption = { "fqt.field-icon" } },
        { type = "choose-elem-button", name = constants.gui.form_icon, elem_type = "signal" },
        { type = "label", caption = { "fqt.field-name" } },
        { type = "textfield", name = constants.gui.form_name, style_mods = { width = 220 } },
      },
      { type = "label", caption = { "fqt.field-desc" } },
      { type = "text-box", name = constants.gui.form_desc, style_mods = { width = 340, height = 120 } },
      {
        type = "flow",
        direction = "horizontal",
        style_mods = { horizontal_spacing = 8, top_margin = 4 },
        { type = "empty-widget", style_mods = { horizontally_stretchable = true } },
        { type = "button", caption = { "fqt.cancel" }, handler = { [CLICK] = h.cancel_manual } },
        {
          type = "button",
          style = "confirm_button",
          caption = { "fqt.save" },
          handler = { [CLICK] = h.save_manual },
        },
      },
    },
  })

  if task then
    elems[constants.gui.form_name].text = task.name or ""
    elems[constants.gui.form_desc].text = task.description or ""
    elems[constants.gui.form_icon].elem_value = task.icon
  end
  elems[constants.gui.form_name].focus()

  local form = player.gui.screen[constants.gui.form]
  form.force_auto_center()
  player.opened = form
end

-- Reads the form and creates/updates the task. Returns true on success (false if name is blank).
function manual_form.save(player)
  local form = player.gui.screen[constants.gui.form]
  if not (form and form.valid) then return false end

  local name = trim(find_by_name(form, constants.gui.form_name).text or "")
  if name == "" then
    player.print({ "fqt.name-required" })
    return false
  end

  local desc = find_by_name(form, constants.gui.form_desc).text or ""
  local icon = find_by_name(form, constants.gui.form_icon).elem_value
  local fields = { name = name, description = desc, icon = icon }

  local ps = storage.players[player.index]
  if ps.editing_task_id then
    manual_tasks.update(ps, ps.editing_task_id, fields)
  else
    manual_tasks.add(ps, fields)
  end
  return true
end

return manual_form
