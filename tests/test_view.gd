extends Node
## Headless checks for the Lite web view. Run:
##   godot --headless --path . res://tests/test_view.tscn
## Exit code 0 when all pass.

var failures := 0
var checks := 0


func _ready() -> void:
	var started := Time.get_ticks_msec()
	await _test_folding_and_live_updates()
	await _test_filters()
	await _test_clicks_and_keys()
	await _test_selection_and_focus()
	await _test_markers()
	await _test_lite_mark()
	await _test_layout()
	await _test_settled_signal()
	_test_colours_and_words()
	if checks < 10:
		failures += 1
		print("FAIL  only %d checks ran: something failed to load (look for SCRIPT ERROR above)" % checks)
	print("\n%d checks, %d failed (%.2f s)" % [checks, failures, (Time.get_ticks_msec() - started) / 1000.0])
	await get_tree().process_frame          # let freed views finish going before the engine checks for leaks
	await get_tree().process_frame
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


## a, b, c, d, e: a–b friends, b–c rivals, c–d family, a→e one way, e on their own otherwise.
func _web() -> RelationshipWeb:
	var web := RelationshipWeb.new()
	for id: String in ["a", "b", "c", "d", "e"]:
		web.add_person(id, {"data": {"name": id.to_upper() + "nna"}})
	web.link("a", "b", &"friend")
	web.link("b", "c", &"rival")
	web.link("c", "d", &"family")
	web.link_one_way("a", "e", {"affinity": 20, "tags": ["crush"]})
	return web


func _view(web: RelationshipWeb) -> RelationshipWebView:
	var view := RelationshipWebView.new()
	view.size = Vector2(800, 600)
	add_child(view)
	view.web = web
	view.settle()
	return view


## The painted colour of one pair's segment (the last one: b's side of the fade), with the layout settled so the
## line is drawn in full.
func _painted(view: RelationshipWebView, a: String, b: String) -> Color:
	view.settle()
	view._sync()
	var pair := view._find_pair(a, b)
	var bucket: int = view._pair_bucket[pair]
	var slot: int = view._pair_slot[pair]
	return view._line_colors[bucket][slot + view._bucket_segments(bucket) - 1]


func _test_folding_and_live_updates() -> void:
	var web := _web()
	var view := _view(web)
	eq(view._pa.size(), 4, "both directions of a pair fold into one line (4 pairs from 7 bonds)")
	ok(view.select_pair("a", "e"), "a one-way bond is still a pair")
	ok(view._ab[view._find_pair("a", "e")] != null and view._ba[view._find_pair("a", "e")] == null, "with one side missing")
	ok(not view.select_pair("a", "c"), "people with no bond aren't a pair")
	web.link("a", "d")
	ok(view.select_pair("a", "d"), "a new link shows up (the view follows the web)")
	var before_color := _painted(view, "a", "b")
	web.apply("b", "a", {"affinity": -80})
	var after_color := _painted(view, "a", "b")
	ok(not after_color.is_equal_approx(before_color), "changed feelings recolour the line")
	ok(after_color.r > after_color.g, "toward the cold colour")
	web.add_person("f")
	ok(view.get_person_screen_position("f").is_finite(), "a new person is drawn")
	var before := view.get_layout_positions()
	web.remove_person("e")
	ok(not view.get_person_screen_position("e").is_finite(), "a removed person is gone")
	ok(not view.select_pair("a", "e"), "and so are their lines")
	var after := view.get_layout_positions()
	var b_after: Vector2 = after["b"]
	var b_before: Vector2 = before["b"]
	ok(b_after.is_equal_approx(b_before), "everyone else keeps their place when the web changes")
	eq(view.get_label("a"), "Anna", "people are named from their data")
	eq(view.get_label("nobody"), "", "and nobody has no name")
	view.web = null
	ok(not view.get_person_screen_position("a").is_finite(), "setting the web to null clears the view")
	view.queue_free()
	await get_tree().process_frame


