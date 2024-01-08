
if not script.active_mods["inserter-throughput-lib"] then
  error("inserter-throughput-lib is required to load this scenario.")
end

require("__inserter-throughput-lib__.scenario-scripts.splitter-drop-target-test.control")
