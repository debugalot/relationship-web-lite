extends Node
## Headless checks for Relationship Web Lite. Run:
##   godot --headless --path . res://tests/test_web.tscn
## Exit code 0 when all pass. Some checks feed in bad input on purpose, so ERROR and WARNING lines from the
## addon are expected in the output; the checks themselves say what passed.

var failures := 0
var checks := 0


func _ready() -> void:
	var started := Time.get_ticks_msec()
	_test_people()
	_test_links_and_presets()
	_test_affinity_maths()
	_test_saturation_guard()
	_test_trust_and_attachment()
	_test_familiarity_and_contact()
	_test_set_feelings_and_bands()
	_test_baseline()
	_test_grievances()
	_test_tension()
	_test_daily_drift()
	_test_festering()
	_test_letting_go()
	_test_remove_and_unlink()
	_test_signals_during_a_day()
	_test_determinism()
	_test_saving()
	_test_bad_saves()
	_test_tuning_problems()
	_test_bad_input()
	_test_data_is_copied()
	_test_custom_presets()
	_test_grievance_queries()
	_test_remembered_grievances()
	if checks < 10:
		failures += 1
		print("FAIL  only %d checks ran: something failed to load (look for SCRIPT ERROR above)" % checks)
	print("\n%d checks, %d failed (%.2f s)" % [checks, failures, (Time.get_ticks_msec() - started) / 1000.0])
	get_tree().quit(1 if failures > 0 else 0)


func ok(cond: bool, what: String) -> void:
	checks += 1
	if cond:
		print("ok    ", what)
	else:
		failures += 1
		print("FAIL  ", what)


func eq(a: Variant, b: Variant, what: String) -> void:
	var same: bool = a == b
	ok(same, what + ("" if same else "  (got %s, expected %s)" % [a, b]))


func near(a: float, b: float, what: String, eps: float = 1e-9) -> void:
	ok(absf(a - b) <= eps, what + ("" if absf(a - b) <= eps else "  (got %.12f, expected %.12f)" % [a, b]))


## Two people, "a" and "b", with optional traits, linked as acquaintances.
func _pair(a_traits: Dictionary = {}, b_traits: Dictionary = {}) -> RelationshipWeb:
	var web := RelationshipWeb.new()
	web.add_person("a", a_traits)
	web.add_person("b", b_traits)
	web.link("a", "b")
	return web


func _test_people() -> void:
	var web := RelationshipWeb.new()
	var added: Array[String] = []
	web.person_added.connect(func(id: String) -> void: added.append(id))
	var ana := web.add_person("ana", {"volatility": 150, "pride": -5, "attachment": "Anxious", "data": {"job": "smith"}})
	eq(ana.volatility, 100.0, "traits clamp to 100")
	eq(ana.pride, 0.0, "traits clamp to 0")
	eq(ana.attachment, RelationshipPerson.Attachment.ANXIOUS, "attachment by name, any case")
	eq(ana.forgiveness, 50.0, "unset traits default to 50")
	eq(ana.data, {"job": "smith"}, "data kept")
	web.add_person("bo", {"attachment": RelationshipPerson.Attachment.AVOIDANT})
	eq(web.get_person("bo").attachment, RelationshipPerson.Attachment.AVOIDANT, "attachment by enum value")
	eq(web.add_person("ana"), ana, "adding a repeated id returns the person already there")
	eq(web.get_person_ids(), PackedStringArray(["ana", "bo"]), "ids in the order added")
	eq(added, ["ana", "bo"] as Array[String], "person_added fires once per new person")
	ok(web.add_person("") == null, "an empty id is refused")
	ana.volatility = NAN
	eq(ana.volatility, 100.0, "a NaN trait is refused and the old value kept")
	ana.id = "someone_else"
	eq(ana.id, "ana", "an id can't change once set")
	eq(web.get_person_count(), 2, "two people")


func _test_links_and_presets() -> void:
	var web := RelationshipWeb.new()
	for id: String in ["a", "b", "c"]:
		web.add_person(id)
	ok(web.link("a", "b", &"friend", &"rival"), "link with a preset each way")
	eq(web.get_bond("a", "b").affinity, 40.0, "friend affinity")
	eq(web.get_bond("a", "b").familiarity_floor, 10.0, "friend floor")
	eq(web.get_bond("b", "a").affinity, -25.0, "rival the other way: lopsided")
	eq(web.get_bond("b", "a").band, RelationshipWeb.COLD, "rival starts cold")
	eq(web.get_bond("a", "b").band, RelationshipWeb.WARM, "friend starts warm")
	ok(web.link("a", "c", {"affinity": 70, "kin": true, "tags": ["mentor"]}), "link with a custom dictionary")
	var custom := web.get_bond("c", "a")
	eq(custom.affinity, 70.0, "custom affinity both ways by default")
	ok(custom.kin, "custom kin")
	eq(custom.tags, PackedStringArray(["mentor"]), "custom tags")
	eq(custom.trust, 30.0, "keys left out come from acquaintance")
	ok(web.link_one_way("b", "c", &"enemy"), "one-way link")
	ok(web.has_bond("b", "c") and not web.has_bond("c", "b"), "one way only")
	ok(not web.link("a", "a"), "nobody links to themselves")
	ok(not web.link("a", "nobody"), "linking someone not in the web fails")
	web.link("b", "c", &"no_such_preset")
	eq(web.get_bond("b", "c").affinity, 0.0, "an unknown preset falls back to acquaintance")
	var g := web.open_grievance("a", "b", 2)
	web.link("a", "b", &"partner")
	eq(web.get_bond("a", "b").affinity, 60.0, "relinking resets to the new preset")
	eq(web.get_grievances("a", "b"), [g] as Array[RelationshipGrievance], "relinking keeps grievances")
	eq(web.get_bonds_from("a").size(), 2, "a feels something about two people")
	eq(web.get_bonds_to("c").size(), 2, "two people feel something about c")
	eq(web.get_bond_count(), 6, "six bonds")


