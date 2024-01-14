
-- This file is not included in the packaged mod.

assert(mods["base"], "Testing inserter throughput lib requires the base mod to be enabled.")

local util = require("__core__.lualib.util")
local configurations = require("__inserter-throughput-lib__.scenario-scripts.throughput-test.configurations")

local max_stack_size = math.max(table.unpack(configurations.stack_sizes))

for _, inserter_speed in pairs(configurations.inserter_speeds) do
  local inserter = util.copy(data.raw["inserter"]["inserter"])
  inserter.allow_custom_vectors = true
  inserter.name = inserter_speed.name
  inserter.rotation_speed = inserter_speed.rotation_speed
  inserter.extension_speed = inserter_speed.extension_speed
  inserter.stack_size_bonus = max_stack_size - 1
  inserter.energy_source = {type = "void"}
  data:extend{inserter}
end

for _, belt_speed in pairs(configurations.belt_speeds) do
  local belt = util.copy(data.raw["transport-belt"]["transport-belt"])
  belt.name = belt_speed.name
  belt.speed = belt_speed.belt_speed

  local loader = util.copy(data.raw["loader-1x1"]["loader-1x1"])
  loader.name = belt_speed.name.."-loader"
  loader.speed = belt_speed.belt_speed
  loader.structure.direction_in = util.empty_sprite(1)
  loader.structure.direction_out = util.empty_sprite(1)

  local splitter = util.copy(data.raw["splitter"]["splitter"])
  splitter.name = belt_speed.name.."-splitter"
  splitter.speed = belt_speed.belt_speed

  local underground = util.copy(data.raw["underground-belt"]["underground-belt"])
  underground.name = belt_speed.name.."-underground"
  underground.speed = belt_speed.belt_speed

  data:extend{belt, loader, splitter, underground}
end

data.raw["editor-controller"]["default"].generate_neighbor_chunks = false

local infinity_chest = util.copy(data.raw["infinity-container"]["infinity-chest"])
infinity_chest.name = "itl-infinity-chest"
infinity_chest.inventory_size = 1 -- Improves performance by 35% in total (so game update).
data:extend{infinity_chest}

local splitter_drop_target_test_inserter = util.copy(data.raw["inserter"]["inserter"])
splitter_drop_target_test_inserter.name = "splitter-drop-target-test"
splitter_drop_target_test_inserter.allow_custom_vectors = true
splitter_drop_target_test_inserter.energy_source = {type = "void"}
splitter_drop_target_test_inserter.rotation_speed = 1024
splitter_drop_target_test_inserter.extension_speed = 1024
splitter_drop_target_test_inserter.stack_size_bonus = 1
data:extend{splitter_drop_target_test_inserter}

local ungodly_slow_splitter = util.copy(data.raw["splitter"]["splitter"])
ungodly_slow_splitter.name = "ungodly-slow-splitter"
ungodly_slow_splitter.speed = 1/256--0.25--
ungodly_slow_splitter.structure = util.empty_sprite(1)
ungodly_slow_splitter.structure_patch = util.empty_sprite(1)
data:extend{ungodly_slow_splitter}
