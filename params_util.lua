
---@class ParamsITL
local current = {
  extension_belt_offset = 0.5,
  rotation_belt_offset = 0.5,
  item_length_for_rotation = 0.25,
}

local initial_min = {
  extension_belt_offset = 0.1,
  rotation_belt_offset = 0.1,
  item_length_for_rotation = 0.05,
}

local initial_max = {
  extension_belt_offset = 1,
  rotation_belt_offset = 1,
  item_length_for_rotation = 0.5,
}

---@type fun(params: ParamsITL)[]
local listeners = {}

---Do not modify the returned table. Or if you do, call set_params right after.
---@return ParamsITL
local function get_params()
  return current
end

---Do not modify params after this call. Or if you do, call set_params again right after.
---@param params ParamsITL
local function set_params(params)
  current = params
  for _, listener in pairs(listeners) do
    listener(current)
  end
end

---@param listener fun(params: ParamsITL) @ Must not modify `params` in the listener.
local function on_params_set(listener)
  listeners[#listeners+1] = listener
end

return {
  get_params = get_params,
  set_params = set_params,
  on_params_set = on_params_set,
  initial_min = initial_min,
  initial_max = initial_max,
}
