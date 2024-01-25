
local vec = require("__inserter-throughput-lib__.vector")
local params_util = require("__inserter-throughput-lib__.params_util")

local math_abs = math.abs
local math_ceil = math.ceil
local math_floor = math.floor
local math_min = math.min
local math_max = math.max

---@alias InserterThroughputTargetType
---| "inventory"
---| "ground"
---| "belt"
---| "linked-belt"
---| "underground"
---| "splitter"
---| "loader"

---@class InserterThroughputDefinition
---Functions setting fields in this table accept it being `nil`, they'll simply create the table. The estimate
---functions however require this table to be non `nil`.
---@field inserter InserterThroughputInserterDefinition
---Functions setting fields in this table accept it being `nil`, they'll simply create the table. The estimate
---functions however require this table to be non `nil`.
---@field pickup InserterThroughputPickupDefinition
---Functions setting fields in this table accept it being `nil`, they'll simply create the table. The estimate
---functions however require this table to be non `nil`.
---@field drop InserterThroughputDropDefinition

---@class InserterThroughputInserterDefinition
---@field extension_speed number @ Tiles per tick.
---@field rotation_speed number @ RealOrientation per tick.
---@field stack_size integer @ Must be at least 1.
---@field pickup_vector VectorXY @ Relative to inserter position.
---@field drop_vector VectorXY @ Relative to inserter position.
---@field chases_belt_items boolean @ https://lua-api.factorio.com/latest/prototypes/InserterPrototype.html#chases_belt_items
---Modulo (%) 1 of x and y of the inserter's position.\
---Only used and required if `drop.is_splitter` is true.
---@field inserter_position_in_tile VectorXY?

---@class InserterThroughputLoaderDefinitionBase
---`LuaEntity::loader_type`. `"input"`: items flow into the loader, `"output"`: items flow out of the loader.
---@field loader_type "input"|"output"?
---@field loader_belt_length number? @ `LuaEntityPrototype::belt_length`.
---How many tiles is the drop distance away from the actual belt of the loader? When dropping onto the tile of
---a 1x2 loader which is next to a container, this is `1`. When dropping onto the tile where items get put
---onto or taken from the belt, this is 0.
---@field loader_tile_distance_from_belt_start integer?

---@class InserterThroughputPickupDefinition : InserterThroughputLoaderDefinitionBase
---@field target_type InserterThroughputTargetType
---Tiles per tick of each item on the belt being picked up from.\
---Required for all belt connectables.
---@field belt_speed number?
---This is the direction items flow in. Always. Even for undergrounds and loaders, be it input or output.\
---Required for all belt connectables.
---@field belt_direction defines.direction?
---@field belt_shape "left"|"right"|"straight"? @ `LuaEntity::belt_shape`. Just used for `"belt"`s.
---`LuaEntity::linked_belt_type`. `"input"`: items go into the belt, `"output"`: items come out of the belt.
---@field linked_belt_type "input"|"output"?
---`LuaEntity::belt_to_ground_type`. `"input"`: goes underground, `"output"`: emerges from the ground.
---@field underground_type "input"|"output"?

---@class InserterThroughputDropDefinition : InserterThroughputLoaderDefinitionBase
---@field target_type InserterThroughputTargetType
---Tiles per tick of each item on the belt being dropped off to.\
---Required for all belt connectables.
---@field belt_speed number?
---Only used and required when dropping to `"splitter"`s or `"loader"`s.
---@field belt_direction defines.direction?

-- ---@field from_belt_is_backed_up boolean? @ Is the belt being picked up backed up or are items moving past?

---All prototypes an inserter may either be able to pick up from or drop off to. Includes rails, those are
---treated as potential inventories, since cargo wagons or locomotives may park there.
local interactive_prototypes = {
  ["ammo-turret"] = true,
  ["artillery-turret"] = true,
  ["artillery-wagon"] = true,
  ["assembling-machine"] = true,
  ["boiler"] = true,
  ["burner-generator"] = true,
  ["car"] = true,
  ["cargo-wagon"] = true,
  ["container"] = true,
  ["curved-rail"] = true,
  ["furnace"] = true,
  ["generator"] = true,
  ["infinity-container"] = true,
  ["inserter"] = true,
  ["lab"] = true,
  ["linked-belt"] = true,
  ["linked-container"] = true,
  ["loader-1x1"] = true,
  ["loader"] = true,
  ["locomotive"] = true,
  ["logistic-container"] = true,
  ["pump"] = true,
  ["radar"] = true,
  ["reactor"] = true,
  ["roboport"] = true,
  ["rocket-silo"] = true,
  ["splitter"] = true,
  ["straight-rail"] = true,
  ["transport-belt"] = true,
  ["turret"] = true,
  ["underground-belt"] = true,
}

---Out of all the prototypes an inserter can interact with, these are just the belt connectable ones.
local belt_connectable_target_type_lut = {
  ["linked-belt"] = "linked-belt",
  ["loader-1x1"] = "loader",
  ["loader"] = "loader",
  ["splitter"] = "splitter",
  ["transport-belt"] = "belt",
  ["underground-belt"] = "underground",
}

local can_always_pickup = {
  ["ammo-turret"] = true,
  ["artillery-turret"] = true,
  ["artillery-wagon"] = true,
  ["assembling-machine"] = true,
  ["beacon"] = true,
  ["burner-generator"] = true,
  ["car"] = true,
  ["cargo-wagon"] = true,
  ["container"] = true,
  ["curved-rail"] = true,
  ["furnace"] = true,
  ["infinity-container"] = true,
  ["lab"] = true,
  ["linked-container"] = true,
  ["logistic-container"] = true,
  ["reactor"] = true,
  ["roboport"] = true,
  ["rocket-silo"] = true,
  ["straight-rail"] = true,
}

---Apparently inserters can have burner energy sources _with burnt results_, but you can't pick it up from them.
local can_pickup_if_burner = {
  ["boiler"] = true,
  ["locomotive"] = true,
  ["mining-drill"] = true,
  ["pump"] = true,
  ["radar"] = true,
}

local can_always_drop = {
  ["ammo-turret"] = true,
  ["artillery-turret"] = true,
  ["artillery-wagon"] = true,
  ["assembling-machine"] = true,
  ["beacon"] = true,
  ["burner-generator"] = true,
  ["car"] = true,
  ["cargo-wagon"] = true,
  ["container"] = true,
  ["curved-rail"] = true,
  ["furnace"] = true,
  ["infinity-container"] = true,
  ["lab"] = true,
  ["linked-container"] = true,
  ["logistic-container"] = true,
  ["reactor"] = true,
  ["roboport"] = true,
  ["rocket-silo"] = true,
  ["straight-rail"] = true,
}

