
local setups = require("__inserter-throughput-lib__.scenario-scripts.throughput-test.setups")
local configurations = require("__inserter-throughput-lib__.scenario-scripts.throughput-test.configurations")
local inserter_throughput = require("__inserter-throughput-lib__.api")

---@class BuiltSetupITL
---@field parsed_setup ParsedSetupITL
---@field configuration ConfigurationITL
---@field left_top MapPosition
---@field inserter LuaEntity
---@field held_stack LuaItemStack
---@field cycle_count integer
---@field average_total_ticks number
---@field was_valid_for_read boolean
---@field cycle_start integer
---@field average_speed_elem LuaGuiElement
---@field average_speed number? @ items/s. When `nil` then the inserter was either way to slow or it never swung.
---@field estimated_speed number? @ items/s
---items/s. How far off estimated speed is from average measured speed. `nil` when `average_speed` is `nil`.
---@field deviation number?
---@field inserter_throughput_definition InserterThroughputDefinition
---@field best_estimated_speed number? @ items/s
---@field best_deviation number?

---@class PlayerDataITL
---@field player LuaPlayer
---@field player_index integer
---@field progress_bar LuaGuiElement?
---@field progress_bar_frame LuaGuiElement?
---@field overview_frame LuaGuiElement?
---@field average_cubed_deviation_label LuaGuiElement?
---@field average_deviation_label LuaGuiElement?
---@field max_deviation_label LuaGuiElement?
---@field per_setup_estimation_labels table<BuiltSetupITL, LuaGuiElement>
---@field per_setup_deviation_labels table<BuiltSetupITL, LuaGuiElement>

---@class GlobalDataITL
---@field state "idle"|"warming_up"|"measuring"|"iterating"|"done"
---@field players table<integer, PlayerDataITL>
---@field estimation_params table<string, number>
---@field built_setups BuiltSetupITL[] @ Can still contain data even when `setups_are_built` is `false`.
---@field setups_are_built boolean @ As in all the entities (still) exist.
---@field is_overview_shown boolean
---@field state_start_tick integer
---@field state_finish_tick integer
---@field iterations_per_tick integer
---@field best_average_cubed_deviation number? @ Uses absolute values.
---@field best_average_deviation number? @ Uses absolute values.
---@field best_max_deviation number? @ Uses absolute values.
---@field changed_param_key string?
---@field changed_param_value_before number?
---@field changed_param_value_after number?
global = {}

local ev = defines.events
local format = string.format

local slowest_belt = 1/0
for _, belt_speed in pairs(configurations.belt_speeds) do
  slowest_belt = math.min(slowest_belt, belt_speed.belt_speed)
end
local warming_up_duration_ticks = math.ceil(10 / slowest_belt) -- The ticks it takes to fill 10 belts.
local measurement_duration_ticks = 15 * 60

---@param event EventData|{player_index: integer}
---@return PlayerDataITL?
local function get_player(event)
  return global.players[event.player_index]
end

local function estimate_all_inserter_speeds()
  for _, built_setup in pairs(global.built_setups) do
    if built_setup.average_speed then
      local def = built_setup.inserter_throughput_definition
      built_setup.estimated_speed = inserter_throughput.estimate_inserter_speed(def)
    end
  end
end