func _test_filters() -> void:
	var web := _web()
	var view := _view(web)
	view.min_affinity = 0.0
	view._sync()
	eq(_shown_pairs(view), ["a|b", "a|e", "c|d"], "affinity 0..100: the rivals go")
	view.min_affinity = -100.0
	view.show_family = false
	view._sync()
	eq(_shown_pairs(view), ["a|b", "a|e", "b|c"], "family hidden")
	view.show_family = true
	view.show_others = false
	view._sync()
	eq(_shown_pairs(view), ["c|d"], "only family")
	view.show_others = true
	view.only_tags = PackedStringArray(["crush"])
	view._sync()
	eq(_shown_pairs(view), ["a|e"], "only pairs tagged crush")
	view.only_tags = PackedStringArray()
	view.focus_person = "a"
	view._sync()
	eq(_shown_pairs(view), ["a|b", "a|e"], "focus on a, one step out")
	view.focus_depth = 2
	view._sync()
	eq(_shown_pairs(view), ["a|b", "a|e", "b|c"], "two steps out")
	ok(view._faded[view._index["d"]] == 1 and view._faded[view._index["a"]] == 0, "people outside the focus are faded")
	view.focus_person = ""
	view.custom_filter = func(ab: RelationshipBond, _ba: RelationshipBond) -> bool: return ab != null and ab.kin
	view._sync()
	eq(_shown_pairs(view), ["c|d"], "your own filter")
	view.custom_filter = Callable()
	web.open_grievance("b", "c", 2)
	view.only_grudges = true
	view._sync()
	eq(_shown_pairs(view), ["b|c"], "only grudges")
	view.only_grudges = false
	view._sync()
	eq(_shown_pairs(view).size(), 4, "every filter off shows everything")
	view.queue_free()
	await get_tree().process_frame


func _shown_pairs(view: RelationshipWebView) -> Array[String]:
	var shown: Array[String] = []
	for pair in view._pa.size():
		if view._shown[pair] == 1:
			shown.append("%s|%s" % [view._ids[view._pa[pair]], view._ids[view._pb[pair]]])
	shown.sort()
	return shown


func _click(view: RelationshipWebView, at: Vector2, shift: bool = false, double: bool = false) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = at
		event.pressed = pressed
		event.shift_pressed = shift
		event.double_click = double and pressed
		view._gui_input(event)


func _test_clicks_and_keys() -> void:
	var web := _web()
	var view := _view(web)
	var heard: Array[String] = []
	view.person_selected.connect(func(id: String) -> void: heard.append("person " + id))
	view.pair_selected.connect(func(a: String, b: String) -> void: heard.append("pair %s %s" % [a, b]))
	view.selection_cleared.connect(func() -> void: heard.append("cleared"))
	view.person_activated.connect(func(id: String) -> void: heard.append("activated " + id))
	_click(view, view.get_person_screen_position("a"))
	eq(view.get_selected_person(), "a", "a click selects a person")
	_click(view, view.get_person_screen_position("b"), true)
	eq(view.get_selected_pair(), PackedStringArray(["a", "b"]), "a Shift-click on a second person selects the pair")
	_click(view, view.get_person_screen_position("c"), false, true)
	var corner := Vector2(2, 2)
	_click(view, corner)
	eq(view.get_selected_person(), "", "a click on empty space clears")
	var middle := (view.get_person_screen_position("c") + view.get_person_screen_position("d")) / 2.0
	var curve := view._curve_point(view._layout.positions[view._index["c"]], view._layout.positions[view._index["d"]], 0.5) * view.zoom + view.pan
	_click(view, curve if view._pair_at(curve) >= 0 else middle)
	eq(view.get_selected_pair(), PackedStringArray(["c", "d"]), "a click on a line selects its pair")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	view._gui_input(escape)
	eq(heard, ["person a", "pair a b", "activated c", "cleared", "pair c d", "cleared"] as Array[String], "every signal, in order")
	var a_before := view.get_person_screen_position("a")
	for step: int in 3:
		var event := InputEventMouseButton.new() if step != 1 else null
		if step == 0:
			event.button_index = MOUSE_BUTTON_LEFT
			event.position = a_before
			event.pressed = true
			view._gui_input(event)
		elif step == 1:
			var drag := InputEventMouseMotion.new()
			drag.position = a_before + Vector2(60, 40)
			drag.relative = Vector2(60, 40)
			view._gui_input(drag)
		else:
			event.button_index = MOUSE_BUTTON_LEFT
			event.position = a_before + Vector2(60, 40)
			event.pressed = false
			view._gui_input(event)
	ok(view._layout.pinned[view._index["a"]] == 1, "dragging a person pins them")
	ok(view.get_person_screen_position("a").distance_to(a_before + Vector2(60, 40)) < 1.0, "where they were dropped")
	view.unpin_all()
	ok(view._layout.pinned[view._index["a"]] == 0, "unpin_all lets them go")
	var zoom_before := view.zoom
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	wheel.position = Vector2(400, 300)
	view._gui_input(wheel)
	ok(view.zoom > zoom_before and not view.auto_fit, "scrolling zooms in and stops auto-fitting")
	var hover := InputEventMouseMotion.new()
	hover.position = view.get_person_screen_position("b")
	view._gui_input(hover)
	eq(view._hover, view._index["b"], "moving over a person hovers them")
	eq(view.tooltip_text, "Bnna", "with their name as the tooltip")
	view.queue_free()
	await get_tree().process_frame


