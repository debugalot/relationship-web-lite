extends RefCounted
## The force layout behind [RelationshipWebView]: Fruchterman–Reingold with cooling. Repulsion only looks at the
## neighbouring cells of a uniform grid, so a step costs O(n) instead of O(n²); family springs pull twice as hard;
## a weak pull toward the centre keeps unconnected groups on screen; pinned nodes (dragged by the user) stay put.
## Deterministic: the same nodes, links and starting positions always settle the same way.

## Where each node is, in world units.
var positions := PackedVector2Array()
## 1 for nodes that don't move.
var pinned := PackedByteArray()
## How far a node may move in one step; it cools every step. The layout has settled below [constant SETTLED].
var temperature := 0.0
## The ideal link length.
var spacing := 80.0
## How much wider than tall the web settles: the forces are worked out as if the web were squeezed sideways by
## this much, so a wide view is filled instead of showing a round web with empty sides. 1 is even.
var stretch := 1.0

## A layout cooler than this has settled.
const SETTLED := 0.6

var _shift := PackedVector2Array()
var _from := PackedInt32Array()
var _to := PackedInt32Array()
var _stiffness := PackedFloat32Array()
var _start_temperature := 0.0


## Sets up [param count] nodes and the links between them ([param from] and [param to] are node indices,
## [param stiffness] 2.0 for family and 1.0 otherwise). Nodes with a position in [param initial] (not NAN) start
## there; the rest start next to a placed neighbour, or on a spiral. Starting from known positions only needs a
## gentle settle.
func setup(count: int, from: PackedInt32Array, to: PackedInt32Array, stiffness: PackedFloat32Array,
		initial: PackedVector2Array) -> void:
	positions.resize(count)
	pinned.resize(count)
	pinned.fill(0)
	_shift.resize(count)
	_from = from
	_to = to
	_stiffness = stiffness
	var placed := PackedByteArray()
	placed.resize(count)
	var known := 0
	for i in count:
		if i < initial.size() and not is_nan(initial[i].x):
			positions[i] = initial[i]
			placed[i] = 1
			known += 1
	if known > 0 and known < count:
		_place_beside_neighbours(placed)
	var radius := spacing * sqrt(float(count)) * 0.6
	for i in count:
		if placed[i] == 0:
			var angle := i * 2.39996
			positions[i] = Vector2(cos(angle), sin(angle)) * radius * sqrt((i + 0.5) / maxf(1.0, count))
	_start_temperature = spacing * 3.0
	temperature = _start_temperature * (0.15 if count > 0 and known == count else (0.5 if known > 0 else 1.0))


## Lets the layout move again (after a drag, or when links change).
func reheat(amount: float = 0.35) -> void:
	temperature = maxf(temperature, _start_temperature * amount)


## Lets every pinned node move again.
func unpin_all() -> void:
	pinned.fill(0)
	reheat()


## True once the layout has stopped moving.
func is_settled() -> bool:
	return temperature < SETTLED


## Steps until settled, or [param max_steps].
func settle(max_steps: int) -> void:
	for _i: int in max_steps:
		if is_settled():
			return
		step()


## One step of the layout. Returns the largest move made.
func step() -> float:
	var n := positions.size()
	if n == 0:
		temperature = 0.0
		return 0.0
	_shift.fill(Vector2.ZERO)
	var squeeze := Vector2(1.0 / stretch, 1.0)
	var k2 := spacing * spacing
	var cell := spacing * 1.25
	var reach2 := (cell * 1.5) * (cell * 1.5)
	var grid: Dictionary[Vector2i, Array] = {}
	for i in n:
		var p := positions[i]
		var key := Vector2i(floori(p.x / (cell * stretch)), floori(p.y / cell))
		var bucket: Array = grid.get(key, [])
		if bucket.is_empty():
			grid[key] = bucket
		bucket.append(i)
	for key: Vector2i in grid:
		var here: Array = grid[key]
		for dx: int in [-1, 0, 1]:
			for dy: int in [-1, 0, 1]:
				var there: Array = grid.get(Vector2i(key.x + dx, key.y + dy), [])
				if there.is_empty():
					continue
				for i: int in here:
					var pi := positions[i]
					var push := Vector2.ZERO
					for j: int in there:
						if j == i:
							continue
						var delta := (pi - positions[j]) * squeeze
						var d2 := delta.length_squared()
						if d2 > reach2:
							continue
						if d2 < 0.01:
							# Two nodes on the same spot: a fixed nudge, exactly opposite for each, so they part.
							var lo := mini(i, j)
							var hi := maxi(i, j)
							var angle := float((lo * 7919 + hi * 104729) % 6283) / 1000.0
							delta = Vector2(cos(angle), sin(angle)) * (0.5 if i == lo else -0.5)
							d2 = delta.length_squared()
						push += delta * (k2 / d2)
					_shift[i] += push
	for e in _from.size():
		var a := _from[e]
		var b := _to[e]
		var delta := (positions[a] - positions[b]) * squeeze
		var d := delta.length()
		if d < 0.01:
			continue
		var pull := delta * (d / spacing) * _stiffness[e]
		_shift[a] -= pull
		_shift[b] += pull
	var biggest := 0.0
	for i in n:
		if pinned[i] == 1:
			continue
		var shift := (_shift[i] - positions[i] * squeeze * 0.02) * Vector2(stretch, 1.0)
		var length := shift.length()
		if length > 0.0:
			var move := shift / length * minf(length, temperature)
			positions[i] += move
			biggest = maxf(biggest, move.length())
	temperature *= 0.95
	return biggest


## The rectangle around every node, with a margin.
func bounds() -> Rect2:
	if positions.is_empty():
		return Rect2(-100, -100, 200, 200)
	var r := Rect2(positions[0], Vector2.ZERO)
	for p in positions:
		r = r.expand(p)
	return r.grow(spacing)


## New nodes next to someone they know: far less shuffling than starting them on the spiral.
func _place_beside_neighbours(placed: PackedByteArray) -> void:
	for e in _from.size():
		for side: int in [0, 1]:
			var fresh := _from[e] if side == 0 else _to[e]
			var known := _to[e] if side == 0 else _from[e]
			if placed[fresh] == 0 and placed[known] == 1:
				var angle := float((fresh * 7919) % 6283) / 1000.0
				positions[fresh] = positions[known] + Vector2(cos(angle), sin(angle)) * spacing * 0.6
				placed[fresh] = 1