func _test_affinity_maths() -> void:
	var calm := _pair({"volatility": 0})
	calm.apply("a", "b", {"affinity": 10}, false)
	near(calm.get_bond("a", "b").affinity, 6.0, "a calm person feels +10 as +6 (0.6×)")
	var volatile := _pair({"volatility": 100})
	volatile.apply("a", "b", {"affinity": 10}, false)
	near(volatile.get_bond("a", "b").affinity, 14.0, "a volatile person feels +10 as +14 (1.4×)")
	var web := _pair()
	web.set_feelings("a", "b", {"affinity": 50})
	web.apply("a", "b", {"affinity": 10}, false)
	near(web.get_bond("a", "b").affinity, 56.0, "a gain at +50 keeps 1 - 50/125 = 60%")
	web.set_feelings("a", "b", {"affinity": 50})
	web.apply("a", "b", {"affinity": -10}, false)
	near(web.get_bond("a", "b").affinity, 40.0, "a loss at +50 isn't damped")
	web.set_feelings("a", "b", {"affinity": -50})
	web.apply("a", "b", {"affinity": -10}, false)
	near(web.get_bond("a", "b").affinity, -56.0, "a loss at -50 keeps 60%")
	web.set_feelings("a", "b", {"affinity": 100})
	web.apply("a", "b", {"affinity": 50}, false)
	near(web.get_bond("a", "b").affinity, 100.0, "affinity never passes 100")
	web.set_feelings("a", "b", {"affinity": -100})
	web.apply("a", "b", {"affinity": -50}, false)
	near(web.get_bond("a", "b").affinity, -100.0, "affinity never passes -100")
	near(web.get_bond("b", "a").affinity, 0.0, "the other direction is untouched")


func _test_saturation_guard() -> void:
	# Tapestry's formula with saturation_divisor below 100 turns gains near the top into losses.
	var web := _pair()
	web.tuning.saturation_divisor = 50.0
	web.set_feelings("a", "b", {"affinity": 90})
	web.apply("a", "b", {"affinity": 10}, false)
	var after := web.get_bond("a", "b").affinity
	ok(after >= 90.0, "a kind act never lowers affinity, whatever saturation_divisor says (%s)" % after)
	near(after, 91.0, "saturation_divisor below 100 is treated as 100 (keeps 1 - 90/100 = 10%)")
	web.tuning.saturation_divisor = NAN
	web.set_feelings("a", "b", {"affinity": 50})
	web.apply("a", "b", {"affinity": 10}, false)
	near(web.get_bond("a", "b").affinity, 56.0, "a NaN saturation_divisor falls back to the default")


func _test_trust_and_attachment() -> void:
	var expected := {
		"secure": [40.0, 20.0], "avoidant": [36.0, 20.0], "anxious": [40.0, 17.0], "disorganized": [38.0, 18.0],
	}
	for style: String in expected:
		var pair: Array = expected[style]
		var gain: float = pair[0]
		var loss: float = pair[1]
		var w := _pair({"attachment": style})
		w.apply("a", "b", {"trust": 10}, false)
		near(w.get_bond("a", "b").trust, gain, "%s: +10 trust from 30" % style)
		w.set_feelings("a", "b", {"trust": 30})
		w.apply("a", "b", {"trust": -10}, false)
		near(w.get_bond("a", "b").trust, loss, "%s: -10 trust from 30" % style)
	var web := _pair()
	web.apply("a", "b", {"trust": 500}, false)
	eq(web.get_bond("a", "b").trust, 100.0, "trust never passes 100")
	web.apply("a", "b", {"trust": -500}, false)
	eq(web.get_bond("a", "b").trust, 0.0, "trust never goes below 0")


func _test_familiarity_and_contact() -> void:
	var web := _pair()
	web.apply("a", "b", {})
	near(web.get_bond("a", "b").familiarity, 7.0, "contact adds 2 familiarity on its own")
	eq(web.get_bond("a", "b").last_contact_day, 0, "contact is remembered")
	web.apply("a", "b", {"familiarity": 10})
	near(web.get_bond("a", "b").familiarity, 19.0, "an event's familiarity plus contact")
	var apart := _pair()
	apart.apply("a", "b", {"affinity": 5}, false)
	near(apart.get_bond("a", "b").familiarity, 5.0, "no contact, no familiarity")
	eq(apart.get_bond("a", "b").last_contact_day, -1, "no contact, no contact day")
	var fresh := RelationshipWeb.new()
	fresh.add_person("x")
	fresh.add_person("y")
	var added: Array[String] = []
	fresh.bond_added.connect(func(f: String, t: String) -> void: added.append(f + ">" + t))
	var bond := fresh.apply("x", "y", {"affinity": 10})
	ok(bond != null and fresh.has_bond("x", "y"), "apply makes a bond on first contact")
	eq(added, ["x>y"] as Array[String], "bond_added for it, one way only")
	ok(not fresh.has_bond("y", "x"), "the other way waits for its own contact")


