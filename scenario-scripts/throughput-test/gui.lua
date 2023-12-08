
---@alias GUIEventHandlerITL fun(player: PlayerDataITL, tags: any, event: EventData)

---"d1c85673" makes it nice and unique
local tags_key = "__d1c85673_"..script.mod_name

---@type table<GUIEventHandlerITL, string>
local handlers_by_func = {}
---@type table<string, GUIEventHandlerITL>
local handlers_by_name = {}

---@type table<defines.events, string>
local event_id_to_name = {}
for name, id in pairs(defines.events) do
  if name:find("^on_gui") then
    event_id_to_name[id] = name
  end
end

---@generic T
---@param name string
---@param handler fun(player: PlayerDataITL, tags: any, event: T)
local function register_handler(name, handler)
  if handlers_by_func[handler] then
    local info = debug.getinfo(handler, "S")
    ---cSpell:ignore linedefined
    error("Attempt to register the handler function "..info.source..":"..info.linedefined
      .." twice. (Handler name: '"..name.."')"
    )
  end
  if handlers_by_name[name] then
    error("Attempt to register 2 handler functions with the name '"..name.."'.")
  end
  handlers_by_func[handler] = name
  handlers_by_name[name] = handler
  return handler
end

---@param element LuaGuiElement
---@return any?
local function try_get_tags(element)
  local tags = element.tags
  if not tags or not tags[tags_key] then return end
  local tag_data = tags[tags_key]
  return tag_data
end

---@param event EventData.on_gui_click @ any gui event
local function handle_gui_event(event)
  if not event.element then return end
  local tags = event.element.tags
  if not tags or not tags[tags_key] then return end
  local tag_data = tags[tags_key]
  local handler_names = tag_data.handlers and tag_data.handlers[event_id_to_name[event.name]]
  if not handler_names then return end
  local player = global.players[event.player_index]
  if not player then return end
  for _, handler_name in pairs(handler_names) do
    local handler = handlers_by_name[handler_name]
    if handler then
      handler(player, tag_data, event)
    end
  end
end

---@param gui_event_define defines.events @ any gui event
local function register_for_gui_event(gui_event_define)
  script.on_event(gui_event_define, handle_gui_event)
end

local function register_for_all_gui_events()
  for name, id in pairs(defines.events) do
    if name:find("^on_gui") then
      register_for_gui_event(id)
    end
  end
end

---@diagnostic disable: duplicate-doc-field

---@class ExtendedLuaGuiElement.add_param : LuaGuiElement.add_param
---@field children ExtendedLuaGuiElement.add_param[]?
---@field tabs {tab: ExtendedLuaGuiElement.add_param, content: ExtendedLuaGuiElement.add_param}[]?
---@field style_mods LuaStyle?
---@field elem_mods LuaGuiElement?
---@field events table<defines.events, GUIEventHandlerITL|(GUIEventHandlerITL[])>

---@param parent_elem LuaGuiElement
---@param args ExtendedLuaGuiElement.add_param
---@param elems table<string, LuaGuiElement>?
---@return LuaGuiElement elem
---@return table<string, LuaGuiElement> inner_elems @
---contains all elements which have a `name`, otherwise `nil`
local function create_elem(parent_elem, args, elems)
  local children = args.children
  local tabs = args.tabs
  local style_mods = args.style_mods
  local elem_mods = args.elem_mods
  local events = args.events
  local tags = args.tags
  args.children = nil
  args.tabs = nil
  args.style_mods = nil
  args.elem_mods = nil
  args.events = nil
  if tags then
    args.tags = {[tags_key] = tags}
  end
  if events then
    local all_handlers = {}
    for event_id, handlers in pairs(events) do
      local event_name = event_id_to_name[event_id]
      local current_handlers = {}
      if type(handlers) == "table" then
        for i, handler in pairs(handlers) do
          current_handlers[tostring(i)] = handlers_by_func[handler]
        end
      else
        current_handlers["1"] = handlers_by_func[handlers]
      end
      all_handlers[event_name] = current_handlers
    end
    args.tags = args.tags or {[tags_key] = {}}
    args.tags[tags_key].handlers = all_handlers
  end
  local elem = parent_elem.add(args)
  if args.name then
    elems = elems or {}
    elems[args.name] = elem
  end
  if style_mods then
    local style = elem.style
    for k, v in pairs(style_mods) do
      style[k] = v
    end
  end
  if elem_mods then
    for k, v in pairs(elem_mods) do
      elem[k] = v
    end
  end
  if children then
    for _, child in pairs(children) do
      _, elems = create_elem(elem, child, elems)
    end
  end
  if tabs then
    for _, tab_def in pairs(tabs) do
      local tab = create_elem(elem, tab_def.tab, elems)
      local content = create_elem(elem, tab_def.content, elems)
      elem.add_tab(tab, content)
    end
  end
  args.children = children
  args.tabs = tabs
  args.style_mods = style_mods
  args.elem_mods = elem_mods
  args.events = events
  args.tags = tags
  if tags then
    tags.handlers = nil
  end
  return elem, elems--[[@as table<string, LuaGuiElement>]]
end

return {
  register_handler = register_handler,
  try_get_tags = try_get_tags,
  handle_gui_event = handle_gui_event,
  register_for_gui_event = register_for_gui_event,
  register_for_all_gui_events = register_for_all_gui_events,
  create_elem = create_elem,
}
