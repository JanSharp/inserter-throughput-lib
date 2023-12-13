
local util = require("__core__.lualib.util")
local configurations = require("__inserter-throughput-lib__.scenario-scripts.throughput-test.configurations")

---@class SetupDefinitionITL
---@field name string
---@field setup string
---@field flipped_variant boolean?
---@field variant_without_output_loader boolean?

---@class EntityDefinitionITL
---@field entity_id integer @ The byte for the character used to define it in the setup string.
---@field position MapPosition
---@field direction defines.direction|"infer" @ For belts, splitters, undergrounds and loaders.
---@field items_moving_in boolean @ For undergrounds and loaders.
---@field other_splitter_half EntityDefinitionITL @ For splitters.
---@field connected_underground EntityDefinitionITL? @ For undergrounds.
---@field connected_chest EntityDefinitionITL @ For loaders.
---@field connected_loader EntityDefinitionITL? @ For input and output chests.

---@class ParsedSetupITL : PickupAndDropTypeITL
---@field name string
---@field setup string
---@field width integer
---@field height integer
---@field left_top_offset MapPosition
---@field grid table<integer, EntityDefinitionITL>
---@field pickup MapPosition
---@field drop MapPosition
---@field pickups MapPosition[] @ `nil` in the final data structure.
---@field drops MapPosition[] @ `nil` in the final data structure.
---@field inserter EntityDefinitionITL
---@field loaders EntityDefinitionITL[]
---@field undergrounds EntityDefinitionITL[]
---@field uses_belts boolean
---@field is_variant_without_output_loader boolean? @ `nil` when not dropping onto any belt connectables.

---@alias PickupOrDropTypeITL "chest"|"belt"|"splitter"|"underground"|"ground"

---@class PickupAndDropTypeITL
---@field pickup_type PickupOrDropTypeITL?
---@field drop_type PickupOrDropTypeITL?
---@field without_output_loader boolean? @ Setups not dropping onto belt connectables always "match" this filter.

---@alias SetupFiltersITL PickupAndDropTypeITL

local string_byte = string.byte

local inverse_direction_lut = {
  [defines.direction.north] = defines.direction.south,
  [defines.direction.east] = defines.direction.west,
  [defines.direction.south] = defines.direction.north,
  [defines.direction.west] = defines.direction.east,
}

---@type ParsedSetupITL[]
local parsed_setups = {}

---@param x uint16
---@param y uint16
---@return uint32
local function get_point(x, y)
  return x * 2^16 + y
end

---@param point uint32
---@return uint16 x
---@return uint16 y
local function get_xy(point)
  -- Not using bit32 because math is faster than those function calls.
  local y = point % 2^16 -- Basically bitwise AND on lower 16 bits.
  return (point - y) / 2^16, y -- Basically right shift by 16 for x.
end

---@param position MapPosition
---@return string
local function pretty_position(position)
  return string.format("x: %d, y: %d", position.x, position.y)
end

---@param setup string
---@return integer width
---@return integer height
local function get_width_and_height(setup)
  local row_char_count = assert(setup:find("\n", 1, true), "setup strings must have a least 1 new line.")
  return (row_char_count - 1) / 2, #setup / row_char_count
end

---@type table<integer, defines.direction|"infer">
local direction_for_entity_id = {
  [string_byte("l")] = "infer",
  [string_byte("^")] = defines.direction.north,
  [string_byte(">")] = defines.direction.east,
  [string_byte("v")] = defines.direction.south,
  [string_byte("<")] = defines.direction.west,
  [string_byte("]")] = "infer",
  [string_byte("[")] = "infer",
  [string_byte("}")] = defines.direction.east,
  [string_byte("{")] = defines.direction.west,
}

local dot_byte = string_byte(".")
local i_byte = string_byte("i")
local o_byte = string_byte("o")
local b_byte = string_byte("b")
local p_byte = string_byte("p")
local d_byte = string_byte("d")
local l_byte = string_byte("l")
local bracket_left_byte = string_byte("[")
local bracket_right_byte = string_byte("]")
local curly_bracket_left_byte = string_byte("{")
local curly_bracket_right_byte = string_byte("}")

---@param entity_def EntityDefinitionITL?
---@return boolean?
local function is_infinity_chest(entity_def)
  return entity_def and (entity_def.entity_id == i_byte or entity_def.entity_id == o_byte)