func _test_set_feelings_and_bands() -> void:
	var web := _pair()
	var changes: Array[String] = []
	web.band_changed.connect(func(f: String, t: String, old_band: StringName, new_band: StringName) -> void:
		changes.append("%s>%s %s>%s" % [f, t, old_band, new_band]))
	var changed := [0]
	web.bond_changed.connect(func(_f: String, _t: String) -> void: changed[0] += 1)
	web.set_feelings("a", "b", {"affinity": 34.9})
	eq(web.get_bond("a", "b").band, RelationshipWeb.NEUTRAL, "34.9 is neutral")
	web.set_feelings("a", "b", {"affinity": 35})
	eq(web.get_bond("a", "b").band, RelationshipWeb.WARM, "35 is warm")
	web.set_feelings("a", "b", {"affinity": -15})
	eq(web.get_bond("a", "b").band, RelationshipWeb.COLD, "-15 is cold")
	eq(changes, ["a>b neutral>warm", "a>b warm>cold"] as Array[String], "band_changed with the old and new band")
	eq(changed[0], 3, "bond_changed once per change")
	web.set_feelings("a", "b", {"affinity": -15})
	eq(changed[0], 3, "setting the same value isn't a change")
	web.set_feelings("a", "b", {"affinity": 500, "trust": -3, "familiarity": 101})
	var bond := web.get_bond("a", "b")
	ok(bond.affinity == 100.0 and bond.trust == 0.0 and bond.familiarity == 100.0, "set_feelings clamps")
	web.set_feelings("a", "b", {"baseline": 20})
	ok(bond.baseline == 20.0 and bond.anchor == 20.0, "setting the baseline also moves its anchor")
	eq(web.band_of(35.0), RelationshipWeb.WARM, "band_of warm")
	eq(web.band_of(0.0), RelationshipWeb.NEUTRAL, "band_of neutral")


func _test_baseline() -> void:
	var web := RelationshipWeb.new()
	web.add_person("a")
	web.add_person("b")
	web.link("a", "b", &"friend")
	web.shift_baseline("a", "b", 50)
	eq(web.get_bond("a", "b").baseline, 60.0, "the baseline heals up to anchor + band (30 + 30)")
	web.shift_baseline("a", "b", -100)
	eq(web.get_bond("a", "b").baseline, 0.0, "and scars down to anchor - band")
	ok(web.shift_baseline("a", "nobody", 5) == null, "no bond, no shift")


func _test_grievances() -> void:
	var web := _pair({"pride": 50}, {"pride": 70})
	var opened: Array[int] = []
	var resolved: Array[String] = []
	web.grievance_opened.connect(func(x: RelationshipGrievance) -> void: opened.append(x.severity))
	web.grievance_resolved.connect(func(x: RelationshipGrievance) -> void: resolved.append(x.resolution))
	var g := web.open_grievance("a", "b", 2, "Broke my cart.")
	eq(g.severity, 2, "severity as given")
	eq(g.id, 1, "ids count from 1")
	eq(g.opened_day, 0, "opened today")
	eq(web.open_grievance("b", "a", 2).severity, 3, "a proud holder (70) takes it one step harder")
	eq(web.open_grievance("b", "a", 5).severity, 5, "but never past 5")
	eq(web.open_grievance("a", "b", 9).severity, 5, "out-of-range severity is clamped")
	eq(opened, [2, 3, 5, 5] as Array[int], "grievance_opened for each")
	ok(web.escalate(g) and g.severity == 3, "escalate")
	web.escalate(g)
	web.escalate(g)
	web.escalate(g)
	eq(g.severity, 5, "escalate stops at 5")
	var small := web.open_grievance("a", "b", 2)
	ok(not web.soften(small) and small.severity == 1, "soften 2 → 1")
	ok(web.soften(small), "softening a 1 resolves it")
	ok(small.status == RelationshipGrievance.Status.RESOLVED and small.severity == 1, "resolved, severity kept at 1")
	eq(small.resolved_day, 0, "resolved today")
	ok(not web.get_grievances("a", "b").has(small), "a resolved grievance leaves its bond")
	ok(web.get_grievance(small.id) == null, "and the web's index")
	ok(not web.soften(small), "a resolved grievance can't be softened again")
	ok(web.resolve(g, "Paid for the cart."), "resolve with your own words")
	eq(resolved, ["Softened until nothing was left of it", "Paid for the cart."] as Array[String], "grievance_resolved with how")
	var other := _pair()
	var foreign := other.open_grievance("a", "b", 1)
	ok(not web.resolve(foreign), "another web's grievance is refused")
	ok(not web.escalate(null), "null is refused")
	ok(web.get_bond("a", "b").has_active_grievance(), "one grievance still open on a→b")
	eq(web.get_bond("b", "a").worst_grievance().severity, 5, "worst grievance")


func _test_tension() -> void:
	var web := _pair()
	eq(web.tension("a", "b"), 0.0, "no grievances, no tension")
	web.open_grievance("a", "b", 2)
	var g := web.open_grievance("a", "b", 3)
	g.status = RelationshipGrievance.Status.FESTERING
	near(web.tension("a", "b"), 2.0 * 1.7 + 3.0 * 1.7 + 2.0, "Σ severity × (1 + (100 - 30)/100) + 2 per festering")
	eq(web.tension("a", "nobody"), 0.0, "no bond, no tension")