func _test_selection_and_focus() -> void:
	var web := _web()
	var view := _view(web)
	var changes := [0]
	var count := func() -> void: changes[0] += 1
	view.selection_changed.connect(count)
	view.select_person("b")
	eq(changes[0], 1, "select_person fires selection_changed")
	eq(view._focus_pairs.size(), 2, "b's two pairs light up")
	ok(view._focus_people.has(view._index["a"]) and view._focus_people.has(view._index["c"]), "with the people on them")
	view.select_pair("c", "d")
	eq(changes[0], 2, "select_pair fires it too")
	eq(view._focus_pairs.size(), 1, "one pair lit up")
	view.clear_selection()
	eq(changes[0], 3, "and clear_selection")
	view.clear_selection()
	eq(changes[0], 3, "clearing twice fires once")
	ok(view._focus_pairs.is_empty(), "nothing lit up")
	view.highlight_pair("a", "b")
	eq(view._focus_pairs.size(), 1, "highlight_pair lights a pair up without selecting")
	eq(view.get_selected_pair().size(), 0, "nothing selected")
	view.highlight_pair("", "")
	ok(view._focus_pairs.is_empty(), "and lets it go")
	view.selection_changed.disconnect(count)
	for _i: int in 20:
		await get_tree().process_frame
	view.select_person("a")
	await get_tree().process_frame
	await get_tree().process_frame
	ok(view._focus_amount > 0.0, "focus fades in over a few frames")
	ok(view._line_layer.modulate.a < 1.0, "dimming the other lines")
	view.queue_free()
	await get_tree().process_frame


func _test_markers() -> void:
	var web := RelationshipWeb.new()
	for id: String in ["x", "y", "z", "w"]:
		web.add_person(id)
	web.link("x", "y", {"affinity": -60, "trust": 60, "familiarity": 40})     # trusting enemies: no broken line
	web.link("z", "w", &"stranger")
	web.open_grievance("x", "y", 4, "the fence")
	var view := _view(web)
	var xy := view._find_pair("x", "y")
	eq(view._grudges(xy), 1, "one grudge on the pair")
	ok(view._carries_marker(xy) and not view._carries_marker(view._find_pair("z", "w")), "the grudge carries an ember; strangers carry nothing")
	var faint := _painted(view, "z", "w")
	var strong := _painted(view, "x", "y")
	ok(faint.a < 0.2 and strong.a > 0.8, "strangers are a hairline; enemies are drawn in full (%.2f vs %.2f)" % [faint.a, strong.a])
	view.queue_free()
	await get_tree().process_frame


