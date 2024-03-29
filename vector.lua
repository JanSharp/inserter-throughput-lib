
---Only accepts tables taking the xy form, not arrays.
---@alias VectorXY Vector|MapPosition|TilePosition

---Must watch (3blue1brown) https://www.youtube.com/playlist?list=PLZHQObOWTQDPD3MizzM2xVFitgF8hE_ab
---@class MatrixIJ
---@field ix number @ Top left corner if you think about it like a 2x2 grid.
---@field iy number @ Bottom left corner if you think about it like a 2x2 grid.
---@field jx number @ Top right corner if you think about it like a 2x2 grid.
---@field jy number @ Bottom right corner if you think about it like a 2x2 grid.

local math_sqrt = math.sqrt
local math_atan2 = math.atan2
local math_sin = math.sin
local math_cos = math.cos
local math_abs = math.abs
local math_floor = math.floor
local math_ceil = math.ceil

---@param left VectorXY
---@param right VectorXY
---@return boolean
local function vec_equals(left, right)
  return left.x == right.x and left.y == right.y
end

---@param left MatrixIJ
---@param right MatrixIJ
---@return boolean
local function matrix_equals(left, right)
  return left.ix == right.ix and left.jx == right.jx
    and left.iy == right.iy and left.jy == right.jy
end

---@generic T : VectorXY
---@param vector T
---@return T
---@nodiscard
local function copy(vector) ---@cast vector VectorXY
  return {x = vector.x, y = vector.y}
end

---@param vector VectorXY
---@return boolean @ `true` when both `x` and `y` are `== 0`.
local function is_zero(vector)
  return vector.x == 0 and vector.y == 0
end

---@param vector VectorXY
---@return number
local function get_length(vector)
  local x, y = vector.x, vector.y
  return math_sqrt(x * x + y * y)
end

---Errors when `target_length ~= 0 and is_zero(vector)`.
---@generic T : VectorXY
---@param vector T @ Gets modified.
---@param target_length number
---@param current_length number? @ Precalculated length if available.
---@return T vector
local function set_length(vector, target_length, current_length) ---@cast vector VectorXY
  if target_length == 0 then
    vector.x = 0
    vector.y = 0
    return vector
  end
  current_length = current_length or get_length(vector)
  if current_length == 0 then
    error("Setting the length of a 0 length vector to non 0 length is undefined. \z
      Instead of starting a NaN infection, this errors. \z
      Check for 0 length vectors before or use 'set_length_safe' which returns nil instead of erroring."
    )
  end
  local multiplier = target_length / current_length
  vector.x = vector.x * multiplier
  vector.y = vector.y * multiplier
  return vector
end

---When the `target_length` is 0, the result is going to be a 0 length vector.\
---Otherwise, when the given vector has a length of 0, the return value is going to be `nil`.
---@generic T : VectorXY
---@param vector T @ Gets modified. When `nil` is returned, `vector` did not get modified.
---@param target_length number
---@param current_length number? @ Precalculated length if available.
---@return T? vector @ `nil` when `target_length ~= 0 and is_zero(vector)`.
local function set_length_safe(vector, target_length, current_length) ---@cast vector VectorXY
  if target_length == 0 then
    vector.x = 0
    vector.y = 0
    return vector
  end
  current_length = current_length or get_length(vector)
  if current_length == 0 then return end
  local multiplier = target_length / current_length
  vector.x = vector.x * multiplier
  vector.y = vector.y * multiplier
  return vector
end

---Errors when `is_zero(vector)`.
---@generic T : VectorXY
---@param vector T @ Gets modified.
---@param current_length number? @ Precalculated length if available.
---@return T vector
local function normalize(vector, current_length) ---@cast vector VectorXY
  current_length = current_length or get_length(vector)
  if current_length == 0 then
    error("Normalizing a vector of 0 length is undefined. \z
      Instead of starting a NaN infection, this errors. \z
      Check for 0 length vectors before or use 'normalize_safe' which returns nil instead of erroring."
    )
  end
  vector.x = vector.x / current_length
  vector.y = vector.y / current_length
  return vector
