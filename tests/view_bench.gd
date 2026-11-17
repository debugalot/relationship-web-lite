extends Control
## Frame-time benchmark for RelationshipWebView at 500 people (about 2,500 pairs, 200 open grievances).
## Run it in a window, not headless (it measures real drawing):
##   godot --path . res://tests/view_bench.tscn
## Phases: the layout settling from scratch, the settled web idle, one relationship event every frame (a live
## game, where the view recolours one line in place), and a person selected (the focus layers at work). Prints
## frame times and the view's own costs, checks them against the budgets, exits 0 if within.

const PEOPLE := 500
const LINKS_EACH := 5
## Budgets, in milliseconds (frame times are whole frames: our work plus Godot's drawing).
const BUDGETS := {
	"settling_frame": 16.7,      # a 60 fps frame while the layout moves
	"settle_seconds": 12000.0,   # (ms) until the layout stops
	"idle_frame": 16.7,
	"live_frame": 16.7,          # with one event a frame
	"live_view_work": 8.0,       # the view's own work per frame with one event a frame
	"focused_frame": 16.7,       # someone selected: focus lines, flow dots, labels
	"full_rebuild": 40.0,        # one full rebuild of every line (a filter change)
}

var web := RelationshipWeb.new()
var view := RelationshipWebView.new()
var results := {}
var failures := 0


func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 500
	var presets: Array[StringName] = [&"acquaintance", &"acquaintance", &"friend", &"rival", &"family", &"ally", &"enemy"]
	for i in PEOPLE:
		web.add_person("p%03d" % i, {"volatility": rng.randf_range(0, 100), "data": {"group": "g%d" % (i % 8)}})
	for i in PEOPLE:
		for _l: int in LINKS_EACH:
			var j := (i + rng.randi_range(1, 40)) % PEOPLE
			web.link("p%03d" % i, "p%03d" % j, presets[rng.randi_range(0, presets.size() - 1)])
	var bonds := web.get_all_bonds()
	for _g: int in 200:
		var bond := bonds[rng.randi_range(0, bonds.size() - 1)]
		web.open_grievance(bond.from_id, bond.to_id, rng.randi_range(1, 5))
	var backdrop := ColorRect.new()
	backdrop.color = Color("#14162a")
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	view.set_anchors_preset(Control.PRESET_FULL_RECT)
	view.presettle_msec = 0
	add_child(view)
	view.web = web
	view._sync()
	print("%d people, %d pairs" % [PEOPLE, view._pa.size()])

	# 1. Settling from scratch.
	var frames: Array[float] = []
	var work: Array[float] = []
	var layout: Array[float] = []
	var lines: Array[float] = []
	var people: Array[float] = []
	var started := Time.get_ticks_usec()
	var last := started
	while not view.is_settled() and Time.get_ticks_usec() - started < 30_000_000:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		frames.append((now - last) / 1000.0)
		work.append((view.last_layout_usec + view.last_draw_usec + view.last_people_usec) / 1000.0)
		layout.append(view.last_layout_usec / 1000.0)
		lines.append(view.last_draw_usec / 1000.0)
		people.append(view.last_people_usec / 1000.0)
		last = now
	print("       while settling: layout + points %.1f, lines %.1f, people %.1f ms mean (markers %.1f, names %.1f)" % [_mean(layout), _mean(lines), _mean(people), view.last_markers_usec / 1000.0, view.last_labels_usec / 1000.0])
	_record("settle_seconds", (Time.get_ticks_usec() - started) / 1000.0, "ms until the layout settled (%d frames)" % frames.size())
	_record("settling_frame", _mean(frames), "ms mean frame while settling (worst %.1f; the view's layout + lines + people %.1f mean)" % [_max(frames), _mean(work)])

	# 2. Settled and idle.
	await get_tree().process_frame
	await get_tree().process_frame
	frames.clear()
	last = Time.get_ticks_usec()
	for _f: int in 120:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		frames.append((now - last) / 1000.0)
		last = now
	_record("idle_frame", _mean(frames), "ms mean frame settled and idle (the view sleeps: processing %s)" % view.is_processing())

	# 3. A live game: one event a frame, recoloured in place.
	frames.clear()
	work.clear()
	layout.clear()
	lines.clear()
	people.clear()
	last = Time.get_ticks_usec()
	for f: int in 240:
		var bond := bonds[(f * 37) % bonds.size()]
		web.apply(bond.from_id, bond.to_id, {"affinity": 8.0 if f % 2 == 0 else -8.0})
		var before := Time.get_ticks_usec()
		view._sync()
		var sync := Time.get_ticks_usec() - before
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		frames.append((now - last) / 1000.0)
		work.append((sync + view.last_draw_usec + view.last_people_usec) / 1000.0)
		layout.append(sync / 1000.0)
		lines.append(view.last_draw_usec / 1000.0)
		people.append(view.last_people_usec / 1000.0)
		view.last_people_usec = 0
		view.last_draw_usec = 0
		last = now
	print("       live: sync %.2f, lines %.2f, people %.2f ms mean (markers %.2f, names %.2f); %d leftover of %d segments" % [_mean(layout), _mean(lines), _mean(people), view.last_markers_usec / 1000.0, view.last_labels_usec / 1000.0, view._leftover_segments, view._total_segments])
	_record("live_frame", _mean(frames), "ms mean frame with one event a frame (worst %.1f)" % _max(frames))
	_record("live_view_work", _mean(work), "ms the view's own work per frame then (recolour + lines + people)")

	# 4. Someone selected: the focus layers, flow dots and labels.
	view.select_person("p042")
	await get_tree().process_frame
	frames.clear()
	last = Time.get_ticks_usec()
	for _f: int in 120:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		frames.append((now - last) / 1000.0)
		last = now
	_record("focused_frame", _mean(frames), "ms mean frame with a person selected (worst %.1f)" % _max(frames))
	var shot := get_viewport().get_texture().get_image()
	shot.save_png("res://tests/out/view_bench_500.png")
	view.clear_selection()

	# 5. One full rebuild (what a filter change costs).
	var rebuild_started := Time.get_ticks_usec()
	view._geometry_dirty = true
	view._rebuild_geometry()
	_record("full_rebuild", (Time.get_ticks_usec() - rebuild_started) / 1000.0, "ms for one full rebuild of every line")
	print("\n%d budgets, %d over" % [results.size(), failures])
	get_tree().quit(1 if failures > 0 else 0)


func _record(key: String, value: float, what: String) -> void:
	results[key] = value
	var budget: float = BUDGETS[key]
	var within := value <= budget
	if not within:
		failures += 1
	print("%s  %9.2f  %s  (budget %s)" % ["ok  " if within else "OVER", value, what, budget])


func _mean(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for v in values:
		total += v
	return total / values.size()


func _max(values: Array[float]) -> float:
	var biggest := 0.0
	for v in values:
		biggest = maxf(biggest, v)
	return biggest