local can_drop_if_burner = {
  ["boiler"] = true,
  ["inserter"] = true,
  ["locomotive"] = true,
  ["mining-drill"] = true,
  ["pump"] = true,
  ["radar"] = true,
}

---@param entity LuaEntity
---@return string type
local function get_real_or_ghost_entity_type(entity)
  local entity_type = entity.type
  if entity_type == "entity-ghost" then
    return entity.ghost_type
  end
  return entity_type
end

---@param entity LuaEntity @ Must not be a ghost for a tile.
---@return LuaEntityPrototype
local function get_real_or_ghost_entity_prototype(entity)
  local entity_type = entity.type
  if entity_type == "entity-ghost" then
    return entity.ghost_prototype--[[@as LuaEntityPrototype]]
  end
  return entity.prototype
end

---@param entity LuaEntity? @ Handles both real and ghost entities.
---@return InserterThroughputTargetType
local function get_target_type(entity)
  if not entity then return "ground" end
  local entity_type = get_real_or_ghost_entity_type(entity)
  local belt_type = belt_connectable_target_type_lut[entity_type]
  if belt_type then return belt_type end
  if interactive_prototypes[entity_type] then return "inventory" end
  return "ground"
end

---@param target_type InserterThroughputTargetType
---@return boolean
local function is_belt_connectable_target_type(target_type)
  return target_type ~= "inventory" and target_type ~= "ground"
end

local get_interactive_entity
do
  -- Since all mutable fields get written to every time this is used, we can reuse the same tables every time.
  local left_top = {x = nil, y = nil}
  local right_bottom = {x = nil, y = nil}
  ---@type LuaSurface.find_entities_filtered_param
  local arg = {area = {left_top = left_top, right_bottom = right_bottom}}

  ---High means better.
  ---@alias CandidatePriorityITL
  ---| 4 @ belt connectable
  ---| 3 @ not belt connectable
  ---| 2 @ ghost belt connectable
  ---| 1 @ ghost not belt connectable
  ---| 0 @ not usable

  ---@param surface LuaSurface
  ---@param position VectorXY
  ---@param inserter LuaEntity?
  ---@param distance_from_tile_edge number
  ---@param get_target_priority fun(entity: LuaEntity, inserter: LuaEntity?): CandidatePriorityITL
  ---@return LuaEntity?
  function get_interactive_entity(surface, position, inserter, distance_from_tile_edge, get_target_priority)
    local left = math_floor(position.x)
    local top = math_floor(position.y)
    left_top.x = left + distance_from_tile_edge
    left_top.y = top + distance_from_tile_edge
    right_bottom.x = left + 1 - distance_from_tile_edge
    right_bottom.y = top + 1 - distance_from_tile_edge
    local best_candidate = nil
    local best_priority = 0
    for _, entity in pairs(surface.find_entities_filtered(arg)) do
      local candidate_priority = get_target_priority(entity, inserter)
      if candidate_priority > best_priority then
        best_priority = candidate_priority
        best_candidate = entity
      end
    end
    return best_candidate
  end
end

---@param entity LuaEntity
---@param inserter LuaEntity?
---@return CandidatePriorityITL
local function get_pickup_target_priority(entity, inserter)
  if entity == inserter then return 0 end
  if inserter and not entity.force.is_friend(inserter.force) then return 0 end
  local entity_type = entity.type
  if entity_type == "entity-ghost" then
    if (entity.ghost_prototype.flags or {})["no-automated-item-removal"] then return 0 end
    entity_type = entity.ghost_type
    return belt_connectable_target_type_lut[entity_type] and 2
      or can_always_pickup[entity_type] and 1
      -- This might not be the best way to check for a burner energy source however it works.
      or can_pickup_if_burner[entity_type] and entity.ghost_prototype.burner_prototype and 1
      or 0
  end
  if (entity.prototype.flags or {})["no-automated-item-removal"] then return 0 end
  return belt_connectable_target_type_lut[entity_type] and 4
    or entity_type == "straight-rail"
    or entity_type == "curved-rail"
    or entity.get_output_inventory() and 3
    or 0
end

---@param surface LuaSurface
---@param position VectorXY
---@param inserter LuaEntity? @ Handles both real and ghost inserters.
---@return LuaEntity?
local function find_pickup_target(surface, position, inserter)
  -- Magic number 25/256 (0.09765625), tested by teleporting a car 1/256 at a time.
  return get_interactive_entity(surface, position, inserter, 25/256, get_pickup_target_priority)
end

---@param entity LuaEntity
---@param inserter LuaEntity?
---@return CandidatePriorityITL
local function get_drop_target_priority(entity, inserter)
  if entity == inserter then return 0 end
  local entity_type = entity.type
  local prototype_key = "prototype"
  local offset = 2
  if entity_type == "entity-ghost" then
    offset = 0
    entity_type = entity.ghost_type
    prototype_key = "ghost_prototype"
  end
  if (entity[prototype_key].flags or {})["no-automated-item-insertion"] then return 0 end
  return belt_connectable_target_type_lut[entity_type] and (2 + offset)
    or can_always_drop[entity_type] and (1 + offset)
    -- This might not be the best way to check for a burner energy source however it works.
    or can_drop_if_burner[entity_type] and entity[prototype_key].burner_prototype and (1 + offset)
    or 0
end

---@param surface LuaSurface
---@param position VectorXY
---@param inserter LuaEntity? @ Handles both real and ghost inserters.
---@return LuaEntity?
local function find_drop_target(surface, position, inserter)
  -- Magic number 12/256 (0.046875), tested by teleporting a car 1/256 at a time.
  return get_interactive_entity(surface, position, inserter, 12/256, get_drop_target_priority)
end

---Instead of getting the `pickup_position` which is an absolute position, this gets the vector from the
---inserter to its `pickup_position`.
---@param inserter LuaEntity
---@param position VectorXY? @
---Prefetched position of the inserter, to reduce the amount of api calls and allocations. Only makes sense in
---code that runs _a lot_.
---@return VectorXY pickup_vector
local function get_pickup_vector(inserter, position)
  position = position or inserter.position
  return vec.sub(inserter.pickup_position, position)
end