func _test_daily_drift() -> void:
	var web := _pair({"loyalty": 50})
	web.set_feelings("a", "b", {"affinity": 40, "familiarity": 50})
	var days: Array[int] = []
	web.day_advanced.connect(func(d: int) -> void: days.append(d))
	web.advance_day()
	near(web.get_bond("a", "b").affinity, 40.0 - 40.0 * 0.03 * 0.75 * 0.75, "affinity drifts toward the baseline (×(1 - loyalty/200)(1 - familiarity/200))")
	near(web.get_bond("a", "b").familiarity, 49.6, "familiarity fades 0.4 a day without contact")
	eq(web.day, 1, "the day moves on")
	eq(days, [1] as Array[int], "day_advanced with the new day")
	var loyal := _pair({"loyalty": 100})
	loyal.set_feelings("a", "b", {"affinity": 40, "familiarity": 50})
	loyal.advance_day()
	ok(loyal.get_bond("a", "b").affinity > web.get_bond("a", "b").affinity, "loyal people hold feelings longer")
	var met := _pair()
	met.set_feelings("a", "b", {"familiarity": 50})
	met.apply("a", "b", {})
	met.advance_day()
	near(met.get_bond("a", "b").familiarity, 52.0, "contact today stops the fade")
	var floor_web := RelationshipWeb.new()
	floor_web.add_person("a")
	floor_web.add_person("b")
	floor_web.link("a", "b", {"familiarity": 30.2, "floor": 30})
	floor_web.advance_day()
	near(floor_web.get_bond("a", "b").familiarity, 30.0, "familiarity stops at its floor")
	var trust_web := _pair()
	trust_web.set_feelings("a", "b", {"trust": 80, "affinity": 60})
	trust_web.advance_day(30)
	eq(trust_web.get_bond("a", "b").trust, 80.0, "trust never drifts")
	eq(trust_web.day, 30, "advance_day(30) moves thirty days")
	var resting := _pair()
	resting.set_feelings("a", "b", {"affinity": 0.04, "familiarity": 0})
	resting.advance_day()
	eq(resting.get_bond("a", "b").affinity, 0.0, "a bond within rest_epsilon of its baseline snaps onto it")
	var bands: Array[String] = []
	var crossing := _pair({"loyalty": 0})
	crossing.set_feelings("a", "b", {"affinity": 35.2, "familiarity": 0})
	crossing.band_changed.connect(func(_f: String, _t: String, old_band: StringName, new_band: StringName) -> void:
		bands.append("%s>%s" % [old_band, new_band]))
	crossing.advance_day()
	eq(bands, ["warm>neutral"] as Array[String], "drifting out of a band fires band_changed")
	crossing.advance_day(0)
	eq(crossing.day, 1, "advance_day(0) is refused")
	var settle := _pair()
	settle.advance_day(20)
	ok(settle.get_bond("a", "b").is_at_rest(), "an acquaintance with nothing going on comes to rest")
	settle.apply("a", "b", {"affinity": 20})
	ok(not settle.get_bond("a", "b").is_at_rest(), "an event wakes it")
	settle.advance_day()
	ok(settle.get_bond("a", "b").affinity < 20.0, "and the woken bond drifts again (%s)" % settle.get_bond("a", "b").affinity)
	var gone := settle.get_bond("a", "b")
	settle.unlink("a", "b")
	ok(not gone.is_in_web(), "an unlinked bond knows it has left the web")
	settle.advance_day(3)
	eq(settle.day, 24, "removed bonds still on the tick's list are skipped safely")


func _test_festering() -> void:
	var web := _pair({"forgiveness": 0, "pride": 50})
	web.set_feelings("a", "b", {"familiarity": 0})
	web.open_grievance("a", "b", 2)
	web.advance_day(3)
	near(web.get_bond("a", "b").affinity, 0.0, "no cost for the first three days")
	web.advance_day()
	near(web.get_bond("a", "b").affinity, -0.3, "then 0.15 × severity × (0.5 + pride/100) a day")
	var hot := _pair({"forgiveness": 0, "pride": 50})
	hot.set_feelings("a", "b", {"familiarity": 0})
	var g := hot.open_grievance("a", "b", 3)
	var changed: Array[String] = []
	hot.grievance_changed.connect(func(x: RelationshipGrievance) -> void: changed.append(x.get_status_name()))
	hot.advance_day(10)
	eq(g.status, RelationshipGrievance.Status.OPEN, "still open after ten days")
	hot.advance_day()
	eq(g.status, RelationshipGrievance.Status.FESTERING, "severity 3 turns festering on day 10")
	eq(changed, ["festering"] as Array[String], "grievance_changed when it does")
	var a1 := hot.get_bond("a", "b").affinity
	hot.advance_day()
	var drift := (0.0 - a1) * 0.03 * 0.75 * 1.0
	near(hot.get_bond("a", "b").affinity, a1 + drift - 0.15 * 3 * 1.0 * 2.0, "festering costs double", 1e-9)
	var slight := _pair({"forgiveness": 0})
	slight.set_feelings("a", "b", {"familiarity": 0})
	var s := slight.open_grievance("a", "b", 2)
	slight.advance_day(40)
	eq(s.status, RelationshipGrievance.Status.OPEN, "severity 2 never festers")


func _test_letting_go() -> void:
	var day_for := func(seed_value: int) -> int:
		var w := _pair({"forgiveness": 100})
		w.random_seed = seed_value
		var held := w.open_grievance("a", "b", 1)
		for _i: int in 400:
			w.advance_day()
			if not held.is_active():
				ok(held.resolution == "Let it go", "seed %d: let go on day %d" % [seed_value, held.resolved_day])
				eq(w.get_bond("a", "b").baseline, -1.0, "seed %d: letting go leaves a scar of -1 on the baseline" % seed_value)
				return held.resolved_day
		return -1
	var first: int = day_for.call(7)
	ok(first >= 0, "a forgiving person lets a severity-1 grievance go")
	eq(day_for.call(7), first, "the same seed lets it go on the same day")
	var others: Array[int] = []
	for seed_value: int in [1, 2, 3, 99, -5, 123456789012345]:
		others.append(day_for.call(seed_value))
	ok(others.any(func(d: int) -> bool: return d != first), "other seeds give other days")
	var never := _pair({"forgiveness": 0})
	var kept := never.open_grievance("a", "b", 1)
	never.advance_day(400)
	ok(kept.is_active(), "forgiveness 0 never lets go")
	var severe := _pair({"forgiveness": 100})
	var big := severe.open_grievance("a", "b", 3)
	severe.advance_day(400)
	ok(big.is_active(), "severity above let_go_max_severity is never let go")
	var rate := 0
	for seed_value: int in 4000:
		if RelationshipWeb._unit(seed_value, 0, 1) < 0.25:
			rate += 1
	ok(rate > 900 and rate < 1100, "the roll is uniform enough (%d of 4000 under 0.25)" % rate)