end

---@generic T : VectorXY
---@param vector T @ Gets modified. When `nil` is returned, `vector` did not get modified.
---@param current_length number? @ Precalculated length if available.
---@return T? vector @ `nil` when `is_zero(vector)`.
local function normalize_safe(vector, current_length) ---@cast vector VectorXY
  current_length = current_length or get_length(vector)
  if current_length == 0 then return end
  vector.x = vector.x / current_length
  vector.y = vector.y / current_length
  return vector
end

---Snaps x and y to the MapPosition grid (1/256).\
---I don't know if the game rounds or floors, but this function is flooring.
---@generic T : VectorXY
---@param vector T @ Gets modified.
---@return T vector
local function snap_to_map(vector) ---@cast vector VectorXY
  -- Fast way of flooring (to negative infinity).
  local x = vector.x
  vector.x = x - (x % (1/256))
  local y = vector.y
  vector.y = y - (y % (1/256))
  return vector
end

---@generic T : VectorXY
---@param left T @ Gets modified.
---@param right VectorXY
---@return T left
local function add(left, right) ---@cast left VectorXY
  left.x = left.x + right.x
  left.y = left.y + right.y
  return left
end

---@generic T : VectorXY
---@param left T @ Gets modified.
---@param right VectorXY
---@return T left
local function sub(left, right) ---@cast left VectorXY
  left.x = left.x - right.x
  left.y = left.y - right.y
  return left
end

---@generic T : VectorXY
---@param left T @ Gets modified.
---@param right number
---@return T left
local function add_scalar(left, right) ---@cast left VectorXY
  left.x = left.x + right
  left.y = left.y + right
  return left
end

---@generic T : VectorXY
---@param left T @ Gets modified.
---@param right number
---@return T left
local function sub_scalar(left, right) ---@cast left VectorXY
  left.x = left.x - right
  left.y = left.y - right
  return left
end

---@generic T : VectorXY
---@param left T @ Gets modified.
---@param right number
---@return T left
local function mul_scalar(left, right) ---@cast left VectorXY
  left.x = left.x * right
  left.y = left.y * right
  return left
end

---@generic T : VectorXY
---@param left T @ Gets modified.
---@param right number
---@return T left
local function div_scalar(left, right) ---@cast left VectorXY
  left.x = left.x / right
  left.y = left.y / right
  return left
end

---@generic T : VectorXY
---@param left T @ Gets modified.
---@param right number
---@return T left
local function mod_scalar(left, right) ---@cast left VectorXY
  left.x = left.x % right
  left.y = left.y % right
  return left
end

---@generic T : VectorXY
---@param left T @ Gets modified.
---@param right number
---@return T left
local function pow_scalar(left, right) ---@cast left VectorXY
  left.x = left.x ^ right
  left.y = left.y ^ right
  return left
end

---Simply calls `math.sqrt` on both `x` and `y`.
---@generic T : VectorXY
---@param vector T @ Gets modified.
---@return T vector
local function sqrt(vector) ---@cast vector VectorXY
  vector.x = math_sqrt(vector.x)
  vector.y = math_sqrt(vector.y)
  return vector
end

---Simply calls `math.abs` on both `x` and `y`.
---@generic T : VectorXY
---@param vector T @ Gets modified.
---@return T vector
local function abs(vector) ---@cast vector VectorXY
  vector.x = math_abs(vector.x)
  vector.y = math_abs(vector.y)
  return vector
end

---Simply calls `math.floor` on both `x` and `y`.
---@generic T : VectorXY
---@param vector T @ Gets modified.
---@return T vector
local function floor(vector) ---@cast vector VectorXY
  vector.x = math_floor(vector.x)
  vector.y = math_floor(vector.y)
  return vector
end

