
---Only accepts tables taking the xy form, not arrays.
---@alias VectorXY Vector|MapPosition

local math_sqrt = math.sqrt
local math_atan2 = math.atan2

---@param vector VectorXY
---@return VectorXY
local function copy(vector)
  return {x = vector.x, y = vector.y}
end

---@param vector VectorXY
---@return number
local function get_length(vector)
  local x, y = vector.x, vector.y
  return math_sqrt(x * x + y * y)
end

---@param vector VectorXY @ Gets modified.
---@param length number
---@return VectorXY vector
local function set_length(vector, length)
  local multiplier = length / get_length(vector)
  vector.x = vector.x * multiplier
  vector.y = vector.y * multiplier
  return vector
end

---Does not copy.
---@param vector VectorXY @ Gets modified.
---@param length number? @ Precalculated length if available.
---@return VectorXY vector
local function normalize(vector, length)
  length = length or get_length(vector)
  vector.x = vector.x / length
  vector.y = vector.y / length
  return vector
end

---Snaps x and y to the MapPosition grid (1/256).\
---Does not copy.\
---I don't know if the game rounds or floors, but this function is flooring.
---@param vector VectorXY @ Gets modified.
---@return VectorXY vector
local function snap_to_map(vector)
  -- Fast way of flooring (to negative infinity).
  local x = vector.x
  vector.x = x - (x % (1/256))
  local y = vector.y
  vector.y = y - (y % (1/256))
  return vector
end

---@param left VectorXY @ Gets modified.
---@param right VectorXY
---@return VectorXY left
local function add(left, right)
  left.x = left.x + right.x
  left.y = left.y + right.y
  return left
end

---@param left VectorXY @ Gets modified.
---@param right VectorXY
---@return VectorXY left
local function sub(left, right)
  left.x = left.x - right.x
  left.y = left.y - right.y
  return left
end

---@param left VectorXY @ Gets modified.
---@param right number
---@return VectorXY left
local function mul_scalar(left, right)
  left.x = left.x * right
  left.y = left.y * right
  return left
end

---@param left VectorXY @ Gets modified.
---@param right number
---@return VectorXY left
local function div_scalar(left, right)
  left.x = left.x / right
  left.y = left.y / right
  return left
end

---@param left VectorXY @ Gets modified.
---@param right number
---@return VectorXY left
local function mod_scalar(left, right)
  left.x = left.x % right
  left.y = left.y % right
  return left
end

local rad360 = math.rad(360)

---North is 0, goes clockwise, always positive.
---@param vector VectorXY
---@return number
local function radians(vector)
  -- https://stackoverflow.com/questions/283406/what-is-the-difference-between-atan-and-atan2-in-c
  -- x and y are flipped because in Factorio north is 0.
  -- Lua's modulo always returns a positive number. This is making use of that to turn the -180 to 180 range.
  -- into a 0 to 360 range.
  return math_atan2(vector.x, -vector.y) % rad360
end

---Returns a RealOrientation, so [0, 1) where 0 is north, 0.25 is east, 0.5 is south, 0.75 is west.
---@param vector VectorXY
---@return RealOrientation
local function orientation(vector)
  -- See comments in `radians`.
  return (math_atan2(vector.x, -vector.y) % rad360) / rad360
end

return {
  copy = copy,
  get_length = get_length,
  set_length = set_length,
  normalize = normalize,
  snap_to_map = snap_to_map,
  add = add,
  sub = sub,
  mul_scalar = mul_scalar,
  div_scalar = div_scalar,
  mod_scalar = mod_scalar,
  radians = radians,
  orientation = orientation,
}
