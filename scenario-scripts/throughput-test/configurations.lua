
local belt_speeds = {
  {
    name = "itl-sleepy-belt",
    belt_speed = 0.03125 / 2,
  },
  {
    name = "itl-transport-belt",
    belt_speed = 0.03125 * 1,
  },
  {
    name = "itl-fast-transport-belt",
    belt_speed = 0.03125 * 2,
  },
  {
    name = "itl-express-transport-belt",
    belt_speed = 0.03125 * 3,
  },
  -- {
  --   name = "itl-speedy-belt",
  --   belt_speed = 0.03125 * 4,
  -- },
  {
    name = "itl-insane-belt",
    belt_speed = 0.03125 * 5,
  },
  -- {
  --   name = "itl-unthinkable-belt",
  --   belt_speed = 0.03125 * 6,
  -- },
}

local inserter_speeds = {
  -- { -- super slow inserter
  --   name = "itl-super-slow-inserter",
  --   rotation_speed = 0.0075,
  --   extension_speed = 0.0175,
  -- },
  { -- burner-inserter
    name = "itl-burner-inserter",
    rotation_speed = 0.01,
    extension_speed = 0.0214,
  },
  { -- inserter
    name = "itl-inserter",
    rotation_speed = 0.014,
    extension_speed = 0.03,
  },
  { -- long-handed-inserter
    name = "itl-long-handed-inserter",
    rotation_speed = 0.02,
    extension_speed = 0.0457,
  },
  { -- fast-inserter, filter-inserter, stack-inserter, stack-filter-inserter
    name = "itl-fast-inserter",
    rotation_speed = 0.04,
    extension_speed = 0.07,
  },
  -- { -- super fast inserter
  --   name = "itl-super-fast-inserter",
  --   rotation_speed = 0.065,
  --   extension_speed = 0.1,
  -- },
}

local stack_sizes = {
  1,
  -- 2,
  3,
  -- 7,
  12,
  -- 17,
}

---@class ConfigurationITL
---@field belt_speed number
---@field rotation_speed number
---@field extension_speed number
---@field stack_size integer
---@field belt_name string
---@field loader_name string
---@field splitter_name string
---@field underground_name string
---@field inserter_name string

---@type ConfigurationITL[]
local configurations = {}

for _, belt_speed in pairs(belt_speeds) do
  for _, inserter_speed in pairs(inserter_speeds) do
    for _, stack_size in pairs(stack_sizes) do
      configurations[#configurations+1] = {
        belt_speed = belt_speed.belt_speed,
        rotation_speed = inserter_speed.rotation_speed,
        extension_speed = inserter_speed.extension_speed,
        stack_size = stack_size,
        belt_name = belt_speed.name,
        loader_name = belt_speed.name.."-loader",
        splitter_name = belt_speed.name.."-splitter",
        underground_name = belt_speed.name.."-underground",
        inserter_name = inserter_speed.name,
      }
    end
  end
end

return {
  belt_speeds = belt_speeds,
  inserter_speeds = inserter_speeds,
  stack_sizes = stack_sizes,
  configurations = configurations,
}