---Simply calls `math.ceil` on both `x` and `y`.
---@generic T : VectorXY
---@param vector T @ Gets modified.
---@return T vector
local function ceil(vector) ---@cast vector VectorXY
  vector.x = math_ceil(vector.x)
  vector.y = math_ceil(vector.y)
  return vector
end

---Can take any amount of vectors, technically even 0 in which case it simply returns `nil`. The only
---limitation is that there must be no gaps in the arguments.
---@generic T : VectorXY?
---@param vector T @ Gets modified.
---@param other VectorXY?
---@param ... VectorXY?
---@return T vector @ A vector with the lowest `x` and the lowest `y` out of all given vectors.
local function min(vector, other, ...) ---@cast vector VectorXY
  if not other then return vector end
  local other_x = other.x
  if other_x < vector.x then
    vector.x = other_x
  end
  local other_y = other.y
  if other_y < vector.y then
    vector.y = other_y
  end
  -- Optimized for the most common case where it is simply given 2 vectors. It does not create create any
  -- temporary tables. Just tail calls until it hits `nil`.
  return min(vector, ...)
end

---Can take any amount of vectors, technically even 0 in which case it simply returns `nil`. The only
---limitation is that there must be no gaps in the arguments.
---@generic T : VectorXY?
---@param vector T @ Gets modified.
---@param other VectorXY?
---@param ... VectorXY?
---@return T vector @ A vector with the highest `x` and the highest `y` out of all given vectors.
local function max(vector, other, ...) ---@cast vector VectorXY
  if not other then return vector end
  local other_x = other.x
  if other_x > vector.x then
    vector.x = other_x
  end
  local other_y = other.y
  if other_y > vector.y then
    vector.y = other_y
  end
  -- Optimized for the most common case where it is simply given 2 vectors. It does not create create any
  -- temporary tables. Just tail calls until it hits `nil`.
  return max(vector, ...)
end

---Project `right` onto `left`, get that length and multiply it by the length of `left`.\
---If they are perpendicular to each other, it is 0.\
---If they are pointing generally away from each other, it is negative.\
---You can also think about it as projecting `left` onto `right` and the result is the same.
---See https://www.3blue1brown.com/lessons/dot-products
---@param left VectorXY
---@param right VectorXY
---@return number
local function dot_product(left, right)
  return left.x * right.x + left.y * right.y
end

local rad360 = math.rad(360)

---North is 0, goes clockwise, always positive.\
---Errors when `is_zero(vector)`. Check for 0 length vectors before or see `get_orientation_safe`.
---@param vector VectorXY
---@return number
local function get_radians(vector)
  local x, y = vector.x, vector.y
  if x == 0 and y == 0 then
    error("Getting the radians of a 0 length vector is undefined. \z
      Check for 0 length vectors before or use 'get_radians_safe' which returns nil instead of erroring."
    )
  end
  -- https://stackoverflow.com/questions/283406/what-is-the-difference-between-atan-and-atan2-in-c
  -- x and y are flipped because in Factorio north is 0.
  -- Lua's modulo always returns a positive number. This is making use of that to turn the -180 to 180 range
  -- into a 0 to 360 range.
  return math_atan2(x, -y) % rad360
end

---North is 0, goes clockwise, always positive.
---@param vector VectorXY
---@return number? @ `nil` when `is_zero(vector)`.
local function get_radians_safe(vector)
  local x, y = vector.x, vector.y
  if x == 0 and y == 0 then return end
  -- Copy paste of get_radians. See get_radians for comments.
  return math_atan2(x, -y) % rad360
end

---Returns a RealOrientation, so `[0, 1)` where 0 is north, 0.25 is east, 0.5 is south, 0.75 is west.\
---Errors when `is_zero(vector)`. Check for 0 length vectors before or see `get_orientation_safe`.
---@param vector VectorXY
---@return RealOrientation
local function get_orientation(vector)
  local x, y = vector.x, vector.y
  if x == 0 and y == 0 then
    error("Getting the orientation of a 0 length vector is undefined. \z
      Check for 0 length vectors before or use 'get_orientation_safe' which returns nil instead of erroring."
    )
  end
  -- Copy paste of get_radians but divided by rad360. See get_radians for comments.
  return (math_atan2(x, -y) % rad360) / rad360