func _test_remove_and_unlink() -> void:
	var web := RelationshipWeb.new()
	for id: String in ["a", "b", "c"]:
		web.add_person(id)
	web.link("a", "b")
	web.link("b", "c")
	web.link("a", "c")
	var g := web.open_grievance("b", "a", 3)
	var removed: Array[String] = []
	var resolved: Array[String] = []
	web.bond_removed.connect(func(f: String, t: String) -> void: removed.append(f + ">" + t))
	web.grievance_resolved.connect(func(x: RelationshipGrievance) -> void: resolved.append(x.resolution))
	ok(web.remove_person("a"), "remove a person")
	removed.sort()
	eq(removed, ["a>b", "a>c", "b>a", "c>a"] as Array[String], "every bond to and from them goes")
	eq(resolved, ["Bond removed"] as Array[String], "their grievances end")
	ok(not g.is_active() and web.get_grievance(g.id) == null, "and leave the index")
	eq(web.get_bond_count(), 2, "b and c are still linked")
	ok(not web.remove_person("a"), "removing twice fails")
	ok(web.unlink("b", "c") and web.get_bond_count() == 0, "unlink both ways")
	ok(not web.unlink("b", "c"), "nothing left to unlink")


func _test_signals_during_a_day() -> void:
	var web := RelationshipWeb.new()
	for id: String in ["a", "b", "c", "d"]:
		web.add_person(id, {"loyalty": 0})
	web.link("a", "b", {"affinity": 35.2, "familiarity": 0})
	web.link("c", "d", {"affinity": 35.2, "familiarity": 0})
	var remover := func(_f: String, _t: String, _o: StringName, _n: StringName) -> void:
		if web.has_person("d"):
			web.remove_person("d")
	web.band_changed.connect(remover)
	web.advance_day()
	eq(web.day, 1, "a handler that removes people mid-day doesn't break the day")
	ok(not web.has_person("d"), "and its change sticks")
	web.advance_day(5)
	eq(web.day, 6, "the web carries on")
	web.band_changed.disconnect(remover)      # the lambda holds the web: disconnect so both can be freed


## The same web built and run twice, and a web saved half-way, all end identical.
func _test_determinism() -> void:
	var a := _story(1234)
	var b := _story(1234)
	a.advance_day(60)
	b.advance_day(60)
	eq(_dump(a), _dump(b), "the same seed and calls give the same web")
	var whole := _story(42)
	whole.advance_day(80)
	var halves := _story(42)
	halves.advance_day(30)
	var reloaded := RelationshipWeb.new()
	var stored: Dictionary = bytes_to_var(var_to_bytes(halves.to_dict()))
	ok(reloaded.from_dict(stored), "reload through Godot's binary format")
	reloaded.advance_day(50)
	eq(_dump(reloaded), _dump(whole), "saved half-way, reloaded and run on: identical to never stopping")
	# Resting bonds are skipped by the daily tick; a web reloaded every day wakes every bond, every day, so it
	# never skips. Both must end the same: skipping a resting bond changes nothing.
	var skipping := _village()
	var never_skips := _village()
	var most_resting := 0
	for d: int in 200:
		_village_day(skipping, d)
		_village_day(never_skips, d)
		skipping.advance_day()
		var reborn: Dictionary = bytes_to_var(var_to_bytes(never_skips.to_dict()))
		never_skips.from_dict(reborn)
		never_skips.advance_day()
		var resting := 0
		for bond in skipping.get_all_bonds():
			resting += 1 if bond.is_at_rest() else 0
		most_resting = maxi(most_resting, resting)
	ok(most_resting >= 20, "many bonds came to rest along the way (up to %d of %d)" % [most_resting, skipping.get_bond_count()])
	eq(_dump(skipping), _dump(never_skips), "skipping resting bonds gives exactly the web you get without skipping")
	var from_json := RelationshipWeb.new()
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(halves.to_dict(), "", false, true))
	ok(from_json.from_dict(parsed), "reload through JSON")
	from_json.advance_day(50)
	ok(_close(from_json.to_dict(), whole.to_dict()), "through JSON, the run on matches to within 1e-9")


func _story(seed_value: int) -> RelationshipWeb:
	var web := RelationshipWeb.new()
	web.random_seed = seed_value
	var names: Array[String] = ["ana", "bo", "cy", "di", "ed", "flo"]
	var styles: Array[String] = ["secure", "anxious", "avoidant", "disorganized"]
	for i in names.size():
		web.add_person(names[i], {"volatility": 15 * i, "pride": 100 - 13 * i, "forgiveness": 90 - 11 * i,
			"loyalty": 20 + 9 * i, "attachment": styles[i % 4]})
	web.link("ana", "bo", &"partner")
	web.link("bo", "cy", &"rival")
	web.link("cy", "di", &"friend", &"acquaintance")
	web.link("di", "ed", &"family")
	web.link("ed", "flo", &"enemy")
	web.apply("ana", "bo", {"affinity": -20, "trust": -15})
	web.interact("cy", "di", {"affinity": 12, "trust": 8})
	web.open_grievance("bo", "ana", 2, "Forgot the anniversary.")
	web.open_grievance("cy", "bo", 4, "Took the prize.")
	web.open_grievance("flo", "ed", 1)
	web.open_grievance("ed", "flo", 2)
	web.open_grievance("di", "cy", 1)
	return web


