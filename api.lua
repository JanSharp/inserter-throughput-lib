
local vec = require("__inserter-throughput-lib__.vector")
local params_util = require("__inserter-throughput-lib__.params_util")

local math_abs = math.abs
local math_ceil = math.ceil
local math_floor = math.floor
local math_min = math.min
local math_max = math.max

---@class InserterThroughputDefinition
---@field extension_speed number @ Tiles per tick.
---@field rotation_speed number @ RealOrientation per tick.
---@field stack_size integer @ Must be at least 1.
---@field chases_belt_items boolean @ https://lua-api.factorio.com/latest/prototypes/InserterPrototype.html#chases_belt_items
---@field inserter_position_in_tile VectorXY @ Modulo (%) of x and y of the inserter's position. -- NOTE: currently unused
---@field from_type "inventory"|"belt"|"ground"
---@field from_vector VectorXY @ Relative to inserter position.
---@field from_belt_speed number? @ Tiles per tick of each item on the belt being picked up from.
---@field from_belt_direction defines.direction?
---@field from_belt_shape "left"|"right"|"straight"
---@field to_type "inventory"|"belt"|"ground"
---@field to_vector VectorXY @ Relative to inserter position.
---@field to_belt_speed number? @ Tiles per tick of each item on the belt being dropped off to.
---@field to_is_splitter boolean? @ Is the belt being dropped off to the input side of a splitter?

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
  def.from_type = from_type
  if from_type == "belt" then ---@cast from_entity -nil
    def.from_belt_speed = get_real_or_ghost_entity_prototype(from_entity).belt_speed
    def.from_belt_direction = from_entity.direction
    def.from_belt_shape = get_real_or_ghost_entity_type(from_entity) == "transport-belt"
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
  def.from_vector = vec.sub(vec.copy(from_position), inserter_position)
  set_from_based_on_entity(def, get_pickup_target(surface, from_position, inserter))
end

---Sets the `from_*` fields in def based on the current pickup position and target of the given inserter.
---@param def InserterThroughputDefinition
---@param inserter LuaEntity @ Handles both real and ghost inserters.
local function set_from_based_on_inserter(def, inserter)
  local pickup_target = inserter.pickup_target
  if pickup_target then
    def.from_vector = vec.sub(inserter.pickup_position, inserter.position)
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
  def.to_type = to_type
  if to_type == "belt" then ---@cast to_entity -nil
    def.to_belt_speed = get_real_or_ghost_entity_prototype(to_entity).belt_speed
    def.to_is_splitter = get_real_or_ghost_entity_type(to_entity) == "splitter"
  end
end

---Sets the `to_*` fields in def based on what it finds at the given position.
---@param def InserterThroughputDefinition
---@param surface LuaSurface
---@param inserter_position VectorXY
---@param to_position VectorXY
---@param inserter LuaEntity? @ Handles both real and ghost inserters.
local function set_to_based_on_position(def, surface, inserter_position, to_position, inserter)
  def.to_vector = vec.sub(vec.copy(to_position), inserter_position)
  set_to_based_on_entity(def, get_drop_target(surface, to_position, inserter))
end

---Sets the `to_*` fields in def based on the current drop position and target of the given inserter.
---@param def InserterThroughputDefinition
---@param inserter LuaEntity @ Handles both real and ghost inserters.
local function set_to_based_on_inserter(def, inserter)
  local drop_target = inserter.drop_target
  if drop_target then
    def.to_vector = vec.sub(inserter.drop_position, inserter.position)
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
---@return integer
local function calculate_extension_ticks(extension_speed, from_length, to_length, does_chase)
  local diff = math_abs(from_length - to_length)
  if not does_chase then
    return math_ceil(diff / extension_speed)
  end
  return math_max(0, (diff + extension_distance_offset) / extension_speed)
end

---@param rotation_speed number @ RealOrientation per tick.
---@param from_vector VectorXY @ Must be normalized.
---@param to_vector VectorXY @ Must be normalized.
---@param does_chase boolean @ Is this inserter picking up from a belt?
---@param from_length number @ Length of the from_vector, before normalization.
---@return integer
local function calculate_rotation_ticks(rotation_speed, from_vector, to_vector, does_chase, from_length)
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

  local orientation_for_half_a_tile
    = vec.get_orientation{x = rotation_osset_from_tile_center % 0.51, y = -from_length}
  return math_max(0, (diff - orientation_for_half_a_tile) / rotation_speed)