end

---Returns a RealOrientation, so `[0, 1)` where 0 is north, 0.25 is east, 0.5 is south, 0.75 is west.
---@param vector VectorXY
---@return RealOrientation? @ `nil` when `is_zero(vector)`.
local function get_orientation_safe(vector)
  local x, y = vector.x, vector.y
  if x == 0 and y == 0 then return end
  -- Copy paste of get_radians but divided by rad360. See get_radians for comments.
  return (math_atan2(x, -y) % rad360) / rad360
end

---@param radians number
---@return number ix @ Top left corner if you think about it like a 2x2 grid.
---@return number jx @ Top right corner if you think about it like a 2x2 grid.
---@return number iy @ Bottom left corner if you think about it like a 2x2 grid.
---@return number jy @ Bottom right corner if you think about it like a 2x2 grid.
local function get_rotation_matrix_values(radians)
  local cos = math_cos(radians)
  local sin = math_sin(radians)
  return
    cos, -sin,
    sin, cos
end

---@generic T : VectorXY
---@param vector T @ Gets modified.
---@param radians_diff number
---@return T vector
local function rotate_by_radians(vector, radians_diff) ---@cast vector VectorXY
  local ix, jx,
        iy, jy = get_rotation_matrix_values(radians_diff)
  local x, y = vector.x, vector.y
  vector.x = x * ix + y * jx
  vector.y = x * iy + y * jy
  return vector
end

---@generic T : VectorXY
---@param vector T @ Gets modified.
---@param orientation_diff RealOrientation @ Can exceed the usual bounds of RealOrientation.
---@return T vector
local function rotate_by_orientation(vector, orientation_diff) ---@cast vector VectorXY
  return rotate_by_radians(vector, orientation_diff * rad360)
end

---@type table<defines.direction, fun(vector: VectorXY): VectorXY>
local rotate_by_direction_lut = setmetatable({
  [defines.direction.north] = function(vector) return vector end,
  [defines.direction.east] = function(vector) vector.x, vector.y = -vector.y, vector.x; return vector end,
  [defines.direction.south] = function(vector) vector.x, vector.y = -vector.x, -vector.y; return vector end,
  [defines.direction.west] = function(vector) vector.x, vector.y = vector.y, -vector.x; return vector end,
  [defines.direction.northeast] = function(vector) return rotate_by_radians(vector, 0.125 * rad360) end,
  [defines.direction.southeast] = function(vector) return rotate_by_radians(vector, 0.375 * rad360) end,
  [defines.direction.southwest] = function(vector) return rotate_by_radians(vector, 0.625 * rad360) end,
  [defines.direction.northwest] = function(vector) return rotate_by_radians(vector, 0.875 * rad360) end,
}, {
  __index = function(_, direction) error("Invalid direction value: "..direction) end,
})

local direction_modulo = defines.direction.south * 2
---@generic T : VectorXY
---@param vector T @ Gets modified.
---@param direction defines.direction @ Can take negative values, which rotate counter clockwise.
---@return T vector
local function rotate_by_direction(vector, direction) ---@cast vector VectorXY
  return rotate_by_direction_lut[direction % direction_modulo](vector)
end

---Right to left... because math.
---@generic T : VectorXY
---@param matrix MatrixIJ
---@param vector T @ Gets modified.
---@return T vector
local function transform_by_matrix(matrix, vector) ---@cast vector VectorXY
  local x, y = vector.x, vector.y
  vector.x = x * matrix.ix + y * matrix.jx
  vector.y = x * matrix.iy + y * matrix.jy
  return vector
end

