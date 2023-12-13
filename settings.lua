
data:extend({
  {
    type = "bool-setting",
    name = "itl-show-left-panel",
    localised_name = "Show left panel",
    localised_description = "Only used on player creation.",
    order = "a",
    setting_type = "runtime-per-user",
    default_value = false,
  },
  {
    type = "bool-setting",
    name = "itl-update-left-panel",
    localised_name = "Update left panel",
    localised_description = "Only used on player creation.",
    order = "b",
    setting_type = "runtime-per-user",
    default_value = true,
  },
  {
    type = "int-setting",
    name = "itl-iterations-per-left-panel-update",
    localised_name = "Iterations per left panel update",
    localised_description = "Only used on player creation.",
    order = "c",
    setting_type = "runtime-per-user",
    default_value = 16,
    minimum_value = 1,
  },
  {
    type = "int-setting",
    name = "itl-iterations-per-tick",
    localised_name = "Iterations per tick",
    localised_description = "Only used on init.",
    order = "d",
    setting_type = "runtime-global",
    default_value = 4,
    minimum_value = 1,
  },
  {
    type = "int-setting",
    name = "itl-pause-iterations-after-no-progress",
    localised_name = "Pause iterations after no progress",
    localised_description = "Only used on init.",
    order = "e",
    setting_type = "runtime-global",
    default_value = 256,
    minimum_value = 1,
  },
  {
    type = "bool-setting",
    name = "itl-pause-iterations",
    localised_name = "Pause iterations",
    localised_description = "Only used on init.",
    order = "f",
    setting_type = "runtime-global",
    default_value = false,
  },
  {
    type = "int-setting",
    name = "itl-seed",
    localised_name = "Seed",
    localised_description = "Only used on init.",
    order = "g",
    setting_type = "runtime-global",
    default_value = 123456789,
    minimum_value = 1,
    maximum_value = 2^32-1,
  },
})