end

---@param def InserterThroughputDefinition
---@return integer ticks
local function calculate_extra_drop_ticks(def)
  if def.to_type == "inventory" then
    return 0
  end
  if def.to_type == "ground" then
    return def.stack_size - 1 -- TODO: test if this is accurate
  end
  -- Is belt.
  local stack_size = def.stack_size
  if stack_size == 1 then return 0 end
  if stack_size == 2 then return 1 end
  if def.to_is_splitter then
    -- TODO: impl splitters
  end
  -- How the hell does changing this to *4 actually make a difference... Makes less than 0 sense.
  local ticks_per_item = 0.25 / def.to_belt_speed
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

---@param def InserterThroughputDefinition
---@param from_length number @ Length of the from_vector.
---@return integer ticks
local function estimate_extra_pickup_ticks(def, from_length)
  if def.from_type == "inventory" then
    return 0
  end
  if def.from_type == "ground" then
    return def.stack_size - 1 -- TODO: test if this is accurate
  end
  -- Is belt.
  if not def.chases_belt_items then
    -- TODO: verify that it does indeed take 1 tick per item.
    -- TODO: also take belt speed into account, if the stack size is > 8 then it would pick up all items and
    -- have to wait for more items.
    -- TODO: also consider the fact that the belt may not be full again in the time it performs a full swing
    return def.stack_size - 1
  end

  local item_flow_vector = item_flow_vector_lut[def.from_belt_direction][def.from_belt_shape]
  -- Since item_flow_vector has a length of 1, extension_influence and rotation influence are values 0 to 1.
  local extension_influence = math_abs(vec.dot_product(item_flow_vector, def.from_vector))
  local rotation_influence = 1 - extension_influence
  local influence_bleed = vec.get_orientation{x = 0.25, y = -from_length} * 4

  local distance_due_to_belt_movement = def.from_belt_speed * belt_speed_multiplier

  local hand_speed = extension_influence * def.extension_speed
    + extension_influence * influence_bleed * def.rotation_speed
    + rotation_influence * def.rotation_speed
    + rotation_influence * influence_bleed * def.extension_speed
  hand_speed = hand_speed + distance_due_to_belt_movement

  local ticks_per_item = 0.25 / hand_speed -- 0.25 == distance per item
  return math_max(def.stack_size, ticks_per_item * def.stack_size)
end

---@param items_per_second number
---@param def InserterThroughputDefinition
---@return number items_per_second
local function cap_to_belt_speed(items_per_second, def)
  if def.to_type == "belt" then
    items_per_second = math_min(60 / (0.25 / def.to_belt_speed), items_per_second)
  end
  if def.from_type == "belt" then
    items_per_second = math_min(60 / (0.125 / def.from_belt_speed), items_per_second)
  end
  return items_per_second
end

---@param def InserterThroughputDefinition
---@return number items_per_second
local function estimate_inserter_speed(def)
  local from_vector = vec.snap_to_map(vec.copy(def.from_vector))
  local to_vector = vec.snap_to_map(vec.copy(def.to_vector))
  local from_length = vec.get_length(from_vector)
  local to_length = vec.get_length(to_vector)
  local does_chase = def.chases_belt_items and def.from_type == "belt"
  local extension_ticks = calculate_extension_ticks(def.extension_speed, from_length, to_length, does_chase)
  vec.normalize(from_vector, from_length)
  vec.normalize(to_vector, to_length)
  local rotation_ticks = calculate_rotation_ticks(def.rotation_speed, from_vector, to_vector, does_chase, from_length)
  local ticks_per_swing = math_max(extension_ticks, rotation_ticks, 1)
  local extra_drop_ticks = calculate_extra_drop_ticks(def)
  local extra_pickup_ticks = estimate_extra_pickup_ticks(def, from_length)
  local total_ticks = (ticks_per_swing * 2) + extra_drop_ticks + extra_pickup_ticks
  return cap_to_belt_speed(60 / total_ticks * def.stack_size, def)
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
}