---@param player PlayerDataITL
local function create_progress_bar(player)
  ---cSpell:ignore progressbar
  player.progress_bar_frame = player.player.gui.screen.add{
    type = "frame",
    caption = (global.state == "measuring")
      and format("Measuring %d setups", #global.built_setups)
      or "Letting belts fill up",
    style = "main_progressbar_frame",
  }
  player.progress_bar_frame.auto_center = true
  player.progress_bar = player.progress_bar_frame.add{
    type = "frame",
    style = "inside_shallow_frame_with_padding",
  }.add{
    type = "progressbar",
  }
  player.progress_bar.style.horizontally_stretchable = true
end

local function create_progress_bars()
  for _, player in pairs(global.players) do
    create_progress_bar(player)
  end
end

---@param player PlayerDataITL
local function destroy_progress_bar(player)
  if player.progress_bar_frame and player.progress_bar_frame.valid then
    player.progress_bar_frame.destroy()
  end
  player.progress_bar_frame = nil
  player.progress_bar = nil
end

local function destroy_progress_bars()
  for _, player in pairs(global.players) do
    destroy_progress_bar(player)
  end
end

local function update_progress_bars()
  for _, player in pairs(global.players) do
    if not player.progress_bar_frame.valid then
      destroy_progress_bar(player)
      create_progress_bar(player)
    end
    local duration = global.state_finish_tick - global.state_start_tick
    player.progress_bar.value = (game.tick - global.state_start_tick) / duration
  end
end

local function calculate_average_speeds()
  for _, built_setup in pairs(global.built_setups) do
    built_setup.average_speed = built_setup.cycle_count >= 3
      and (60 / built_setup.average_total_ticks * built_setup.configuration.stack_size)
      or nil
  end
end

---@return number? average_cubed_deviation
---@return number? average_deviation
---@return number? max_deviation
local function calculate_deviations()
  local total_cubed_deviation = 0
  local total_deviation = 0
  local deviation_count = 0
  local max_deviation = 0
  for _, built_setup in pairs(global.built_setups) do
    if not built_setup.average_speed then
      built_setup.deviation = nil
      goto continue
    end
    built_setup.deviation = built_setup.estimated_speed - built_setup.average_speed
    local abs_deviation = math.abs(built_setup.deviation)
    if abs_deviation > max_deviation then
      max_deviation = abs_deviation
    end
    deviation_count = deviation_count + 1
    total_cubed_deviation = total_cubed_deviation + (abs_deviation ^ 3)
    total_deviation = total_deviation + abs_deviation
    ::continue::
  end
  local average_cubed_deviation = total_cubed_deviation / deviation_count
  local average_deviation = total_deviation / deviation_count
  return average_cubed_deviation, average_deviation, max_deviation
end

---@param player PlayerDataITL
local function update_overview_frame_size(player)
  if not player.overview_frame or not player.overview_frame.valid then return end
  local size = player.player.display_resolution
  size.width = size.width / player.player.display_scale
  size.height = size.height / player.player.display_scale
  player.overview_frame.style.size = size
end

---@param value number?
---@return string
local function format_optional_value(value)
  return value and format("%.6f", value) or "N/A"
end

---@param speed number?
---@return string
local function format_speed(speed)
  return speed and format("%.6f/s", speed) or "N/A"
end

---@param deviation number?
---@return string
local function format_deviation(deviation)
  return not deviation and "N/A"
    or (-0.0000005 < deviation and deviation < 0.0000005) and "=="
    or format(
      deviation > 0 and "[color=#77ff77]%+.6f/s[/color]" or "[color=#ff7777]%+.6f/s[/color]",
      deviation
    )
end

---@param player PlayerDataITL
---@param flow LuaGuiElement
local function create_overview_table(player, flow)
  local deep_frame = flow.add{
    type = "frame",
    style = "inside_deep_frame",
  }
  deep_frame.style.horizontally_stretchable = false
  deep_frame.style.horizontally_squashable = false
  deep_frame.style.vertically_stretchable = true
  local scroll_pane = deep_frame.add{type = "scroll-pane"}
  scroll_pane.style.padding = 4
  local column_count = 7
  local tab = scroll_pane.add{
    type = "table",
    column_count = column_count,
  }
  ---@type LuaStyle
  local table_style = tab.style
  table_style.horizontally_stretchable = true
  table_style.vertically_stretchable = true
  for i = 2, column_count do
    table_style.column_alignments[i] = "right"
  end
  table_style.horizontal_spacing = 12

  local param = {
    type = "label",
    caption = "",
  }
  local add = tab.add

  param.style = "heading_3_label_yellow"
  param.caption = "setup"
  add(param)
  param.caption = "belt"
  add(param)
  param.caption = "inserter"
  add(param)
  param.caption = "stack"
  add(param)
  param.caption = "measured"
  add(param)
  param.caption = "estimated"
  add(param)
  param.caption = "deviation"
  add(param)
  param.style = nil

  local estimation_labels = player.per_setup_estimation_labels
  local deviation_labels = player.per_setup_deviation_labels

  for _, built_setup in pairs(global.built_setups) do
    local config = built_setup.configuration
    param.caption = built_setup.parsed_setup.name
    add(param)
    param.caption = config.belt_name or "-"
    add(param)
    param.caption = config.inserter_name
    add(param)
    param.caption = format("%d stack", config.stack_size)
    add(param)
    param.caption = format_speed(built_setup.average_speed)
    add(param)
    param.caption = format_speed(built_setup.best_estimated_speed)
    estimation_labels[built_setup] = add(param)
    param.caption = format_deviation(built_setup.best_deviation)
    deviation_labels[built_setup] = add(param)
  end
end

---@param player PlayerDataITL
---@param frame LuaGuiElement
local function populate_overview_right_top_panel(player, frame)
  local tab = frame.add{
    type = "table",
    column_count = 2,
  }
  tab.style.horizontally_stretchable = true

  ---@param name string
  ---@param value string
  ---@return LuaGuiElement value_label
  local function add_row(name, value)
    tab.add{
      type = "label",
      caption = name,
      style = "heading_3_label_yellow",
    }.style.horizontally_stretchable = true
    local value_label = tab.add{
      type = "label",
      caption = value,
    }
    value_label.style.horizontally_stretchable = true
    return value_label
  end

  player.average_cubed_deviation_label
    = add_row("Average cubed deviation", format_optional_value(global.best_average_cubed_deviation))
  player.average_deviation_label = add_row("Average deviation", format_speed(global.best_average_deviation))
  player.max_deviation_label = add_row("Max deviation", format_speed(global.best_max_deviation))
end

---@param frame LuaGuiElement
local function populate_overview_right_bottom_panel(frame)
end

---@param player PlayerDataITL
---@param content_flow LuaGuiElement
local function create_overview_right_panels(player, content_flow)
  local panel_flow = content_flow.add{
    type = "flow",
    direction = "vertical",
    style = "inset_frame_container_vertical_flow",
  }
  panel_flow.style.horizontally_stretchable = true
  panel_flow.style.vertically_stretchable = true

  local top_frame = panel_flow.add{
    type = "frame",
    direction = "vertical",
    style = "inside_shallow_frame_with_padding",
  }
  top_frame.style.horizontally_stretchable = true
  top_frame.style.vertically_stretchable = false
  populate_overview_right_top_panel(player, top_frame)

  local bottom_frame = panel_flow.add{
    type = "frame",
    direction = "vertical",
    style = "inside_shallow_frame_with_padding",
  }
  bottom_frame.style.horizontally_stretchable = true
  bottom_frame.style.vertically_stretchable = true
  populate_overview_right_bottom_panel(bottom_frame)
end

---@param player PlayerDataITL
local function create_overview_gui(player)
  player.overview_frame = player.player.gui.screen.add{
    type = "frame",
    direction = "vertical",
  }
  update_overview_frame_size(player)
  local header_flow = player.overview_frame.add{
    type = "flow",
    direction = "horizontal",
  }
  header_flow.style.vertical_align = "center"
  header_flow.add{
    type = "label",
    caption = "Overview",
    style = "heading_1_label",
  }

  local content_flow = player.overview_frame.add{
    type = "flow",
    style = "inset_frame_container_horizontal_flow",
  }
  content_flow.style.horizontally_stretchable = true

  create_overview_table(player, content_flow)
  create_overview_right_panels(player, content_flow)
end

local function create_overview_guis()
  for _, player in pairs(global.players) do
    create_overview_gui(player)
  end
end

---@param player PlayerDataITL
local function update_overview_gui(player)
  if not player.overview_frame or not player.overview_frame.valid then
    create_overview_gui(player)
    return
  end

  player.average_cubed_deviation_label.caption = format_optional_value(global.best_average_cubed_deviation)
  player.average_deviation_label.caption = format_speed(global.best_average_deviation)
  player.max_deviation_label.caption = format_speed(global.best_max_deviation)

  local estimation_labels = player.per_setup_estimation_labels
  local deviation_labels = player.per_setup_deviation_labels
  for _, built_setup in pairs(global.built_setups) do
    estimation_labels[built_setup].caption = format_speed(built_setup.best_estimated_speed)
    deviation_labels[built_setup].caption = format_deviation(built_setup.best_deviation)
  end
end

local function update_overview_guis()
  for _, player in pairs(global.players) do
    update_overview_gui(player)
  end
end

---@param player PlayerDataITL
local function destroy_overview_gui(player)
  if player.overview_frame and player.overview_frame.valid then
    player.overview_frame.destroy()
  end
  player.overview_frame = nil
  player.average_cubed_deviation_label = nil
  player.average_deviation_label = nil
  player.max_deviation_label = nil
  player.per_setup_estimation_labels = {}
  player.per_setup_deviation_labels = {}
end

local function destroy_overview_guis()
  for _, player in pairs(global.players) do
    destroy_overview_gui(player)
  end
end

local function ensure_overviews_are_shown()
  if global.is_overview_shown then return end
  global.is_overview_shown = true
  create_overview_guis()
end

local function ensure_overviews_are_hidden()
  if not global.is_overview_shown then return end
  global.is_overview_shown = false
  destroy_overview_guis()
end

local function randomize_params()
  local keys = {}
  for key in pairs(global.estimation_params) do
    keys[#keys+1] = key
  end
  local key = keys[math.random(#keys)]
  local value = global.estimation_params[key]
  global.estimation_params[key] = value + ((math.random() - 0.5) * 0.1)
  global.changed_param_key = key
  global.changed_param_value_before = value
  global.changed_param_value_after = global.estimation_params[key]
  inserter_throughput.set_params(global.estimation_params)
end

---@param average_cubed_deviation number
---@param average_deviation number
---@param max_deviation number
local function save_best_attempt(average_cubed_deviation, average_deviation, max_deviation)
  global.best_average_cubed_deviation = average_cubed_deviation
  global.best_average_deviation = average_deviation
  global.best_max_deviation = max_deviation
  for _, built_setup in pairs(global.built_setups) do
    built_setup.best_estimated_speed = built_setup.estimated_speed
    built_setup.best_deviation = built_setup.deviation
  end
end

---@param average_cubed_deviation number?
---@param average_deviation number?
---@param max_deviation number?
local function check_if_param_change_attempt_was_good(average_cubed_deviation, average_deviation, max_deviation)
  if not average_deviation or not max_deviation or not average_cubed_deviation then return end
  if average_cubed_deviation < (global.best_average_cubed_deviation or (1/0)) then -- Good attempt, keep it.
    save_best_attempt(average_cubed_deviation, average_deviation, max_deviation)
  else -- Poor attempt, revert it.
    global.estimation_params[global.changed_param_key] = global.changed_param_value_before
    inserter_throughput.set_params(global.estimation_params)
  end
end

---@param active boolean
local function set_active_of_all_inserters(active)
  for _, built_setup in pairs(global.built_setups) do
    built_setup.inserter.active = active
  end
end

local function ensure_all_setups_are_built()
  if global.setups_are_built then return end
  global.setups_are_built = true
  global.built_setups = {}
  setups.build_setups{{pickup_type = "belt"}}
  local nauvis = game.surfaces["nauvis"]
  for _, built_setup in pairs(global.built_setups) do
    local config = built_setup.configuration
    ---@type InserterThroughputDefinition
    local def = {
      extension_speed = config.extension_speed,
      rotation_speed = config.rotation_speed,
      chases_belt_items = true,
      stack_size = config.stack_size,
    }
    -- Cannot use the inserters directly because they need a tick to find their pickup and drop targets.
    inserter_throughput.set_from_based_on_position(
      def,
      nauvis,
      built_setup.inserter.position,
      built_setup.inserter.pickup_position
    )
    inserter_throughput.set_to_based_on_position(
      def,
      nauvis,
      built_setup.inserter.position,
      built_setup.inserter.drop_position
    )
    built_setup.inserter_throughput_definition = def
  end
end

local function ensure_all_setups_are_destroyed()
  if not global.setups_are_built then return end
  global.setups_are_built = false
  game.surfaces["nauvis"].clear()
end

local function pause_game()
  game.speed = 1
  game.tick_paused = true
end

local function unpause_game()
  game.speed = 2 ^ 16 -- Run the game as fast as possible.
  game.tick_paused = false
end

local function built_setups_have_belts()
  for _, built_setup in pairs(global.built_setups) do
    local parsed_setup = built_setup.parsed_setup
    if parsed_setup.pickup_type == "belt" or parsed_setup.drop_type == "belt" then
      return true
    end
  end
end

---@param duration integer
local function init_state_with_progress_bar(duration)
  global.state_start_tick = game.tick
  global.state_finish_tick = game.tick + duration
  create_progress_bars()
end

---@param keep_built_setups boolean?
---@param keep_overviews boolean?
local function switch_to_idle(keep_built_setups, keep_overviews)
  if global.state == "idle" then return end
  pause_game()
  destroy_progress_bars()
  if not keep_built_setups then ensure_all_setups_are_destroyed() end
  if not keep_overviews then ensure_overviews_are_hidden() end
  global.state_start_tick = nil
  global.state_finish_tick = nil
  global.state = "idle"
end

local switch_to_measuring
local function switch_to_warming_up()
  if global.state == "warming_up" then return end
  ensure_all_setups_are_built()
  if not built_setups_have_belts() then
    switch_to_measuring()
    return
  end
  switch_to_idle(true)
  global.state = "warming_up"
  unpause_game()
  set_active_of_all_inserters(false)
  init_state_with_progress_bar(warming_up_duration_ticks) -- After state has been set.
end

function switch_to_measuring()
  if global.state == "measuring" then return end
  switch_to_idle(true)
  global.state = "measuring"
  unpause_game()
  ensure_all_setups_are_built()
  set_active_of_all_inserters(true)
  init_state_with_progress_bar(measurement_duration_ticks) -- After state has been set.
end

local function switch_to_iterating()
  if global.state == "iterating" then return end
  switch_to_idle(false, true)
  global.state = "iterating"
  unpause_game()
  ensure_overviews_are_shown()
end

local function switch_to_done()
  if global.state == "done" then return end
  switch_to_idle(false, true)
  global.state = "done"
  ensure_overviews_are_shown()
end

---A state with a progress bar/meter has filled said progress 100%. What happens next?
local function on_state_progress_finish()
  if global.state == "warming_up" then
    switch_to_measuring()
  elseif global.state == "measuring" then
    calculate_average_speeds()
    switch_to_iterating()
  end
end

---@param player LuaPlayer
local function init_player(player)
  local is_tick_paused = game.tick_paused
  player.toggle_map_editor() -- Have this function do all the work, but retain tick paused state.
  game.tick_paused = is_tick_paused
  local gvs = player.game_view_settings
  gvs.show_controller_gui = false
  gvs.show_minimap = false
  gvs.show_research_info = false
  gvs.show_entity_info = false
  gvs.show_alert_gui = false
  -- gvs.update_entity_selection = false
  gvs.show_rail_block_visualisation = false
  gvs.show_side_menu = false
  gvs.show_map_view_options = false
  gvs.show_quickbar = false
  gvs.show_shortcut_bar = false

  ---@type PlayerDataITL
  local player_data = {
    player = player,
    player_index = player.index,
    per_setup_estimation_labels = {},
    per_setup_deviation_labels = {},
  }
  global.players[player_data.player_index] = player_data

  if global.state == "warming_up" or global.state == "measuring" then
    create_progress_bar(player_data)
  end
end

---@param tick integer
local function update_measuring(tick)
  update_progress_bars()
  for _, built_setup in pairs(global.built_setups) do
    local valid_for_read = built_setup.held_stack.valid_for_read
    if valid_for_read ~= built_setup.was_valid_for_read then
      built_setup.was_valid_for_read = valid_for_read
      if not valid_for_read then
        local cycle_start = built_setup.cycle_start
        built_setup.cycle_start = tick
        if cycle_start < 0 then goto continue end
        local cycle_ticks = tick - cycle_start
        local cycle_count = built_setup.cycle_count
        local new_cycle_count = cycle_count + 1
        built_setup.cycle_count = new_cycle_count
        local average_total_ticks = built_setup.average_total_ticks
        built_setup.average_total_ticks = (average_total_ticks * cycle_count + cycle_ticks) / new_cycle_count
      end
    end
    ::continue::
  end
end

local function update_iterating()
  for _ = 1, global.iterations_per_tick do
    randomize_params()
    estimate_all_inserter_speeds()
    check_if_param_change_attempt_was_good(calculate_deviations())
    -- global.completed_interaction_count = global.completed_interaction_count + 1
  end
  update_overview_guis()
end

script.on_event(ev.on_tick, function(event)
  local tick = event.tick
  if global.state_finish_tick then
    if global.state_finish_tick == tick then
      on_state_progress_finish()
      return
    end
    update_progress_bars()
  end

  if global.state == "measuring" then
    update_measuring(tick)
  elseif global.state == "iterating" then
    update_iterating()
  end
end)

script.on_event(ev.on_player_created, function(event)
  local player = game.get_player(event.player_index) ---@cast player -nil
  init_player(player)
  player.teleport{x = -48, y = -48}
end)

script.on_event({ev.on_player_display_resolution_changed, ev.on_player_display_scale_changed}, function(event)
  local player = get_player(event)
  if not player then return end
  update_overview_frame_size(player)
end)

script.on_init(function()
  ---@type GlobalDataITL
  global = {
    state = (nil)--[[@as string]],
    players = {},
    -- TODO: randomize the starting values using the same rng instance as all future randomization...
    -- with fixed ranges for each parameter. That way a given seed will always behave the same, no matter what
    -- default parameters are currently defined in the inserter throughput api file.
    estimation_params = inserter_throughput.get_params(),
    built_setups = {},
    setups_are_built = false,
    is_overview_shown = false,
    iterations_per_tick = 4,
  }
  for _, player in pairs(game.players) do
    init_player(player)
  end
  switch_to_idle()
  switch_to_warming_up()
end)
