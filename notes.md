
- [x] show completed iterations
- [x] show iterations without progress progressbar
- [x] show setups count in the overview GUI
- [x] show left panel checkbox (per player)
- [x] update left pane checkbox (per player)
- [x] iterations per left panel update slider (per player)
- [x] iterations per tick slider (global)
- [x] pause iteration after no progress slider (global)
- [x] pause iteration checkbox (global)
  - [x] tick pause while iteration is paused
  - [x] pausing only resets auto pause progress if it was currently 100% filled, otherwise progress is retained
- [x] seed field (global)
  - [x] generate seed button
  - [x] reset and use new seed button
- [x] map setting for everything above (probably only used on init)
- [x] write files on auto pause
- [x] write files on button press
- [x] human readable header
- [x] params in table form, formatted using %a with %.9f as comments at the end of the line
- [ ] maybe add weighting to prefer negative deviations over positive ones
- [x] make sure the inserter throughput measuring is actually accurate
- [ ] measurement is accurate, yes, however when picking up from belts timing plays a huge role. Measurement pauses help with it but it's still not great. It would be better if each segment between pauses was measured truly separately and then ones with nearly identical averages get discarded. After that it can take the average of all the "unique" ones, making reducing the chance of uneven weights for some timings
- [ ] add math for picking up from
  - [ ] undergrounds
  - [ ] loaders
  - [ ] splitters
- [ ] when dropping to loaders it's probably possible for them to get removed from the transport line faster than they would move 0.25 tiles, in other words dropping to loaders can probably be faster than dropping to belts. This is currently not considered anywhere in the logic.
- [ ] add necessary data for dropping to undergrounds and loaders, namely direction, input/output type and position relative to inserter
- [x] support ghost inserter
- [x] support ghost targets
- [x] when picking up tons of items from a belt, extra pickup ticks must not be faster than the belt is moving
- [ ] add readme
- [ ] add changelog
- [ ] think about improving the "set from inserter, entity or position" api
- [x] rename api file to inserter_throughput
- [ ] rename "from" and "to" to "pickup" and "drop"
- [ ] change data structure to be a definition table containing 3 more tables, inserter, pickup, and drop
- [ ] add functions to create definitions from prototypes
- [ ] add functions to create the inserter part of definitions
- [ ] set version to 1.1.0
- [ ] when setting stack size using an inserter and it ends up being 1, calculate the actual stack size using technologies and overrides, because newly placed inserters don't update their stack size yet

NOTE: It takes 1 tick after placement for an inserter's stack bonuses to get applied. Oof.

# What affects belt item seeking

- pickup vector length
- pickup vector orientation
- belt direction
- belt type
  - belt: shape
  - splitter
  - underground: in/out
  - loader: in/out
- belt speed
- extension speed
- rotation speed
- stack size
- belt being backed up or not

if it picks up too many items for the belt to keep up, reduce speed

make vector for belt flow direction, length 1
take dot product of that and pickup vector
take the absolute
result is extension influence
1 - result is rotation influence
the shorter the pickup vector, the more the opposite influences bleed into each other


- [ ] something worth an attempt is having different belt speed multiplier parameters for when it is backed up vs not backed up. It's not great but it'd be better than nothing


sine wave the belt speed
sine wave the inserter speed
somehow make seek times even longer for slow inserters on faster belts
test chest to chest
compare with the stupid simple algorithm where it's just the same logic for pickup and drop
add more belt test cases
remove splitter and underground test cases for now
add more stack sizes
add more inserters
add more belt speeds, like 1 or 2
