
- [x] show completed iterations
- [x] show iterations without progress progressbar
- [ ] show setups count in the overview GUI

- [x] show left panel checkbox (per player)
- [x] update left pane checkbox (per player)
- [x] iterations per left panel update slider (per player)
- [x] iterations per tick slider (global)
- [x] pause iteration after no progress slider (global)
- [x] pause iteration checkbox (global)
  - [x] tick pause while iteration is paused
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

- [ ] pausing should not reset auto pause
  - [ ] add button to reset auto pause instead

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