## Twelve acquaintances in a ring (they settle fast) plus a few friends and a family, for the resting test.
func _village() -> RelationshipWeb:
	var web := RelationshipWeb.new()
	web.random_seed = 11
	for i: int in 12:
		web.add_person("v%d" % i, {"forgiveness": 8 * i, "loyalty": 7 * i, "pride": 100 - 6 * i})
	for i: int in 12:
		web.link("v%d" % i, "v%d" % ((i + 1) % 12))
	web.link("v0", "v6", &"friend")
	web.link("v3", "v9", &"family")
	return web


## Something happens every few days, waking bonds that had come to rest.
func _village_day(web: RelationshipWeb, d: int) -> void:
	var a := "v%d" % (d % 12)
	var b := "v%d" % ((d + 1) % 12)
	if d % 9 == 0:
		web.apply(a, b, {"affinity": 12, "trust": 4})
	if d % 23 == 0:
		web.open_grievance(b, a, 1 + d % 3, "Day %d" % d)
	if d % 31 == 5:
		web.set_feelings(a, b, {"affinity": -20})


func _dump(web: RelationshipWeb) -> String:
	return JSON.stringify(web.to_dict(), "", false, true)


## The same structure and text, with numbers equal to within `eps`.
func _close(a: Variant, b: Variant, eps: float = 1e-9) -> bool:
	if (a is float or a is int) and (b is float or b is int):
		var x: float = a
		var y: float = b
		return absf(x - y) <= eps
	if a is Dictionary and b is Dictionary:
		var da: Dictionary = a
		var db: Dictionary = b
		if da.keys() != db.keys():
			return false
		for key: Variant in da:
			if not _close(da[key], db[key], eps):
				return false
		return true
	if a is Array and b is Array:
		var aa: Array = a
		var ab: Array = b
		if aa.size() != ab.size():
			return false
		for i in aa.size():
			if not _close(aa[i], ab[i], eps):
				return false
		return true
	var same: bool = a == b
	return same


func _test_saving() -> void:
	var web := _story(9)
	web.advance_day(12)
	web.get_person("ana").data = {"hometown": "Vell"}
	var bin_path := "user://relationship_web_test.bin"
	eq(web.save_binary(bin_path), OK, "save_binary")
	var exact := RelationshipWeb.new()
	eq(exact.load_binary(bin_path), OK, "load_binary")
	eq(_dump(exact), _dump(web), "a binary round trip is exact, to the last bit")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(bin_path))
	var path := "user://relationship_web_test.json"
	eq(web.save_json(path), OK, "save_json")
	var back := RelationshipWeb.new()
	eq(back.load_json(path), OK, "load_json")
	ok(_close(back.to_dict(), web.to_dict()), "a JSON round trip matches to within 1e-9")
	eq(back.get_person("ana").data, {"hometown": "Vell"}, "person data survives")
	eq(back.get_bond("cy", "bo").grievances[0].description, "Took the prize.", "grievance text survives")
	eq(back.get_bond("cy", "bo").grievances[0].from_id, "cy", "grievance holder survives")
	var g := back.open_grievance("ana", "bo", 1)
	ok(g.id > 5, "grievance ids carry on after a reload (%d)" % g.id)
	var big := RelationshipWeb.new()
	big.random_seed = 9007199254740993
	var copy := RelationshipWeb.new()
	var big_data: Dictionary = JSON.parse_string(JSON.stringify(big.to_dict()))
	copy.from_dict(big_data)
	eq(copy.random_seed, 9007199254740993, "a 64-bit seed survives JSON (saved as text)")
	eq(back.load_json("user://no_such_file.json"), ERR_FILE_NOT_FOUND, "a missing JSON file is reported")
	ok(back.load_binary("user://no_such_file.bin") != OK, "a missing binary file is reported")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _test_bad_saves() -> void:
	var web := _story(5)
	var good := web.to_dict()
	var cases := {
		"a newer format": func(d: Dictionary) -> void: d["format"] = 2,
		"a repeated person": func(d: Dictionary) -> void: _rows(d, "people").append(_row(d, "people")),
		"a bond to nobody": func(d: Dictionary) -> void: _row(d, "bonds")["to"] = "nobody",
		"a repeated bond": func(d: Dictionary) -> void: _rows(d, "bonds").append(_row(d, "bonds")),
		"severity 9": func(d: Dictionary) -> void: _first_grievance(d)["severity"] = 9,
		"a resolved grievance": func(d: Dictionary) -> void: _first_grievance(d)["status"] = "resolved",
		"a repeated grievance id": func(d: Dictionary) -> void: _first_grievance(d)["id"] = 2,
		"a text affinity": func(d: Dictionary) -> void: _row(d, "bonds")["affinity"] = "lots",
		"a fractional day": func(d: Dictionary) -> void: d["day"] = 1.5,
		"people not an array": func(d: Dictionary) -> void: d["people"] = "everyone",
		"a bad attachment": func(d: Dictionary) -> void: _row(d, "people")["attachment"] = "clingy",
		"a low next_grievance_id": func(d: Dictionary) -> void: d["next_grievance_id"] = 1,
		"a bad seed": func(d: Dictionary) -> void: d["random_seed"] = "lucky",
	}
	var target := _story(77)
	var before := _dump(target)
	for what: String in cases:
		var broken: Dictionary = good.duplicate(true)
		var breaker: Callable = cases[what]
		breaker.call(broken)
		ok(not target.from_dict(broken), "refused: %s" % what)
	eq(_dump(target), before, "a refused load changes nothing")
	var bad_json := "user://relationship_web_bad.json"
	var file := FileAccess.open(bad_json, FileAccess.WRITE)
	file.store_string("{not json")
	file.close()
	eq(target.load_json(bad_json), ERR_PARSE_ERROR, "broken JSON is reported")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(bad_json))


