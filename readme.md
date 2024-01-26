
# Introduction

Determining the throughput of inserters is a fairly common problem in Factorio, both for players and for mod creators, yet it is a very difficult problem to solve.

This library aims to provide mod creators with reasonable throughput estimates for use in their mods.

# Technical Background

The throughput of inserters can actually be calculated very accurately in many setups. Especially when it comes to dropping items it can all be calculated, the only tricky situations being dropping to splitters. Dropping to loaders which take items from the belt is also awkward, but this is much less common at least.

The major difficulty with calculation originates from belt item chasing. In other words, picking items up from any belt connectable. There are many variable which influence how long it takes an inserter to pick up an item from a belt, leaving just 2 options for calculation: Simulation or estimation.

Simulation is out of the question. I could just leave it at that, but if you are curious there are at least 4 reasons: Reimplementing item chasing exactly the way it works in game would take a long time, and would be so implementation dependent that any micro change to the game would invalidate the simulation. So while possible, it'd be really bad for maintainability. The second reason is performance. Without going into detail, there are inserters out there with over 100 stack sizes, requiring long simulations. And the third reason is that inserters behave differently when picking up from belts depending on timing. It may require multiple simulations with different item timings on the belt to determine accurate enough throughput... but wait, at that point it's just an estimate. And inserters can get stuck chasing items, never picking any up, so it would need a timeout as well. There are just too many issues with simulation making it not feasible.

That leaves estimation. More specifically a bit of math trying to get close to real values. To get closer to real values the algorithm can be parametrized and then run through iterations with different values for those parameters, comparing estimated values with real measured values. The result is a few magic values with which the algorithm is tuned to be a little bit more accurate.

# API

The inserter throughput api consists of 3 parts: utility, definition creation and estimation.

The vector api mainly contains vector functions, with a few 2x2 matrix functions mixed in.

## Overview

### Inserter Throughput API

The estimation function takes a definition table which contains all necessary data for the estimation. This definition does not contain any references to entities or prototypes. Therefore the definition table gets created beforehand through definition creation functions (or manually, technically). Nearly all of these functions only set a part of the definition, referred to as setter functions.

Apart from that there are a few utility functions in relation to inserter pickup and drop targets, stack sizes and default positions. They are used internally, however they are also exposed in the api for more flexibility.

The definition table consists of 3 parts: inserter data, pickup data, drop data.

The majority of the definition creation functions only set 1 of those 3 parts in the definition table. The only exceptions are 1 function which sets all 3, and a few which set pickup or drop data, and then also set the pickup or drop vector inside of the inserter data.

The estimation function does not modify the definition allowing for reuse of the same definition table. The setter functions also accept a given part of the definition table being set already, they will simply clear out the old data and set new data.

### Vector API

When working with inserter pickup and drop positions, a vector library tends to be quite useful.

It tries to strike a balance between usability and performance:

- Every function expects positions or vectors using `x` and `y` fields. Arrays as positions are not accepted.
- It modifies a given table instead of creating a new one whenever possible to reduce the amount of table allocations. Use `vec.copy` on the argument when modifying is undesired.
- There are no metatables. Addition takes the form `vec.add(left, right)` for example.

## Usage

This mod contains two files which are public api:

- `local inserter_throughput = require("__inserter-throughput-lib__.inserter_throughput")`
- `local vec = require("__inserter-throughput-lib__.vector")`

`local inserter_throughput` is quite a long name and many times more verbose than necessary. Feel free to shorten it to `local ins_throughput` or `local throughput` or whatever feels right. Even `local itl` for inserter throughput library is an option, but I'd warn you about using too many acronyms in code. It'll quickly become hard to read.

## Documentation through Annotations

