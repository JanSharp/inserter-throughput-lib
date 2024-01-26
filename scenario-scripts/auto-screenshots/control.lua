
assert(script.active_mods["base"], "inserter-throughput-lib auto-screenshots scenario requires the base mod.")

local vec = require("__inserter-throughput-lib__.vector")

local ev = defines.events

local actions = {}
local next_free_tick = 0

---@param tick_count integer
local function wait_ticks(tick_count)
  next_free_tick = next_free_tick + tick_count
end

---@param action fun()
local function add_action(action)
  assert(not actions[next_free_tick])
  actions[next_free_tick] = action
end

---@param from MapPosition
---@param to MapPosition
---@param dotted boolean?
local function draw_line(from, to, dotted)
  rendering.draw_line{
    surface = global.surface,
    color = {r = 1, g = 1, b = 1, a = 1},
    width = 2,
    from = from,
    to = to,
    gap_length = dotted and 2/32 or nil,
    dash_length = dotted and 2/32 or nil,
    dash_offset = dotted and 1/32 or nil,
  }
end

---@param from MapPosition
---@param to MapPosition
local function draw_arrow(from, to)
  draw_line(from, to)
  rendering.draw_polygon{
    surface = global.surface,
    color = {r = 1, g = 1, b = 1, a = 1},
    target = to,
    orientation = vec.get_orientation(vec.sub(vec.copy(to), from)),
    vertices = {
      {target = {x = 0, y = -2/32}},
      {target = {x = -4/32, y = 2/32}},
      {target = {x = 4/32, y = 2/32}},
    },
  }
end

---@param position MapPosition
local function draw_dot(position)
  rendering.draw_circle{
    surface = global.surface,
    color = {r = 1, g = 1, b = 1, a = 1},
    radius = 3/32,
    filled = true,
    target = position,
  }
end

add_action(function()
  if not global.player then return end
  global.player.teleport{x = 0.5, y = 0.5}
  global.player.zoom = 2
end)
wait_ticks(1)

add_action(function()
  local inserter = assert(global.surface.create_entity{
    name = "splitter-drop-target-test",
    position = {x = 0.5, y = 0.5},
    direction = defines.direction.south,
  })
  inserter.pickup_position = {x = 1.5, y = 2.5}
  inserter.drop_position = {x = -0.5 - 51/256, y = -0.5 + 51/256}

  global.surface.create_entity{
    name = "transport-belt",
    position = {x = 1.5, y = 4.5},
    direction = defines.direction.north,
  }
  global.surface.create_entity{
    name = "transport-belt",
    position = {x = 1.5, y = 3.5},
    direction = defines.direction.north,
  }
  global.surface.create_entity{
    name = "transport-belt",
    position = {x = 1.5, y = 2.5},
    direction = defines.direction.east,
  }
  global.surface.create_entity{
    name = "transport-belt",
    position = {x = 2.5, y = 2.5},
    direction = defines.direction.east,
  }
  global.surface.create_entity{
    name = "transport-belt",
    position = {x = 3.5, y = 2.5},
    direction = defines.direction.east,
  }

  for x = 3.5, -3.5, -1 do
    global.surface.create_entity{
      name = "transport-belt",
      position = {x = x, y = -0.5},
      direction = defines.direction.west,
    }
  end

  local pickup_vector = vec.sub(inserter.pickup_position, inserter.position)
  local drop_vector = vec.sub(inserter.drop_position, inserter.position)

  draw_line(inserter.position, inserter.pickup_position)
  draw_line(inserter.position, inserter.drop_position)
  local extended_drop = vec.add(inserter.position, vec.set_length(vec.copy(drop_vector), vec.get_length(pickup_vector)))
  draw_line(inserter.drop_position, extended_drop, true)
  draw_dot(inserter.position)
  draw_dot(inserter.pickup_position)
  draw_dot(inserter.drop_position)
  draw_dot(extended_drop)

  rendering.draw_arc{
    surface = global.surface,
    color = {r = 1, g = 1, b = 1, a = 1},
    min_radius = vec.get_length(pickup_vector) - 1/32,
    max_radius = vec.get_length(pickup_vector) + 1/32,
    target = inserter.position,
    start_angle = vec.get_radians(pickup_vector) - math.rad(90), -- 0 is east... while 0 everywhere else is north.
    angle = vec.get_radians(drop_vector) - vec.get_radians(pickup_vector),
  }

  rendering.draw_arc{
    surface = global.surface,
    color = {r = 1, g = 1, b = 1, a = 1},
    min_radius = vec.get_length(drop_vector) - 1/32,
    max_radius = vec.get_length(drop_vector) + 1/32,
    target = inserter.position,
    start_angle = vec.get_radians(pickup_vector) - math.rad(90),
    angle = vec.get_radians(drop_vector) - vec.get_radians(pickup_vector),
  }

  local belt_flow_vector = vec.rotate_by_orientation({x = 0, y = -1}, 0.125)
  draw_arrow(inserter.pickup_position, vec.add(inserter.pickup_position, belt_flow_vector))
  local projected_point = vec.add(
    inserter.pickup_position,
    vec.set_length(
      vec.copy(pickup_vector),
      (vec.dot_product(pickup_vector, belt_flow_vector) / vec.get_length(pickup_vector))
    )
  )
  draw_dot(projected_point)
  draw_line(vec.add(inserter.pickup_position, belt_flow_vector), projected_point, true)

  rendering.draw_text{
    surface = global.surface,
    color = {r = 1, g = 1, b = 1, a = 1},
    target = vec.add(inserter.position, {x = 2.625, y = -3}),
    text = "?/s",
    alignment = "right",
    vertical_alignment = "top",
    scale = 5,
  }

  rendering.draw_text{
    surface = global.surface,
    color = {r = 1, g = 1, b = 1, a = 1},
    target = vec.add(inserter.position, {x = 2.625, y = 3}),
    text = "lib",
    alignment = "right",
    vertical_alignment = "bottom",
    scale = 2,
  }
end)
wait_ticks(60)
add_action(function()
  local pixels_per_tile = 144 / 6
  game.take_screenshot{
    surface = global.surface,
    position = {x = 0.5, y = 0.5},
    daytime = 0,
    path = "itl/thumbnail.png",
    resolution = {144, 144},
    zoom = pixels_per_tile / 32,
    force_render = true,
    show_entity_info = true,
  }
end)
wait_ticks(1)
add_action(function()
  game.print("Screenshot taken.")
end)

script.on_event(ev.on_player_created, function(event)
  local player = game.get_player(event.player_index) ---@cast player -nil
  player.toggle_map_editor()
  game.tick_paused = false
  global.player = player
end)

script.on_event(ev.on_tick, function(event)
  local relative_tick = event.tick - global.start_tick
  local action = actions[relative_tick]
  if action and not global.ran_actions[relative_tick] then
    global.ran_actions[relative_tick] = true
    action()
  end
end)

script.on_init(function()
  global.start_tick = game.tick + 1
  global.surface = game.surfaces["nauvis"]
  global.force = game.forces["player"]
  global.ran_actions = {}
end)