---Instead of getting the `drop_position` which is an absolute position, this gets the vector from the
---inserter to its `drop_position`.
---@param inserter LuaEntity
---@param position VectorXY? @
---Prefetched position of the inserter, to reduce the amount of api calls and allocations. Only makes sense in
---code that runs _a lot_.
---@return VectorXY drop_vector
local function get_drop_vector(inserter, position)
  position = position or inserter.position
  return vec.sub(inserter.drop_position, position)
end

local north_or_south_lut = {}
do
  -- Based on testing it seems like directions "round down" when it comes to determining the position within a
  -- tile (using tile width and height). northeast gets treated as north, southeast gets treated as east, etc.
  -- And this code is written with support for 16 directions. At least in theory, who knows if the behavior is
  -- the same in 2.0.
  local directions_count = table_size(defines.direction)
  for _, direction in pairs(defines.direction) do
    if (direction % (directions_count / 2)) <= (directions_count / 4) then
      north_or_south_lut[direction] = true
    end
  end
end

---Pretends off grid inserters are placed on the grid, so they get zero special treatment.
---@param prototype LuaEntityPrototype
---@param direction defines.direction
---@return VectorXY position @ The position within a tile, so x and y are in the [0, 1) range.
local function get_default_inserter_position_in_tile(prototype, direction)
  local is_north_north = north_or_south_lut[direction]
  local width = is_north_north and prototype.tile_width or prototype.tile_height
  local height = is_north_north and prototype.tile_height or prototype.tile_width
  return {
    x = (width % 2) * 0.5, -- Even: 0. odd: 0.5.
    y = (height % 2) * 0.5, -- Even: 0. odd: 0.5.
  }
end

---@generic T : VectorXY
---@param position T
---@return T position_within_tile @ A new table.
local function get_position_in_tile(position) ---@cast position VectorXY
  return vec.mod_scalar(vec.copy(position), 1)
end

---@param prototype LuaEntityPrototype
---@return boolean
local function is_placeable_off_grid(prototype)
  local flags = prototype.flags -- Can be nil when all flags are unset.
  return flags and flags["placeable-off-grid"] or false
end

---This appears to match the game's snapping logic perfectly.
---@generic T : VectorXY
---@param prototype LuaEntityPrototype
---@param position T @ Gets modified.
---@param direction defines.direction
---@return T position @ The same table as the `position` parameter.
local function snap_build_position(prototype, position, direction) ---@cast position VectorXY
  if is_placeable_off_grid(prototype) then return position end
  local is_north_south = north_or_south_lut[direction]
  local width = is_north_south and prototype.tile_width or prototype.tile_height
  local height = is_north_south and prototype.tile_height or prototype.tile_width
  position.x = (width % 2) == 0
    and math.floor(position.x + 0.5) -- even
    or math.floor(position.x) + 0.5 -- odd
  position.y = (height % 2) == 0
    and math.floor(position.y + 0.5) -- even
    or math.floor(position.y) + 0.5 -- odd
  return position
end

---Rounds down to nearest valid number, because items on belts also use fixed point positions. Same resolution
---as MapPositions, so 1/256.
---@param belt_speed number @ Tiles per tick.
---@return number belt_speed
local function normalize_belt_speed(belt_speed)
  return belt_speed - (belt_speed % (1/256))
end

---@param tab table?
local function clear_table(tab)
  if not tab then return end
  local next = next
  local k = next(tab)
  while k do
    local next_k = next(tab, k)
    tab[k] = nil
    k = next_k
  end
end

---@param loader_data InserterThroughputLoaderDefinitionBase
---@param loader LuaEntity
---@param target_position VectorXY @ The pickup or drop position.
local function loaders_are_hard(loader_data, loader, target_position)
  loader_data.loader_type = loader.loader_type
  loader_data.loader_belt_length = get_real_or_ghost_entity_prototype(loader).belt_length
  loader_data.loader_tile_distance_from_belt_start = 0 -- TODO: how to evaluate this?
end

---@param def InserterThroughputDefinition
---@return InserterThroughputDropDefinition drop_data
local function get_drop_data(def)
  local drop = def.drop
  if drop then return drop end
  drop = {}
  def.drop = drop
  return drop
end

---@param def InserterThroughputDefinition
---@return InserterThroughputPickupDefinition pickup_data
local function get_pickup_data(def)
  local pickup = def.pickup
  if pickup then return pickup end
  pickup = {}
  def.pickup = pickup
  return pickup
end

---@param def InserterThroughputDefinition
---@return InserterThroughputInserterDefinition inserter_data
local function get_inserter_data(def)
  local inserter = def.inserter
  if inserter then return inserter end
  inserter = {}
  def.inserter = inserter
  return inserter
end

-- pickup from prototype

---Sets all fields in `def.pickup`, unrelated fields get set to `nil`.
---@param def InserterThroughputDefinition
local function pickup_from_inventory(def)
  clear_table(def.pickup)
  local pickup = get_pickup_data(def)
  pickup.target_type = "inventory"
end

---Sets all fields in `def.pickup`, unrelated fields get set to `nil`.
---@param def InserterThroughputDefinition
local function pickup_from_ground(def)
  clear_table(def.pickup)
  local pickup = get_pickup_data(def)
  pickup.target_type = "ground"
end

---Sets all fields in `def.pickup`, unrelated fields get set to `nil`.
---@param def InserterThroughputDefinition
---@param belt_speed number @ Tiles per tick that each item moves.
---@param belt_direction defines.direction
---@param belt_shape "left"|"right"|"straight" @ Example: If a belt is pointing at this belt from the left, set "left".
local function pickup_from_belt(def, belt_speed, belt_direction, belt_shape)
  clear_table(def.pickup)
  local pickup = get_pickup_data(def)
  pickup.target_type = "belt"
  pickup.belt_speed = belt_speed
  pickup.belt_direction = belt_direction
  pickup.belt_shape = belt_shape
end

---Sets all fields in `def.pickup`, unrelated fields get set to `nil`.
---@param def InserterThroughputDefinition
---@param belt_speed number @ Tiles per tick that each item moves.
---@param belt_direction defines.direction
---@param linked_belt_type "input"|"output" @ `LuaEntity::linked_belt_type`. `"input"`: items go into the belt, `"output"`: items come out of the belt.
local function pickup_from_linked_belt(def, belt_speed, belt_direction, linked_belt_type)
  clear_table(def.pickup)
  local pickup = get_pickup_data(def)
  pickup.target_type = "linked-belt"
  pickup.belt_speed = belt_speed
  pickup.belt_direction = belt_direction
