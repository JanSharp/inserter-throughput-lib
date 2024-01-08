
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

---@param left defines.direction
---@param right defines.direction
---@return defines.direction result
local function add_directions(left, right)
  return (left + right) % 8
end

---@param direction defines.direction
---@return number orientation
local function direction_to_orientation(direction)
  return direction / 8
end

---@param drop_tile TilePosition
---@param inserter_direction defines.direction
---@param splitter_direction defines.direction
---@param target_right_splitter_side boolean
local function build(drop_tile, inserter_direction, splitter_direction, target_right_splitter_side)
  local tile_center = vec.add_scalar(vec.copy(drop_tile), 0.5)
  local splitter_orientation = direction_to_orientation(splitter_direction)
  local inserter_orientation = direction_to_orientation(inserter_direction)
  local function rotate_position(position)
    return vec.add(vec.rotate_by_orientation(vec.sub(position, tile_center), splitter_orientation), tile_center)
  end
  local create_entity = global.surface.create_entity
  global.splitter = assert(create_entity{
    name = "express-splitter",
    direction = splitter_direction,
    position = rotate_position(vec.add({x = target_right_splitter_side and -0.5 or 0.5, y = 0}, tile_center)),
    force = global.force,
  })
  global.inserter = assert(create_entity{
    name = "splitter-drop-target-test",
    direction = add_directions(inserter_direction, splitter_direction),
    position = rotate_position(vec.add(vec.rotate_by_orientation({x = 0, y = -2}, inserter_orientation), tile_center)),
    force = global.force,
  })
  global.inserter.drop_position = tile_center
  global.shift_count = 0
end

local function give_inserter_two_items()
  global.inserter.held_stack.set_stack{name = "iron-plate", count = 2}
end

local function has_items_on_both_outputs()
  for i = 1, 8 do
    local count = #global.splitter.get_transport_line(i)
    if count > 0 then
      return count == 1 -- if it were == 2 then both items ended up on the same line.
    end
  end
  error("No items.")
end

local function clear_splitter()
  for i = 1, 8 do
    global.splitter.get_transport_line(i).clear()
  end
end

---@param splitter_direction defines.direction
local function shift_inserter_drop(splitter_direction)
  local shift = vec.rotate_by_orientation({x = 0, y = -1/256}, direction_to_orientation(splitter_direction))
  -- print(string.format("x: %d, y: %d", shift.x * 256, shift.y * 256))
  global.inserter.drop_position = vec.add(global.inserter.drop_position, shift)
  global.shift_count = global.shift_count + 1
end

local function reset_world()
  global.splitter.destroy()
  global.inserter.destroy()
end

-- https://chrisyeh96.github.io/2020/03/28/terminal-colors.html
-- https://www2.ccs.neu.edu/research/gpc/VonaUtils/vona/terminal/vtansi.htm
local reset = "\x1b[0m"
local bold = "\x1b[1m"
local faint = "\x1b[2m"
local singly_underlined = "\x1b[4m"
local blink = "\x1b[5m"
local reverse = "\x1b[7m"
local hidden = "\x1b[8m"
-- foreground colors:
local black = "\x1b[30m"
local red = "\x1b[31m"
local green = "\x1b[32m"
local yellow = "\x1b[33m"
local blue = "\x1b[34m"
local magenta = "\x1b[35m"
local cyan = "\x1b[36m"
local white = "\x1b[37m"

local direction_name_lut = {
  [defines.direction.north] = "north",
  [defines.direction.east] = "east ",
  [defines.direction.south] = "south",
  [defines.direction.west] = "west ",
}

---@param inserter_direction defines.direction
---@param splitter_direction defines.direction
---@param target_right_splitter_side boolean
local function perform_test(inserter_direction, splitter_direction, target_right_splitter_side)
  add_action(function()
    build({x = 0, y = 0}, inserter_direction, splitter_direction, target_right_splitter_side)
  end)
  wait_ticks(1)
  for _ = 1, 3 do
    add_action(give_inserter_two_items)
    wait_ticks(5)
    add_action(function()
      local did_split = has_items_on_both_outputs()
      if global.shift_count == 1 then
        print((did_split and magenta or green)
          ..direction_name_lut[inserter_direction].." inserter, "
          ..direction_name_lut[splitter_direction].." splitter, "
          -- .."targeting "..(target_right_splitter_side and "right" or "left ").." side, "
          .."drop shifted by "..global.shift_count.."/256 "..direction_name_lut[splitter_direction]..", "
          .."did split: "..(did_split and "true" or "false")
          ..reset
        )
      end
      clear_splitter()
      shift_inserter_drop(splitter_direction)
    end)
    wait_ticks(1)
  end
  add_action(reset_world)
  wait_ticks(1)
end

local function add_white_line_print()
  add_action(function()
    print(white..string.rep("-", 77)..reset)
  end)
  wait_ticks(1)
end

add_action(function()
  game.speed = 1024
end)
wait_ticks(1)
add_white_line_print()
for _, splitter_direction in pairs{
  defines.direction.north,
  defines.direction.east,
  defines.direction.south,
  defines.direction.west,
}
do
  for _, inserter_direction in pairs{
    defines.direction.north,
    defines.direction.east,
    defines.direction.south,
    defines.direction.west,
  }
  do
    perform_test(splitter_direction, inserter_direction, false)
    -- perform_test(splitter_direction, inserter_direction, true)
  end
  add_white_line_print()
end
add_action(function()
  game.speed = 1
end)
wait_ticks(1)

script.on_event(ev.on_player_created, function(event)
  local player = game.get_player(event.player_index) ---@cast player -nil
  if player.controller_type ~= defines.controllers.editor then
    player.toggle_map_editor()
  end
  game.tick_paused = false
  global.player = player
end)

script.on_event(ev.on_tick, function(event)
  local relative_tick = event.tick - global.start_tick
  local action = actions[relative_tick]
  if action then
    action()
  end
end)

script.on_init(function()
  global.start_tick = game.tick + 1
  global.surface = game.surfaces["nauvis"]
  global.force = game.forces["player"]
end)