func _first_grievance(d: Dictionary) -> Dictionary:
	for row: Dictionary in _rows(d, "bonds"):
		var grievances: Array = row["grievances"]
		if not grievances.is_empty():
			return grievances[0]
	return {}


func _rows(d: Dictionary, key: String) -> Array:
	return d[key]


func _row(d: Dictionary, key: String) -> Dictionary:
	return _rows(d, key)[0]


func _test_tuning_problems() -> void:
	var t := RelationshipTuning.new()
	eq(t.get_problems().size(), 0, "the defaults have no problems")
	t.saturation_divisor = 50.0
	ok("saturation_divisor" in "".join(t.get_problems()), "saturation_divisor below 100 is a problem")
	t = RelationshipTuning.new()
	t.warm_at = 0.0
	t.cold_at = 10.0
	ok("cold_at" in "".join(t.get_problems()), "cold above warm is a problem")
	t = RelationshipTuning.new()
	t.decay_rate = NAN
	ok("finite" in "".join(t.get_problems()), "NaN is a problem")
	t = RelationshipTuning.new()
	t.fester_rate = -1.0
	ok("negative" in "".join(t.get_problems()), "a negative rate is a problem")
	var web := _pair()
	web.tuning = null
	ok(web.tuning != null, "a null tuning restores the defaults")
	var shared := RelationshipTuning.new()
	shared.contact_familiarity = 10.0
	web.tuning = shared
	web.apply("a", "b", {})
	near(web.get_bond("a", "b").familiarity, 15.0, "the web uses the tuning it is given")
	var wild := _pair({"loyalty": 50})
	wild.tuning.decay_rate = 5.0
	wild.set_feelings("a", "b", {"affinity": 40, "familiarity": 0})
	wild.advance_day()
	ok(wild.get_bond("a", "b").affinity >= 0.0, "decay_rate above 1 never overshoots the baseline")
	wild.tuning.let_go_divisor = 0.0
	wild.open_grievance("a", "b", 1)
	wild.advance_day(50)
	ok(wild.get_bond("a", "b").has_active_grievance(), "let_go_divisor 0 turns letting go off instead of dividing by zero")


func _test_bad_input() -> void:
	var web := _pair()
	ok(web.apply("a", "nobody", {"affinity": 5}) == null, "apply to someone not in the web returns null")
	web.apply("a", "b", {"affinity": "lots", "trust": 5}, false)
	near(web.get_bond("a", "b").trust, 35.0, "a non-number change is skipped, the rest applied")
	near(web.get_bond("a", "b").affinity, 0.0, "and the bad one ignored")
	web.apply("a", "b", {"afinity": 5}, false)
	near(web.get_bond("a", "b").affinity, 0.0, "a misspelt key changes nothing (and warns)")
	web.apply("a", "b", {"affinity": INF}, false)
	near(web.get_bond("a", "b").affinity, 0.0, "infinity is refused")
	ok(not web.interact("a", "b", {}, "nope"), "interact refuses a non-dictionary b_changes")
	ok(web.interact("a", "b", {"affinity": 10}, {"affinity": -10}, false), "interact both ways")
	ok(web.get_bond("a", "b").affinity > 0.0 and web.get_bond("b", "a").affinity < 0.0, "each side its own change")
	ok(web.open_grievance("a", "nobody", 1) == null, "no grievance against someone not in the web")
	ok(web.set_feelings("nobody", "b", {}) == null, "set_feelings needs both people")


func _test_data_is_copied() -> void:
	var given := {"hometown": "Vell", "tools": ["hammer"]}
	var web := RelationshipWeb.new()
	web.add_person("a", {"data": given})
	given["hometown"] = "changed"
	var tools: Array = given["tools"]
	tools.append("saw")
	eq(web.get_person("a").data, {"hometown": "Vell", "tools": ["hammer"]}, "add_person copies data in, deeply")
	var saved := web.to_dict()
	var row := _row(saved, "people")
	var row_data: Dictionary = row["data"]
	row_data["hometown"] = "edited the save"
	eq(web.get_person("a").data["hometown"], "Vell", "editing to_dict()'s result doesn't touch the web")
	var loaded := RelationshipWeb.new()
	var source := web.to_dict()
	loaded.from_dict(source)
	var loaded_row := _row(source, "people")
	var loaded_data: Dictionary = loaded_row["data"]
	loaded_data["hometown"] = "edited after load"
	eq(loaded.get_person("a").data["hometown"], "Vell", "from_dict copies data in")


