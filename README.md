# Malderan's Quick Tasks

A task list for Factorio 2.0 built around one idea: **modifier-click a recipe and it becomes a live,
inventory-aware crafting checklist** that breaks down into everything you still need to make or gather.

## Features

- **Grab from the crafting menu** — `Ctrl+Shift+Left-click` a recipe to add it as a goal (`+1`),
  `Ctrl+Shift+Right-click` for `+5`. Re-clicking the same recipe just increments its count. All binds
  are rebindable in *Settings → Controls*.
- **Live breakdown** — each goal expands into a nested, collapsible tree of its components, recomputed
  continuously from your current inventory. Items you already have drop out; only real shortfalls show.
- **Counts what you actually have** — main inventory, the stack in your cursor, ingredients sequestered
  in your hand-crafting queue, and fluids in storage tanks. Items still being crafted are *not* counted
  until they're really in your inventory.
- **Cheapest recipe selection** — when an item can be made several ways, it picks the simplest path
  (fewest raw materials), prefers researched recipes, and avoids barrel/box/recycling loops.
- **Readiness colours** — an item turns **green** when you can hand-craft it right now (you have the
  ingredients, or can hand-craft them), **yellow** when a machine can make it from inputs you already
  have.
- **Heads-up overlay** — close the panel and a compact, click-through overlay stays on screen showing
  your top remaining needs (and a tick for completed goals).
- **Manual tasks** — add free-form to-dos with an optional icon and a description, tick them off, and
  reorder anything in the list.
- **Auto-complete** — finished goals are removed automatically (or kept with a green tick — your
  choice).

## Usage

- Toggle the panel with the **shortcut button** (top toolbar) or `Ctrl+Shift+T`.
- `Ctrl+Shift+Left/Right-click` a recipe in the crafting menu to queue it.
- Use **+ Task** for a manual note.

## Settings (per player)

- **Min ticks per recalculation** — how often the list refreshes; the hard rate cap. Lower = snappier,
  higher = lower overhead. Default 15.
- **Max breakdown depth** — how deep the component tree may go (cycle/explosion guard). Default 25.
- **Auto-remove completed goals** — drop goals once built, or keep them shown with a tick. Default on.

## Dependencies

- [flib](https://mods.factorio.com/mod/flib) `>= 0.16.0`

## Support

- Questions and bug reports: **[Malderan's Factorio Discord](https://discord.gg/pWX7wPd)** or the
  [issue tracker](https://github.com/malderan-falquis/factorio-malderans-quick-tasks/issues).

## License

[MIT](LICENSE) © Malderan