end

---Sets all fields in `def.pickup`, unrelated fields get set to `nil`.
---@param def InserterThroughputDefinition
---@param belt_speed number @ Tiles per tick that each item moves.
---@param belt_direction defines.direction
---@param underground_type "input"|"output" @ `LuaEntity::belt_to_ground_type`. `"input"`: goes underground, `"output"`: emerges from the ground.
local function pickup_from_underground(def, belt_speed, belt_direction, underground_type)
  clear_table(def.pickup)
  local pickup = get_pickup_data(def)
  pickup.target_type = "underground"
  pickup.belt_speed = belt_speed
  pickup.belt_direction = belt_direction
  pickup.underground_type = underground_type
end

---Sets all fields in `def.pickup`, unrelated fields get set to `nil`.
---@param def InserterThroughputDefinition
---@param belt_speed number @ Tiles per tick that each item moves.
---@param belt_direction defines.direction
local function pickup_from_splitter(def, belt_speed, belt_direction)
  clear_table(def.pickup)
  local pickup = get_pickup_data(def)
  pickup.target_type = "splitter"
  pickup.belt_speed = belt_speed
  pickup.belt_direction = belt_direction
end

---Sets all fields in `def.pickup`, unrelated fields get set to `nil`.
---@param def InserterThroughputDefinition
---@param belt_speed number @ Tiles per tick that each item moves.
---@param belt_direction defines.direction
---@param loader_type "input"|"output" @ `LuaEntity::loader_type`. `"input"`: items flow into the loader, `"output"`: items flow out of the loader.
---@param loader_belt_length number @ `LuaEntityPrototype::belt_length`.
---@param loader_tile_distance_from_belt_start integer @
---How many tiles is the drop distance away from the actual belt of the loader? When dropping onto the tile of
---a 1x2 loader which is next to a container, this is `1`. When dropping onto the tile where items get put
---onto or taken from the belt, this is 0.
local function pickup_from_loader(
  def,
  belt_speed,
  belt_direction,
  loader_type,
  loader_belt_length,
  loader_tile_distance_from_belt_start
)
  clear_table(def.pickup)
  local pickup = get_pickup_data(def)
  pickup.target_type = "loader"
  pickup.belt_speed = belt_speed
  pickup.belt_direction = belt_direction
  pickup.loader_type = loader_type
  pickup.loader_belt_length = loader_belt_length
  pickup.loader_tile_distance_from_belt_start = loader_tile_distance_from_belt_start
end

-- pickup from real world

---Sets all fields in `def.pickup`, unrelated fields get set to `nil`.
---@param def InserterThroughputDefinition
---@param entity LuaEntity?
---@param pickup_position VectorXY? @ Required if `entity` is any loader.
local function pickup_from_entity(def, entity, pickup_position)
  clear_table(def.pickup)
  local pickup = get_pickup_data(def)
  local target_type = get_target_type(entity)
  pickup.target_type = target_type
  if is_belt_connectable_target_type(target_type) then ---@cast entity -nil
    pickup.belt_speed = get_real_or_ghost_entity_prototype(entity).belt_speed
    pickup.belt_direction = entity.direction
  end
  if target_type == "belt" then ---@cast entity -nil
    pickup.belt_shape = entity.belt_shape
  elseif target_type == "linked-belt" then ---@cast entity -nil
    pickup.linked_belt_type = entity.linked_belt_type
  elseif target_type == "underground" then ---@cast entity -nil
    pickup.underground_type = entity.belt_to_ground_type
  elseif target_type == "loader" then ---@cast entity -nil
    if not pickup_position then error("'pickup_position' is required to set pickup data for loaders.") end
    loaders_are_hard(pickup, entity, pickup_position)
  end
end

---Sets all fields in `def.pickup`, unrelated fields get set to `nil`.
---@param def InserterThroughputDefinition
---@param surface LuaSurface
---@param position VectorXY @ A MapPosition on the given surface.
---@param inserter LuaEntity? @ Used to prevent an inserter from picking up from itself, provide it if applicable.
local function pickup_from_position(def, surface, position, inserter)
  pickup_from_entity(def, find_pickup_target(surface, position, inserter), position)
end

---Sets all fields in `def.pickup`, unrelated fields get set to `nil`.\
---Also sets `def.inserter.pickup_vector` using `position` and `inserter_position`.
---@param def InserterThroughputDefinition
---@param surface LuaSurface
---@param position VectorXY @ A MapPosition on the given surface.
---@param inserter LuaEntity? @ Used to prevent an inserter from picking up from itself, provide it if applicable.
---@param inserter_position VectorXY? @ Default: `inserter.position`. Required if `inserter` is `nil`.
local function pickup_from_position_and_set_pickup_vector(def, surface, position, inserter, inserter_position)
  pickup_from_position(def, surface, position, inserter)
  inserter_position = inserter_position
    or assert(inserter, "'inserter' and 'inserter_position' must not both be 'nil'.").position
  local inserter_data = get_inserter_data(def)
  inserter_data.pickup_vector = vec.sub(vec.copy(position), inserter_position)
end

---Sets all fields in `def.pickup`, unrelated fields get set to `nil`.
---@param def InserterThroughputDefinition
---@param inserter LuaEntity @ Ghost or real.
local function pickup_from_pickup_target_of_inserter(def, inserter)
  local pickup_target = inserter.pickup_target
  if pickup_target then
    pickup_from_entity(def, pickup_target, inserter.pickup_position)
  else
    pickup_from_position(def, inserter.surface, inserter.pickup_position)
  end
end

---Sets all fields in `def.pickup`, unrelated fields get set to `nil`.\
---Also sets `def.inserter.pickup_vector` using `inserter.pickup_position` and `inserter.position`.
---@param def InserterThroughputDefinition
---@param inserter LuaEntity @ Ghost or real.
local function pickup_from_pickup_target_of_inserter_and_set_pickup_vector(def, inserter)
  pickup_from_pickup_target_of_inserter(def, inserter)
  local inserter_data = get_inserter_data(def)
  inserter_data.pickup_vector = vec.sub(inserter.pickup_position, inserter.position)
end

-- drop to prototype

---Sets all fields in `def.drop`, unrelated fields get set to `nil`.
---@param def InserterThroughputDefinition
local function drop_to_inventory(def)
  clear_table(def.drop)
  local drop = get_drop_data(def)
  drop.target_type = "inventory"
end

