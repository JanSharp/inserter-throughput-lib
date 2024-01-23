
local vec = require("__inserter-throughput-lib__.vector")
local params_util = require("__inserter-throughput-lib__.params_util")

local math_abs = math.abs
local math_ceil = math.ceil
local math_floor = math.floor
local math_min = math.min
local math_max = math.max

---@class InserterThroughputDefinition
---@field inserter InserterThroughputInserterDefinition
---@field pickup InserterThroughputPickupDefinition
---@field drop InserterThroughputDropDefinition

---@class InserterThroughputInserterDefinition
---@field extension_speed number @ Tiles per tick.
---@field rotation_speed number @ RealOrientation per tick.
---@field stack_size integer @ Must be at least 1.
---@field chases_belt_items boolean @ https://lua-api.factorio.com/latest/prototypes/InserterPrototype.html#chases_belt_items
---Modulo (%) 1 of x and y of the inserter's position.\
---Only used and required if `to_is_splitter` is true.
---@field inserter_position_in_tile VectorXY?

---@class InserterThroughputPickupDefinition
---@field target_type "inventory"|"belt"|"ground"
---@field vector VectorXY @ Relative to inserter position.
---@field belt_speed number? @ Tiles per tick of each item on the belt being picked up from.
---@field belt_direction defines.direction?
---@field belt_shape "left"|"right"|"straight"