func _test_custom_presets() -> void:
	var web := RelationshipWeb.new()
	for id: String in ["tom", "pip", "x", "y"]:
		web.add_person(id)
	web.presets[&"mentor"] = {"affinity": 30, "trust": 70, "familiarity": 40, "baseline": 25, "tags": ["mentor"]}
	ok(web.link("tom", "pip", &"mentor", &"acquaintance"), "link with a preset of your own")
	var bond := web.get_bond("tom", "pip")
	ok(bond.trust == 70.0 and bond.baseline == 25.0, "its values are used")
	eq(bond.tags, PackedStringArray(["mentor"]), "its tags too")
	eq(web.get_bond("pip", "tom").trust, 30.0, "the other way as an acquaintance")
	web.presets[&"acquaintance"] = {"trust": 45.0, "familiarity": 10.0}
	web.apply("x", "y", {}, false)
	ok(web.get_bond("x", "y").trust == 45.0, "first contact uses your acquaintance preset")
	web.link("tom", "pip", &"mentor", &"acquaintance")
	(web.presets[&"mentor"] as Dictionary)["trust"] = 90
	web.link("tom", "pip", &"mentor", &"acquaintance")
	eq(web.get_bond("tom", "pip").trust, 90.0, "editing a preset in place is noticed (no stale cache)")
	web.presets[&"broken"] = {"affinity": "very"}
	web.link("x", "y", &"broken")
	eq(web.get_bond("x", "y").affinity, 0.0, "a bad value in a preset is refused (and reported)")
	eq(RelationshipWeb.new().presets.has(&"mentor"), false, "each web has its own presets")
	var quiet := _pair()
	var changes := [0]
	quiet.bond_changed.connect(func(_f: String, _t: String) -> void: changes[0] += 1)
	quiet.link("a", "b")
	eq(changes[0], 0, "relinking with the same values isn't a change")
	quiet.link("a", "b", &"friend")
	eq(changes[0], 2, "relinking with new values is (once each way)")


func _test_grievance_queries() -> void:
	var web := RelationshipWeb.new()
	for id: String in ["a", "b", "c"]:
		web.add_person(id)
	var ab := web.open_grievance("a", "b", 2)
	var ac := web.open_grievance("a", "c", 3)
	var cb := web.open_grievance("c", "b", 1)
	eq(web.get_grievances_held_by("a"), [ab, ac] as Array[RelationshipGrievance], "grievances a holds")
	eq(web.get_grievances_against("b"), [ab, cb] as Array[RelationshipGrievance], "grievances held against b")
	eq(web.get_grievances_held_by("b"), [] as Array[RelationshipGrievance], "b holds none")
	web.resolve(ab)
	eq(web.get_grievances_against("b"), [cb] as Array[RelationshipGrievance], "resolved ones drop out")


func _test_remembered_grievances() -> void:
	var web := _pair({"forgiveness": 0})
	var held: Array[RelationshipGrievance] = []
	for i: int in 7:
		var g := web.open_grievance("a", "b", 1, "Wrong %d" % i)
		held.append(g)
		web.resolve(g, "Made up %d" % i)
	var past := web.get_past_grievances("a", "b")
	eq(past.size(), 5, "a bond remembers its last 5 resolved grievances")
	eq(past[0], held[2], "the oldest are forgotten first")
	eq(past[4].resolution, "Made up 6", "each keeps how it ended")
	var soft := web.open_grievance("a", "b", 1)
	web.soften(soft)
	eq(web.get_past_grievances("a", "b").back(), soft, "softened-away grievances are remembered")
	var forgiving := _pair({"forgiveness": 100})
	forgiving.random_seed = 7
	var small := forgiving.open_grievance("a", "b", 1, "Stepped on my foot")
	forgiving.advance_day(400)
	var only_small: Array[RelationshipGrievance] = [small]
	ok(not small.is_active() and forgiving.get_past_grievances("a", "b") == only_small, "let-go grievances are remembered")
	var bin_web := _story(3)
	var g1 := bin_web.open_grievance("ana", "bo", 2, "Ate the pie")
	bin_web.resolve(g1, "Baked another")
	var stored: Dictionary = bytes_to_var(var_to_bytes(bin_web.to_dict()))
	var reloaded := RelationshipWeb.new()
	ok(reloaded.from_dict(stored), "a web with memories reloads")
	var memory := reloaded.get_past_grievances("ana", "bo")
	ok(memory.size() == 1 and memory[0].description == "Ate the pie" and memory[0].resolution == "Baked another", "memories survive a save")
	eq(memory[0].status, RelationshipGrievance.Status.RESOLVED, "and are resolved")
	eq(_dump(reloaded), _dump(bin_web), "and the reloaded web is identical")
	ok(reloaded.open_grievance("ana", "bo", 1).id > g1.id, "new grievance ids carry on past remembered ones")
	var clash: Dictionary = bin_web.to_dict()
	var past_row: Dictionary = {}
	for bond_row: Dictionary in _rows(clash, "bonds"):
		if bond_row.has("past"):
			var past_rows: Array = bond_row["past"]
			past_row = past_rows[0]
	past_row["id"] = 1
	ok(not RelationshipWeb.new().from_dict(clash), "a remembered grievance can't reuse an open one's id")
	web.unlink("a", "b")
	web.link("a", "b")
	eq(web.get_past_grievances("a", "b").size(), 0, "memories go with a removed bond")
	var forgetful := _pair()
	forgetful.tuning.remembered_grievances = 0
	forgetful.resolve(forgetful.open_grievance("a", "b", 2))
	eq(forgetful.get_past_grievances("a", "b").size(), 0, "remembered_grievances 0 forgets at once")
	var bandless: Dictionary = _pair().to_dict()
	var bandless_row := _row(bandless, "bonds")
	bandless_row.erase("band")
	bandless_row["affinity"] = 40.0
	var tuned := RelationshipWeb.new()
	tuned.tuning.warm_at = 50.0
	ok(tuned.from_dict(bandless), "a save without bands loads")
	eq(tuned.get_bond("a", "b").band, RelationshipWeb.NEUTRAL, "a missing band is worked out with this web's tuning (40 < 50)")
