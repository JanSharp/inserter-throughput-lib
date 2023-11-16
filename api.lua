
local vec = require("__inserter_throughput_lib__.vector")

---@class InserterThroughputDefinition
---@field extension_speed number @ Tiles per tick.
---@field rotation_speed number @ RealOrientation per tick.
---@field stack_size integer @ Must be at least 1.
---@field chases_belt_items boolean @ https://lua-api.factorio.com/latest/prototypes/InserterPrototype.html#chases_belt_items
---@field inserter_position_in_tile VectorXY @ Modulo (%) of x and y of the inserter's position. -- NOTE: currently unused
---@field from_type "inventory"|"belt"|"ground"
---@field from_vector VectorXY @ Relative to inserter position.
---@field from_belt_speed number? @ Tiles per tick of each item on the belt being picked up from.
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
  ["loader"] = true,
  ["loader-1x1"] = true,
  ["locomotive"] = true,
  ["logistic-container"] = true,
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
local belt_prototypes = {
  ["linked-belt"] = true,
  ["loader-1x1"] = true,
  ["loader"] = true,
  ["splitter"] = true,
  ["transport-belt"] = true,
  ["underground-belt"] = true,
}

---@param entity LuaEntity?
---@return "ground"|"inventory"|"belt"
local function get_interactive_type(entity)
  if not entity then return "ground" end
  local entity_type = entity.type
  if belt_prototypes[entity_type] then return "belt" end
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

  ---@param surface LuaSurface
  ---@param position VectorXY
  ---@return LuaEntity?
  function get_interactive_entity(surface, position)
    local left = math.floor(position.x)
    local top = math.floor(position.y)
    left_top.x = left
    left_top.y = top
    right_bottom.x = left + 1
    right_bottom.y = top + 1
    for _, entity in pairs(surface.find_entities_filtered(arg)) do
      if interactive_prototypes[entity.type] then
        return entity
      end
    end
    return nil
  end
end

---Sets the `from_*` fields in def based on what it finds at the given position.\
---Does **not** set `from_vector` (because how would it).
---@param def InserterThroughputDefinition
---@param from_entity LuaEntity?
local function set_from_based_on_entity(def, from_entity)
  local from_type = get_interactive_type(from_entity)
  def.from_type = from_type
  if from_type == "belt" then ---@cast from_entity -nil
    def.from_belt_speed = from_entity.prototype.belt_speed
  end
end

---Sets the `from_*` fields in def based on what it finds at the given position.
---@param def InserterThroughputDefinition
---@param surface LuaSurface
---@param inserter_position VectorXY
---@param from_position VectorXY
local function set_from_based_on_position(def, surface, inserter_position, from_position)
  def.from_vector = vec.sub(vec.copy(from_position), inserter_position)
  set_from_based_on_entity(def, get_interactive_entity(surface, from_position))
end

---Sets the `from_*` fields in def based on the current pickup position and target of the given inserter.
---@param def InserterThroughputDefinition
---@param inserter LuaEntity
local function set_from_based_on_inserter(def, inserter)
  def.from_vector = vec.sub(inserter.pickup_position, inserter.position)
  set_from_based_on_entity(def, inserter.pickup_target)
end

---Sets the `to_*` fields in def based on what it finds at the given position.\
---Does **not** set `to_vector` (because how would it).
---@param def InserterThroughputDefinition
---@param to_entity LuaEntity?
local function set_to_based_on_entity(def, to_entity)
  local to_type = get_interactive_type(to_entity)
  def.to_type = to_type
  if to_type == "belt" then ---@cast to_entity -nil
    def.to_belt_speed = to_entity.prototype.belt_speed
    def.to_is_splitter = to_entity.type == "splitter"
  end
end

---Sets the `to_*` fields in def based on what it finds at the given position.
---@param def InserterThroughputDefinition
---@param surface LuaSurface
---@param inserter_position VectorXY
---@param to_position VectorXY
local function set_to_based_on_position(def, surface, inserter_position, to_position)
  def.to_vector = vec.sub(vec.copy(to_position), inserter_position)
  set_to_based_on_entity(def, get_interactive_entity(surface, to_position))
end

---Sets the `to_*` fields in def based on the current drop position and target of the given inserter.
---@param def InserterThroughputDefinition
---@param inserter LuaEntity
local function set_to_based_on_inserter(def, inserter)
  def.to_vector = vec.sub(inserter.drop_position, inserter.position)
  set_to_based_on_entity(def, inserter.drop_target)
end

---Sets the `from_*` and `to_*` fields in def based on the current pickup and drop positions and targets of
---the given inserter.
---@param def InserterThroughputDefinition
---@param inserter LuaEntity
local function set_from_and_to_based_on_inserter(def, inserter)
  local position = inserter.position
  def.from_vector = vec.sub(inserter.pickup_position, position)
  def.to_vector = vec.sub(inserter.drop_position, position)
  set_from_based_on_entity(def, inserter.pickup_target)
  set_to_based_on_entity(def, inserter.drop_target)
end

---@param extension_speed number @ Tiles per tick.
---@param from_length number @ Tiles.
---@param to_length number @ Tiles.
---@param does_chase boolean @ Is this inserter picking up from a belt?
---@return integer
local function calculate_extension_ticks(extension_speed, from_length, to_length, does_chase)
  local diff = math.abs(from_length - to_length)
  if does_chase then
    diff = math.max(0, diff - 0.5)
  end
  return math.ceil(diff / extension_speed)
