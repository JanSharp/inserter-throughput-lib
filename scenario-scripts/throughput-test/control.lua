
local setups = require("__inserter-throughput-lib__.scenario-scripts.throughput-test.setups")
local inserter_throughput = require("__inserter-throughput-lib__.api")

---@class BuiltSetupITL
---@field parsed_setup ParsedSetupITL
---@field configuration ConfigurationITL
---@field inserter LuaEntity
---@field held_stack LuaItemStack
---@field cycle_count integer
---@field average_total_ticks number
---@field was_valid_for_read boolean
---@field cycle_start integer
---@field average_speed_elem LuaGuiElement
---@field average_speed number? @ items/s. When `nil` then the inserter was either way to slow or it never swung.
---@field estimated_speed number @ items/s

---@class PlayerDataITL
---@field player LuaPlayer
---@field player_index integer
---@field progress_bar LuaGuiElement?
---@field progress_bar_frame LuaGuiElement?
---@field results_frame LuaGuiElement?

---@class GlobalDataITL
---@field players table<integer, PlayerDataITL>
---@field built_setups BuiltSetupITL[]
---@field is_measuring boolean
---@field start_measurement_tick integer
---@field finish_measurement_tick integer
global = {}

local ev = defines.events
local format = string.format

local measurement_duration_ticks = 15 * 60

---@param event EventData|{player_index: integer}
---@return PlayerDataITL?
local function get_player(event)
  return global.players[event.player_index]
end

local function estimate_all_inserter_speeds()
  for _, built_setup in pairs(global.built_setups) do
    local config = built_setup.configuration
    ---@type InserterThroughputDefinition
    local def = {
      extension_speed = config.extension_speed,
      rotation_speed = config.rotation_speed,
      chases_belt_items = true,
      stack_size = config.stack_size,
    }
    inserter_throughput.set_from_based_on_inserter(def, built_setup.inserter)
    inserter_throughput.set_to_based_on_inserter(def, built_setup.inserter)
    built_setup.estimated_speed = inserter_throughput.estimate_inserter_speed(def)
  end
end

---@param player PlayerDataITL
local function create_progress_bar(player)
  ---cSpell:ignore progressbar
  player.progress_bar_frame = player.player.gui.screen.add{
    type = "frame",
    caption = "Measuring",
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
  if player.progress_bar_frame.valid then
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
    player.progress_bar.value = (game.tick - global.start_measurement_tick) / measurement_duration_ticks
  end
end

local function calculate_average_speeds()
  for _, built_setup in pairs(global.built_setups) do
    built_setup.average_speed = built_setup.cycle_count >= 3
      and (60 / built_setup.average_total_ticks * built_setup.configuration.stack_size)
      or nil
  end
end

---@param player PlayerDataITL
local function update_results_frame_size(player)
  if not player.results_frame or not player.results_frame.valid then return end
  local size = player.player.display_resolution
  size.width = size.width / player.player.display_scale
  size.height = size.height / player.player.display_scale
  player.results_frame.style.size = size
end

---@param player PlayerDataITL
local function create_results_gui(player)
  player.results_frame = player.player.gui.screen.add{
    type = "frame",
    direction = "vertical",
  }
  update_results_frame_size(player)
  local header_flow = player.results_frame.add{
    type = "flow",
    direction = "horizontal",
  }
  header_flow.style.vertical_align = "center"
  header_flow.add{
    type = "label",
    caption = "Results",
    style = "heading_1_label",
  }
  local deep_frame = player.results_frame.add{
    type = "frame",
    style = "inside_deep_frame",
  }
  local scroll_pane = deep_frame.add{
    type = "scroll-pane",
  }
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

  local total_deviation = 0
  local deviation_count = 0
  local max_deviation = 0

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
    param.caption = built_setup.average_speed and format("%.6f/s", built_setup.average_speed) or "N/A"
    add(param)
    param.caption = format("%.6f/s", built_setup.estimated_speed)
    add(param)
    if built_setup.average_speed then
      local deviation = built_setup.estimated_speed - built_setup.average_speed
      local abs_deviation = deviation < 0 and - deviation or deviation
      if abs_deviation > max_deviation then
        max_deviation = abs_deviation
      end
      deviation_count = deviation_count + 1
      total_deviation = total_deviation + abs_deviation
      param.caption = (-0.0000005 < deviation and deviation < 0.0000005) and "=="
        or format(
          deviation > 0 and "[color=#77ff77]%+.6f/s[/color]" or "[color=#ff7777]%+.6f/s[/color]",
          deviation
        )
      add(param)
    else
      param.caption = "N/A"
      add(param)
    end
  end

  local function add_deviation_to_header(caption, deviation)
    header_flow.add{
      type = "label",
      caption = caption,
      style = "heading_3_label_yellow",
    }.style.left_margin = 32
    header_flow.add{
      type = "label",
      caption = format("%.6f/s", deviation),
    }
  end

  add_deviation_to_header("Average deviation:", total_deviation / deviation_count)
  add_deviation_to_header("Max deviation:", max_deviation)
end

local function create_results_guis()
  for _, player in pairs(global.players) do
    create_results_gui(player)
  end
end

local function start_measurement()
  global.start_measurement_tick = game.tick
  global.finish_measurement_tick = game.tick + measurement_duration_ticks
  global.is_measuring = true
  create_progress_bars()
  game.speed = 2 ^ 16 -- Run the game as fast as possible.
  game.tick_paused = false
end

local function finish_measurements()
  global.start_measurement_tick = nil
  global.finish_measurement_tick = nil
  global.is_measuring = false
  destroy_progress_bars()
  calculate_average_speeds()
  create_results_guis()
  game.tick_paused = true
  game.speed = 1
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
  }
  global.players[player_data.player_index] = player_data

  if global.is_measuring then
    create_progress_bar(player_data)
  end
end

script.on_event(ev.on_tick, function(event)
  local tick = event.tick
  if global.finish_measurement_tick == tick then
    finish_measurements()
    return
  end

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
end)

script.on_event(ev.on_player_created, function(event)
  local player = game.get_player(event.player_index) ---@cast player -nil
  init_player(player)
  player.teleport{x = -48, y = -48}
end)

script.on_event({ev.on_player_display_resolution_changed, ev.on_player_display_scale_changed}, function(event)
  local player = get_player(event)
  if not player then return end
  update_results_frame_size(player)
end)

script.on_init(function()
  ---@type GlobalDataITL
  global = {
    players = {},
    built_setups = {},
    is_measuring = false,
  }
  for _, player in pairs(game.players) do
    init_player(player)
  end
  setups.build_setups{{pickup_type = "belt"}}
  print("Total amount of setups: "..#global.built_setups)
  estimate_all_inserter_speeds()
  start_measurement()
end)