end

---@param entity_def EntityDefinitionITL?
---@return boolean?
local function is_belt_for_loader_infer(entity_def)
  return entity_def
    and entity_def.direction
    and entity_def.entity_id ~= l_byte
end

---@param loader EntityDefinitionITL
---@param chest EntityDefinitionITL
---@param in_direction defines.direction
---@param out_direction defines.direction
local function set_loader_direction(loader, chest, in_direction, out_direction)
  loader.items_moving_in = chest.entity_id == o_byte
  loader.direction = loader.items_moving_in and in_direction or out_direction
  loader.connected_chest = chest
  chest.connected_loader = loader
end

---@param parsed_setup ParsedSetupITL
local function infer_loader_directions(parsed_setup)
  for _, loader in pairs(parsed_setup.loaders) do
    local top = parsed_setup.grid[get_point(loader.position.x, loader.position.y - 1)]
    local right = parsed_setup.grid[get_point(loader.position.x + 1, loader.position.y)]
    local bottom = parsed_setup.grid[get_point(loader.position.x, loader.position.y + 1)]
    local left = parsed_setup.grid[get_point(loader.position.x - 1, loader.position.y)]
    if is_infinity_chest(top) and is_belt_for_loader_infer(bottom) then
      set_loader_direction(loader, top, defines.direction.north, defines.direction.south)
    elseif is_infinity_chest(bottom) and is_belt_for_loader_infer(top) then
      set_loader_direction(loader, bottom, defines.direction.south, defines.direction.north)
    elseif is_infinity_chest(right) and is_belt_for_loader_infer(left) then
      set_loader_direction(loader, right, defines.direction.east, defines.direction.west)
    elseif is_infinity_chest(left) and is_belt_for_loader_infer(right) then
      set_loader_direction(loader, left, defines.direction.west, defines.direction.east)
    else
      error("Unable to infer direction for loader at "..pretty_position(loader.position)..".")
    end
  end
end

---@param entity_def EntityDefinitionITL?
---@return boolean?
local function is_belt_for_underground_infer(entity_def)
  return entity_def
    and entity_def.direction
    and entity_def.entity_id ~= bracket_left_byte
    and entity_def.entity_id ~= bracket_right_byte
    and (entity_def.direction == defines.direction.east or entity_def.direction == defines.direction.west)
end

---@param parsed_setup ParsedSetupITL
local function infer_underground_directions(parsed_setup)
  ---@type table<EntityDefinitionITL, true>
  local pending_infer_through_connection = {}
  for _, underground in pairs(parsed_setup.undergrounds) do
    if underground.direction ~= "infer" then goto continue end

    local right = parsed_setup.grid[get_point(underground.position.x + 1, underground.position.y)]
    local left = parsed_setup.grid[get_point(underground.position.x - 1, underground.position.y)]
    if is_belt_for_underground_infer(right) then
      underground.direction = right.direction
    elseif is_belt_for_underground_infer(left) then
      underground.direction = left.direction
    elseif not underground.connected_underground
      or pending_infer_through_connection[underground.connected_underground]
    then
      error("Unable to infer direction for underground at "..pretty_position(underground.position)..".")
    else
      pending_infer_through_connection[underground] = true
    end
    underground.items_moving_in
      = (underground.entity_id == bracket_right_byte) == (underground.direction == defines.direction.east)

    if underground.connected_underground then
      pending_infer_through_connection[underground.connected_underground] = nil
      underground.connected_underground.direction = underground.direction
      underground.connected_underground.items_moving_in = not underground.items_moving_in
    end
    ::continue::
  end

  assert(not next(pending_infer_through_connection),
    "This should be impossible so long as underground connects are evaluated correctly."
  )
end