func _test_lite_mark() -> void:
	var view := _view(_web())
	ok(view.is_lite(), "this is the Lite view")
	ok(view._mark_layer != null and view._mark_layer.get_index(true) > view._people_layer.get_index(true),
		"the mark has a layer of its own, over the people")
	ok(view._mark_layer.mouse_filter == Control.MOUSE_FILTER_IGNORE, "and it doesn't get in the way of clicks")
	ok(view._LITE_MARK != null and view._LITE_MARK.get_width() > 0, "the knight is there to draw")
	view.queue_free()
	await get_tree().process_frame

func _test_layout() -> void:
	var one := _view(_web())
	var two := _view(_web())
	var same := true
	for id: String in ["a", "b", "c", "d", "e"]:
		var p1: Vector2 = one.get_layout_positions()[id]
		var p2: Vector2 = two.get_layout_positions()[id]
		same = same and p1.is_equal_approx(p2)
	ok(same, "the same web always settles the same way")
	ok(one.is_settled(), "settle() settles")
	var saved := one.get_layout_positions()
	one.relayout()
	one.set_layout_positions(saved)
	var c_now: Vector2 = one.get_layout_positions()["c"]
	var c_saved: Vector2 = saved["c"]
	ok(c_now.is_equal_approx(c_saved), "a saved layout is restored")
	var linked := one._layout.positions[one._index["a"]].distance_to(one._layout.positions[one._index["b"]])
	var apart := one._layout.positions[one._index["a"]].distance_to(one._layout.positions[one._index["d"]])
	ok(linked < apart, "linked people end up closer than strangers (%.0f < %.0f)" % [linked, apart])
	one.fit_view()
	var inside := true
	for id: String in ["a", "b", "c", "d", "e"]:
		var p := one.get_person_screen_position(id)
		inside = inside and Rect2(Vector2.ZERO, one.size).has_point(p)
	ok(inside, "fit_view puts everyone on screen")
	var wide := _view(_web())
	wide.size = Vector2(1600, 400)
	wide.relayout()
	wide.settle()
	var bounds := wide._layout.bounds()
	ok(bounds.size.x > bounds.size.y, "a wide view gets a wide layout (%.0f × %.0f)" % [bounds.size.x, bounds.size.y])
	one.queue_free()
	two.queue_free()
	wide.queue_free()
	await get_tree().process_frame


func _test_settled_signal() -> void:
	var web := _web()
	var view := RelationshipWebView.new()
	view.size = Vector2(800, 600)
	add_child(view)
	view.web = web
	var settled := [false]
	view.layout_settled.connect(func() -> void: settled[0] = true)
	for _i: int in 600:
		await get_tree().process_frame
		if settled[0]:
			break
	var did_settle: bool = settled[0]
	ok(did_settle, "the animated layout settles and says so")
	ok(not view.is_processing(), "and then stops working every frame")
	web.apply("a", "b", {"affinity": 5})
	ok(view.is_processing(), "a change wakes it")
	await get_tree().process_frame
	await get_tree().process_frame
	ok(not view.is_processing(), "and it sleeps again once redrawn")
	view.queue_free()
	await get_tree().process_frame


func _test_colours_and_words() -> void:
	var view := RelationshipWebView.new()
	var style := view.style
	ok(view.affinity_color(-100.0).is_equal_approx(style.cold_color), "-100 is the cold colour")
	ok(view.affinity_color(0.0).is_equal_approx(style.neutral_color), "0 is the neutral colour")
	ok(view.affinity_color(100.0).is_equal_approx(style.warm_color), "+100 is the warm colour")
	style.cold_color = Color.BLUE
	ok(view.affinity_color(-100.0).is_equal_approx(Color.BLUE), "colours are yours to change")
	var first := style.bold_font()
	style.font = ThemeDB.fallback_font
	ok(style.bold_font() != first, "a new font replaces the cached weights")
	eq(style.palette_color("Keep"), style.palette_color("Keep"), "a group always gets the same colour")
	view.free()
