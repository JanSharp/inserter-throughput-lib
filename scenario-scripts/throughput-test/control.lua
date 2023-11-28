
local setups = require("__inserter-throughput-lib__.scenario-scripts.throughput-test.setups")

local ev = defines.events

script.on_event(ev.on_player_created, function(event)
  local player = game.get_player(event.player_index) ---@cast player -nil
  player.toggle_map_editor()
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
end)

script.on_init(function()
  setups.build_all_setups()
end)