---@param setup_def SetupDefinitionITL
local function parse_setup(setup_def)
  ---@type ParsedSetupITL
  local parsed_setup = {
    name = setup_def.name,
    setup = setup_def.setup,
    grid = {},
    pickups = {},
    drops = {},
    loaders = {},
    undergrounds = {},
  }

  ---@type table<EntityDefinitionITL, true>
  local open_splitters = {}
  local width, height = get_width_and_height(setup_def.setup)
  for y = 1, height do
    for x = 1, width do
      local i = (y - 1) * (width * 2 + 1) + (x * 2 - 1)
      local entity_id, metadata = string_byte(setup_def.setup, i, i + 1)

      if metadata == p_byte then
        parsed_setup.pickups[#parsed_setup.pickups+1] = {x = x, y = y}
      elseif metadata == d_byte then
        parsed_setup.drops[#parsed_setup.drops+1] = {x = x, y = y}
      end

      if entity_id == dot_byte then goto continue end

      ---@type EntityDefinitionITL
      local entity_def = {
        entity_id = entity_id,
        position = {x = x, y = y},
        direction = direction_for_entity_id[entity_id],
      }
      parsed_setup.grid[get_point(x, y)] = entity_def

      if entity_id == b_byte then
        assert(not parsed_setup.inserter, "Each setup can only contain one inserter.")
        parsed_setup.inserter = entity_def
      elseif entity_id == l_byte then
        parsed_setup.loaders[#parsed_setup.loaders+1] = entity_def
      elseif entity_id == bracket_left_byte then
        parsed_setup.undergrounds[#parsed_setup.undergrounds+1] = entity_def
        for other_x = x - 1, math.max(1, x - 5), -1 do
          local other = parsed_setup.grid[get_point(other_x, y)]
          if other and other.entity_id == bracket_right_byte then
            if other.connected_underground then
              error("Unable to connect underground at "..pretty_position(entity_def.position)..".")
            end
            other.connected_underground = entity_def
            entity_def.connected_underground = other
            break
          end
        end
      elseif entity_id == bracket_right_byte then
        parsed_setup.undergrounds[#parsed_setup.undergrounds+1] = entity_def
      elseif entity_id == curly_bracket_left_byte or entity_id == curly_bracket_right_byte then
        local above = parsed_setup.grid[get_point(x, y - 1)]
        if above and above.entity_id == entity_id and not above.other_splitter_half then
          entity_def.other_splitter_half = above
          above.other_splitter_half = entity_def
          open_splitters[above] = nil
        else
          open_splitters[entity_def] = true
        end
      end

      ::continue::
    end
  end

  assert(parsed_setup.inserter, "Each setup must contain exactly one inserter.")

  local open_splitter = next(open_splitters)
  if open_splitter then
    error("Invalid splitter at "..pretty_position(open_splitter.position)..".")
  end

  infer_loader_directions(parsed_setup)
  infer_underground_directions(parsed_setup) -- Must come after loader inference.

  return parsed_setup
end

local flipped_setup_lut = {
  [string_byte("i")] = "i",
  [string_byte("o")] = "o",
  [string_byte("l")] = "l",
  [string_byte("b")] = "b",
  [string_byte("^")] = "^",
  [string_byte(">")] = "<",
  [string_byte("v")] = "v",
  [string_byte("<")] = ">",
  [string_byte("]")] = "[",
  [string_byte("[")] = "]",
  [string_byte("}")] = "{",
  [string_byte("{")] = "}",
  [string_byte(".")] = ".",
  [string_byte(" ")] = " ",
  [string_byte("p")] = "p",
  [string_byte("d")] = "d",
}

---@param setup string
local function flip_setup(setup)
  local out = {}
  local width, height = get_width_and_height(setup)
  local row_char_count = width * 2 + 1
  local start = 0
  local stop = row_char_count
  for _ = 1, height do
    for i = 1, row_char_count - 2, 2 do
      local one, two = string_byte(setup, start + i, start + i + 1)
      out[stop - i - 1] = flipped_setup_lut[one]
      out[stop - i] = flipped_setup_lut[two]
    end
    out[stop] = "\n"
    start = start + row_char_count
    stop = stop + row_char_count
  end
  return table.concat(out)
end

---@param parsed_setup ParsedSetupITL
local function remove_unused_chests(parsed_setup)
  local pickup = parsed_setup.pickup
  local drop = parsed_setup.drop
  local point, entity_def = next(parsed_setup.grid)
  while point do
    local next_point, next_entity_def = next(parsed_setup.grid, point)
    if entity_def.entity_id ~= i_byte and entity_def.entity_id ~= o_byte then goto continue end
    if entity_def.connected_loader then goto continue end
    if entity_def.position.x == pickup.x and entity_def.position.y == pickup.y then goto continue end
    if entity_def.position.x == drop.x and entity_def.position.y == drop.y then goto continue end
    parsed_setup.grid[point] = nil
    ::continue::
    point, entity_def = next_point, next_entity_def
  end
end

---@param parsed_setup ParsedSetupITL
local function eval_final_width_and_height(parsed_setup)
  local left, top = 1/0, 1/0
  local right, bottom = -1/0, -1/0
  for _, entity_def in pairs(parsed_setup.grid) do
    left = math.min(left, entity_def.position.x)
    top = math.min(top, entity_def.position.y)
    right = math.max(right, entity_def.position.x)
    bottom = math.max(bottom, entity_def.position.y)
  end
  parsed_setup.width = right - left + 1
  parsed_setup.height = bottom - top + 1
  parsed_setup.left_top_offset = {
    x = -(left - 1),
    y = -(top - 1),
  }
end

---@param parsed_setup ParsedSetupITL
---@param position MapPosition
---@return EntityDefinitionITL?
local function get_entity_def(parsed_setup, position)
  return parsed_setup.grid[get_point(position.x, position.y)]
end

---@param entity_def EntityDefinitionITL?
---@return PickupOrDropTypeITL
local function get_pickup_or_drop_type(entity_def)
  ---@cast entity_def -nil
  return not entity_def and "ground"
    or entity_def.entity_id == i_byte and "chest"
    or entity_def.entity_id == bracket_left_byte and "underground"
    or entity_def.entity_id == bracket_right_byte and "underground"
    or entity_def.entity_id == curly_bracket_left_byte and "splitter"
    or entity_def.entity_id == curly_bracket_right_byte and "splitter"
    or "belt"
end

---@param parsed_setup ParsedSetupITL
local function determine_pickup_and_drop_types(parsed_setup)
  parsed_setup.pickup_type = get_pickup_or_drop_type(get_entity_def(parsed_setup, parsed_setup.pickup))
  parsed_setup.drop_type = get_pickup_or_drop_type(get_entity_def(parsed_setup, parsed_setup.drop))
end

---@param pickup_or_dro_type PickupOrDropTypeITL
---@return boolean
local function is_belt_connectable_type(pickup_or_dro_type)
  return pickup_or_dro_type == "belt"
    or pickup_or_dro_type == "splitter"
    or pickup_or_dro_type == "underground"
end

---@param parsed_setup ParsedSetupITL
local function eval_uses_belts(parsed_setup)
  parsed_setup.uses_belts = is_belt_connectable_type(parsed_setup.pickup_type)
    or is_belt_connectable_type(parsed_setup.drop_type)
end

---@param parsed_setup ParsedSetupITL
local function eval_is_variant_without_output_loader(parsed_setup)
  if parsed_setup.is_variant_without_output_loader then return end
  if is_belt_connectable_type(parsed_setup.pickup_type) then
    parsed_setup.is_variant_without_output_loader = false
  end
  -- `nil` otherwise, which has the defined meaning that it is not dropping onto any belts, therefore filters
  -- using this field should ignore it (and therefore be considered a match).
end

---@param parsed_setup ParsedSetupITL
local function add_parsed_setup(parsed_setup)
  parsed_setups[#parsed_setups+1] = parsed_setup
end

---@param parsed_setup ParsedSetupITL
local function generate_and_add_variants(parsed_setup)
  local base_setup = util.copy(parsed_setup)
  base_setup.pickups = nil
  base_setup.drops = nil
  for _, pickup in pairs(parsed_setup.pickups) do
    base_setup.pickup = pickup
    for _, drop in pairs(parsed_setup.drops) do
      base_setup.drop = drop
      -- TODO: modify the name, or add some other variant info to the data structure
      local variant = util.copy(base_setup)
      remove_unused_chests(variant)
      eval_final_width_and_height(variant)
      determine_pickup_and_drop_types(variant)
      eval_uses_belts(variant)
      eval_is_variant_without_output_loader(variant)
      add_parsed_setup(variant)
    end
  end
end

---@param setup_def SetupDefinitionITL
local function parse_generate_and_add_variants(setup_def)
  local parsed_setup = parse_setup(setup_def)
  generate_and_add_variants(parsed_setup)

  if not setup_def.variant_without_output_loader then return end

  parsed_setup.name = parsed_setup.name..", with backed up belts"
  parsed_setup.is_variant_without_output_loader = true
  local list = parsed_setup.loaders
  for i = #list, 1, -1 do
    local loader = list[i]
    if loader.items_moving_in then
      loader.connected_chest.connected_loader = nil
      loader.connected_chest = nil
      list[i] = list[#list]
      list[#list] = nil
      parsed_setup.grid[get_point(loader.position.x, loader.position.y)] = nil
    end
  end
  generate_and_add_variants(parsed_setup)
end

---@param setup_def SetupDefinitionITL
local function add_setup(setup_def)
  parse_generate_and_add_variants(setup_def)
  if setup_def.flipped_variant then
    setup_def.name = setup_def.name
      :gsub("left", "cfb7e2dc")
      :gsub("right", "left")
      :gsub("cfb7e2dc", "right")
    setup_def.setup = flip_setup(setup_def.setup)
    parse_generate_and_add_variants(setup_def)
  end
end

---@param create_entity fun(param: LuaSurface.create_entity_param): LuaEntity?
---@param position MapPosition
---@param entity_def EntityDefinitionITL
---@param configuration ConfigurationITL
local function create_belt(create_entity, position, entity_def, configuration)
  assert(create_entity{
    name = configuration.belt_name,
    position = position,
    direction = entity_def.direction--[[@as defines.direction]],
  })
end

---@param create_entity fun(param: LuaSurface.create_entity_param): LuaEntity?
---@param position MapPosition
---@param entity_def EntityDefinitionITL
---@param configuration ConfigurationITL
local function create_underground(create_entity, position, entity_def, configuration)
  assert(create_entity{
    name = configuration.underground_name,
    position = position,
    direction = entity_def.direction--[[@as defines.direction]],
    type = entity_def.items_moving_in and "input" or "output",
  })
end

---@param create_entity fun(param: LuaSurface.create_entity_param): LuaEntity?
---@param position MapPosition
---@param entity_def EntityDefinitionITL
---@param configuration ConfigurationITL
local function create_splitter(create_entity, position, entity_def, configuration)
  if entity_def.position.y > entity_def.other_splitter_half.position.y then return end
  position.y = position.y + 0.5
  assert(create_entity{
    name = configuration.splitter_name,
    position = position,
    direction = entity_def.direction--[[@as defines.direction]],
  })
end

---@type table<integer, fun(create_entity: (fun(param: LuaSurface.create_entity_param): LuaEntity?), position: MapPosition, entity_def: EntityDefinitionITL, configuration: ConfigurationITL): LuaEntity?>
local create_entity_from_def_lut = {
  [string_byte("i")] = function(create_entity, position, entity_def, configuration)
    local entity = assert(create_entity{
      name = "itl-infinity-chest",
      position = position,
    })
    entity.set_infinity_container_filter(1, {
      name = "iron-plate",
      count = 100,
    })
  end,
  [string_byte("o")] = function(create_entity, position, entity_def, configuration)
    local entity = assert(create_entity{
      name = "itl-infinity-chest",
      position = position,
    })
    entity.remove_unfiltered_items = true
  end,
  [string_byte("l")] = function(create_entity, position, entity_def, configuration)
    local entity = assert(create_entity{
      name = configuration.loader_name,
      position = position,
      direction = entity_def.items_moving_in
        and entity_def.direction--[[@as defines.direction]]
        or inverse_direction_lut[entity_def.direction],
    })
    entity.loader_type = entity_def.items_moving_in and "input" or "output"
  end,
  [string_byte("b")] = function(create_entity, position, entity_def, configuration)
    return assert(create_entity{
      name = configuration.inserter_name,
      position = position,
    })
  end,
  [string_byte("^")] = create_belt,
  [string_byte(">")] = create_belt,
  [string_byte("v")] = create_belt,
  [string_byte("<")] = create_belt,
  [string_byte("]")] = create_underground,
  [string_byte("[")] = create_underground,
  [string_byte("}")] = create_splitter,
  [string_byte("{")] = create_splitter,
}

---@param surface LuaSurface
---@param x integer
---@param y integer
---@param parsed_setup ParsedSetupITL
---@param configuration ConfigurationITL
---@return LuaEntity inserter
local function build_setup(surface, x, y, parsed_setup, configuration)
  local inserter
  local create_entity = surface.create_entity
  local top_left_offset = parsed_setup.left_top_offset
  for _, entity_def in pairs(parsed_setup.grid) do
    local create_entity_from_def = create_entity_from_def_lut[entity_def.entity_id]
    inserter = create_entity_from_def(create_entity, {
      x = x + 0.5 + entity_def.position.x + top_left_offset.x,
      y = y + 0.5 + entity_def.position.y + top_left_offset.y,
    }, entity_def, configuration) or inserter
  end
  ---@cast inserter LuaEntity
  inserter.inserter_stack_size_override = configuration.stack_size
  inserter.pickup_position = {
    x = x + 0.5 + parsed_setup.pickup.x + top_left_offset.x,
    y = y + 0.5 + parsed_setup.pickup.y + top_left_offset.y,
  }
  local x_offset = parsed_setup.drop.x > parsed_setup.inserter.position.x and 51/256
    or parsed_setup.drop.x < parsed_setup.inserter.position.x and -51/256
    or 0
  local y_offset = parsed_setup.drop.y > parsed_setup.inserter.position.y and 51/256
    or parsed_setup.drop.y < parsed_setup.inserter.position.y and -51/256
    or 0
  inserter.drop_position = {
    x = x + 0.5 + parsed_setup.drop.x + top_left_offset.x + x_offset,
    y = y + 0.5 + parsed_setup.drop.y + top_left_offset.y + y_offset,
  }
  return inserter
end

---@param parsed_setup ParsedSetupITL
---@param filters SetupFiltersITL[]?
local function matches_filters(parsed_setup, filters)
  if not filters then return true end
  for _, filter in pairs(filters) do
    if (not filter.pickup_type or filter.pickup_type == parsed_setup.pickup_type)
      and (not filter.drop_type or filter.drop_type == parsed_setup.drop_type)
      and (filter.without_output_loader == nil or parsed_setup.is_variant_without_output_loader == nil
        or filter.without_output_loader == parsed_setup.is_variant_without_output_loader)
    then
      return true
    end
  end
  return false
end

---@param filters SetupFiltersITL[]? @ Combined with an OR. `nil` matches everything. Empty array matches nothing.
local function build_setups(filters)
  local setup_count = 0
  local nauvis = game.get_surface("nauvis") ---@cast nauvis -nil
  local x = 0
  for _, parsed_setup in pairs(parsed_setups) do
    if not matches_filters(parsed_setup, filters) then goto continue end
    for i, configuration in
      pairs(parsed_setup.uses_belts
        and configurations.configurations
        or configurations.configurations_without_belts
      )
    do
      local y = (i - 1) * (parsed_setup.height + 1)
      local inserter = build_setup(nauvis, x, y, parsed_setup, configuration)
      setup_count = setup_count + 1
      ---@type BuiltSetupITL
      global.built_setups[setup_count] = {
        parsed_setup = parsed_setup,
        configuration = configuration,
        inserter = inserter,
        held_stack = inserter.held_stack,
        cycle_count = 0,
        average_total_ticks = 0,
        was_valid_for_read = false,
        cycle_start = -1,
      }
    end
    x = x + parsed_setup.width + 1
    ::continue::
  end
end

--[[
setup definition:

first column per tile:
i = input infinity chest
o = output infinity chest
l = 1x1 loader
b = inserter base
^>v< = belts
][ = undergrounds, can only go horizontally
}{ = splitters, can only go horizontally
. = ground

second column per tile:
space = nothing
p = pickup position for inserter
d = drop position for inserter

Each line must have the same length and end in a \n.
Flipping means it gets flipped horizontally. It also flips "left" and "right" in the name.
Multiple drop positions define multiple variants. Same for multiple pickup positions.
Variant without output loader means it removes all loaders going into output chests.
The direction of loaders is inferred by looking for input or output chests where on the opposite side there is
  also an adjacent belt, splitter or underground.
The direction of undergrounds is inferred through adjacent belts, splitters, loaders or connected undergrounds.
Having curved belts immediately after undergrounds is not supported.
Drop offset is automatically determined as "far", in relation to the inserter base position.
For simplicity on one loader is allowed to interact with a chest.
]]

---cSpell:disable
add_setup{
  name = "chest to chest, near straight pickup",
  setup = "\z
    ododododod\n\z
    ododododod\n\z
    ododb odod\n\z
    ododipodod\n\z
    ododododod\n\z
  ",
}
add_setup{
  name = "chest to chest, far semi diagonal pickup",
  setup = "\z
    ododododod\n\z
    ododododod\n\z
    ododb odod\n\z
    ododododod\n\z
    odipododod\n\z
  ",
}
add_setup{
  name = "chest to belt, straight, right to left",
  flipped_variant = true,
  setup = "\z
    o l <d. . \n\z
    ipipb ipip\n\z
    ipipip. . \n\z
    ipipip. . \n\z
  ",
}
add_setup{
  name = "chest to belt, curved, top to left",
  flipped_variant = true,
  setup = "\z
    . . v . . \n\z
    o l <d. . \n\z
    ipipb ipip\n\z
    ipipip. . \n\z
    ipipip. . \n\z
  ",
}
add_setup{
  name = "chest to splitter",
  flipped_variant = true,
  setup = "\z
    o l { . . \n\z
    o l {d. . \n\z
    ipipb ipip\n\z
    ipipip. . \n\z
    ipipip. . \n\z
  ",
}
add_setup{
  name = "pickup straight, taking from the top of right to left",
  flipped_variant = true,
  variant_without_output_loader = true,
  setup = "\z
    . ododod. \n\z
    . odb od. \n\z
    o l <pl i \n\z
  ",
}
add_setup{
  name = "pickup straight, taking from the right of going right",
  flipped_variant = true,
  setup = "\z
    . . ododod\n\z
    i l >pb od\n\z
    . . ododod\n\z
  ",
}
add_setup{
  name = "pickup curved, taking from the top of bottom to left",
  flipped_variant = true,
  variant_without_output_loader = true,
  setup = "\z
    . ododod\n\z
    . odb od\n\z
    o l <pod\n\z
    . . l . \n\z
    . . i . \n\z
  ",
}
add_setup{
  name = "pickup curved, taking from the top of left to bottom",
  flipped_variant = true,
  variant_without_output_loader = true,
  setup = "\z
    . ododod\n\z
    . odb od\n\z
    i l vpod\n\z
    . . l . \n\z
    . . o . \n\z
  ",
}
add_setup{
  name = "pickup underground, taking from the top of output going left",
  flipped_variant = true,
  variant_without_output_loader = true,
  setup = "\z
    . ododod. . . \n\z
    . odb od. . . \n\z
    o l ]pod[ l i \n\z
  ",
}
add_setup{
  name = "pickup underground, taking from the top of input going right",
  flipped_variant = true,
  variant_without_output_loader = true,
  setup = "\z
    . ododod. . . \n\z
    . odb od. . . \n\z
    i l ]pod[ l o \n\z
  ",
}
add_setup{
  name = "pickup underground, taking from the right of output going right",
  flipped_variant = true,
  setup = "\z
    . . . ododod\n\z
    i l ] [pb od\n\z
    . . . ododod\n\z
  ",
}
add_setup{
  name = "pickup underground, taking from the right of input going right",
  flipped_variant = true,
  setup = "\z
    . . ododod. . . \n\z
    i l ]pb od[ l o \n\z
    . . ododod. . . \n\z
  ",
}
add_setup{
  name = "pickup splitter, taking from the right of going left",
  flipped_variant = true,
  variant_without_output_loader = true,
  setup = "\z
    . . ododod\n\z
    o l {pb od\n\z
    . . { l i \n\z
  ",
}
add_setup{
  name = "pickup splitter, taking from the right of going right",
  flipped_variant = true,
  setup = "\z
    . . ododod\n\z
    i l }pb od\n\z
    . . } odod\n\z
  ",
}
add_setup{
  name = "pickup splitter, taking from the top of going right",
  flipped_variant = true,
  variant_without_output_loader = true,
  setup = "\z
    . ododod. \n\z
    . odb od. \n\z
    i l }pl o \n\z
    . . } . . \n\z
  ",
}
-- TODO: add a bunch of setups where it picks up from side loaded belts, both regular and underground.
---cSpell:enable

return {
  build_setups = build_setups,
}