---@class InserterThroughputDropDefinition
---@field target_type "inventory"|"belt"|"ground"
---@field vector VectorXY @ Relative to inserter position.
---@field belt_speed number? @ Tiles per tick of each item on the belt being dropped off to.
---@field belt_direction defines.direction? @ Only used and required if `to_is_splitter` is true.
---@field is_splitter boolean? @ Is the belt being dropped off to the input side of a splitter?

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
local belt_connectable = {
  ["linked-belt"] = true,
  ["loader-1x1"] = true,
  ["loader"] = true,
  ["splitter"] = true,
  ["transport-belt"] = true,
  ["underground-belt"] = true,
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
---@return "ground"|"inventory"|"belt"
local function get_interactive_type(entity)
  if not entity then return "ground" end
  local entity_type = get_real_or_ghost_entity_type(entity)
  if belt_connectable[entity_type] then return "belt" end
  if interactive_prototypes[entity_type] then return "inventory" end
  return "ground"
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
    return belt_connectable[entity_type] and 2
      or can_always_pickup[entity_type] and 1
      -- This might not be the best way to check for a burner energy source however it works.
      or can_pickup_if_burner[entity_type] and entity.ghost_prototype.burner_prototype and 1
      or 0
  end
  if (entity.prototype.flags or {})["no-automated-item-removal"] then return 0 end
  return belt_connectable[entity_type] and 4
    or entity_type == "straight-rail"
    or entity_type == "curved-rail"
    or entity.get_output_inventory() and 3
    or 0
end

---@param surface LuaSurface
---@param position VectorXY
---@param inserter LuaEntity? @ Handles both real and ghost inserters.
---@return LuaEntity?
local function get_pickup_target(surface, position, inserter)
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
  return belt_connectable[entity_type] and (2 + offset)
    or can_always_drop[entity_type] and (1 + offset)
    -- This might not be the best way to check for a burner energy source however it works.
    or can_drop_if_burner[entity_type] and entity[prototype_key].burner_prototype and (1 + offset)
    or 0
end

---@param surface LuaSurface
---@param position VectorXY
---@param inserter LuaEntity? @ Handles both real and ghost inserters.
---@return LuaEntity?
local function get_drop_target(surface, position, inserter)
  -- Magic number 12/256 (0.046875), tested by teleporting a car 1/256 at a time.
  return get_interactive_entity(surface, position, inserter, 12/256, get_drop_target_priority)
end

---Sets the `from_*` fields in def based on what it finds at the given position.\
---Does **not** set `from_vector` (because how would it).
---@param def InserterThroughputDefinition
---@param from_entity LuaEntity? @ Handles both real and ghost entities.
local function set_from_based_on_entity(def, from_entity)
  local from_type = get_interactive_type(from_entity)
  def.pickup.target_type = from_type
  if from_type == "belt" then ---@cast from_entity -nil
    def.pickup.belt_speed = get_real_or_ghost_entity_prototype(from_entity).belt_speed
    def.pickup.belt_direction = from_entity.direction
    def.pickup.belt_shape = get_real_or_ghost_entity_type(from_entity) == "transport-belt"
      and from_entity.belt_shape
      or "straight"
  end
end

---Sets the `from_*` fields in def based on what it finds at the given position.
---@param def InserterThroughputDefinition
---@param surface LuaSurface
---@param inserter_position VectorXY
---@param from_position VectorXY
---@param inserter LuaEntity? @ Handles both real and ghost inserters.
local function set_from_based_on_position(def, surface, inserter_position, from_position, inserter)
  if inserter then
    def.inserter.inserter_position_in_tile = vec.mod_scalar(inserter.position, 1)
  end
  def.pickup.vector = vec.sub(vec.copy(from_position), inserter_position)
  set_from_based_on_entity(def, get_pickup_target(surface, from_position, inserter))
end

---Sets the `from_*` fields in def based on the current pickup position and target of the given inserter.
---@param def InserterThroughputDefinition
---@param inserter LuaEntity @ Handles both real and ghost inserters.
local function set_from_based_on_inserter(def, inserter)
  local pickup_target = inserter.pickup_target
  if pickup_target then
    def.pickup.vector = vec.sub(inserter.pickup_position, inserter.position)
    def.inserter.inserter_position_in_tile = vec.mod_scalar(inserter.position, 1)
    set_from_based_on_entity(def, pickup_target)
  else
    -- If the inserter is a ghost, the pickup_target is always nil, so this is ghost support. For non ghosts:
    -- The inserter could have been placed in this tick, in which case the pickup and drop targets have not
    -- been evaluated yet, so we're using the position as the fallback. The chance of this being the case is
    -- especially high when the game is tick paused.
    set_from_based_on_position(def, inserter.surface, inserter.position, inserter.pickup_position, inserter)
  end
end

---Sets the `to_*` fields in def based on what it finds at the given position.\
---Does **not** set `to_vector` (because how would it).
---@param def InserterThroughputDefinition
---@param to_entity LuaEntity? @ Handles both real and ghost entities.
local function set_to_based_on_entity(def, to_entity)
  local to_type = get_interactive_type(to_entity)
  def.drop.target_type = to_type
  if to_type == "belt" then ---@cast to_entity -nil
    def.drop.belt_speed = get_real_or_ghost_entity_prototype(to_entity).belt_speed
    def.drop.is_splitter = get_real_or_ghost_entity_type(to_entity) == "splitter"
    def.drop.belt_direction = to_entity.direction
  end
end

---Sets the `to_*` fields in def based on what it finds at the given position.
---@param def InserterThroughputDefinition
---@param surface LuaSurface
---@param inserter_position VectorXY
---@param to_position VectorXY
---@param inserter LuaEntity? @ Handles both real and ghost inserters.
local function set_to_based_on_position(def, surface, inserter_position, to_position, inserter)
  if inserter then
    def.inserter.inserter_position_in_tile = vec.mod_scalar(inserter.position, 1)
  end
  def.drop.vector = vec.sub(vec.copy(to_position), inserter_position)
  set_to_based_on_entity(def, get_drop_target(surface, to_position, inserter))
end

---Sets the `to_*` fields in def based on the current drop position and target of the given inserter.
---@param def InserterThroughputDefinition
---@param inserter LuaEntity @ Handles both real and ghost inserters.
local function set_to_based_on_inserter(def, inserter)
  local drop_target = inserter.drop_target
  if drop_target then
    def.drop.vector = vec.sub(inserter.drop_position, inserter.position)
    def.inserter.inserter_position_in_tile = vec.mod_scalar(inserter.position, 1)
    set_to_based_on_entity(def, inserter.drop_target)
  else
    -- Same as in `set_from_based_on_inserter`, see there for the comment.
    set_to_based_on_position(def, inserter.surface, inserter.position, inserter.drop_position, inserter)
  end
end

---Sets the `from_*` and `to_*` fields in def based on the current pickup and drop positions and targets of
---the given inserter.
---@param def InserterThroughputDefinition
---@param inserter LuaEntity @ Handles both real and ghost inserters.
local function set_from_and_to_based_on_inserter(def, inserter)
  set_from_based_on_inserter(def, inserter)
  set_to_based_on_inserter(def, inserter)
end

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
    assert(drop.is_splitter, "How did is_drop_to_input_of_splitter get called with falsy 'to_is_splitter'?")
    error("When 'to_is_splitter' is true, 'inserter_position_in_tile' and 'to_belt_direction' must both be set.")
  end
  inserter_position_in_tile = vec.snap_to_map(vec.copy(inserter_position_in_tile))
  local position_in_drop_tile = vec.mod_scalar(vec.add(inserter_position_in_tile, to_vector), 1)
  local drop_vector_from_tile_center = vec.sub_scalar(position_in_drop_tile, 0.5)
  local distance_from_center = vec.rotate_by_direction(drop_vector_from_tile_center, -drop.belt_direction).y
  return distance_from_center >= 0 and distance_from_center or nil
end

---@param inserter InserterThroughputInserterDefinition
---@param drop InserterThroughputDropDefinition
---@param to_vector VectorXY
---@return integer ticks
---@return boolean? drops_to_input_of_splitter
local function calculate_extra_drop_ticks(inserter, drop, to_vector)
  if drop.target_type == "inventory" then
    return 0
  end
  if drop.target_type == "ground" then
    return inserter.stack_size - 1
  end
  -- Is belt.
  local stack_size = inserter.stack_size
  local distance_on_input = drop.is_splitter and is_drop_to_input_of_splitter(inserter, drop, to_vector)
  if stack_size == 1 then return 0, not not distance_on_input end
  if stack_size == 2 then return 1, not not distance_on_input end

  local ticks_per_item = 0.25 / drop.belt_speed
  if distance_on_input then
    -- TODO: Return max possible drop speed instead of just a bool.
    -- TODO: Actually test how accurate this is with inserters not dropping exactly in the middle of splitters.
    -- It probably is very wrong, like I think stack_size -3 and -4 would need to change to -2 and use ticks_until_split somehow.
    -- TODO: This is currently only accurate for itl-express-transport-belt and faster. For the slower ones the estimate is too slow by ~0.3.

    local ticks_until_split = math_max(distance_on_input / drop.belt_speed)
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
---@param pickup InserterThroughputPickupDefinition
---@param extra_pickup_ticks number
---@return number extra_pickup_ticks
local function cap_extra_pickup_ticks_to_belt_speed(inserter, pickup, extra_pickup_ticks)
  -- Magic 8. It's simply the amount of items that are already on the belt, before more items have to move in.
  -- If the inserter is so fast that there wouldn't actually be 8 items on the belt yet, there's the final
  -- cap that will handle that case.
  local item_count = inserter.stack_size - 8
  if item_count < 0 then return extra_pickup_ticks end -- Not required, just short circuit.
  local ticks_per_item = (0.25 / pickup.belt_speed) / 2
  return math_max(math_ceil(item_count * ticks_per_item), extra_pickup_ticks)
end

---@param inserter InserterThroughputInserterDefinition
---@param pickup InserterThroughputPickupDefinition
---@param from_length number @ Length of the from_vector.
---@return number ticks
local function estimate_extra_pickup_ticks(inserter, pickup, from_length)
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
  local extension_influence = math_abs(vec.dot_product(item_flow_vector, pickup.vector))
  local rotation_influence = 1 - extension_influence
  local influence_bleed = vec.get_orientation{x = 0.25, y = -from_length} * 4

  local distance_due_to_belt_movement = pickup.belt_speed * belt_speed_multiplier

  local hand_speed = extension_influence * inserter.extension_speed
    + extension_influence * influence_bleed * inserter.rotation_speed
    + rotation_influence * inserter.rotation_speed
    + rotation_influence * influence_bleed * inserter.extension_speed
  hand_speed = hand_speed + distance_due_to_belt_movement

  local ticks_per_item = 0.25 / hand_speed -- 0.25 == distance per item
  return cap_extra_pickup_ticks_to_belt_speed(
    inserter,
    pickup,
    math_max(inserter.stack_size, ticks_per_item * inserter.stack_size)
  )
end

---@param items_per_second number
---@param pickup InserterThroughputPickupDefinition
---@param drop InserterThroughputDropDefinition
---@param drops_to_input_of_splitter boolean?
---@return number items_per_second
local function cap_to_belt_speed(items_per_second, pickup, drop, drops_to_input_of_splitter)
  if drop.target_type == "belt" then
    local max_per_second = 60 / (0.25 / drop.belt_speed) * (drops_to_input_of_splitter and 2 or 1)
    items_per_second = math_min(max_per_second, items_per_second)
  end
  if pickup.target_type == "belt" then
    items_per_second = math_min(60 / (0.125 / pickup.belt_speed), items_per_second)
  end
  return items_per_second
end

---@param def InserterThroughputDefinition
---@return number items_per_second
local function estimate_inserter_speed(def)
  local inserter = def.inserter
  local pickup = def.pickup
  local drop = def.drop
  local pickup_vector = vec.snap_to_map(vec.copy(pickup.vector))
  local drop_vector = vec.snap_to_map(vec.copy(drop.vector))
  local pickup_length = vec.get_length(pickup_vector)
  local drop_length = vec.get_length(drop_vector)
  local pickup_is_belt = pickup.target_type == "belt"
  local does_chase = inserter.chases_belt_items and pickup_is_belt
  local extension_ticks = calculate_extension_ticks(
    inserter.extension_speed,
    pickup_length,
    drop_length,
    does_chase,
    pickup_is_belt
  )
  local extra_drop_ticks, drops_to_input_of_splitter = calculate_extra_drop_ticks(inserter, drop, drop_vector)
  vec.normalize(pickup_vector, pickup_length)
  vec.normalize(drop_vector, drop_length) -- Must happen _after_ `calculate_extra_drop_ticks`.
  local rotation_ticks = calculate_rotation_ticks(
    inserter.rotation_speed,
    pickup_vector,
    drop_vector,
    does_chase,
    pickup_length,
    pickup_is_belt
  )
  local ticks_per_swing = math_max(extension_ticks, rotation_ticks, 1)
  local extra_pickup_ticks = estimate_extra_pickup_ticks(inserter, pickup, pickup_length)
  local total_ticks = (ticks_per_swing * 2) + extra_drop_ticks + extra_pickup_ticks
  return cap_to_belt_speed(60 / total_ticks * inserter.stack_size, pickup, drop, drops_to_input_of_splitter)
end

---Whether or not the given definition can be used accurate throughput calculation or if it is just an estimate.
---@param def InserterThroughputDefinition
---@return boolean
local function is_estimate(def)
  -- TODO: when addressing the TODOs for splitters in calculate_extra_drop_ticks, remove drop.is_splitter from here.
  return def.pickup.target_type == "belt" or not not def.drop.is_splitter
end

return {
  get_target_type = get_interactive_type,
  set_from_based_on_entity = set_from_based_on_entity,
  set_from_based_on_position = set_from_based_on_position,
  set_from_based_on_inserter = set_from_based_on_inserter,
  set_to_based_on_entity = set_to_based_on_entity,
  set_to_based_on_position = set_to_based_on_position,
  set_to_based_on_inserter = set_to_based_on_inserter,
  set_from_and_to_based_on_inserter = set_from_and_to_based_on_inserter,
  estimate_inserter_speed = estimate_inserter_speed,
  is_estimate = is_estimate,
}