---@param radians number
---@return MatrixIJ matrix
local function rotation_matrix_by_radians(radians)
  local ix, jx,
        iy, jy = get_rotation_matrix_values(radians)
  return {
    ix = ix, jx = jx,
    iy = iy, jy = jy,
  }
end

---@param orientation RealOrientation @ Can exceed the usual bounds of RealOrientation.
---@return MatrixIJ matrix
local function rotation_matrix_by_orientation(orientation)
  return rotation_matrix_by_radians(orientation * rad360)
end

---@param ix number @ Top left corner if you think about it like a 2x2 grid.
---@param jx number @ Top right corner if you think about it like a 2x2 grid.
---@param iy number @ Bottom left corner if you think about it like a 2x2 grid.
---@param jy number @ Bottom right corner if you think about it like a 2x2 grid.
---@return MatrixIJ matrix
local function new_matrix(ix, jx, iy, jy)
  return {
    ix = ix, jx = jx,
    iy = iy, jy = jy,
  }
end

---@return MatrixIJ matrix
local function new_identity_matrix()
  return {
    ix = 1, jx = 0,
    iy = 0, jy = 1,
  }
end

---@param matrix MatrixIJ
---@return MatrixIJ
local function copy_matrix(matrix)
  return {
    ix = matrix.ix, jx = matrix.jx,
    iy = matrix.iy, jy = matrix.jy,
  }
end

---Right to left... because math.
---@param second MatrixIJ @ The transformation that should happen after the first one.
---@param first MatrixIJ @ (Gets modified.) The first transformation that should happen.
---@return MatrixIJ first
local function compose_matrices(second, first)
  -- https://www.youtube.com/watch?v=XkY2DOUCWMU&list=PLZHQObOWTQDPD3MizzM2xVFitgF8hE_ab&index=5
  local first_ix, first_jx = second.ix, second.jx
  local first_iy, first_jy = second.iy, second.jy
  local second_ix, second_jx = first.ix, first.jx
  local second_iy, second_jy = first.iy, first.jy
  -- Transform vector first_i using the second matrix. Do the same with vector first_j.
  -- first_i then defines the i vector of the resulting transformation, first_j defines the j vector.
  first.ix = second_ix * first_ix + second_iy * first_jx
  first.iy = second_ix * first_iy + second_iy * first_jy
  first.jx = second_jx * first_ix + second_jy * first_jx
  first.jy = second_jx * first_iy + second_jy * first_jy
  return first
end

---@class VectorLib
local vector_lib = {
  vec_equals = vec_equals,
  matrix_equals = matrix_equals,
  copy = copy,
  is_zero = is_zero,
  get_length = get_length,
  set_length = set_length,
  set_length_safe = set_length_safe,
  normalize = normalize,
  normalize_safe = normalize_safe,
  snap_to_map = snap_to_map,
  add = add,
  sub = sub,
  add_scalar = add_scalar,
  sub_scalar = sub_scalar,
  mul_scalar = mul_scalar,
  div_scalar = div_scalar,
  mod_scalar = mod_scalar,
  pow_scalar = pow_scalar,
  sqrt = sqrt,
  abs = abs,
  floor = floor,
  ceil = ceil,
  min = min,
  max = max,
  dot_product = dot_product,
  get_radians = get_radians,
  get_radians_safe = get_radians_safe,
  get_orientation = get_orientation,
  get_orientation_safe = get_orientation_safe,
  rotate_by_radians = rotate_by_radians,
  rotate_by_orientation = rotate_by_orientation,
  rotate_by_direction = rotate_by_direction,
  transform_by_matrix = transform_by_matrix,
  rotation_matrix_by_radians = rotation_matrix_by_radians,
  rotation_matrix_by_orientation = rotation_matrix_by_orientation,
  new_matrix = new_matrix,
  new_identity_matrix = new_identity_matrix,
  copy_matrix = copy_matrix,
  compose_matrices = compose_matrices,
}
return vector_lib
