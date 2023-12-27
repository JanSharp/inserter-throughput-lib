
local setups = require("__inserter-throughput-lib__.scenario-scripts.throughput-test.setups")
local configurations = require("__inserter-throughput-lib__.scenario-scripts.throughput-test.configurations")
local gui = require("__inserter-throughput-lib__.scenario-scripts.throughput-test.gui")
local inserter_throughput = require("__inserter-throughput-lib__.api")
local params_util = require("__inserter-throughput-lib__.params_util")

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
---@field left_panel_visible boolean
---@field do_update_left_panel boolean
---@field iterations_per_left_panel_update integer
---@field iterations_at_last_left_panel_update integer?
---@field progress_bar_frame LuaGuiElement?
---@field overview_frame LuaGuiElement?
---@field left_panel_frame LuaGuiElement?
---@field average_cubed_deviation_label LuaGuiElement?
---@field average_deviation_label LuaGuiElement?
---@field max_deviation_label LuaGuiElement?
---@field completed_iterations_label LuaGuiElement?
---@field iterations_per_tick_elems SliderElemsITL?
---@field pause_iteration_after_no_progress_elems SliderElemsITL?
---@field pause_iteration_checkbox LuaGuiElement?
---@field auto_pause_iterations_progress_bar LuaGuiElement?
---@field per_setup_estimation_labels table<BuiltSetupITL, LuaGuiElement>
---@field per_setup_deviation_labels table<BuiltSetupITL, LuaGuiElement>

---@class GlobalDataITL
---@field state "idle"|"warming_up"|"measuring"|"iterating"|"done"
---@field players table<integer, PlayerDataITL>
---@field built_setups BuiltSetupITL[] @ Can still contain data even when `setups_are_built` is `false`.
---@field setups_are_built boolean @ As in all the entities (still) exist.
---@field is_overview_shown boolean
---@field state_start_tick integer
---@field state_finish_tick integer
---@field toggle_measurement_pause_tick integer
---@field current_measurement_pause_index integer
---@field are_inserters_active boolean
---@field iterations_per_tick integer
---@field iteration_is_paused boolean
---@field pause_iteration_after_no_progress integer
---@field random_hash integer
---@field seed integer
---@field rng LuaRandomGenerator?
---@field estimation_params ParamsITL?
---@field best_average_cubed_deviation number? @ Uses absolute values.
---@field best_average_deviation number? @ Uses absolute values.
---@field best_max_deviation number? @ Uses absolute values.
---@field changed_param_key string?
---@field changed_param_value_before number?
---@field changed_param_value_after number?
---@field completed_interaction_count integer?
---@field last_successful_iteration integer?
global = {}

---@class SliderHandlersITL
---@field on_slider GUIEventHandlerITL
---@field on_textfield_changed GUIEventHandlerITL
---@field on_textfield_confirmed GUIEventHandlerITL

---@class SliderElemsITL
---@field slider LuaGuiElement
---@field textfield LuaGuiElement

local ev = defines.events
local format = string.format

local slowest_belt = 1/0
for _, belt_speed in pairs(configurations.belt_speeds) do
  slowest_belt = math.min(slowest_belt, belt_speed.belt_speed)