---Sets all fields in `def.drop`, unrelated fields get set to `nil`.
---@param def InserterThroughputDefinition
local function drop_to_ground(def)
  clear_table(def.drop)
  local drop = get_drop_data(def)
  drop.target_type = "ground"
end

---Sets all fields in `def.drop`, unrelated fields get set to `nil`.
---@param def InserterThroughputDefinition
---@param belt_speed number @ Tiles per tick that each item moves.
local function drop_to_belt(def, belt_speed)
  clear_table(def.drop)
  local drop = get_drop_data(def)
  drop.target_type = "belt"
  drop.belt_speed = belt_speed
end

---Sets all fields in `def.drop`, unrelated fields get set to `nil`.
---@param def InserterThroughputDefinition
---@param belt_speed number @ Tiles per tick that each item moves.
local function drop_to_linked_belt(def, belt_speed)
  clear_table(def.drop)
  local drop = get_drop_data(def)
  drop.target_type = "linked-belt"
  drop.belt_speed = belt_speed
end

---Sets all fields in `def.drop`, unrelated fields get set to `nil`.
---@param def InserterThroughputDefinition
---@param belt_speed number @ Tiles per tick that each item moves.
local function drop_to_underground(def, belt_speed)
  local drop = get_drop_data(def)
  drop.target_type = "underground"
  drop.belt_speed = belt_speed
end

---Sets all fields in `def.drop`, unrelated fields get set to `nil`.
---@param def InserterThroughputDefinition
---@param belt_speed number @ Tiles per tick that each item moves.
---@param belt_direction defines.direction
local function drop_to_splitter(def, belt_speed, belt_direction)
  clear_table(def.drop)
  local drop = get_drop_data(def)
  drop.target_type = "splitter"
  drop.belt_speed = belt_speed
  drop.belt_direction = belt_direction
end

---Sets all fields in `def.drop`, unrelated fields get set to `nil`.
---@param def InserterThroughputDefinition
---@param belt_speed number @ Tiles per tick that each item moves.
---@param belt_direction defines.direction
---@param loader_type "input"|"output" @ `LuaEntity::loader_type`. `"input"`: items flow into the loader, `"output"`: items flow out of the loader.
---@param loader_belt_length number @ `LuaEntityPrototype::belt_length`.
---@param loader_tile_distance_from_belt_start integer @
---How many tiles is the drop distance away from the actual belt of the loader? When dropping onto the tile of
---a 1x2 loader which is next to a container, this is `1`. When dropping onto the tile where items get put
---onto or taken from the belt, this is 0.
local function drop_to_loader(
  def,
  belt_speed,
  belt_direction,
  loader_type,
  loader_belt_length,
  loader_tile_distance_from_belt_start
)
  clear_table(def.drop)
  local drop = get_drop_data(def)
  drop.target_type = "loader"
  drop.belt_speed = belt_speed
  drop.belt_direction = belt_direction
  drop.loader_type = loader_type
  drop.loader_belt_length = loader_belt_length
  drop.loader_tile_distance_from_belt_start = loader_tile_distance_from_belt_start
end

-- drop to real world

---Sets all fields in `def.drop`, unrelated fields get set to `nil`.
---@param def InserterThroughputDefinition
---@param entity LuaEntity?
---@param drop_position VectorXY? @ Required if `entity` is any loader.
local function drop_to_entity(def, entity, drop_position)
  clear_table(def.drop)
  local drop = get_drop_data(def)
  local target_type = get_target_type(entity)
  drop.target_type = target_type
  if is_belt_connectable_target_type(target_type) then ---@cast entity -nil
    drop.belt_speed = get_real_or_ghost_entity_prototype(entity).belt_speed
  end
  if target_type == "splitter" then ---@cast entity -nil
    drop.belt_direction = entity.direction
  elseif target_type == "loader" then ---@cast entity -nil
    drop.belt_direction = entity.direction
    if not drop_position then error("'drop_position' is required to set drop data for loaders.") end
    loaders_are_hard(drop, entity, drop_position)
  end
end

---Sets all fields in `def.drop`, unrelated fields get set to `nil`.
---@param def InserterThroughputDefinition
---@param surface LuaSurface
---@param position VectorXY @ A MapPosition on the given surface.
---@param inserter LuaEntity? @ Used to prevent an inserter from dropping to itself, provide it if applicable.
local function drop_to_position(def, surface, position, inserter)
  drop_to_entity(def, find_drop_target(surface, position, inserter), position)
end

---Sets all fields in `def.drop`, unrelated fields get set to `nil`.\
---Also sets `def.inserter.drop_vector` using `position` and `inserter_position`.
---@param def InserterThroughputDefinition
---@param surface LuaSurface
---@param position VectorXY @ A MapPosition on the given surface.
---@param inserter LuaEntity? @ Used to prevent an inserter from dropping to itself, provide it if applicable.
---@param inserter_position VectorXY? @ Default: `inserter.position`. Required if `inserter` is `nil`.
local function drop_to_position_and_set_drop_vector(def, surface, position, inserter, inserter_position)
  drop_to_position(def, surface, position, inserter)
  inserter_position = inserter_position
    or assert(inserter, "'inserter' and 'inserter_position' must not both be 'nil'.").position
  local inserter_data = get_inserter_data(def)
  inserter_data.drop_vector = vec.sub(vec.copy(position), inserter_position)
end

---Sets all fields in `def.drop`, unrelated fields get set to `nil`.
---@param def InserterThroughputDefinition
---@param inserter LuaEntity @ Ghost or real.
local function drop_to_drop_target_of_inserter(def, inserter)
  local drop_target = inserter.drop_target
  if drop_target then
    drop_to_entity(def, drop_target, inserter.drop_position)
  else
    drop_to_position(def, inserter.surface, inserter.drop_position)
  end
end

---Sets all fields in `def.drop`, unrelated fields get set to `nil`.\
---Also sets `def.inserter.drop_vector` using `inserter.drop_position` and `inserter.position`.
---@param def InserterThroughputDefinition
---@param inserter LuaEntity @ Ghost or real.
local function drop_to_drop_target_of_inserter_and_set_drop_vector(def, inserter)
  drop_to_drop_target_of_inserter(def, inserter)
  local inserter_data = get_inserter_data(def)
  inserter_data.drop_vector = vec.sub(inserter.drop_position, inserter.position)
end

-- inserter data