This mod contains type annotations for the [LuaLS](https://github.com/LuaLS/lua-language-server). If you are using said language server I would recommend to **extract this mod** and put it in a place the language server can see, such as the workspace itself or in a library path of the language server. I **recommend against cloning the source** because it contains dev only test files which create several prototypes and modify the editor controller.

If you are not seeing type information on the return value of `require("__inserter-throughput-lib__.inserter_throughput")` you can try adding `---@type InserterThroughputLib` at the end of that line (or on a new line above). Same goes for the `vector` file, use `---@type VectorLib` for that.

For completeness I'll also point you to [FMTK](https://github.com/justarandomgeek/vscode-factoriomod-debug/blob/current/doc/workspace.md) which has support for LuaLS as well, and this mod is using some of the type definitions that FMTK generates from the machine readable documentation of Factorio, such as LuaEntity, LuaEntityPrototype or MapPosition, etc.

## Example

Print inserter throughput to chat whenever the player hovers an inserter. (The hello world for this library :P)

```lua
local inserter_throughput = require("__inserter-throughput-lib__.inserter_throughput")

script.on_event(defines.events.on_selected_entity_changed, function(event)
  local player = game.get_player(event.player_index) ---@cast player -nil
  local selected = player.selected
  if not selected then return end
  local entity_type = inserter_throughput.get_real_or_ghost_entity_type(selected)
  if entity_type ~= "inserter" then return end
  local def = inserter_throughput.make_full_definition_for_inserter(selected)
  local items_per_second = inserter_throughput.estimate_inserter_speed(def)
  local is_estimate = inserter_throughput.is_estimate(def)
  player.print(string.format(
    "Inserter speed: %s%.3f/s",
    is_estimate and "~ " or "",
    items_per_second
  ))
end)
```

## Data Structures

- [`InserterThroughputTargetType`](#inserterthroughputtargettype)
- [`InserterThroughputDefinition`](#inserterthroughputdefinition)
- [`InserterThroughputInserterDefinition`](#inserterthroughputinserterdefinition)
- [`InserterThroughputLoaderDefinitionBase`](#inserterthroughputloaderdefinitionbase)
- [`InserterThroughputPickupDefinition`](#inserterthroughputpickupdefinition)
- [`InserterThroughputDropDefinition`](#inserterthroughputdropdefinition)
- [`VectorXY`](#vectorxy)
- [`MatrixIJ`](#matrixij)

## Estimation Functions

- [`estimate_inserter_speed`](#estimate_inserter_speed)
- [`is_estimate`](#is_estimate)

## Definition Creation Functions

### Definition

- [`make_empty_definition`](#make_empty_definition)
- [`make_full_definition_for_inserter`](#make_full_definition_for_inserter)

### Inserter Data

- [`inserter_data_based_on_prototype`](#inserter_data_based_on_prototype)
- [`inserter_data_based_on_entity`](#inserter_data_based_on_entity)

### Pickup Data

- [`pickup_from_inventory`](#pickup_from_inventory)
- [`pickup_from_ground`](#pickup_from_ground)
- [`pickup_from_belt`](#pickup_from_belt)
- [`pickup_from_linked_belt`](#pickup_from_linked_belt)
- [`pickup_from_underground`](#pickup_from_underground)
- [`pickup_from_splitter`](#pickup_from_splitter)
- [`pickup_from_loader`](#pickup_from_loader)
- [`pickup_from_entity`](#pickup_from_entity)
- [`pickup_from_position`](#pickup_from_position)
- [`pickup_from_position_and_set_pickup_vector`](#pickup_from_position_and_set_pickup_vector)
- [`pickup_from_pickup_target_of_inserter`](#pickup_from_pickup_target_of_inserter)
- [`pickup_from_pickup_target_of_inserter_and_set_pickup_vector`](#pickup_from_pickup_target_of_inserter_and_set_pickup_vector)

### Drop Data

- [`drop_to_inventory`](#drop_to_inventory)
- [`drop_to_ground`](#drop_to_ground)
- [`drop_to_belt`](#drop_to_belt)
- [`drop_to_linked_belt`](#drop_to_linked_belt)
- [`drop_to_underground`](#drop_to_underground)
- [`drop_to_splitter`](#drop_to_splitter)
- [`drop_to_loader`](#drop_to_loader)
- [`drop_to_entity`](#drop_to_entity)
- [`drop_to_position`](#drop_to_position)
- [`drop_to_position_and_set_drop_vector`](#drop_to_position_and_set_drop_vector)
- [`drop_to_drop_target_of_inserter`](#drop_to_drop_target_of_inserter)
- [`drop_to_drop_target_of_inserter_and_set_drop_vector`](#drop_to_drop_target_of_inserter_and_set_drop_vector)

## Utility Functions

- [`get_real_or_ghost_entity_type`](#get_real_or_ghost_entity_type)
- [`get_real_or_ghost_entity_prototype`](#get_real_or_ghost_entity_prototype)
- [`get_target_type`](#get_target_type)
- [`is_belt_connectable_target_type`](#is_belt_connectable_target_type)
- [`get_pickup_vector`](#get_pickup_vector)
- [`get_drop_vector`](#get_drop_vector)
- [`get_default_inserter_position_in_tile`](#get_default_inserter_position_in_tile)
- [`get_position_in_tile`](#get_position_in_tile)
- [`get_stack_size_for_prototype`](#get_stack_size_for_prototype)
- [`get_stack_size`](#get_stack_size)
- [`is_placeable_off_grid`](#is_placeable_off_grid)
- [`snap_build_position`](#snap_build_position)
- [`normalize_belt_speed`](#normalize_belt_speed)

## Vector Functions

- [`vec_equals`](#vec_equals)
- [`matrix_equals`](#matrix_equals)
- [`copy`](#copy)
- [`get_length`](#get_length)
- [`set_length`](#set_length)
- [`normalize`](#normalize)
- [`snap_to_map`](#snap_to_map)
- [`add`](#add)
- [`sub`](#sub)
- [`add_scalar`](#add_scalar)
- [`sub_scalar`](#sub_scalar)
- [`mul_scalar`](#mul_scalar)
- [`div_scalar`](#div_scalar)
- [`mod_scalar`](#mod_scalar)
- [`dot_product`](#dot_product)
- [`get_radians`](#get_radians)
- [`get_orientation`](#get_orientation)
- [`rotate_by_radians`](#rotate_by_radians)
- [`rotate_by_orientation`](#rotate_by_orientation)
- [`rotate_by_direction`](#rotate_by_direction)
- [`transform_by_matrix`](#transform_by_matrix)
- [`rotation_matrix_by_radians`](#rotation_matrix_by_radians)
- [`rotation_matrix_by_orientation`](#rotation_matrix_by_orientation)
- [`new_matrix`](#new_matrix)
- [`new_identity_matrix`](#new_identity_matrix)
- [`copy_matrix`](#copy_matrix)
- [`compose_matrices`](#compose_matrices)

## All Data Structures

### InserterThroughputTargetType

Alias of:

- `"inventory"`
- `"ground"`
- `"belt"`
- `"linked-belt"`
- `"underground"`
- `"splitter"`
- `"loader"`

### InserterThroughputDefinition

- `inserter` :: [`InserterThroughputInserterDefinition`](#inserterthroughputinserterdefinition)\
  Functions setting fields in this table accept it being `nil`, they'll simply create the table. The estimate functions however require this table to be non `nil`.
- `pickup` :: [`InserterThroughputPickupDefinition`](#inserterthroughputpickupdefinition)\
  Functions setting fields in this table accept it being `nil`, they'll simply create the table. The estimate functions however require this table to be non `nil`.
- `drop` :: [`InserterThroughputDropDefinition`](#inserterthroughputdropdefinition)\
  Functions setting fields in this table accept it being `nil`, they'll simply create the table. The estimate functions however require this table to be non `nil`.

### InserterThroughputInserterDefinition

- `extension_speed` :: `number`\
  Tiles per tick.
- `rotation_speed` :: `number`\
  [`RealOrientation`](https://lua-api.factorio.com/latest/concepts.html#RealOrientation) per tick.
- `stack_size` :: `integer`\
  Must be at least 1.
- `pickup_vector` :: [`VectorXY`](#vectorxy)\
  Relative to inserter position.
- `drop_vector` :: [`VectorXY`](#vectorxy)\
  Relative to inserter position.
- `chases_belt_items` :: `boolean`\
  [`InserterPrototype::chases_belt_items`](https://lua-api.factorio.com/latest/prototypes/InserterPrototype.html#chases_belt_items).
- `inserter_position_in_tile` :: [`VectorXY`](#vectorxy)?\
  Modulo (%) 1 of x and y of the inserter's position.

### InserterThroughputLoaderDefinitionBase

Abstract.

- `loader_type` :: `"input"|"output"?`\
  [`LuaEntity::loader_type`](https://lua-api.factorio.com/latest/classes/LuaEntity.html#loader_type). `"input"`: items flow into the loader, `"output"`: items flow out of the loader.
- `loader_belt_length` :: `number`?\
  [`LuaEntityPrototype::belt_length`](https://lua-api.factorio.com/latest/classes/LuaEntityPrototype.html#belt_length).
- `loader_tile_distance_from_belt_start` :: `integer`?\
  How many tiles is the drop distance away from the actual belt of the loader? When dropping onto the tile of a 1x2 loader which is next to a container, this is `1`. When dropping onto the tile where items get put onto or taken from the belt, this is 0.

### InserterThroughputPickupDefinition

Inherits [`InserterThroughputLoaderDefinitionBase`](#inserterthroughputloaderdefinitionbase).

- `target_type` :: [`InserterThroughputTargetType`](#inserterthroughputtargettype)
- `belt_speed` :: `number`?\
  Tiles per tick of each item on the belt being picked up from.\
  Required for all belt connectables.
- `belt_direction` :: [`defines.direction`](https://lua-api.factorio.com/latest/defines.html#defines.direction)?\
  This is the direction items flow in. Always. Even for undergrounds and loaders, be it input or output.\
  Required for all belt connectables.
- `belt_shape` :: `"left"|"right"|"straight"`?\
  [`LuaEntity::belt_shape`](https://lua-api.factorio.com/latest/classes/LuaEntity.html#belt_shape). Just used for `"belt"`s.
- `linked_belt_type` :: `"input"|"output"`?\
  [`LuaEntity::linked_belt_type`](https://lua-api.factorio.com/latest/classes/LuaEntity.html#linked_belt_type). `"input"`: items go into the belt, `"output"`: items come out of the belt.
- `underground_type` :: `"input"|"output"`?\
  [`LuaEntity::belt_to_ground_type`](https://lua-api.factorio.com/latest/classes/LuaEntity.html#belt_to_ground_type). `"input"`: goes underground, `"output"`: emerges from the ground.

### InserterThroughputDropDefinition

Inherits [`InserterThroughputLoaderDefinitionBase`](#inserterthroughputloaderdefinitionbase).

- `target_type` :: [`InserterThroughputTargetType`](#inserterthroughputtargettype)
- `belt_speed` :: `number`?\
  Tiles per tick of each item on the belt being dropped off to.\
  Required for all belt connectables.
- `belt_direction` :: [`defines.direction`](https://lua-api.factorio.com/latest/defines.html#defines.direction)?\
  Only used and required when dropping to `"splitter"`s or `"loader"`s.

### VectorXY

Only accepts tables taking the xy form, not arrays.

Alias of:

- [`Vector`](https://lua-api.factorio.com/latest/concepts.html#Vector)
- [`MapPosition`](https://lua-api.factorio.com/latest/concepts.html#MapPosition)
- [`TilePosition`](https://lua-api.factorio.com/latest/concepts.html#TilePosition)

### MatrixIJ

Must watch (3blue1brown) https://www.youtube.com/playlist?list=PLZHQObOWTQDPD3MizzM2xVFitgF8hE_ab

- `ix` :: `number`\
  Top left corner if you think about it like a 2x2 grid.
- `iy` :: `number`\
  Bottom left corner if you think about it like a 2x2 grid.
- `jx` :: `number`\
  Top right corner if you think about it like a 2x2 grid.
- `jy` :: `number`\
  Bottom right corner if you think about it like a 2x2 grid.

## All Inserter Throughput Lib Functions

### estimate_inserter_speed

Snaps belt speeds and vectors to valid 1/256ths, because they are all related to MapPositions. Does not modify the given definition however.

**Parameters**

- `def` :: [`InserterThroughputDefinition`](#inserterthroughputdefinition)

**Return values**

- `items_per_second` :: `number`

### is_estimate

Whether or not the given definition can be used for accurate throughput calculation or if it is just an estimate. Under what conditions this returns true or false is not part of the public api.

**Parameters**

- `def` :: [`InserterThroughputDefinition`](#inserterthroughputdefinition)

**Return values**

- `boolean`

### make_empty_definition

Creates a new definition with `def.inserter`, `def.pickup` and `def.drop` all being empty tables.

**Return values**

- [`InserterThroughputDefinition`](#inserterthroughputdefinition)

### make_full_definition_for_inserter

Sets all fields in `def.inserter`, `def.pickup` and `def.drop`. In other words: everything.

**Parameters**

- `inserter` :: [`LuaEntity`](https://lua-api.factorio.com/latest/classes/LuaEntity.html)
- `def_to_reuse` :: [`InserterThroughputDefinition`](#inserterthroughputdefinition)?

**Return values**

- [`InserterThroughputDefinition`](#inserterthroughputdefinition)

### inserter_data_based_on_prototype

Sets all fields in `def.inserter`.

**Parameters**

- `def` :: [`InserterThroughputDefinition`](#inserterthroughputdefinition)
- `inserter_prototype` :: [`LuaEntityPrototype`](https://lua-api.factorio.com/latest/classes/LuaEntityPrototype.html)
- `direction` :: [`defines.direction`](https://lua-api.factorio.com/latest/defines.html#defines.direction)
- `position` :: [`VectorXY`](#vectorxy)?\
  Default: `get_default_inserter_position_in_tile(inserter_prototype, direction)`.
- `stack_size` :: `integer`

### inserter_data_based_on_entity

Sets all fields in `def.inserter`.

**Parameters**

- `def` :: [`InserterThroughputDefinition`](#inserterthroughputdefinition)
- `inserter` :: [`LuaEntity`](https://lua-api.factorio.com/latest/classes/LuaEntity.html)

### pickup_from_inventory

Sets all fields in `def.pickup`, unrelated fields get set to `nil`.

**Parameters**

- `def` :: [`InserterThroughputDefinition`](#inserterthroughputdefinition)

### pickup_from_ground

Sets all fields in `def.pickup`, unrelated fields get set to `nil`.

**Parameters**

- `def` :: [`InserterThroughputDefinition`](#inserterthroughputdefinition)

### pickup_from_belt

Sets all fields in `def.pickup`, unrelated fields get set to `nil`.

**Parameters**

- `def` :: [`InserterThroughputDefinition`](#inserterthroughputdefinition)
- `belt_speed` :: `number`\
  Tiles per tick that each item moves.
- `belt_direction` :: [`defines.direction`](https://lua-api.factorio.com/latest/defines.html#defines.direction)
- `belt_shape` :: `"left"|"right"|"straight"`\
  Example: If a belt is pointing at this belt from the left, set "left".

### pickup_from_linked_belt

Sets all fields in `def.pickup`, unrelated fields get set to `nil`.

**Parameters**

- `def` :: [`InserterThroughputDefinition`](#inserterthroughputdefinition)
- `belt_speed` :: `number`\
  Tiles per tick that each item moves.
- `belt_direction` :: [`defines.direction`](https://lua-api.factorio.com/latest/defines.html#defines.direction)
- `linked_belt_type` :: `"input"|"output"`\
  `LuaEntity::linked_belt_type`. `"input"`: items go into the belt, `"output"`: items come out of the belt.

### pickup_from_underground

Sets all fields in `def.pickup`, unrelated fields get set to `nil`.

**Parameters**

- `def` :: [`InserterThroughputDefinition`](#inserterthroughputdefinition)
- `belt_speed` :: `number`\
  Tiles per tick that each item moves.
- `belt_direction` :: [`defines.direction`](https://lua-api.factorio.com/latest/defines.html#defines.direction)
- `underground_type` :: `"input"|"output"`\
  `LuaEntity::belt_to_ground_type`. `"input"`: goes underground, `"output"`: emerges from the ground.

### pickup_from_splitter

Sets all fields in `def.pickup`, unrelated fields get set to `nil`.

**Parameters**

- `def` :: [`InserterThroughputDefinition`](#inserterthroughputdefinition)
- `belt_speed` :: `number`\
  Tiles per tick that each item moves.
- `belt_direction` :: [`defines.direction`](https://lua-api.factorio.com/latest/defines.html#defines.direction)

### pickup_from_loader

Sets all fields in `def.pickup`, unrelated fields get set to `nil`.

**Parameters**

- `def` :: [`InserterThroughputDefinition`](#inserterthroughputdefinition)
- `belt_speed` :: `number`\
  Tiles per tick that each item moves.
- `belt_direction` :: [`defines.direction`](https://lua-api.factorio.com/latest/defines.html#defines.direction)
- `loader_type` :: `"input"|"output"`\
  `LuaEntity::loader_type`. `"input"`: items flow into the loader, `"output"`: items flow out of the loader.
- `loader_belt_length` :: `number`\
  `LuaEntityPrototype::belt_length`.
- `loader_tile_distance_from_belt_start` :: `integer`\
  How many tiles is the drop distance away from the actual belt of the loader? When dropping onto the tile of a 1x2 loader which is next to a container, this is `1`. When dropping onto the tile where items get put onto or taken from the belt, this is 0.

### pickup_from_entity

Sets all fields in `def.pickup`, unrelated fields get set to `nil`.

**Parameters**

- `def` :: [`InserterThroughputDefinition`](#inserterthroughputdefinition)
- `entity` :: [`LuaEntity`](https://lua-api.factorio.com/latest/classes/LuaEntity.html)?
- `pickup_position` :: [`VectorXY`](#vectorxy)?\
  Required if `entity` is any loader.

### pickup_from_position

Sets all fields in `def.pickup`, unrelated fields get set to `nil`.

**Parameters**

- `def` :: [`InserterThroughputDefinition`](#inserterthroughputdefinition)
- `surface` :: [`LuaSurface`](https://lua-api.factorio.com/latest/classes/LuaSurface.html)
- `position` :: [`VectorXY`](#vectorxy)\
  A MapPosition on the given surface.
- `inserter` :: [`LuaEntity`](https://lua-api.factorio.com/latest/classes/LuaEntity.html)?\
  Used to prevent an inserter from picking up from itself, provide it if applicable.

### pickup_from_position_and_set_pickup_vector

Sets all fields in `def.pickup`, unrelated fields get set to `nil`.\
Also sets `def.inserter.pickup_vector` using `position` and `inserter_position`.

**Parameters**

- `def` :: [`InserterThroughputDefinition`](#inserterthroughputdefinition)
- `surface` :: [`LuaSurface`](https://lua-api.factorio.com/latest/classes/LuaSurface.html)
- `position` :: [`VectorXY`](#vectorxy)\
  A MapPosition on the given surface.
- `inserter` :: [`LuaEntity`](https://lua-api.factorio.com/latest/classes/LuaEntity.html)?\
  Used to prevent an inserter from picking up from itself, provide it if applicable.
- `inserter_position` :: [`VectorXY`](#vectorxy)?\
  Default: `inserter.position`. Required if `inserter` is `nil`.

### pickup_from_pickup_target_of_inserter

Sets all fields in `def.pickup`, unrelated fields get set to `nil`.

**Parameters**

- `def` :: [`InserterThroughputDefinition`](#inserterthroughputdefinition)
- `inserter` :: [`LuaEntity`](https://lua-api.factorio.com/latest/classes/LuaEntity.html)\
  Ghost or real.

### pickup_from_pickup_target_of_inserter_and_set_pickup_vector

Sets all fields in `def.pickup`, unrelated fields get set to `nil`.\
Also sets `def.inserter.pickup_vector` using `inserter.pickup_position` and `inserter.position`.

**Parameters**

- `def` :: [`InserterThroughputDefinition`](#inserterthroughputdefinition)
- `inserter` :: [`LuaEntity`](https://lua-api.factorio.com/latest/classes/LuaEntity.html)\
  Ghost or real.

### drop_to_inventory

Sets all fields in `def.drop`, unrelated fields get set to `nil`.

**Parameters**

- `def` :: [`InserterThroughputDefinition`](#inserterthroughputdefinition)

### drop_to_ground

Sets all fields in `def.drop`, unrelated fields get set to `nil`.

**Parameters**

- `def` :: [`InserterThroughputDefinition`](#inserterthroughputdefinition)

### drop_to_belt

Sets all fields in `def.drop`, unrelated fields get set to `nil`.

**Parameters**

- `def` :: [`InserterThroughputDefinition`](#inserterthroughputdefinition)
- `belt_speed` :: `number`\
  Tiles per tick that each item moves.

### drop_to_linked_belt

Sets all fields in `def.drop`, unrelated fields get set to `nil`.

**Parameters**

- `def` :: [`InserterThroughputDefinition`](#inserterthroughputdefinition)
- `belt_speed` :: `number`\
  Tiles per tick that each item moves.

### drop_to_underground

Sets all fields in `def.drop`, unrelated fields get set to `nil`.

**Parameters**

- `def` :: [`InserterThroughputDefinition`](#inserterthroughputdefinition)
- `belt_speed` :: `number`\
  Tiles per tick that each item moves.

### drop_to_splitter

Sets all fields in `def.drop`, unrelated fields get set to `nil`.

**Parameters**

- `def` :: [`InserterThroughputDefinition`](#inserterthroughputdefinition)
- `belt_speed` :: `number`\
  Tiles per tick that each item moves.
- `belt_direction` :: [`defines.direction`](https://lua-api.factorio.com/latest/defines.html#defines.direction)

### drop_to_loader

Sets all fields in `def.drop`, unrelated fields get set to `nil`.

**Parameters**

- `def` :: [`InserterThroughputDefinition`](#inserterthroughputdefinition)
- `belt_speed` :: `number`\
  Tiles per tick that each item moves.
- `belt_direction` :: [`defines.direction`](https://lua-api.factorio.com/latest/defines.html#defines.direction)
- `loader_type` :: `"input"|"output"`\
  `LuaEntity::loader_type`. `"input"`: items flow into the loader, `"output"`: items flow out of the loader.
- `loader_belt_length` :: `number`\
  `LuaEntityPrototype::belt_length`.
- `loader_tile_distance_from_belt_start` :: `integer`\
  How many tiles is the drop distance away from the actual belt of the loader? When dropping onto the tile of a 1x2 loader which is next to a container, this is `1`. When dropping onto the tile where items get put onto or taken from the belt, this is 0.

### drop_to_entity

Sets all fields in `def.drop`, unrelated fields get set to `nil`.

**Parameters**

- `def` :: [`InserterThroughputDefinition`](#inserterthroughputdefinition)
- `entity` :: [`LuaEntity`](https://lua-api.factorio.com/latest/classes/LuaEntity.html)?
- `drop_position` :: [`VectorXY`](#vectorxy)?\
  Required if `entity` is any loader.

### drop_to_position

Sets all fields in `def.drop`, unrelated fields get set to `nil`.

**Parameters**

- `def` :: [`InserterThroughputDefinition`](#inserterthroughputdefinition)
- `surface` :: [`LuaSurface`](https://lua-api.factorio.com/latest/classes/LuaSurface.html)
- `position` :: [`VectorXY`](#vectorxy)\
  A MapPosition on the given surface.
- `inserter` :: [`LuaEntity`](https://lua-api.factorio.com/latest/classes/LuaEntity.html)?\
  Used to prevent an inserter from dropping to itself, provide it if applicable.

### drop_to_position_and_set_drop_vector

Sets all fields in `def.drop`, unrelated fields get set to `nil`.\
Also sets `def.inserter.drop_vector` using `position` and `inserter_position`.

**Parameters**

- `def` :: [`InserterThroughputDefinition`](#inserterthroughputdefinition)
- `surface` :: [`LuaSurface`](https://lua-api.factorio.com/latest/classes/LuaSurface.html)
- `position` :: [`VectorXY`](#vectorxy)\
  A MapPosition on the given surface.
- `inserter` :: [`LuaEntity`](https://lua-api.factorio.com/latest/classes/LuaEntity.html)?\
  Used to prevent an inserter from dropping to itself, provide it if applicable.
- `inserter_position` :: [`VectorXY`](#vectorxy)?\
  Default: `inserter.position`. Required if `inserter` is `nil`.

### drop_to_drop_target_of_inserter

Sets all fields in `def.drop`, unrelated fields get set to `nil`.

**Parameters**

- `def` :: [`InserterThroughputDefinition`](#inserterthroughputdefinition)
- `inserter` :: [`LuaEntity`](https://lua-api.factorio.com/latest/classes/LuaEntity.html)\
  Ghost or real.

### drop_to_drop_target_of_inserter_and_set_drop_vector

Sets all fields in `def.drop`, unrelated fields get set to `nil`.\
Also sets `def.inserter.drop_vector` using `inserter.drop_position` and `inserter.position`.

**Parameters**

- `def` :: [`InserterThroughputDefinition`](#inserterthroughputdefinition)
- `inserter` :: [`LuaEntity`](https://lua-api.factorio.com/latest/classes/LuaEntity.html)\
  Ghost or real.

### get_real_or_ghost_entity_type

**Parameters**

- `entity` :: [`LuaEntity`](https://lua-api.factorio.com/latest/classes/LuaEntity.html)

**Return values**

- `type` :: `string`

### get_real_or_ghost_entity_prototype

**Parameters**

- `entity` :: [`LuaEntity`](https://lua-api.factorio.com/latest/classes/LuaEntity.html)\
  Must not be a ghost for a tile.

**Return values**

- [`LuaEntityPrototype`](https://lua-api.factorio.com/latest/classes/LuaEntityPrototype.html)

### get_target_type

**Parameters**

- `entity` :: [`LuaEntity`](https://lua-api.factorio.com/latest/classes/LuaEntity.html)?\
  Handles both real and ghost entities.

**Return values**

- [`InserterThroughputTargetType`](#inserterthroughputtargettype)

### is_belt_connectable_target_type

**Parameters**

- `target_type` :: [`InserterThroughputTargetType`](#inserterthroughputtargettype)

**Return values**

- `boolean`

### get_pickup_vector

Instead of getting the `pickup_position` which is an absolute position, this gets the vector from the inserter to its `pickup_position`.

**Parameters**

- `inserter` :: [`LuaEntity`](https://lua-api.factorio.com/latest/classes/LuaEntity.html)
- `position` :: [`VectorXY`](#vectorxy)?\
  Prefetched position of the inserter, to reduce the amount of api calls and allocations. Only makes sense in code that runs _a lot_.

**Return values**

- `pickup_vector` :: [`VectorXY`](#vectorxy)

### get_drop_vector

Instead of getting the `drop_position` which is an absolute position, this gets the vector from the inserter to its `drop_position`.

**Parameters**

- `inserter` :: [`LuaEntity`](https://lua-api.factorio.com/latest/classes/LuaEntity.html)
- `position` :: [`VectorXY`](#vectorxy)?\
  Prefetched position of the inserter, to reduce the amount of api calls and allocations. Only makes sense in code that runs _a lot_.

**Return values**

- `drop_vector` :: [`VectorXY`](#vectorxy)

### get_default_inserter_position_in_tile

Pretends off grid inserters are placed on the grid, so they get zero special treatment.

**Parameters**

- `prototype` :: [`LuaEntityPrototype`](https://lua-api.factorio.com/latest/classes/LuaEntityPrototype.html)
- `direction` :: [`defines.direction`](https://lua-api.factorio.com/latest/defines.html#defines.direction)

**Return values**

- `position` :: [`VectorXY`](#vectorxy)\
  The position within a tile, so x and y are in the [0, 1) range.

### get_position_in_tile

**Generics**

- `T` of type [`VectorXY`](#vectorxy)

**Parameters**

- `position` :: `T`

**Return values**

- `position_within_tile` :: `T`\
  A new table.

### get_stack_size_for_prototype

**Parameters**

- `prototype` :: [`LuaEntityPrototype`](https://lua-api.factorio.com/latest/classes/LuaEntityPrototype.html)
- `force` :: [`LuaForce`](https://lua-api.factorio.com/latest/classes/LuaForce.html)?
- `manual_override` :: `integer`?
- `control_signal_id` :: [`SignalID`](https://lua-api.factorio.com/latest/concepts.html#SignalID)?
- `red` :: [`LuaCircuitNetwork`](https://lua-api.factorio.com/latest/classes/LuaCircuitNetwork.html)?
- `green` :: [`LuaCircuitNetwork`](https://lua-api.factorio.com/latest/classes/LuaCircuitNetwork.html)?

**Return values**

- `stack_size` :: `integer`

### get_stack_size

Uses `inserter.inserter_target_pickup_count`. However `get_stack_size` also handles inserters which have just been built in this tick, while `inserter_target_pickup_count` returns `1` in that case in several situations.

**Parameters**

- `inserter` :: [`LuaEntity`](https://lua-api.factorio.com/latest/classes/LuaEntity.html)\
  Ghost or real.

### is_placeable_off_grid

**Parameters**

- `prototype` :: [`LuaEntityPrototype`](https://lua-api.factorio.com/latest/classes/LuaEntityPrototype.html)

**Return values**

- `boolean`

### snap_build_position

This appears to match the game's snapping logic perfectly.

**Generics**

- `T` of type [`VectorXY`](#vectorxy)

**Parameters**

- `prototype` :: [`LuaEntityPrototype`](https://lua-api.factorio.com/latest/classes/LuaEntityPrototype.html)
- `position` :: `T`\
  Gets modified.
- `direction` :: [`defines.direction`](https://lua-api.factorio.com/latest/defines.html#defines.direction)

**Return values**

- `position` :: `T`\
  The same table as the `position` parameter.

### normalize_belt_speed

Rounds down to nearest valid number, because items on belts also use fixed point positions. Same resolution as MapPositions, so 1/256.

**Parameters**

- `belt_speed` :: `number`\
  Tiles per tick.

**Return values**

- `belt_speed` :: `number`

## All Vector Lib Functions

### vec_equals

**Parameters**

- `left` :: [`VectorXY`](#vectorxy)
- `right` :: [`VectorXY`](#vectorxy)

**Return values**

- `boolean`

### matrix_equals

**Parameters**

- `left` :: [`MatrixIJ`](#matrixij)
- `right` :: [`MatrixIJ`](#matrixij)

**Return values**

- `boolean`

### copy

**Generics**

- `T` of type [`VectorXY`](#vectorxy)

**Parameters**

- `vector` :: `T`

**Return values**

- `T`

### get_length

**Parameters**

- `vector` :: [`VectorXY`](#vectorxy)

**Return values**

- `number`

### set_length

**Generics**

- `T` of type [`VectorXY`](#vectorxy)

**Parameters**

- `vector` :: `T`\
  Gets modified.
- `length` :: `number`

**Return values**

- `vector` :: `T`

### normalize

**Generics**

- `T` of type [`VectorXY`](#vectorxy)

**Parameters**

- `vector` :: `T`\
  Gets modified.
- `length` :: `number`?\
  Precalculated length if available.

**Return values**

- `vector` :: `T`

### snap_to_map

Snaps x and y to the MapPosition grid (1/256).\
I don't know if the game rounds or floors, but this function is flooring.

**Generics**

- `T` of type [`VectorXY`](#vectorxy)

**Parameters**

- `vector` :: `T`\
  Gets modified.

**Return values**

- `vector` :: `T`

### add

**Generics**

- `T` of type [`VectorXY`](#vectorxy)

**Parameters**

- `left` :: `T`\
  Gets modified.
- `right` :: [`VectorXY`](#vectorxy)

**Return values**

- `left` :: `T`

### sub

**Generics**

- `T` of type [`VectorXY`](#vectorxy)

**Parameters**

- `left` :: `T`\
  Gets modified.
- `right` :: [`VectorXY`](#vectorxy)

**Return values**

- `left` :: `T`

### add_scalar

**Generics**

- `T` of type [`VectorXY`](#vectorxy)

**Parameters**

- `left` :: `T`\
  Gets modified.
- `right` :: `number`

**Return values**

- `left` :: `T`

### sub_scalar

**Generics**

- `T` of type [`VectorXY`](#vectorxy)

**Parameters**

- `left` :: `T`\
  Gets modified.
- `right` :: `number`

**Return values**

- `left` :: `T`

### mul_scalar

**Generics**

- `T` of type [`VectorXY`](#vectorxy)

**Parameters**

- `left` :: `T`\
  Gets modified.
- `right` :: `number`

**Return values**

- `left` :: `T`

### div_scalar

**Generics**

- `T` of type [`VectorXY`](#vectorxy)

**Parameters**

- `left` :: `T`\
  Gets modified.
- `right` :: `number`

**Return values**

- `left` :: `T`

### mod_scalar

**Generics**

- `T` of type [`VectorXY`](#vectorxy)

**Parameters**

- `left` :: `T`\
  Gets modified.
- `right` :: `number`

**Return values**

- `left` :: `T`

### dot_product

Project `right` onto `left`, get that length and multiply it by the length of `left`.\
If they are perpendicular to each other, it is 0.\
If they are pointing generally away from each other, it is negative.\
You can also think about it as projecting `left` onto `right` and the result is the same. See https://www.3blue1brown.com/lessons/dot-products

**Parameters**

- `left` :: [`VectorXY`](#vectorxy)
- `right` :: [`VectorXY`](#vectorxy)

**Return values**

- `number`

### get_radians

North is 0, goes clockwise, always positive.

**Parameters**

- `vector` :: [`VectorXY`](#vectorxy)

**Return values**

- `number`

### get_orientation

Returns a RealOrientation, so `[0, 1)` where 0 is north, 0.25 is east, 0.5 is south, 0.75 is west.

**Parameters**

- `vector` :: [`VectorXY`](#vectorxy)

**Return values**

- [`RealOrientation`](https://lua-api.factorio.com/latest/concepts.html#RealOrientation)

### rotate_by_radians

**Generics**

- `T` of type [`VectorXY`](#vectorxy)

**Parameters**

- `vector` :: `T`\
  Gets modified.
- `radians_diff` :: `number`

**Return values**

- `vector` :: `T`

### rotate_by_orientation

**Generics**

- `T` of type [`VectorXY`](#vectorxy)

**Parameters**

- `vector` :: `T`\
  Gets modified.
- `orientation_diff` :: [`RealOrientation`](https://lua-api.factorio.com/latest/concepts.html#RealOrientation)\
  Can exceed the usual bounds of RealOrientation.

**Return values**

- `vector` :: `T`

### rotate_by_direction

**Generics**

- `T` of type [`VectorXY`](#vectorxy)

**Parameters**

- `vector` :: `T`\
  Gets modified.
- `direction` :: [`defines.direction`](https://lua-api.factorio.com/latest/defines.html#defines.direction)\
  Can take negative values, which rotate counter clockwise.

**Return values**

- `vector` :: `T`

### transform_by_matrix

Right to left... because math.

**Generics**

- `T` of type [`VectorXY`](#vectorxy)

**Parameters**

- `matrix` :: [`MatrixIJ`](#matrixij)
- `vector` :: `T`\
  Gets modified.

**Return values**

- `vector` :: `T`

### rotation_matrix_by_radians

**Parameters**

- `radians` :: `number`

**Return values**

- `matrix` :: [`MatrixIJ`](#matrixij)

### rotation_matrix_by_orientation

**Parameters**

- `orientation` :: [`RealOrientation`](https://lua-api.factorio.com/latest/concepts.html#RealOrientation)\
  Can exceed the usual bounds of RealOrientation.

**Return values**

- `matrix` :: [`MatrixIJ`](#matrixij)

### new_matrix

**Parameters**

- `ix` :: `number`\
  Top left corner if you think about it like a 2x2 grid.
- `jx` :: `number`\
  Top right corner if you think about it like a 2x2 grid.
- `iy` :: `number`\
  Bottom left corner if you think about it like a 2x2 grid.
- `jy` :: `number`\
  Bottom right corner if you think about it like a 2x2 grid.

**Return values**

- `matrix` :: [`MatrixIJ`](#matrixij)

### new_identity_matrix

**Return values**

- `matrix` :: [`MatrixIJ`](#matrixij)

### copy_matrix

**Parameters**

- `matrix` :: [`MatrixIJ`](#matrixij)

**Return values**

- [`MatrixIJ`](#matrixij)

### compose_matrices

Right to left... because math.

**Parameters**

- `second` :: [`MatrixIJ`](#matrixij)\
  The transformation that should happen after the first one.
- `first` :: [`MatrixIJ`](#matrixij)\
  (Gets modified.) The first transformation that should happen.

**Return values**

- `first` :: [`MatrixIJ`](#matrixij)
