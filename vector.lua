
---Only accepts tables taking the xy form, not arrays.
---@alias VectorXY Vector|MapPosition

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

---@generic T : VectorXY
---@param vector T
---@return T
local function copy(vector) ---@cast vector VectorXY
  return {x = vector.x, y = vector.y}
end

---@param vector VectorXY
---@return number
local function get_length(vector)
  local x, y = vector.x, vector.y
  return math_sqrt(x * x + y * y)
end

---@generic T : VectorXY
---@param vector T @ Gets modified.
---@param length number
---@return T vector
local function set_length(vector, length) ---@cast vector VectorXY
  local multiplier = length / get_length(vector)
  vector.x = vector.x * multiplier
  vector.y = vector.y * multiplier
  return vector
end

---@generic T : VectorXY
---@param vector T @ Gets modified.
---@param length number? @ Precalculated length if available.
---@return T vector
local function normalize(vector, length) ---@cast vector VectorXY
  length = length or get_length(vector)
  vector.x = vector.x / length
  vector.y = vector.y / length
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

---North is 0, goes clockwise, always positive.
---@param vector VectorXY
---@return number
local function get_radians(vector)
  -- https://stackoverflow.com/questions/283406/what-is-the-difference-between-atan-and-atan2-in-c
  -- x and y are flipped because in Factorio north is 0.
  -- Lua's modulo always returns a positive number. This is making use of that to turn the -180 to 180 range.
  -- into a 0 to 360 range.
  return math_atan2(vector.x, -vector.y) % rad360
end

---Returns a RealOrientation, so [0, 1) where 0 is north, 0.25 is east, 0.5 is south, 0.75 is west.
---@param vector VectorXY
---@return RealOrientation
local function get_orientation(vector)
  -- See comments in `radians`.
  return (math_atan2(vector.x, -vector.y) % rad360) / rad360
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
local function rotation_matrix_by_radians(radians)
  local ix, jx,
        iy, jy = get_rotation_matrix_values(radians)
  return {
    ix = ix, jx = jx,
    iy = iy, jy = jy,
  }
end

---@param orientation RealOrientation @ Can exceed the usual bounds of RealOrientation.
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
  dot_product = dot_product,
  get_radians = get_radians,
  get_orientation = get_orientation,
  rotate_by_radians = rotate_by_radians,
  rotate_by_orientation = rotate_by_orientation,
  transform_by_matrix = transform_by_matrix,
  rotation_matrix_by_radians = rotation_matrix_by_radians,
  rotation_matrix_by_orientation = rotation_matrix_by_orientation,
  new_matrix = new_matrix,
  new_identity_matrix = new_identity_matrix,
  copy_matrix = copy_matrix,
  compose_matrices = compose_matrices,
}