---Sets all fields in `def.inserter`.
---@param inserter_data InserterThroughputInserterDefinition
---@param inserter_prototype LuaEntityPrototype
---@param direction defines.direction
---@param position VectorXY? @ Default: `get_default_inserter_position_in_tile(inserter_prototype, direction)`.
---@param stack_size integer
local function inserter_data_based_on_prototype_except_for_vectors(inserter_data, inserter_prototype, direction, position, stack_size)
  inserter_data.rotation_speed = inserter_prototype.inserter_rotation_speed
  inserter_data.extension_speed = inserter_prototype.inserter_extension_speed
  -- inserter_data.stack_size = inserter_prototype.inserter_stack_size_bonus + 1 -- TODO: which force to use?
  inserter_data.stack_size = stack_size
  inserter_data.chases_belt_items = inserter_prototype.inserter_chases_belt_items
  position = position -- `snap_build_position` checks if it is placeable off grid.
    and vec.mod_scalar(snap_build_position(inserter_prototype, vec.copy(position), direction), 1)
    or get_default_inserter_position_in_tile(inserter_prototype, direction)
  inserter_data.inserter_position_in_tile = position
end

---Sets all fields in `def.inserter`.
---@param def InserterThroughputDefinition
---@param inserter_prototype LuaEntityPrototype
---@param direction defines.direction
---@param position VectorXY? @ Default: `get_default_inserter_position_in_tile(inserter_prototype, direction)`.
---@param stack_size integer
local function inserter_data_based_on_prototype(def, inserter_prototype, direction, position, stack_size)
  local inserter_data = get_inserter_data(def)
  inserter_data_based_on_prototype_except_for_vectors(inserter_data, inserter_prototype, direction, position, stack_size)
  inserter_data.pickup_vector = vec.rotate_by_direction(inserter_prototype.inserter_pickup_position, direction)--[[@as MapPosition]]
  inserter_data.drop_vector = vec.rotate_by_direction(inserter_prototype.inserter_drop_position, direction)--[[@as MapPosition]]
end

---Sets all fields in `def.inserter`.
---@param def InserterThroughputDefinition
---@param inserter LuaEntity
local function inserter_data_based_on_entity(def, inserter)
  local inserter_data = get_inserter_data(def)
  local position = inserter.position
  inserter_data_based_on_prototype_except_for_vectors(
    inserter_data,
    get_real_or_ghost_entity_prototype(inserter),
    inserter.direction,
    position,
    -- TODO: I remember checking this on ghosts, but it probably also takes 1 tick to update after being placed
    inserter.inserter_target_pickup_count
  )
  inserter_data.pickup_vector = get_pickup_vector(inserter, position)
  inserter_data.drop_vector = get_drop_vector(inserter, position)
end

-- definitions

---Creates a new definition with `def.inserter`, `def.pickup` and `def.drop` all being empty tables.
---@return InserterThroughputDefinition
local function make_empty_definition()
  ---@type InserterThroughputDefinition
  local def = {
    inserter = {},
    pickup = {},
    drop = {},
  }
  return def
end

---Sets all fields in `def.inserter`, `def.pickup` and `def.drop`. In other words: everything.
---@param inserter LuaEntity
---@param def_to_reuse InserterThroughputDefinition?
---@return InserterThroughputDefinition
local function make_full_definition_for_inserter(inserter, def_to_reuse)
  local def = def_to_reuse or make_empty_definition()
  inserter_data_based_on_entity(def, inserter)
  pickup_from_pickup_target_of_inserter(def, inserter)
  drop_to_drop_target_of_inserter(def, inserter)
  return def
end

-- calculations and estimations

local extension_distance_offset ---@type number
local rotation_osset_from_tile_center ---@type number
local belt_speed_multiplier ---@type number

---@param params ParamsITL
local function update_params(params)
  extension_distance_offset = params.extension_distance_offset
  rotation_osset_from_tile_center = params.rotation_osset_from_tile_center
  belt_speed_multiplier = params.belt_speed_multiplier
end

params_util.on_params_set(update_params)
update_params(params_util.get_params())

---@param extension_speed number @ Tiles per tick.
---@param from_length number @ Tiles.
---@param to_length number @ Tiles.
---@param does_chase boolean @ Is this inserter picking up from a belt?
---@param from_is_belt boolean
---@return integer
local function calculate_extension_ticks(extension_speed, from_length, to_length, does_chase, from_is_belt)
  local diff = math_abs(from_length - to_length)
  if not does_chase then
    return math_ceil(diff / extension_speed)
  end
  return math_max(0, (diff + (from_is_belt and extension_distance_offset or 0)) / extension_speed)
end

---@param rotation_speed number @ RealOrientation per tick.
---@param from_vector VectorXY @ Must be normalized.
---@param to_vector VectorXY @ Must be normalized.
---@param does_chase boolean @ Is this inserter picking up from a belt?
---@param from_length number @ Length of the from_vector, before normalization.
---@param from_is_belt boolean
---@return integer
local function calculate_rotation_ticks(rotation_speed, from_vector, to_vector, does_chase, from_length, from_is_belt)
  local from_orientation = vec.get_orientation(from_vector)
  local to_orientation = vec.get_orientation(to_vector)

  local diff = math_abs(from_orientation - to_orientation)
  if diff > 0.5 then
    if from_orientation < to_orientation then
      from_orientation = from_orientation + 1
    else
      to_orientation = to_orientation + 1
    end
    diff = math_abs(to_orientation - from_orientation)
  end
  if not does_chase then
    return math_ceil(diff / rotation_speed)
  end

  local orientation_for_half_a_tile = from_is_belt
    and vec.get_orientation{x = rotation_osset_from_tile_center % 0.51, y = -from_length}
    or 0
  return math_max(0, (diff - orientation_for_half_a_tile) / rotation_speed)
end

---The game has some inconsistencies when the drop position is shifted just 1/256 or 2/256 in terms of when it
---drops to the input vs output side of the splitter. There's no understandable pattern to it, so this logic
---works on the assumption that those inconsistencies do not exist. Which means that there's a clean straight
---line for when a drop position is on the input vs output side, which is the exact center of the tile,
---inclusive. Inclusive being the important part, to make flipping consistent.
---@param inserter InserterThroughputInserterDefinition
---@param drop InserterThroughputDropDefinition
---@param to_vector VectorXY
---@return number?
local function is_drop_to_input_of_splitter(inserter, drop, to_vector)
  local inserter_position_in_tile = inserter.inserter_position_in_tile
  if not inserter_position_in_tile or not drop.belt_direction then
    error("When 'drop.target_type == \"splitter\"', 'inserter.inserter_position_in_tile' and 'drop.belt_direction' must both be set.")
  end
  inserter_position_in_tile = vec.snap_to_map(vec.copy(inserter_position_in_tile))
  local position_in_drop_tile = vec.mod_scalar(vec.add(inserter_position_in_tile, to_vector), 1)
  local drop_vector_from_tile_center = vec.sub_scalar(position_in_drop_tile, 0.5)
  local distance_from_center = vec.rotate_by_direction(drop_vector_from_tile_center, -drop.belt_direction).y
  return distance_from_center >= 0 and distance_from_center or nil
