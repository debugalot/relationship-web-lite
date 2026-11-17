extends Node
## Scale benchmark: 2,000 people and 40,000 bonds (20,000 linked pairs) with 2,000 grievances. Run:
##   godot --headless --path . res://tests/bench.tscn
## Prints how long each operation takes and checks it against the beta budgets. Exit code 0 when all are within.

const PEOPLE := 2000
const PAIRS := 20000
const GRIEVANCES := 2000
const EVENTS := 10000
## The beta budgets (milliseconds unless noted) on the development machine (Ryzen 9 7900X), set in phase 1 above
## the measured times as regression guards. Per bond that is about 2 µs a day while it moves and nothing once at rest.
const BUDGETS := {
	"build": 1000.0, "apply_us": 20.0, "first_day": 120.0, "mean_day": 100.0, "rested_day": 10.0,
	"save_binary": 500.0, "load_binary": 1200.0,
}

var results := {}
var failures := 0


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	var styles: Array[String] = ["secure", "anxious", "avoidant", "disorganized"]
	var presets: Array[StringName] = [&"acquaintance", &"acquaintance", &"acquaintance", &"friend", &"ally", &"rival",
		&"family", &"partner", &"enemy", &"stranger"]
	var memory_before := Performance.get_monitor(Performance.MEMORY_STATIC)

	var started := Time.get_ticks_usec()
	var web := RelationshipWeb.new()
	web.random_seed = 7
	var ids := PackedStringArray()
	for i in PEOPLE:
		var id := "p%04d" % i
		ids.append(id)
		web.add_person(id, {"volatility": rng.randf_range(0, 100), "pride": rng.randf_range(0, 100),
			"forgiveness": rng.randf_range(0, 100), "loyalty": rng.randf_range(0, 100),
			"attachment": styles[rng.randi_range(0, 3)]})
	var linked := 0
	while linked < PAIRS:
		var a := ids[rng.randi_range(0, PEOPLE - 1)]
		var b := ids[rng.randi_range(0, PEOPLE - 1)]
		if a == b or web.has_bond(a, b):
			continue
		var preset := presets[rng.randi_range(0, presets.size() - 1)]
		web.link(a, b, preset)
		linked += 1
	var bonds := web.get_all_bonds()
	for i in GRIEVANCES:
		var bond := bonds[rng.randi_range(0, bonds.size() - 1)]
		web.open_grievance(bond.from_id, bond.to_id, rng.randi_range(1, 5), "Benchmark grievance %d" % i)
	_record("build", (Time.get_ticks_usec() - started) / 1000.0, "ms to add 2,000 people, link 20,000 pairs, open 2,000 grievances")
	var memory_after := Performance.get_monitor(Performance.MEMORY_STATIC)
	print("       memory for the web: about %.1f MB" % ((memory_after - memory_before) / 1048576.0))

	started = Time.get_ticks_usec()
	for i in EVENTS:
		var bond := bonds[rng.randi_range(0, bonds.size() - 1)]
		web.apply(bond.from_id, bond.to_id, {"affinity": rng.randf_range(-15, 15), "trust": rng.randf_range(-10, 10)})
	_record("apply_us", float(Time.get_ticks_usec() - started) / EVENTS, "µs per apply() (10,000 random events)")

	var day_ms: Array[float] = []
	for i in 30:
		started = Time.get_ticks_usec()
		web.advance_day()
		day_ms.append((Time.get_ticks_usec() - started) / 1000.0)
	_record("first_day", day_ms[0], "ms for the first advance_day() (every bond moving)")
	var total := 0.0
	var worst := 0.0
	for ms in day_ms:
		total += ms
		worst = maxf(worst, ms)
	_record("mean_day", total / day_ms.size(), "ms mean advance_day() over 30 days (worst %.1f)" % worst)

	started = Time.get_ticks_usec()
	web.advance_day(400)
	print("       400 more days took %.1f s (%d grievances still open, %d bonds)" % [
		(Time.get_ticks_usec() - started) / 1e6, _open_grievances(web), web.get_bond_count()])
	started = Time.get_ticks_usec()
	web.advance_day()
	_record("rested_day", (Time.get_ticks_usec() - started) / 1000.0, "ms for advance_day() after 430 days (most bonds at rest)")

	var path := "user://bench_web.bin"
	started = Time.get_ticks_usec()
	web.save_binary(path)
	_record("save_binary", (Time.get_ticks_usec() - started) / 1000.0, "ms save_binary() (%.1f MB)" % (FileAccess.get_file_as_bytes(path).size() / 1048576.0))
	var copy := RelationshipWeb.new()
	started = Time.get_ticks_usec()
	copy.load_binary(path)
	_record("load_binary", (Time.get_ticks_usec() - started) / 1000.0, "ms load_binary()")
	var same := JSON.stringify(copy.to_dict(), "", false, true) == JSON.stringify(web.to_dict(), "", false, true)
	print("       reloaded web identical: %s" % same)
	if not same:
		failures += 1
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var json_path := "user://bench_web.json"
	started = Time.get_ticks_usec()
	web.save_json(json_path)
	var json_save := (Time.get_ticks_usec() - started) / 1000.0
	started = Time.get_ticks_usec()
	RelationshipWeb.new().load_json(json_path)
	print("       save_json %.0f ms, load_json %.0f ms (%.1f MB)" % [json_save, (Time.get_ticks_usec() - started) / 1000.0,
		FileAccess.get_file_as_bytes(json_path).size() / 1048576.0])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(json_path))

	print("\n%d budgets, %d over" % [results.size(), failures])
	get_tree().quit(1 if failures > 0 else 0)


func _record(key: String, value: float, what: String) -> void:
	results[key] = value
	var budget: float = BUDGETS[key]
	var within := value <= budget
	if not within:
		failures += 1
	print("%s  %8.2f  %s  (budget %s)" % ["ok  " if within else "OVER", value, what, budget])


func _open_grievances(web: RelationshipWeb) -> int:
	var n := 0
	for bond in web.get_all_bonds():
		n += bond.grievances.size()
	return n