end

---@param rotation_speed number @ RealOrientation per tick.
---@param from_vector VectorXY @ Must be normalized.
---@param to_vector VectorXY @ Must be normalized.
---@param does_chase boolean @ Is this inserter picking up from a belt?
---@param from_length number @ Length of the from_vector, before normalization.
---@return integer
local function calculate_rotation_ticks(rotation_speed, from_vector, to_vector, does_chase, from_length)
  -- This math is horrendous and I need to learn to use my brain better with angles. Good lord.

  local from_angle = math.abs(math.asin(from_vector.x)) / math.rad(360)
  if from_vector.y > 0 then from_angle = 0.5 - from_angle end
  if from_vector.x < 0 then from_angle = 1 - from_angle end
  local to_angle = math.abs(math.asin(to_vector.x)) / math.rad(360)
  -- game.print(tostring(to_angle), {skip_if_redundant = false})
  if to_vector.y > 0 then to_angle = 0.5 - to_angle end
  if to_vector.x < 0 then to_angle = 1 - to_angle end

  local diff = math.abs(from_angle - to_angle)
  if diff > 0.5 then
    if from_angle < to_angle then
      from_angle = from_angle + 1
    else
      to_angle = to_angle + 1
    end
    diff = math.abs(to_angle - from_angle)
  end
  -- game.print(string.format("from: %.3f, to: %.3f, diff: %.3f", from_angle, to_angle, tostring(diff)), {skip_if_redundant = false})

  if does_chase then
    local vector = vec.normalize{x = 0.5, y = from_length}
    local angle_for_half_a_tile = math.asin(vector.x) / math.rad(360)
    diff = math.max(0, diff - angle_for_half_a_tile)
  end

  return math.ceil(diff / rotation_speed)
end

---@param def InserterThroughputDefinition
---@return integer ticks
local function calculate_extra_drop_ticks(def)
  if def.to_type == "inventory" then
    return 0
  end
  if def.to_type == "ground" then
    return def.stack_size - 1
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
  return math.max(stack_size - 1, math.floor(ticks_per_item * (stack_size - 2)))
end

---@param def InserterThroughputDefinition
---@param from_length number @ Length of the from_vector.
---@return integer ticks
local function estimate_extra_pickup_ticks(def, from_length)
  if def.from_type == "inventory" then
    return 0
  end
  if def.from_type == "ground" then
    return def.stack_size - 1
  end
  -- Is belt.
  if def.chases_belt_items then
    -- TODO: verify that it does indeed take 1 tick per item.
    -- TODO: also take belt speed into account, if the stack size is > 8 then it would pick up all items and
    -- have to wait for more items.
    -- TODO: also consider the fact that the belt may not be full again in the time it performs a full swing
    return def.stack_size - 1
  end
  -- TODO: Improve this a lot.
  local vector = vec.normalize{x = 0.25, y = from_length}
  local angle_per_item = math.asin(vector.x) / math.rad(360)
  vector = vec.normalize{x = def.from_belt_speed, y = from_length}
  local belt_angle_per_tick = math.asin(vector.x) / math.rad(360)
  belt_angle_per_tick = belt_angle_per_tick % def.rotation_speed
  local average_seek_ticks = angle_per_item / (def.rotation_speed + belt_angle_per_tick)
  return math.max(def.stack_size, average_seek_ticks * def.stack_size)
end

---@param def InserterThroughputDefinition
---@return number items_per_second
local function estimate_inserter_speed(def)
  local from_vector = vec.snap_to_map(vec.copy(def.from_vector))
  local to_vector = vec.snap_to_map(vec.copy(def.to_vector))
  local from_length = vec.length(from_vector)
  local to_length = vec.length(to_vector)
  local does_chase = def.chases_belt_items and def.from_type == "belt"
  local extension_ticks = calculate_extension_ticks(def.extension_speed, from_length, to_length, does_chase)
  vec.normalize(from_vector, from_length)
  vec.normalize(to_vector, to_length)
  local rotation_ticks = calculate_rotation_ticks(def.rotation_speed, from_vector, to_vector, does_chase, from_length)
  local ticks_per_swing = math.max(extension_ticks, rotation_ticks, 1)
  local extra_drop_ticks = calculate_extra_drop_ticks(def)
  local extra_pickup_ticks = estimate_extra_pickup_ticks(def, from_length)
  local total_ticks = (ticks_per_swing * 2) + extra_drop_ticks + extra_pickup_ticks
  return 60 / total_ticks * def.stack_size
end

return {
  get_target_type = get_interactive_type,
  get_interactive_entity = get_interactive_entity,
  set_from_based_on_entity = set_from_based_on_entity,
  set_from_based_on_position = set_from_based_on_position,
  set_from_based_on_inserter = set_from_based_on_inserter,
  set_to_based_on_entity = set_to_based_on_entity,
  set_to_based_on_position = set_to_based_on_position,
  set_to_based_on_inserter = set_to_based_on_inserter,
  set_from_and_to_based_on_inserter = set_from_and_to_based_on_inserter,
  estimate_inserter_speed = estimate_inserter_speed,
}