end

---@param inserter InserterThroughputInserterDefinition
---@param drop InserterThroughputDropDefinition
---@param drop_belt_speed number
---@param to_vector VectorXY
---@return integer ticks
---@return boolean? drops_to_input_of_splitter
local function calculate_extra_drop_ticks(inserter, drop, drop_belt_speed, to_vector)
  if drop.target_type == "inventory" then
    return 0
  end
  if drop.target_type == "ground" then
    return inserter.stack_size - 1
  end
  -- Is belt.
  local stack_size = inserter.stack_size
  local distance_on_input = drop.target_type == "splitter" and is_drop_to_input_of_splitter(inserter, drop, to_vector)
  if stack_size == 1 then return 0, not not distance_on_input end
  if stack_size == 2 then return 1, not not distance_on_input end

  local ticks_per_item = 0.25 / drop_belt_speed
  if distance_on_input then
    -- TODO: Return max possible drop speed instead of just a bool.
    -- TODO: Actually test how accurate this is with inserters not dropping exactly in the middle of splitters.
    -- It probably is very wrong, like I think stack_size -3 and -4 would need to change to -2 and use ticks_until_split somehow.
    -- TODO: This is currently only accurate for itl-express-transport-belt and faster. For the slower ones the estimate is too slow by ~0.3.

    local ticks_until_split = math_max(distance_on_input / drop_belt_speed)
    if ticks_until_split < ticks_per_item then
      local ticks_between_left_and_right = ticks_until_split + 1
      ticks_per_item = ticks_until_split + ticks_per_item / 2
      if (stack_size % 2) == 0 then -- even
        return math_max(stack_size - 1, math_floor(ticks_per_item * (stack_size - 3))), true
      else -- odd
        return math_max(stack_size - 1, math_floor(ticks_per_item * (stack_size - 4)) + ticks_between_left_and_right), true
      end
    end
  end
  return math_max(stack_size - 1, math_floor(ticks_per_item * (stack_size - 2)))
end

local item_flow_vector_lut = {
  [defines.direction.north] = {
    ["straight"] = {x = 0, y = -1},
    ["left"] = vec.normalize{x = -1, y = -1},
    ["right"] = vec.normalize{x = 1, y = -1},
  },
  [defines.direction.east] = {
    ["straight"] = {x = 1, y = 0},
    ["left"] = vec.normalize{x = 1, y = -1},
    ["right"] = vec.normalize{x = 1, y = 1},
  },
  [defines.direction.south] = {
    ["straight"] = {x = 0, y = 1},
    ["left"] = vec.normalize{x = 1, y = 1},
    ["right"] = vec.normalize{x = -1, y = 1},
  },
  [defines.direction.west] = {
    ["straight"] = {x = -1, y = 0},
    ["left"] = vec.normalize{x = -1, y = 1},
    ["right"] = vec.normalize{x = -1, y = -1},
  },
}

---This logic is especially relevant for inserters with large stack sizes. It is different from the belt speed
---cap performed at the very end, because imagine this: huge stack size, fairly fast inserter, picking up and
---dropping to slow belts. In this case it could think it can pick up items faster than the belt can provide
---them, and the cap at the very end won't catch that because the inserter is also spending a lot of time
---dropping items to the slow belt. It is this logic that has to catch it.
---@param inserter InserterThroughputInserterDefinition
---@param pickup_belt_speed number
---@param extra_pickup_ticks number
---@return number extra_pickup_ticks
local function cap_extra_pickup_ticks_to_belt_speed(inserter, pickup_belt_speed, extra_pickup_ticks)
  -- Magic 8. It's simply the amount of items that are already on the belt, before more items have to move in.
  -- If the inserter is so fast that there wouldn't actually be 8 items on the belt yet, there's the final
  -- cap that will handle that case.
  local item_count = inserter.stack_size - 8
  if item_count < 0 then return extra_pickup_ticks end -- Not required, just short circuit.
  local ticks_per_item = (0.25 / pickup_belt_speed) / 2
  return math_max(math_ceil(item_count * ticks_per_item), extra_pickup_ticks)
end

---@param inserter InserterThroughputInserterDefinition
---@param pickup InserterThroughputPickupDefinition
---@param pickup_belt_speed number
---@param pickup_vector VectorXY
---@param pickup_length number @ Length of the `pickup_vector`.
---@return number ticks
local function estimate_extra_pickup_ticks(inserter, pickup, pickup_belt_speed, pickup_vector, pickup_length)
  if pickup.target_type == "inventory" then
    return 0
  end
  if pickup.target_type == "ground" then
    return inserter.stack_size - 1
  end
  -- Is belt.
  if not inserter.chases_belt_items then
    -- TODO: verify that it does indeed take 1 tick per item.
    -- TODO: also take belt speed into account, if the stack size is > 8 then it would pick up all items and
    -- have to wait for more items.
    -- TODO: when the above is tested, return false in `is_estimate` when `def.chases_belt_items` is false.
    return inserter.stack_size - 1
  end

  local item_flow_vector = item_flow_vector_lut[pickup.belt_direction][pickup.belt_shape]
  -- Since item_flow_vector has a length of 1, extension_influence and rotation influence are values 0 to 1.
  local extension_influence = math_abs(vec.dot_product(item_flow_vector, pickup_vector))
  local rotation_influence = 1 - extension_influence
  local influence_bleed = vec.get_orientation{x = 0.25, y = -pickup_length} * 4

  local distance_due_to_belt_movement = pickup_belt_speed * belt_speed_multiplier

  local hand_speed = extension_influence * inserter.extension_speed
    + extension_influence * influence_bleed * inserter.rotation_speed
    + rotation_influence * inserter.rotation_speed
    + rotation_influence * influence_bleed * inserter.extension_speed
  hand_speed = hand_speed + distance_due_to_belt_movement

  local ticks_per_item = 0.25 / hand_speed -- 0.25 == distance per item
  return cap_extra_pickup_ticks_to_belt_speed(
    inserter,
    pickup_belt_speed,
    math_max(inserter.stack_size, ticks_per_item * inserter.stack_size)
  )