end
local warming_up_duration_ticks = math.ceil(10 / slowest_belt) -- The ticks it takes to fill 10 belts.
local measurement_duration_between_pauses = 15 * 60
local measurement_pause_durations = {
  1,
  2,
  3,
  5,
  7,
  13,
  17,
  19,
  29,
}
local measurement_duration_ticks = measurement_duration_between_pauses * (#measurement_pause_durations + 1)
for _, pause_duration in pairs(measurement_pause_durations) do
  measurement_duration_ticks = measurement_duration_ticks + pause_duration
end

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
local function populate_left_panel(player)
  local scroll_pane = player.left_panel_frame.add{type = "scroll-pane"}
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
local function toggle_left_panel(player)
  player.left_panel_visible = not player.left_panel_visible
  if not player.overview_frame or not player.left_panel_frame.valid then return end
  if player.left_panel_visible then
    populate_left_panel(player)
    player.left_panel_frame.visible = true
  else
    player.left_panel_frame.visible = false
    player.left_panel_frame.clear()
  end
end

---@param player PlayerDataITL
---@param flow LuaGuiElement
local function create_left_panel(player, flow)
  player.left_panel_frame = flow.add{
    type = "frame",
    style = "inside_deep_frame",
    visible = player.left_panel_visible,
  }
  player.left_panel_frame.style.horizontally_stretchable = false
  player.left_panel_frame.style.horizontally_squashable = false
  player.left_panel_frame.style.vertically_stretchable = true
  if not player.left_panel_visible then return end
  populate_left_panel(player)
end

local set_iteration_is_paused
local switch_to_idle
local switch_to_iterating

---@param seed integer
local function set_seed(seed)
  global.seed = seed
  if global.state == "iterating" then
    switch_to_idle()
    set_iteration_is_paused(false)
    switch_to_iterating()
  end
end

---@param text string
---@return integer?
local function try_parse_seed_text(text)
  local value = tonumber(text)
  if not value or value >= 2^32 then return nil end
  return value
end

local on_seed_text_changed = gui.register_handler(
  "on_seed_text_changed",
  ---@param event EventData.on_gui_text_changed
  function(player, tags, event)
    local elem = event.element
    local value = try_parse_seed_text(elem.text)
    if value then
      elem.style = "long_number_textfield"
    else
      elem.style = "invalid_value_textfield"
      elem.style.width = 150
    end
    elem.style.font = "default-bold"
  end
)

local on_seed_confirmed = gui.register_handler(
  "on_seed_confirmed",
  ---@param event EventData.on_gui_confirmed
  function(player, tags, event)
    local elem = event.element
    local value = try_parse_seed_text(elem.text)
    if not value then return end
    set_seed(value)
  end
)

local on_seed_shuffle_click = gui.register_handler(
  "on_seed_shuffle_click",
  ---@param event EventData.on_gui_click
  function(player, tags, event)
    set_seed(global.random_hash)
  end
)

---@param player PlayerDataITL
---@param frame LuaGuiElement
local function create_top_right_subheader_frame(player, frame)
  gui.create_elem(frame, {
    type = "frame",
    style = "subheader_frame",
    direction = "horizontal",
    style_mods = {horizontally_stretchable = true},
    children = {
      {
        type = "empty-widget",
        style_mods = {horizontally_stretchable = true},
      },
      {
        type = "label",
        style = "caption_label",
        caption = "Seed",
      },
      {
        type = "textfield",
        style = "long_number_textfield",
        text = format("%d", global.seed),
        numeric = true,
        allow_negative = false,
        clear_and_focus_on_right_click = true,
        lose_focus_on_confirm = false, -- Just being explicit.
        events = {
          [ev.on_gui_text_changed] = on_seed_text_changed,
          [ev.on_gui_confirmed] = on_seed_confirmed,
        },
      },
      {
        type = "sprite-button",
        style = "tool_button",
        sprite = "utility/shuffle",
        tooltip = "Generate a new seed and instantly reset and restart iterations with that seed.",
        style_mods = {
          top_margin = 1,
          bottom_margin = -1,
        },
        events = {[ev.on_gui_click] = on_seed_shuffle_click},
      },
    },
  })
end

---@param parent LuaGuiElement
---@param name LocalisedString
---@return LuaGuiElement label
local function add_row_name(parent, name)
  local label = gui.create_elem(parent, {
    type = "label",
    caption = name,
    style = "heading_3_label_yellow",
    style_mods = {
      right_margin = 16,
    },
  })
  return label
end

---@param parent LuaGuiElement
---@param name LocalisedString
---@return LuaGuiElement value_label
local function add_label_row(parent, name, value)
  add_row_name(parent, name)
  local label = parent.add{
    type = "label",
    caption = value,
    style = "heading_3_label_yellow",
  }
  label.style.horizontally_stretchable = true
  return label
end

---@param parent LuaGuiElement
---@param name LocalisedString
---@param value boolean
---@param handler function
---@return LuaGuiElement checkbox
local function add_checkbox_row(parent, name, value, handler)
  add_row_name(parent, name)
  local checkbox = gui.create_elem(parent, {
    type = "checkbox",
    state = value,
    events = {[ev.on_gui_checked_state_changed] = handler},
  })
  return checkbox
end

---@param elems SliderElemsITL
---@param value integer
local function set_slider_elems_value(elems, value)
  elems.slider.slider_value = value
  elems.textfield.text = format("%d", value)
  elems.textfield.style = "short_number_textfield"
end

---@param name string
---@param handler fun(player: PlayerDataITL, value: integer)
---@return SliderHandlersITL
local function register_slider_handlers(name, handler)
  return {
    ---@param event EventData.on_gui_value_changed
    on_slider = gui.register_handler(name.."_slider", function(player, tags, event)
      local elem = event.element
      local value = elem.slider_value
      local tf = elem.parent.slider_textfield
      tf.text = format("%d", value)
      tf.style = "short_number_textfield"
      handler(player, value)
    end),
    ---@param event EventData.on_gui_text_changed
    on_textfield_changed = gui.register_handler(name.."_tf_changed", function(player, tags, event)
      local elem = event.element
      local value = tonumber(elem.text)
      elem.style = value and "short_number_textfield" or "invalid_value_short_number_textfield"
      if not value then return end
      elem.parent.slider_slider.slider_value = value
      handler(player, value)
    end),
    ---@param event EventData.on_gui_confirmed
    on_textfield_confirmed = gui.register_handler(name.."_tf_confirmed", function(player, tags, event)
      local elem = event.element
      local value = tonumber(elem.text)
      if value then return end
      value = tags.default_value
      elem.text = format("%d", value)
      elem.style = "short_number_textfield"
      elem.parent.slider_slider.slider_value = value
      handler(player, value)
    end),
  }
end

---@param parent LuaGuiElement
---@param name LocalisedString
---@param value integer
---@param min integer
---@param max integer
---@param handlers SliderHandlersITL
---@return SliderElemsITL
local function add_slider_row(parent, name, value, min, max, handlers)
  add_row_name(parent, name)
  local _, elems = gui.create_elem(parent, {
    type = "flow",
    direction = "horizontal",
    style_mods = {
      vertical_align = "center",
    },
    children = {
      {
        type = "slider",
        name = "slider_slider",
        value = value,
        minimum_value = min,
        maximum_value = max,
        events = {[ev.on_gui_value_changed] = handlers.on_slider},
      },
      {
        type = "textfield",
        name = "slider_textfield",
        style = "short_number_textfield",
        numeric = true,
        allow_negative = false,
        text = tostring(value),
        lose_focus_on_confirm = true,
        clear_and_focus_on_right_click = true,
        tags = {default_value = value},
        events = {
          [ev.on_gui_text_changed] = handlers.on_textfield_changed,
          [ev.on_gui_confirmed] = handlers.on_textfield_confirmed,
        },
      },
    },
  })
  return {
    slider = elems.slider_slider,
    textfield = elems.slider_textfield,
  }
end

---@param parent LuaGuiElement
---@param name LocalisedString
---@param value number
local function add_progress_bar_row(parent, name, value)
  add_row_name(parent, name)
  local progress_bar = gui.create_elem(parent, {
    type = "progressbar",
    value = value,
    style_mods = {width = 244},
  })
  return progress_bar
end

local on_left_panel_visibility_state_changed = gui.register_handler(
  "on_left_panel_visibility_state_changed",
  ---@param event EventData.on_gui_checked_state_changed
  function(player, tags, event)
    if player.left_panel_visible == event.element.state then return end
    toggle_left_panel(player)
  end
)

local on_left_panel_update_state_changed = gui.register_handler(
  "on_left_panel_update_state_changed",
  ---@param event EventData.on_gui_checked_state_changed
  function(player, tags, event)
    player.do_update_left_panel = event.element.state
  end
)

local iterations_per_left_panel_update_handlers = register_slider_handlers(
  "iterations_per_left_panel_update",
  function(player, value)
    player.iterations_per_left_panel_update = value
  end
)

---@param player PlayerDataITL?
---@return fun(): PlayerDataITL?
local function other_players(player)
  local players = global.players
  local i = 0
  return function()
    i = i + 1
    local other_player = players[i]
    if other_player == player then
      i = i + 1
      other_player = players[i]
    end
    return other_player
  end
end

local iterations_per_tick_handlers = register_slider_handlers(
  "iterations_per_tick",
  function(player, value)
    global.iterations_per_tick = value
    for other_player in other_players(player) do
      set_slider_elems_value(other_player.iterations_per_tick_elems, value)
    end
  end
)

local pause_iteration_after_no_progress_handlers = register_slider_handlers(
  "pause_iteration_after_no_progress",
  function(player, value)
    global.pause_iteration_after_no_progress = value
    for other_player in other_players(player) do
      set_slider_elems_value(other_player.pause_iteration_after_no_progress_elems, value)
    end
  end
)

local function iterations_since_last_success()
  return global.completed_interaction_count - global.last_successful_iteration
end

local function auto_pause_progress()
  return math.min(1, iterations_since_last_success() / global.pause_iteration_after_no_progress)
end

local set_paused_game

---@param paused boolean
---@param source_player PlayerDataITL?
function set_iteration_is_paused(paused, source_player)
  global.iteration_is_paused = paused
  if global.state ~= "iterating" then return end
  set_paused_game(paused)
  for player in other_players(source_player) do
    player.pause_iteration_checkbox.state = paused
  end
  if not paused and auto_pause_progress() == 1 then
    global.last_successful_iteration = global.completed_interaction_count
  end
end

local on_iteration_paused_state_changed = gui.register_handler(
  "on_iteration_paused_state_changed",
  ---@param event EventData.on_gui_checked_state_changed
  function(player, tags, event)
    set_iteration_is_paused(event.element.state, player)
  end
)

local function write_report_file()
  local out = {
    "\n",
    format("-- seed:                    %d\n", global.seed),
    format("-- setup count:             %d\n", #global.built_setups),
    format("-- average cubed deviation: %s\n", format_optional_value(global.best_average_cubed_deviation)),
    format("-- average deviation:       %s\n", format_speed(global.best_average_deviation)),
    format("-- max deviation:           %s\n", format_speed(global.best_max_deviation)),
    format("-- iterations:              %d\n", global.completed_interaction_count),
    "\n",
    "---cSpell:disable\n",
    "\n",
    "return {\n",
  }
  local c = #out
  for key, value in pairs(global.estimation_params) do
    c=c+1;out[c] = format("  %s = %a, -- %.9f\n", key, value, value)
  end
  c=c+1;out[c] = "}\n"
  local report = table.concat(out)
  game.write_file("itl/latest_report.lua", report)
  game.write_file(format("itl/report_%010d.lua", global.seed), report)
end

local on_generate_report_files_click = gui.register_handler(
  "on_generate_report_files_click",
  ---@param event EventData.on_gui_click
  function(player, tags, event)
    write_report_file()
  end
)

---@param player PlayerDataITL
---@param frame LuaGuiElement
local function populate_overview_right_top_panel(player, frame)
  create_top_right_subheader_frame(player, frame)
  local flow_under_subheader = frame.add{
    type = "flow",
    style = "vertical_flow_under_subheader",
    direction = "vertical",
  }
  local tab = flow_under_subheader.add{
    type = "table",
    column_count = 2,
  }
  tab.style.horizontally_stretchable = true

  add_label_row(tab, "Setup count", format("%d", #global.built_setups))
  player.average_cubed_deviation_label
    = add_label_row(tab, "Average cubed deviation", format_optional_value(global.best_average_cubed_deviation))
  player.average_deviation_label
    = add_label_row(tab, "Average deviation", format_speed(global.best_average_deviation))
  player.max_deviation_label
    = add_label_row(tab, "Max deviation", format_speed(global.best_max_deviation))
  player.completed_iterations_label
    = add_label_row(tab, "Completed iterations", format("%d", global.completed_interaction_count))

  player.pause_iteration_checkbox
    = add_checkbox_row(tab, "Pause iteration", global.iteration_is_paused, on_iteration_paused_state_changed)
  player.auto_pause_iterations_progress_bar
    = add_progress_bar_row(tab, "Auto pause progress", auto_pause_progress())

  add_checkbox_row(tab, "Show left panel", player.left_panel_visible, on_left_panel_visibility_state_changed)
  add_checkbox_row(tab, "Update left panel", player.do_update_left_panel, on_left_panel_update_state_changed)
  add_slider_row(tab, "Iterations per left panel update",
    player.iterations_per_left_panel_update, 1, 64,
    iterations_per_left_panel_update_handlers
  )
  player.iterations_per_tick_elems = add_slider_row(tab, "Iterations per tick",
    global.iterations_per_tick, 1, 32,
    iterations_per_tick_handlers
  )
  player.pause_iteration_after_no_progress_elems = add_slider_row(tab, "Pause iteration after no progress",
    global.pause_iteration_after_no_progress, 1, 256,
    pause_iteration_after_no_progress_handlers
  )

  gui.create_elem(flow_under_subheader, {
    type = "button",
    caption = "Generate report files",
    tooltip = "Writes files to script-output",
    events = {[ev.on_gui_click] = on_generate_report_files_click},
  })
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
    style = "inside_shallow_frame",
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

  create_left_panel(player, content_flow)
  create_overview_right_panels(player, content_flow)

  player.iterations_at_last_left_panel_update = global.completed_interaction_count
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
  player.completed_iterations_label.caption = format("%d", global.completed_interaction_count)
  player.auto_pause_iterations_progress_bar.value = auto_pause_progress()

  local iterations_since_last_update = global.completed_interaction_count - player.iterations_at_last_left_panel_update
  if player.do_update_left_panel and player.left_panel_visible
    and iterations_since_last_update >= player.iterations_per_left_panel_update
  then
    local estimation_labels = player.per_setup_estimation_labels
    local deviation_labels = player.per_setup_deviation_labels
    for _, built_setup in pairs(global.built_setups) do
      estimation_labels[built_setup].caption = format_speed(built_setup.best_estimated_speed)
      deviation_labels[built_setup].caption = format_deviation(built_setup.best_deviation)
    end
    player.iterations_at_last_left_panel_update = global.completed_interaction_count
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
  player.completed_iterations_label = nil
  player.iterations_per_tick_elems = nil
  player.pause_iteration_after_no_progress_elems = nil
  player.pause_iteration_checkbox = nil
  player.auto_pause_iterations_progress_bar = nil
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
  local key = keys[global.rng(#keys)]
  local value = global.estimation_params[key]
  global.estimation_params[key] = value + ((global.rng() - 0.5) * (1.001 - auto_pause_progress()) * 0.25)
  global.changed_param_key = key
  global.changed_param_value_before = value
  global.changed_param_value_after = global.estimation_params[key]
  params_util.set_params(global.estimation_params)
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
---@return boolean success
local function check_if_param_change_attempt_was_good(average_cubed_deviation, average_deviation, max_deviation)
  if not average_deviation or not max_deviation or not average_cubed_deviation then return false end
  if average_cubed_deviation < (global.best_average_cubed_deviation or (1/0)) then -- Good attempt, keep it.
    save_best_attempt(average_cubed_deviation, average_deviation, max_deviation)
    return true
  else -- Poor attempt, revert it.
    global.estimation_params[global.changed_param_key] = global.changed_param_value_before
    params_util.set_params(global.estimation_params)
    return false
  end
end

---@param active boolean
local function set_active_of_all_inserters(active)
  for _, built_setup in pairs(global.built_setups) do
    built_setup.inserter.active = active
  end
  global.are_inserters_active = active
end

local function ensure_all_setups_are_built()
  if global.setups_are_built then return end
  global.setups_are_built = true
  global.are_inserters_active = true
  global.built_setups = {}
  setups.build_setups{{pickup_type = "belt", without_output_loader = false}}
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
      built_setup.inserter.pickup_position,
      built_setup.inserter
    )
    inserter_throughput.set_to_based_on_position(
      def,
      nauvis,
      built_setup.inserter.position,
      built_setup.inserter.drop_position,
      built_setup.inserter
    )
    built_setup.inserter_throughput_definition = def
  end
end

local function ensure_all_setups_are_destroyed()
  if not global.setups_are_built then return end
  global.setups_are_built = false
  global.are_inserters_active = nil
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

---@param paused boolean
function set_paused_game(paused)
  if paused then
    pause_game()
  else
    unpause_game()
  end
end

local function generate_initial_estimation_params()
  ---@type ParamsITL
  local params = {}
  for key, min in pairs(params_util.initial_min) do
    local max = params_util.initial_max[key]
    params[key] = min + global.rng() * (max - min)
  end
  global.estimation_params = params
  params_util.set_params(params)
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
function switch_to_idle(keep_built_setups, keep_overviews)
  if global.state == "idle" then return end
  pause_game()
  destroy_progress_bars()
  if not keep_built_setups then ensure_all_setups_are_destroyed() end
  if not keep_overviews then
    ensure_overviews_are_hidden()
    global.rng = nil
    global.estimation_params = nil
    global.best_average_cubed_deviation = nil
    global.best_average_deviation = nil
    global.best_max_deviation = nil
    global.changed_param_key = nil
    global.changed_param_value_before = nil
    global.changed_param_value_after = nil
    global.completed_interaction_count = nil
    global.last_successful_iteration = nil
    for _, player in pairs(global.players) do
      player.iterations_at_last_left_panel_update = nil
    end
    for _, built_setup in pairs(global.built_setups) do
      built_setup.estimated_speed = nil
      built_setup.deviation = nil
      built_setup.best_estimated_speed = nil
      built_setup.best_deviation = nil
    end
  end
  global.state_start_tick = nil
  global.state_finish_tick = nil
  global.toggle_measurement_pause_tick = nil
  global.current_measurement_pause_index = nil
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
  global.toggle_measurement_pause_tick = game.tick + measurement_duration_between_pauses
  global.current_measurement_pause_index = 1
end

function switch_to_iterating()
  if global.state == "iterating" then return end
  switch_to_idle(false, true)
  global.state = "iterating"
  global.rng = game.create_random_generator(global.seed)
  generate_initial_estimation_params()
  global.completed_interaction_count = 0
  global.last_successful_iteration = 0
  set_paused_game(global.iteration_is_paused)
  ensure_overviews_are_shown()
end

---NOTE: This is currently unused. The idea was that once iteration has finished it would switch to this state,
---however as it is right now it's never truly finished. It just pauses automatically, however can be resumed
---at a press of a button.
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

  local player_settings = settings.get_player_settings(player)
  ---@type PlayerDataITL
  local player_data = {
    player = player,
    player_index = player.index,
    per_setup_estimation_labels = {},
    per_setup_deviation_labels = {},
    left_panel_visible = player_settings["itl-show-left-panel"].value--[[@as boolean]],
    do_update_left_panel = player_settings["itl-update-left-panel"].value--[[@as boolean]],
    iterations_per_left_panel_update = player_settings["itl-iterations-per-left-panel-update"].value--[[@as integer]],
  }
  global.players[player_data.player_index] = player_data

  if global.state == "warming_up" or global.state == "measuring" then
    create_progress_bar(player_data)
  end
end

---@param tick integer
local function update_measuring(tick)
  if tick == global.toggle_measurement_pause_tick then
    set_active_of_all_inserters(not global.are_inserters_active)
    global.toggle_measurement_pause_tick = global.are_inserters_active
      and (tick + measurement_duration_between_pauses)
      or (tick + measurement_pause_durations[global.current_measurement_pause_index])
    if not global.are_inserters_active then
      global.current_measurement_pause_index = global.current_measurement_pause_index + 1
      for _, built_setup in pairs(global.built_setups) do
        built_setup.cycle_start = -1
      end
    end
  end
  if not global.are_inserters_active then return end

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
  if global.iteration_is_paused then return end
  for _ = 1, global.iterations_per_tick do
    randomize_params()
    estimate_all_inserter_speeds()
    local success = check_if_param_change_attempt_was_good(calculate_deviations())
    global.completed_interaction_count = global.completed_interaction_count + 1
    if success then
      global.last_successful_iteration = global.completed_interaction_count
    else
      if iterations_since_last_success() >= global.pause_iteration_after_no_progress then
        set_iteration_is_paused(true)
        write_report_file()
        break
      end
    end
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

gui.register_for_all_gui_events()

script.on_event(ev.on_gui_click, function(event)
  global.random_hash = (global.random_hash * 37 + event.tick) % (2^32)
  global.random_hash = (global.random_hash * 37 + game.ticks_played) % (2^32)
  gui.handle_gui_event(event)
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
    random_hash = 23,
    seed = settings.global["itl-seed"].value--[[@as integer]],
    built_setups = {},
    setups_are_built = false,
    is_overview_shown = false,
    iterations_per_tick = settings.global["itl-iterations-per-tick"].value--[[@as integer]],
    pause_iteration_after_no_progress = settings.global["itl-pause-iterations-after-no-progress"].value--[[@as integer]],
    iteration_is_paused = settings.global["itl-pause-iterations"].value--[[@as boolean]],
  }
  for _, player in pairs(game.players) do
    init_player(player)
  end
  switch_to_idle()
  switch_to_warming_up()
end)