end

---@param items_per_second number
---@param pickup InserterThroughputPickupDefinition
---@param pickup_belt_speed number
---@param drop InserterThroughputDropDefinition
---@param drop_belt_speed number
---@param drops_to_input_of_splitter boolean?
---@return number items_per_second
local function cap_to_belt_speed(
  items_per_second,
  pickup,
  pickup_belt_speed,
  drop,
  drop_belt_speed,
  drops_to_input_of_splitter
)
  if is_belt_connectable_target_type(drop.target_type) then
    local max_per_second = 60 / (0.25 / drop_belt_speed) * (drops_to_input_of_splitter and 2 or 1)
    items_per_second = math_min(max_per_second, items_per_second)
  end
  if is_belt_connectable_target_type(pickup.target_type) then
    items_per_second = math_min(60 / (0.125 / pickup_belt_speed), items_per_second)
  end
  return items_per_second
end

---Snaps belt speeds and vectors to valid 1/256ths, because they are all related to MapPositions. Does not
---modify the given definition however.
---@param def InserterThroughputDefinition
---@return number items_per_second
local function estimate_inserter_speed(def)
  local inserter = def.inserter
  local pickup = def.pickup
  local drop = def.drop
  local pickup_belt_speed = pickup.belt_speed
  pickup_belt_speed = pickup_belt_speed and normalize_belt_speed(pickup_belt_speed) ---@cast pickup_belt_speed -nil
  local drop_belt_speed = drop.belt_speed
  drop_belt_speed = drop_belt_speed and normalize_belt_speed(drop_belt_speed) ---@cast drop_belt_speed -nil
  local pickup_vector = vec.snap_to_map(vec.copy(inserter.pickup_vector))
  local drop_vector = vec.snap_to_map(vec.copy(inserter.drop_vector))
  local pickup_length = vec.get_length(pickup_vector)
  local drop_length = vec.get_length(drop_vector)
  local pickup_is_belt = is_belt_connectable_target_type(pickup.target_type)
  local does_chase = inserter.chases_belt_items and pickup_is_belt
  local extension_ticks = calculate_extension_ticks(
    inserter.extension_speed,
    pickup_length,
    drop_length,
    does_chase,
    pickup_is_belt
  )
  local extra_drop_ticks, drops_to_input_of_splitter = calculate_extra_drop_ticks(
    inserter,
    drop,
    drop_belt_speed,
    drop_vector
  )
  local extra_pickup_ticks = estimate_extra_pickup_ticks(
    inserter,
    pickup,
    pickup_belt_speed,
    pickup_vector,
    pickup_length
  )
  -- Normalize just before `calculate_rotation_ticks` because it is the only func that needs them normalized.
  vec.normalize(pickup_vector, pickup_length)
  vec.normalize(drop_vector, drop_length)
  local rotation_ticks = calculate_rotation_ticks(
    inserter.rotation_speed,
    pickup_vector,
    drop_vector,
    does_chase,
    pickup_length,
    pickup_is_belt
  )
  local ticks_per_swing = math_max(extension_ticks, rotation_ticks, 1)
  local total_ticks = (ticks_per_swing * 2) + extra_drop_ticks + extra_pickup_ticks
  return cap_to_belt_speed(
    60 / total_ticks * inserter.stack_size,
    pickup,
    pickup_belt_speed,
    drop,
    drop_belt_speed,
    drops_to_input_of_splitter
  )
end

---Whether or not the given definition can be used accurate throughput calculation or if it is just an estimate.
---@param def InserterThroughputDefinition
---@return boolean
local function is_estimate(def)
  -- TODO: when addressing the TODOs for splitters in calculate_extra_drop_ticks, remove `drop.target_type == "splitter"` from here.
  return is_belt_connectable_target_type(def.pickup.target_type) or def.drop.target_type == "splitter"
end

return {
  get_target_type = get_target_type,
  is_belt_connectable_target_type = is_belt_connectable_target_type,
  get_pickup_vector = get_pickup_vector,
  get_drop_vector = get_drop_vector,
  get_default_inserter_position_in_tile = get_default_inserter_position_in_tile,
  get_position_in_tile = get_position_in_tile,
  is_placeable_off_grid = is_placeable_off_grid,
  snap_build_position = snap_build_position,
  normalize_belt_speed = normalize_belt_speed,
  pickup_from_inventory = pickup_from_inventory,
  pickup_from_ground = pickup_from_ground,
  pickup_from_belt = pickup_from_belt,
  pickup_from_linked_belt = pickup_from_linked_belt,
  pickup_from_underground = pickup_from_underground,
  pickup_from_splitter = pickup_from_splitter,
  pickup_from_loader = pickup_from_loader,
  pickup_from_entity = pickup_from_entity,
  pickup_from_position = pickup_from_position,
  pickup_from_position_and_set_pickup_vector = pickup_from_position_and_set_pickup_vector,
  pickup_from_pickup_target_of_inserter = pickup_from_pickup_target_of_inserter,
  pickup_from_pickup_target_of_inserter_and_set_pickup_vector = pickup_from_pickup_target_of_inserter_and_set_pickup_vector,
  drop_to_inventory = drop_to_inventory,
  drop_to_ground = drop_to_ground,
  drop_to_belt = drop_to_belt,
  drop_to_linked_belt = drop_to_linked_belt,
  drop_to_underground = drop_to_underground,
  drop_to_splitter = drop_to_splitter,
  drop_to_loader = drop_to_loader,
  drop_to_entity = drop_to_entity,
  drop_to_position = drop_to_position,
  drop_to_position_and_set_drop_vector = drop_to_position_and_set_drop_vector,
  drop_to_drop_target_of_inserter = drop_to_drop_target_of_inserter,
  drop_to_drop_target_of_inserter_and_set_drop_vector = drop_to_drop_target_of_inserter_and_set_drop_vector,
  inserter_data_based_on_prototype = inserter_data_based_on_prototype,
  inserter_data_based_on_entity = inserter_data_based_on_entity,
  make_empty_definition = make_empty_definition,
  make_full_definition_for_inserter = make_full_definition_for_inserter,
  estimate_inserter_speed = estimate_inserter_speed,
  is_estimate = is_estimate,
}
