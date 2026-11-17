@icon("res://addons/relationship_web/icon.svg")
class_name RelationshipWebView
extends Control
## Draws a [RelationshipWeb]: who feels what about whom, at a glance.
##
## Each pair of people is one curved line that fades from one side's feeling into the other's, cold to warm, so a
## lopsided pair reads as a gradient. Thicker means they know each other better; a gold ember marks a grudge at the
## end of the one who holds it. The overview draws strong feelings (and grudges) in full and everything else as
## faint hairlines, so the shape of the web reads at once; select someone and their bonds light up while everyone
## else fades back. People who feel strongly about more people are drawn bigger.[br][br]
## Set [member web] and the view keeps itself up to date: it listens to the web's signals and redraws only what
## changed. Drag to pan (or drag a person to pin them), scroll to zoom, click a person or a line to select it,
## Shift- or Ctrl-click a second person to select the pair, double-click to activate. Escape clears, F fits.
## [codeblock]
## var view := RelationshipWebView.new()
## view.set_anchors_preset(Control.PRESET_FULL_RECT)
## add_child(view)
## view.web = my_web
## view.person_selected.connect(_on_person_selected)
## [/codeblock]
## [member label_for], [member color_for] and [member icon_for] decide how each person is shown.[br][br]
## This is the view of [b]Relationship Web Lite[/b], the free edition: a fixed look, and the Lite mark (a faint
## knight across the middle and "Relationship Web Lite" in the corner) on every frame. The full Relationship Web
## has no mark, a look of your own, glowing lines, flowing dots, hearts and broken hearts, the relationship list,
## the family tree and the ready-made screen. https://debugalot.itch.io/relationship-web

## A person was clicked.
signal person_selected(id: String)
## A pair was selected: a line was clicked, or a second person Shift- or Ctrl-clicked.
signal pair_selected(a_id: String, b_id: String)
## The selection was cleared (a click on empty space, or Escape).
signal selection_cleared()
## A person was double-clicked.
signal person_activated(id: String)
## The layout stopped moving.
signal layout_settled()
## The selection changed, by a click or by a method ([method select_person], [method select_pair],
## [method clear_selection]).
signal selection_changed()

const _Layout := preload("res://addons/relationship_web/view/web_layout.gd")
const _SEGMENTS := 8          # per settled curve; the colours fade along them
const _FOCUS_SEGMENTS := 20
const _LITE_MARK := preload("res://addons/relationship_web/view/lite_watermark.png")

## The look: colours, fonts, the people palette (fixed in Lite: change it in the full version's Inspector).
var style: RelationshipWebTheme = RelationshipWebTheme.new():
	set(value):
		style = value if value != null else RelationshipWebTheme.new()
		refresh_people()
		_geometry_dirty = true
		_wake()

@export_group("Lines")
## Pairs where either side feels at least this strongly (either way), or with a grudge, are drawn in full in the
## overview; the rest are faint hairlines.
@export_range(0.0, 100.0, 1.0) var strong_feeling := 35.0:
	set(value):
		strong_feeling = value
		_geometry_dirty = true
		_wake()
## How visible the faint hairlines are.
@export_range(0.0, 1.0, 0.01) var faint_alpha := 0.07:
	set(value):
		faint_alpha = value
		_geometry_dirty = true
		_wake()
## Line widths in pixels, from least to most familiar (familiarity 0–100 is split evenly between them).
@export var line_widths: PackedFloat32Array = [1.2, 2.0, 3.0, 4.2]:
	set(value):
		line_widths = value if not value.is_empty() else PackedFloat32Array([2.0])
		_geometry_dirty = true
		_wake()
## A side whose trust is below this is drawn broken.
@export_range(0.0, 100.0, 1.0) var dashed_below_trust := 30.0:
	set(value):
		dashed_below_trust = value
		_geometry_dirty = true
		_wake()
## How far each line bows to one side, as a share of its length.
@export_range(0.0, 0.5, 0.01) var curve_bow := 0.12:
	set(value):
		curve_bow = value
		_geometry_dirty = true
		_wake()

@export_group("People")
## The radius of a person with no strong feelings, in world units; stronger, busier people are drawn bigger.
@export_range(3.0, 60.0, 0.5) var person_radius := 11.0:
	set(value):
		person_radius = value
		_layers_redraw()
## The size of the names, in pixels.
@export_range(6, 48) var label_font_size := 13:
	set(value):
		label_font_size = value
		_layers_redraw()
## In the overview, at most this many names are shown (the most connected first; never overlapping). Zoomed in
## far enough, everyone is named.
@export_range(0, 1000) var max_labels := 40:
	set(value):
		max_labels = value
		_layers_redraw()
## How far everything else fades back when someone is selected.
@export_range(0.0, 1.0, 0.01) var focus_dim := 0.16

@export_group("Background")
## Fill the background with [member RelationshipWebTheme.background_color], a soft vignette and a faint grid.
## Off, the view is transparent.
@export var draw_background := true:
	set(value):
		draw_background = value
		queue_redraw()

@export_group("Filters")
## Only pairs where at least one side's affinity is between [member min_affinity] and [member max_affinity].
@export_range(-100.0, 100.0, 1.0) var min_affinity := -100.0:
	set(value):
		min_affinity = value
		_filters_changed()
## See [member min_affinity].
@export_range(-100.0, 100.0, 1.0) var max_affinity := 100.0:
	set(value):
		max_affinity = value
		_filters_changed()
## Show family ([member RelationshipBond.kin] on either side).
@export var show_family := true:
	set(value):
		show_family = value
		_filters_changed()
## Show everyone who isn't family.
@export var show_others := true:
	set(value):
		show_others = value
		_filters_changed()
## Show only pairs with a grudge either way.
@export var only_grudges := false:
	set(value):
		only_grudges = value
		_filters_changed()
## Only pairs where either side has one of these tags ([member RelationshipBond.tags]). Empty shows all.
@export var only_tags := PackedStringArray():
	set(value):
		only_tags = value
		_filters_changed()
## Show only this person and the people within [member focus_depth] steps of them. Empty shows everyone.
@export var focus_person := "":
	set(value):
		focus_person = value
		_filters_changed()
## How many steps out from [member focus_person] to show.
@export_range(1, 6) var focus_depth := 1:
	set(value):
		focus_depth = value
		_filters_changed()
## People left without a visible line are faded (true) or hidden (false).
@export var fade_unconnected := true:
	set(value):
		fade_unconnected = value
		_layers_redraw()

@export_group("Behaviour")
## Animate the layout. Off, it settles at once whenever the web changes shape.
@export var animate := true
## Keep fitting the whole web to the view until the user pans or zooms.
@export var auto_fit := true
## Layout work per frame while it moves, in microseconds.
@export_range(500, 30000, 100) var layout_budget_usec := 5000
## Work the layout out before showing it for up to this long (milliseconds), so a new web appears mostly settled
## instead of exploding into place.
@export_range(0, 2000) var presettle_msec := 120

## The web to draw. The view follows its changes on its own.
var web: RelationshipWeb:
	set = set_web
## Your own filter: called with the two bonds of a pair (either can be null) and returns true to show it.
var custom_filter := Callable():
	set(value):
		custom_filter = value
		_filters_changed()
## The name shown for a person: a [Callable] taking a [RelationshipPerson] and returning a [String]. By default
## [code]person.data["name"][/code] if there is one, else the id.
var label_for := Callable(self, "_default_label"):
	set(value):
		label_for = value
		refresh_people()
## A person's colour: a [Callable] taking a [RelationshipPerson] and returning a [Color]. By default the colour of
## their [code]data["group"][/code] (or of their id) from [member RelationshipWebTheme.people_palette].
var color_for := Callable(self, "_default_color"):
	set(value):
		color_for = value
		refresh_people()
## A picture drawn inside a person (a portrait, an icon): a [Callable] taking a [RelationshipPerson] and returning a
## [Texture2D] or null. It is cropped to a circle. Not set by default: people show their initials.
var icon_for := Callable():
	set(value):
		icon_for = value
		refresh_people()
## The zoom, 1 being one world unit to one pixel. Scrolling changes it.
var zoom := 1.0:
	set(value):
		zoom = clampf(value, 0.03, 6.0)
		_view_moved()
## Where the web's origin sits in the view, in pixels. Panning changes it.
var pan := Vector2.ZERO:
	set(value):
		pan = value
		_view_moved()
## How long the last redraw of the lines took, in microseconds (for profiling).
var last_draw_usec := 0
## How long the last frame's layout work took, in microseconds.
var last_layout_usec := 0
## How long the last redraw of the people and names took, in microseconds (for profiling).
var last_people_usec := 0
## How long the grudge embers took in the last redraw, in microseconds (for profiling).
var last_markers_usec := 0
## How long the names took in the last redraw, in microseconds (for profiling).
var last_labels_usec := 0

var _layout := _Layout.new()
var _ids := PackedStringArray()
var _index: Dictionary[String, int] = {}
var _people: Array[RelationshipPerson] = []
var _labels := PackedStringArray()
var _initials := PackedStringArray()
var _colors := PackedColorArray()
var _icons: Array[Texture2D] = []
var _icon_cache: Dictionary[Texture2D, Texture2D] = {}     # picture → its circle crop
var _weight := PackedFloat64Array()                         # how big each person is drawn (1 = plain)
var _faded := PackedByteArray()
var _adjacent: Array[Array] = []                            # person → their pairs (plain Arrays: references)
var _pa := PackedInt32Array()                               # pair → its two people
var _pb := PackedInt32Array()
var _ab: Array[RelationshipBond] = []                       # pair → how a feels about b (or null)
var _ba: Array[RelationshipBond] = []
var _pair_of: Dictionary[int, int] = {}                     # a * count + b → pair
var _shown := PackedByteArray()
# Line batches, one per width: segment endpoints, their colours and their glow colours. Each shown pair owns
# _segments_now segments starting at _pair_slot[pair] in batch _pair_bucket[pair], so one pair is recoloured in place.
var _points: Array[PackedVector2Array] = []
var _line_colors: Array[PackedColorArray] = []
var _glow_colors: Array[PackedColorArray] = []
var _pair_bucket := PackedInt32Array()
var _pair_slot := PackedInt32Array()
var _notable := PackedByteArray()                           # pair → drawn in full (1) or as a faint hairline (0)
var _total_segments := 0
var _leftover_segments := 0                                 # segments painted away when a pair changed batch
var _marked := PackedByteArray()                            # pair → carries a marker (a grudge)
var _marked_pairs := PackedInt32Array()
var _markers_dirty := true
var _label_order := PackedInt32Array()                      # everyone, the most connected first
var _segments_now := _SEGMENTS
var _dirty_pairs: Dictionary[int, bool] = {}
var _recolor_all := false
var _selected_person := -1
var _selected_pair := -1
var _hover := -1
var _hover_pair := -1
var _focus_pairs := PackedInt32Array()
var _focus_people: Dictionary[int, bool] = {}
var _focus_amount := 0.0
var _drag := -1
var _panning := false
var _press := Vector2.ZERO
var _moved := false
var _skip_release := false
var _was_moving := false
var _structure_dirty := false
var _values_dirty := false
var _filters_dirty := false
var _geometry_dirty := false
var _line_layer: Control
var _focus_layer: Control
var _people_layer: Control
var _medallions := _Medallions.new()
var _mark_layer: Control
var _line_markers := _Markers.new()
var _focus_markers := _Markers.new()
var _vignette: GradientTexture2D


func _init() -> void:
	clip_contents = true
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	_line_layer = _make_layer(_draw_lines)
	_focus_layer = _make_layer(_draw_focus)
	_people_layer = _make_layer(_draw_people)
	_mark_layer = _make_layer(_draw_mark)
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0, 0, 0, 0))
	gradient.set_color(1, Color(0, 0, 0, 0.45))
	_vignette = GradientTexture2D.new()
	_vignette.gradient = gradient
	_vignette.fill = GradientTexture2D.FILL_RADIAL
	_vignette.fill_from = Vector2(0.5, 0.5)
	_vignette.fill_to = Vector2(1.05, 1.05)
	resized.connect(_on_resized)


func _ready() -> void:
	_wake()


func _make_layer(drawer: Callable) -> Control:
	var layer := Control.new()
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.draw.connect(drawer)
	add_child(layer, false, Node.INTERNAL_MODE_FRONT)
	return layer


## Sets the web to draw (null clears the view).
func set_web(value: RelationshipWeb) -> void:
	if web == value:
		return
	if web != null:
		for pair: Array in _signal_pairs():
			var sig := Signal(web, str(pair[0]))
			var handler: Callable = pair[1]
			if sig.is_connected(handler):
				sig.disconnect(handler)
	web = value
	if web != null:
		for pair: Array in _signal_pairs():
			var handler: Callable = pair[1]
			Signal(web, str(pair[0])).connect(handler)
	_selected_person = -1
	_selected_pair = -1
	_hover = -1
	_hover_pair = -1
	_structure_dirty = true
	_wake()


# ------------------------------------------------------------------------------------------ public

## Fits the whole web in the view.
func fit_view() -> void:
	var r := _layout.bounds().grow(-_layout.spacing * 0.45)
	if size.x < 10.0 or size.y < 10.0 or r.size.x <= 0.0 or r.size.y <= 0.0:
		return
	zoom = clampf(minf(size.x / r.size.x, size.y / r.size.y) * 0.9, 0.05, 2.0)
	pan = size / 2.0 - r.get_center() * zoom


## Selects a person, as a click would (without [signal person_selected]). Returns false if they aren't drawn.
func select_person(id: String) -> bool:
	_sync()
	if not _index.has(id):
		return false
	_selected_person = _index[id]
	_selected_pair = -1
	_selection_moved()
	return true


## Selects the pair of [param a_id] and [param b_id], as a click would (without [signal pair_selected]). Returns
## false if they have no bond either way.
func select_pair(a_id: String, b_id: String) -> bool:
	_sync()
	var pair := _find_pair(a_id, b_id)
	if pair < 0:
		return false
	_selected_pair = pair
	_selected_person = -1
	_selection_moved()
	return true


## Clears the selection (without [signal selection_cleared]).
func clear_selection() -> void:
	if _selected_person < 0 and _selected_pair < 0:
		return
	_selected_person = -1
	_selected_pair = -1
	_selection_moved()


## Lights up a pair as if the pointer were on it (for a list or tooltip that points at pairs). Pass "" to stop.
func highlight_pair(a_id: String, b_id: String) -> void:
	_sync()
	var pair := _find_pair(a_id, b_id) if not a_id.is_empty() else -1
	if pair != _hover_pair:
		_hover_pair = pair
		_update_focus()


## The selected person's id, or "".
func get_selected_person() -> String:
	return _ids[_selected_person] if _selected_person >= 0 and _selected_person < _ids.size() else ""


## The selected pair as [code][a_id, b_id][/code], or an empty array.
func get_selected_pair() -> PackedStringArray:
	if _selected_pair < 0 or _selected_pair >= _pa.size():
		return PackedStringArray()
	return PackedStringArray([_ids[_pa[_selected_pair]], _ids[_pb[_selected_pair]]])


## Moves the view so this person is in the middle. Returns false if they aren't drawn.
func center_on(id: String) -> bool:
	_sync()
	if not _index.has(id):
		return false
	auto_fit = false
	pan = size / 2.0 - _layout.positions[_index[id]] * zoom
	return true


## Where a person is drawn, in the view's own pixels (NAN if they aren't drawn).
func get_person_screen_position(id: String) -> Vector2:
	_sync()
	if not _index.has(id):
		return Vector2(NAN, NAN)
	return _layout.positions[_index[id]] * zoom + pan


## The name the view shows for a person ("" if they aren't drawn).
func get_label(id: String) -> String:
	_sync()
	return _labels[_index[id]] if _index.has(id) else ""


## The colour the view gives a person (their group's colour by default).
func get_person_color(id: String) -> Color:
	_sync()
	return _colors[_index[id]] if _index.has(id) else style.neutral_color


## The picture the view shows inside a person, cropped to a circle (null if they show initials).
func get_person_icon(id: String) -> Texture2D:
	_sync()
	return _icons[_index[id]] if _index.has(id) else null


## Every person's place in the layout, by id, for saving. Hand it back to [method set_layout_positions] to restore
## the layout instead of letting it find a new one.
func get_layout_positions() -> Dictionary:
	_sync()
	var places := {}
	for i in _ids.size():
		places[_ids[i]] = _layout.positions[i]
	return places


## Restores places from [method get_layout_positions] (people not in it are placed beside someone they know).
func set_layout_positions(places: Dictionary) -> void:
	_sync()
	var initial := PackedVector2Array()
	initial.resize(_ids.size())
	initial.fill(Vector2(NAN, NAN))
	for i in _ids.size():
		var place: Variant = places.get(_ids[i], null)
		if place is Vector2:
			initial[i] = place
	_setup_layout(initial)
	_geometry_dirty = true
	_wake()


## True once the layout has stopped moving.
func is_settled() -> bool:
	_sync()
	return _layout.is_settled()


## Runs the layout until it settles (or [param max_steps]), at once.
func settle(max_steps: int = 2000) -> void:
	_sync()
	_layout.settle(max_steps)
	_geometry_dirty = true
	if auto_fit:
		fit_view()
	_wake()


## Lets everyone the user dragged move again.
func unpin_all() -> void:
	_layout.unpin_all()
	_wake()


## Starts the layout over from scratch.
func relayout() -> void:
	_sync()
	var fresh := PackedVector2Array()
	fresh.resize(_ids.size())
	fresh.fill(Vector2(NAN, NAN))
	_setup_layout(fresh)
	auto_fit = true
	_geometry_dirty = true
	_wake()


## Asks [member label_for], [member color_for] and [member icon_for] again for everyone (after their names or
## colours change).
func refresh_people() -> void:
	if _people.is_empty():
		return
	_labels.resize(_people.size())
	_initials.resize(_people.size())
	_colors.resize(_people.size())
	_icons.resize(_people.size())
	for i in _people.size():
		_refresh_person(i)
	_layers_redraw()


## The colour for an affinity on this view's scale (see [member RelationshipWebTheme.feeling_color]).
func affinity_color(affinity: float) -> Color:
	return style.feeling_color(affinity)


# ------------------------------------------------------------------------------------------ keeping up

func _signal_pairs() -> Array:
	return [
		["person_added", _on_structure], ["person_removed", _on_structure], ["bond_added", _on_structure],
		["bond_removed", _on_structure], ["bond_changed", _on_bond_changed], ["grievance_opened", _on_grievance],
		["grievance_changed", _on_grievance], ["grievance_resolved", _on_grievance], ["day_advanced", _on_day],
	]


func _on_structure(_a: Variant = null, _b: Variant = null) -> void:
	_structure_dirty = true
	_wake()


func _on_bond_changed(from_id: String, to_id: String) -> void:
	var pair := _find_pair(from_id, to_id) if not _structure_dirty else -1
	if pair >= 0:
		_dirty_pairs[pair] = true
	_values_dirty = true
	_wake()


func _on_grievance(grievance: RelationshipGrievance) -> void:
	_on_bond_changed(grievance.from_id, grievance.to_id)


func _on_day(_day: int) -> void:
	_recolor_all = true
	_values_dirty = true
	_wake()


func _filters_changed() -> void:
	_filters_dirty = true
	_wake()


func _on_resized() -> void:
	var stretch := _stretch()
	if absf(stretch - _layout.stretch) > 0.05:
		# A new shape of view: let the web spread to fill it.
		_layout.stretch = stretch
		if not _layout.positions.is_empty():
			_layout.reheat(0.3)
			_wake()
	if auto_fit:
		fit_view()
	_view_moved()


## How much wider than tall the layout should settle, to fill this view (within reason: past 1.4 the web would look
## squashed).
func _stretch() -> float:
	return clampf(size.x / size.y, 1.0 / 1.4, 1.4) if size.x > 10.0 and size.y > 10.0 else 1.0


func _view_moved() -> void:
	queue_redraw()
	_layers_redraw()


func _layers_redraw() -> void:
	if _line_layer != null:
		_line_layer.queue_redraw()
		_focus_layer.queue_redraw()
		_people_layer.queue_redraw()
		_mark_layer.queue_redraw()


func _wake() -> void:
	if is_inside_tree():
		set_process(true)


## Brings everything up to date now (the public methods call it, so they see the latest web).
func _sync() -> void:
	if _structure_dirty:
		_rebuild_structure()
	if _values_dirty:
		_refresh_values()
	if _filters_dirty:
		_apply_filters()
	if _geometry_dirty:
		_rebuild_geometry()


func _process(delta: float) -> void:
	_sync()
	var started := Time.get_ticks_usec()
	var moving := animate and not _layout.is_settled()
	if moving:
		var budget := started + layout_budget_usec
		_layout.step()
		while Time.get_ticks_usec() < budget and not _layout.is_settled():
			_layout.step()
		if _segments_now != 1 or _points.is_empty():
			_rebuild_geometry()       # the first moving frame: straight lines from here on
		else:
			_rebuild_points()
		if auto_fit:
			fit_view()
		_layers_redraw()
	last_layout_usec = Time.get_ticks_usec() - started
	var focus_target := 0.0
	if _selected_person >= 0 or _selected_pair >= 0:
		focus_target = 1.0
	elif _hover >= 0 or _hover_pair >= 0:
		focus_target = 0.6
	var easing := absf(focus_target - _focus_amount) > 0.002
	if easing:
		_focus_amount = lerpf(_focus_amount, focus_target, 1.0 - exp(-delta * 14.0))
		_line_layer.modulate.a = lerpf(1.0, focus_dim, _focus_amount)
		_people_layer.queue_redraw()
		_focus_layer.queue_redraw()
	if moving:
		_was_moving = true
		return
	if _was_moving:
		_was_moving = false
		_geometry_dirty = true
		_rebuild_geometry()     # the settled web is drawn with full curves
		_layers_redraw()
		layout_settled.emit()
	if not easing and _drag < 0:
		set_process(false)


func _rebuild_structure() -> void:
	_structure_dirty = false
	var places := {}
	for i in _ids.size():
		if i < _layout.positions.size():
			places[_ids[i]] = _layout.positions[i]
	var selected_person := get_selected_person()
	var selected_pair := get_selected_pair()
	_ids = PackedStringArray() if web == null else web.get_person_ids()
	var count := _ids.size()
	_index.clear()
	_people.clear()
	for i in count:
		_index[_ids[i]] = i
		_people.append(web.get_person(_ids[i]))
	_pa.clear()
	_pb.clear()
	_ab.clear()
	_ba.clear()
	_pair_of.clear()
	_adjacent.clear()
	for i in count:
		_adjacent.append([])
	if web != null:
		for bond in web.get_all_bonds():
			var a: int = _index[bond.from_id]
			var b: int = _index[bond.to_id]
			var lo := mini(a, b)
			var hi := maxi(a, b)
			var key := lo * count + hi
			var pair: int = _pair_of.get(key, -1)
			if pair < 0:
				pair = _pa.size()
				_pair_of[key] = pair
				_pa.append(lo)
				_pb.append(hi)
				_ab.append(null)
				_ba.append(null)
				_adjacent[lo].append(pair)
				_adjacent[hi].append(pair)
			if a == lo:
				_ab[pair] = bond
			else:
				_ba[pair] = bond
	refresh_people()
	var initial := PackedVector2Array()
	initial.resize(count)
	initial.fill(Vector2(NAN, NAN))
	var known := 0
	for i in count:
		var place: Variant = places.get(_ids[i], null)
		if place is Vector2:
			initial[i] = place
			known += 1
	_setup_layout(initial)
	if known == 0 and presettle_msec > 0:
		var until := Time.get_ticks_msec() + presettle_msec
		while Time.get_ticks_msec() < until and not _layout.is_settled():
			_layout.step()
		if auto_fit:
			fit_view()
	_selected_person = _index.get(selected_person, -1)
	_selected_pair = -1 if selected_pair.is_empty() else _find_pair(selected_pair[0], selected_pair[1])
	_hover = -1
	_hover_pair = -1
	_dirty_pairs.clear()
	_values_dirty = true
	_filters_dirty = true
	_geometry_dirty = true
	_update_focus()


func _setup_layout(initial: PackedVector2Array) -> void:
	var stiffness := PackedFloat32Array()
	stiffness.resize(_pa.size())
	for pair in _pa.size():
		# Family and friends pull close, enemies keep their distance: the web clusters around who gets on.
		stiffness[pair] = (2.0 if _is_family(pair) else 1.0) * clampf(0.8 + _standing(pair) / 100.0, 0.3, 1.8)
	_layout.spacing = 95.0
	_layout.stretch = _stretch()
	_layout.setup(_ids.size(), _pa, _pb, stiffness, initial)
	if not animate:
		_layout.settle(2000)
	if auto_fit:
		fit_view()
	_was_moving = true          # so the next frame draws the settled web in full and says it has settled


func _refresh_person(i: int) -> void:
	var person := _people[i]
	var label := person.id
	if label_for.is_valid():
		label = str(label_for.call(person))
	_labels[i] = label
	var words := label.split(" ", false)
	var initials := ""
	for word in words.slice(0, 2):
		initials += word.left(1).to_upper()
	_initials[i] = initials if not initials.is_empty() else "?"
	_colors[i] = style.neutral_color
	if color_for.is_valid():
		var color: Variant = color_for.call(person)
		if color is Color:
			_colors[i] = color
	_icons[i] = null
	if icon_for.is_valid():
		var icon: Variant = icon_for.call(person)
		if icon is Texture2D:
			var picture: Texture2D = icon
			_icons[i] = _circle_crop(picture)


## A picture cropped to a circle with soft edges, made once per picture.
func _circle_crop(source: Texture2D) -> Texture2D:
	if _icon_cache.has(source):
		return _icon_cache[source]
	var image := source.get_image()
	if image == null:
		return source
	image = image.duplicate()
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	var side := mini(image.get_width(), image.get_height())
	var corner := Vector2i((Vector2(image.get_size()) - Vector2(side, side)) * 0.5)
	image = image.get_region(Rect2i(corner, Vector2i(side, side)))
	if side > 128:
		image.resize(128, 128, Image.INTERPOLATE_LANCZOS)
		side = 128
	var centre := (side - 1) / 2.0
	for y in side:
		for x in side:
			var d := Vector2(x - centre, y - centre).length() / (side / 2.0)
			var pixel := image.get_pixel(x, y)
			pixel.a *= clampf((1.0 - d) * side * 0.5, 0.0, 1.0)
			image.set_pixel(x, y, pixel)
	var cropped := ImageTexture.create_from_image(image)
	_icon_cache[source] = cropped
	return cropped


func _refresh_values() -> void:
	_values_dirty = false
	var touched := PackedInt32Array()
	if not _recolor_all:
		for pair: int in _dirty_pairs:
			if pair < _pa.size():
				touched.append(_pa[pair])
				touched.append(_pb[pair])
	var sizes_changed := _weigh_people(touched)
	var range_used := min_affinity > -100.0 or max_affinity < 100.0 or only_grudges or custom_filter.is_valid()
	if range_used:
		_filters_dirty = true        # what the filters see changed: redo them (and the geometry)
	elif _recolor_all or _segments_now != _SEGMENTS:
		_geometry_dirty = true
	else:
		_recolor(_dirty_pairs.keys())
	_recolor_all = false
	_dirty_pairs.clear()
	if sizes_changed or not _focus_pairs.is_empty():
		_people_layer.queue_redraw()
	if not _focus_pairs.is_empty():
		_focus_layer.queue_redraw()


## How big each person is drawn: by how many people they feel strongly about (or who feel strongly about them).
## Returns true if anyone's size changed (the people need redrawing). Sizes move in steps, so a small change of
## feeling doesn't redraw everyone. With [param only] given, just those people are weighed again.
func _weigh_people(only: PackedInt32Array = PackedInt32Array()) -> bool:
	var changed := _weight.size() != _ids.size()
	_weight.resize(_ids.size())
	var who := only
	if changed or who.is_empty():
		who = PackedInt32Array()
		who.resize(_ids.size())
		for i in _ids.size():
			who[i] = i
	for i in who:
		var strong := 0.0
		for pair: int in _adjacent[i]:
			strong += _strength(pair) / 100.0
		var weight := 1.0 + minf(0.9, roundf(sqrt(strong) * 0.32 / 0.03) * 0.03)
		if weight != _weight[i]:
			_weight[i] = weight
			changed = true
	if changed:
		# Sort natively: a key of (how light) then index, so the heaviest come first and ties keep their order.
		var keys := PackedInt64Array()
		keys.resize(_ids.size())
		for i in _ids.size():
			keys[i] = (int((2.0 - _weight[i]) * 100000.0) << 20) | i
		keys.sort()
		_label_order.resize(keys.size())
		for k in keys.size():
			_label_order[k] = int(keys[k] & 0xFFFFF)
	return changed


func _strength(pair: int) -> float:
	var ab := _ab[pair]
	var ba := _ba[pair]
	return maxf(absf(ab.affinity) if ab != null else 0.0, absf(ba.affinity) if ba != null else 0.0)


## The mean of both sides' affinities (just one side's for a one-way pair).
func _standing(pair: int) -> float:
	var ab := _ab[pair]
	var ba := _ba[pair]
	if ab != null and ba != null:
		return (ab.affinity + ba.affinity) / 2.0
	return ab.affinity if ab != null else (ba.affinity if ba != null else 0.0)


func _grudges(pair: int) -> int:
	return (_ab[pair].grievances.size() if _ab[pair] != null else 0) + (_ba[pair].grievances.size() if _ba[pair] != null else 0)


func _apply_filters() -> void:
	_filters_dirty = false
	var count := _ids.size()
	_shown.resize(_pa.size())
	for pair in _pa.size():
		_shown[pair] = 1 if _passes(pair) else 0
	if not focus_person.is_empty() and _index.has(focus_person):
		var reach := PackedInt32Array()
		reach.resize(count)
		reach.fill(-1)
		var start: int = _index[focus_person]
		reach[start] = 0
		var frontier := PackedInt32Array([start])
		for depth in focus_depth:
			var next_frontier := PackedInt32Array()
			for person in frontier:
				for pair: int in _adjacent[person]:
					if _shown[pair] == 0:
						continue
					var other := _pb[pair] if _pa[pair] == person else _pa[pair]
					if reach[other] < 0:
						reach[other] = depth + 1
						next_frontier.append(other)
			frontier = next_frontier
		for pair in _pa.size():
			if reach[_pa[pair]] < 0 or reach[_pb[pair]] < 0:
				_shown[pair] = 0
	_faded.resize(count)
	_faded.fill(1)
	for pair in _pa.size():
		if _shown[pair] == 1:
			_faded[_pa[pair]] = 0
			_faded[_pb[pair]] = 0
	if not focus_person.is_empty() and _index.has(focus_person):
		_faded[_index[focus_person]] = 0
	_geometry_dirty = true
	_update_focus()


func _passes(pair: int) -> bool:
	var ab := _ab[pair]
	var ba := _ba[pair]
	var family := (ab != null and ab.kin) or (ba != null and ba.kin)
	if (family and not show_family) or (not family and not show_others):
		return false
	var in_range := (ab != null and ab.affinity >= min_affinity and ab.affinity <= max_affinity) \
		or (ba != null and ba.affinity >= min_affinity and ba.affinity <= max_affinity)
	if not in_range:
		return false
	if only_grudges and _grudges(pair) == 0:
		return false
	if not only_tags.is_empty():
		var tagged := false
		for tag in only_tags:
			if (ab != null and ab.tags.has(tag)) or (ba != null and ba.tags.has(tag)):
				tagged = true
				break
		if not tagged:
			return false
	if custom_filter.is_valid():
		var keep: Variant = custom_filter.call(ab, ba)
		return keep is bool and keep
	return true


func _is_family(pair: int) -> bool:
	return (_ab[pair] != null and _ab[pair].kin) or (_ba[pair] != null and _ba[pair].kin)


# ------------------------------------------------------------------------------------------ selection and focus

func _selection_moved() -> void:
	_update_focus()
	_wake()
	selection_changed.emit()


## Who is lit up: the selected person and their bonds, the selected pair, or (with nothing selected) whoever the
## pointer is on.
func _update_focus() -> void:
	_focus_pairs.clear()
	_focus_people.clear()
	var person := _selected_person
	var pair := _selected_pair
	if person < 0 and pair < 0:
		person = _hover
		pair = _hover_pair
	if pair >= 0 and pair < _pa.size():
		_focus_pairs.append(pair)
		_focus_people[_pa[pair]] = true
		_focus_people[_pb[pair]] = true
	elif person >= 0 and person < _adjacent.size():
		_focus_people[person] = true
		for p: int in _adjacent[person]:
			if p < _shown.size() and _shown[p] == 1:
				_focus_pairs.append(p)
				_focus_people[_pb[p] if _pa[p] == person else _pa[p]] = true
	if _hover_pair >= 0 and _hover_pair < _pa.size() and not _focus_pairs.has(_hover_pair):
		_focus_pairs.append(_hover_pair)
		_focus_people[_pa[_hover_pair]] = true
		_focus_people[_pb[_hover_pair]] = true
	_people_layer.queue_redraw()
	_focus_layer.queue_redraw()
	_wake()


# ------------------------------------------------------------------------------------------ geometry

func _curve_point(pa: Vector2, pb: Vector2, t: float) -> Vector2:
	var middle := (pa + pb) * 0.5
	var control := middle + (pb - pa).orthogonal() * curve_bow
	var u := 1.0 - t
	return pa * (u * u) + control * (2.0 * u * t) + pb * (t * t)


func _width_bucket(familiarity: float) -> int:
	return clampi(int(familiarity / (100.0 / line_widths.size())), 0, line_widths.size() - 1)


func _familiarity(pair: int) -> float:
	return maxf(_ab[pair].familiarity if _ab[pair] != null else 0.0, _ba[pair].familiarity if _ba[pair] != null else 0.0)


## Every shown pair's segments, batched for drawing: notable pairs (strong feelings or grudges) are curved
## and batched by width, one draw call per width; the faint rest are one straight hairline each in a
## batch of their own. While the layout moves everything is one straight segment and only the points are redone
## each frame ([method _rebuild_points]); once it settles the curves come back. Colours are written by
## _paint_pair, which can also redo one pair in place.
func _rebuild_geometry() -> void:
	_geometry_dirty = false
	_dirty_pairs.clear()
	if _shown.size() != _pa.size():
		_apply_filters()
	var settled := _layout.is_settled()
	_segments_now = _SEGMENTS if settled else 1
	var widths := line_widths.size()
	var faint_bucket := widths
	_pair_bucket.resize(_pa.size())
	_pair_slot.resize(_pa.size())
	_notable.resize(_pa.size())
	var counts := PackedInt32Array()
	counts.resize(widths + 1)
	_marked.resize(_pa.size())
	_markers_dirty = true
	for pair in _pa.size():
		if _shown[pair] == 0:
			_pair_bucket[pair] = -1
			_notable[pair] = 0
			_marked[pair] = 0
			continue
		_marked[pair] = 1 if _carries_marker(pair) else 0
		var notable := _is_notable(pair)
		_notable[pair] = 1 if notable else 0
		var bucket := _width_bucket(_familiarity(pair)) if notable else faint_bucket
		_pair_bucket[pair] = bucket
		_pair_slot[pair] = counts[bucket] * _bucket_segments(bucket)
		counts[bucket] += 1
	_points.clear()
	_line_colors.clear()
	_glow_colors.clear()
	for w in widths + 1:
		var segments := _bucket_segments(w)
		var points := PackedVector2Array()
		points.resize(counts[w] * segments * 2)
		var colors := PackedColorArray()
		colors.resize(counts[w] * segments)
		var glows := PackedColorArray()
		glows.resize(counts[w] * segments if w < widths else 0)
		_points.append(points)
		_line_colors.append(colors)
		_glow_colors.append(glows)
	_total_segments = 0
	_leftover_segments = 0
	for w in widths + 1:
		var colors := _line_colors[w]
		_line_colors[w] = PackedColorArray()
		var glows := _glow_colors[w]
		_glow_colors[w] = PackedColorArray()
		var segments := _bucket_segments(w)
		_total_segments += counts[w] * segments
		for pair in _pa.size():
			if _pair_bucket[pair] == w:
				_paint_pair(pair, colors, glows, _pair_slot[pair], segments)
		_line_colors[w] = colors
		_glow_colors[w] = glows
	_rebuild_points()


## Moves every shown pair's segments to where its people are now, keeping the batches and colours.
func _rebuild_points() -> void:
	var positions := _layout.positions
	var widths := line_widths.size()
	# Take each batch out of the list so the writes below don't copy it (packed arrays copy on write when shared).
	var batches: Array[PackedVector2Array] = []
	for w in widths + 1:
		batches.append(_points[w])
		_points[w] = PackedVector2Array()
	var curved := _segments_now
	for pair in _pa.size():
		var w := _pair_bucket[pair]
		if w < 0:
			continue
		var pa := positions[_pa[pair]]
		var pb := positions[_pb[pair]]
		var slot := _pair_slot[pair]
		if w == widths or curved == 1:
			batches[w][slot * 2] = pa
			batches[w][slot * 2 + 1] = pb
		else:
			var previous := pa
			for seg in curved:
				var next := _curve_point(pa, pb, float(seg + 1) / curved)
				batches[w][(slot + seg) * 2] = previous
				batches[w][(slot + seg) * 2 + 1] = next
				previous = next
	for w in widths + 1:
		_points[w] = batches[w]
	_line_layer.queue_redraw()


## How many segments a batch draws per pair: the faint batch is always straight.
func _bucket_segments(bucket: int) -> int:
	return 1 if bucket >= line_widths.size() else _segments_now


## A pair drawn in full: strong feelings either way, or a grudge.
func _is_notable(pair: int) -> bool:
	return _strength(pair) >= strong_feeling or _grudges(pair) > 0


## Recolours some pairs in place (their feelings changed, their places didn't). A pair that became notable, or
## stopped being so, or got thicker or thinner, moves to another batch: its old segments are left in place,
## painted away, and new ones are added at the end of its new batch. Once a quarter of the segments are such
## leftovers, the batches are rebuilt from scratch.
func _recolor(pairs: Array) -> void:
	if pairs.is_empty():
		return
	var widths := line_widths.size()
	var by_bucket: Dictionary[int, Array] = {}
	for pair: int in pairs:
		if pair >= _pair_bucket.size():
			_geometry_dirty = true
			return
		var bucket := _pair_bucket[pair]
		if bucket < 0:
			continue
		var notable := _is_notable(pair)
		var wanted := (_width_bucket(_familiarity(pair)) if notable else widths)
		if wanted != bucket:
			_move_pair(pair, bucket, wanted, notable)
			bucket = wanted
		var marked := 1 if _carries_marker(pair) else 0
		if pair < _marked.size() and _marked[pair] != marked:
			_marked[pair] = marked
			_markers_dirty = true
		if not by_bucket.has(bucket):
			by_bucket[bucket] = []
		by_bucket[bucket].append(pair)
	for bucket: int in by_bucket:
		var colors := _line_colors[bucket]
		_line_colors[bucket] = PackedColorArray()
		var glows := _glow_colors[bucket]
		_glow_colors[bucket] = PackedColorArray()
		var segments := _bucket_segments(bucket)
		for pair: int in by_bucket[bucket]:
			_paint_pair(pair, colors, glows, _pair_slot[pair], segments)
		_line_colors[bucket] = colors
		_glow_colors[bucket] = glows
	if _leftover_segments * 4 > _total_segments:
		_geometry_dirty = true
	_line_layer.queue_redraw()


## Moves one pair from one batch to another without rebuilding: the old segments stay, painted away.
func _move_pair(pair: int, from_bucket: int, to_bucket: int, notable: bool) -> void:
	var old_segments := _bucket_segments(from_bucket)
	var slot := _pair_slot[pair]
	var colors := _line_colors[from_bucket]
	_line_colors[from_bucket] = PackedColorArray()
	for seg in old_segments:
		colors[slot + seg] = Color(0, 0, 0, 0)
	_line_colors[from_bucket] = colors
	if from_bucket < line_widths.size():
		var glows := _glow_colors[from_bucket]
		_glow_colors[from_bucket] = PackedColorArray()
		for seg in old_segments:
			glows[slot + seg] = Color(0, 0, 0, 0)
		_glow_colors[from_bucket] = glows
	_leftover_segments += old_segments
	var new_segments := _bucket_segments(to_bucket)
	var points := _points[to_bucket]
	_points[to_bucket] = PackedVector2Array()
	@warning_ignore("integer_division")
	var new_slot := points.size() / 2
	var pa := _layout.positions[_pa[pair]]
	var pb := _layout.positions[_pb[pair]]
	var previous := pa
	for seg in new_segments:
		var next := pb if new_segments == 1 else _curve_point(pa, pb, float(seg + 1) / new_segments)
		points.append(previous)
		points.append(next)
		previous = next
	_points[to_bucket] = points
	var new_colors := _line_colors[to_bucket]
	_line_colors[to_bucket] = PackedColorArray()
	new_colors.resize(new_colors.size() + new_segments)
	_line_colors[to_bucket] = new_colors
	if to_bucket < line_widths.size():
		var new_glows := _glow_colors[to_bucket]
		_glow_colors[to_bucket] = PackedColorArray()
		new_glows.resize(new_glows.size() + new_segments)
		_glow_colors[to_bucket] = new_glows
	_total_segments += new_segments
	_pair_bucket[pair] = to_bucket
	_pair_slot[pair] = new_slot
	_notable[pair] = 1 if notable else 0


## Writes one pair's segment colours: fading from a's feeling to b's, faint when neither feels much, broken where
## a side's trust is low.
func _paint_pair(pair: int, colors: PackedColorArray, glows: PackedColorArray, slot: int, segments: int) -> void:
	var ab := _ab[pair]
	var ba := _ba[pair]
	var from_color := style.feeling_color(ab.affinity) if ab != null else Color(style.neutral_color, 0.35)
	var to_color := style.feeling_color(ba.affinity) if ba != null else Color(style.neutral_color, 0.35)
	var notable := _is_notable(pair)
	var alpha := 0.92 if notable else faint_alpha
	var broken_ab := ab != null and ab.trust < dashed_below_trust
	var broken_ba := ba != null and ba.trust < dashed_below_trust
	var glowing := not glows.is_empty()
	for s in segments:
		var t := (s + 0.5) / segments
		var color := from_color.lerp(to_color, t)
		color.a *= alpha
		var first_half := t < 0.5
		if segments > 2 and (broken_ab if first_half else broken_ba) and s % 2 == 1:
			color.a *= 0.25
		colors[slot + s] = color
		if glowing:
			glows[slot + s] = Color(color, 0.13 if notable else 0.0)


# ------------------------------------------------------------------------------------------ drawing

func _draw() -> void:
	if not draw_background:
		return
	draw_rect(Rect2(Vector2.ZERO, size), style.background_color)
	if style.grid_color.a > 0.0 and zoom > 0.08:
		var step := 80.0 * zoom
		while step < 24.0:
			step *= 2.0
		var lines := PackedVector2Array()
		var x := fposmod(pan.x, step)
		while x < size.x:
			lines.append(Vector2(x, 0))
			lines.append(Vector2(x, size.y))
			x += step
		var y := fposmod(pan.y, step)
		while y < size.y:
			lines.append(Vector2(0, y))
			lines.append(Vector2(size.x, y))
			y += step
		if not lines.is_empty():
			draw_multiline(lines, style.grid_color, 1.0)
	draw_texture_rect(_vignette, Rect2(Vector2.ZERO, size), false)


func _draw_lines() -> void:
	var started := Time.get_ticks_usec()
	last_markers_usec = 0
	if _ids.is_empty():
		return
	_line_layer.draw_set_transform(pan, 0.0, Vector2(zoom, zoom))
	var inverse := 1.0 / zoom
	var widths := line_widths.size()
	if _points.size() > widths and _points[widths].size() > 0:
		_line_layer.draw_multiline_colors(_points[widths], _line_colors[widths], line_widths[0] * inverse, false)
	for w in widths:
		if _points[w].size() > 0:
			_line_layer.draw_multiline_colors(_points[w], _line_colors[w], line_widths[w] * inverse, true)
	_draw_markers(_line_layer, _line_markers, inverse, false)
	last_draw_usec = Time.get_ticks_usec() - started


## A grudge is a gold ember near whoever holds it (one ember: one-sided; one at each end: both hold one). The pairs
## that carry one are kept in a list (the recolouring keeps it right), and the embers are one [MultiMesh] draw.
func _draw_markers(layer: Control, markers: _Markers, inverse: float, focused_only: bool) -> void:
	var started := Time.get_ticks_usec()
	var positions := _layout.positions
	var pairs := _focus_pairs if focused_only else _marker_pairs()
	markers.begin(pairs.size())
	var gold := style.grudge_color
	for pair in pairs:
		var pa := positions[_pa[pair]]
		var pb := positions[_pb[pair]]
		for side: int in [0, 1]:
			var bond := _ab[pair] if side == 0 else _ba[pair]
			if bond == null or bond.grievances.is_empty():
				continue
			var at := _curve_point(pa, pb, 0.18 if side == 0 else 0.82)
			var r := (2.6 + float(bond.worst_grievance().severity) * 0.55) * inverse
			markers.add(_Markers.GLOW, at, r * 2.6, Color(gold, 0.35))
			markers.add(_Markers.EMBER, at, r, gold)
	markers.draw(layer, [style.shape("glow"), style.shape("ember")])
	last_markers_usec += Time.get_ticks_usec() - started


## Whether a shown pair carries a marker (a grudge either way).
func _carries_marker(pair: int) -> bool:
	return pair < _shown.size() and _shown[pair] == 1 and _grudges(pair) > 0


## The pairs with markers, worked out again only when one gained or lost its marker.
func _marker_pairs() -> PackedInt32Array:
	if _markers_dirty:
		_markers_dirty = false
		_marked_pairs.clear()
		for pair in _pa.size():
			if pair < _marked.size() and _marked[pair] == 1:
				_marked_pairs.append(pair)
	return _marked_pairs


## Batches of baked shapes, one [MultiMesh] per kind, filled afresh each draw.
class _Markers:
	enum { GLOW, EMBER, KINDS }
	var meshes: Array[MultiMesh] = []
	var buffers: Array[PackedFloat32Array] = []
	var counts := PackedInt32Array()

	func _init() -> void:
		var quad := RelationshipWebTheme.unit_quad()
		counts.resize(KINDS)
		for _k in KINDS:
			var mesh := MultiMesh.new()
			mesh.transform_format = MultiMesh.TRANSFORM_2D
			mesh.use_colors = true
			mesh.mesh = quad
			meshes.append(mesh)
			buffers.append(PackedFloat32Array())

	## Room for [param pairs] pairs: at most two of each kind per pair (one at each end).
	func begin(pairs: int) -> void:
		for k in KINDS:
			counts[k] = 0
			if buffers[k].size() < pairs * 24:
				buffers[k].resize(pairs * 24)

	func add(kind: int, centre: Vector2, radius: float, tint: Color) -> void:
		var buffer := buffers[kind]
		buffers[kind] = PackedFloat32Array()
		_Medallions.write(buffer, counts[kind] * 12, centre, radius, tint)
		buffers[kind] = buffer
		counts[kind] += 1

	func draw(layer: Control, textures: Array[Texture2D]) -> void:
		for k in KINDS:
			var n := counts[k]
			if n == 0:
				continue
			if meshes[k].instance_count != n:
				meshes[k].instance_count = n
			meshes[k].buffer = buffers[k].slice(0, n * 12)
			layer.draw_multimesh(meshes[k], textures[k])


func _draw_focus() -> void:
	if _focus_pairs.is_empty() or _focus_amount < 0.02:
		return
	_focus_layer.draw_set_transform(pan, 0.0, Vector2(zoom, zoom))
	var inverse := 1.0 / zoom
	var positions := _layout.positions
	var alpha := clampf(_focus_amount, 0.0, 1.0)
	for pair in _focus_pairs:
		var pa := positions[_pa[pair]]
		var pb := positions[_pb[pair]]
		var ab := _ab[pair]
		var ba := _ba[pair]
		var from_color := style.feeling_color(ab.affinity) if ab != null else Color(style.neutral_color, 0.4)
		var to_color := style.feeling_color(ba.affinity) if ba != null else Color(style.neutral_color, 0.4)
		var line := PackedVector2Array()
		var colors := PackedColorArray()
		for s in _FOCUS_SEGMENTS + 1:
			var t := float(s) / _FOCUS_SEGMENTS
			line.append(_curve_point(pa, pb, t))
			var color := from_color.lerp(to_color, t)
			colors.append(Color(color, color.a * alpha))
		var width := line_widths[_width_bucket(_familiarity(pair))] + 1.6
		_focus_layer.draw_polyline_colors(line, colors, width * inverse, true)
	_draw_markers(_focus_layer, _focus_markers, inverse, true)


## The Lite mark, over everything: the knight, large and faint across the middle, and the edition's name in the
## corner.
func _draw_mark() -> void:
	var side := minf(size.x, size.y) * 0.62
	if side > 8.0:
		_mark_layer.draw_texture_rect(_LITE_MARK, Rect2((size - Vector2(side, side)) / 2.0, Vector2(side, side)), false,
			Color(1, 1, 1, 0.08))
	var font := style.bold_font()
	var text := "Relationship Web Lite"
	var font_size := 13
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var at := Vector2(size.x - w - 14.0, size.y - 14.0)
	_mark_layer.draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 5, Color(style.background_color, 0.85))
	_mark_layer.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(style.text_color, 0.55))


## True: this is the Lite edition's view (it draws the Lite mark).
func is_lite() -> bool:
	return true


func _radius(i: int) -> float:
	return person_radius * (_weight[i] if i < _weight.size() else 1.0)


func _draw_people() -> void:
	var started := Time.get_ticks_usec()
	if _ids.is_empty():
		return
	var layer := _people_layer
	var moving := not _layout.is_settled()
	var bold := style.bold_font()
	var positions := _layout.positions
	var count := _ids.size()
	var dim := lerpf(1.0, 0.22, _focus_amount) if not _focus_people.is_empty() else 1.0
	var focusing := not _focus_people.is_empty()
	var screen_rect := Rect2(Vector2.ZERO, size).grow(person_radius * 2.0 * zoom)
	# Every person is four tinted discs drawn in four batches: a shadow, the disc, the darker inside, the ring.
	_medallions.resize(count)
	var shadow := _medallions.buffers[0]
	var disc := _medallions.buffers[1]
	var inner := _medallions.buffers[2]
	var ring := _medallions.buffers[3]
	_medallions.buffers = []
	var detail_from := 7.0
	for i in count:
		var at := i * 12
		var faded := i < _faded.size() and _faded[i] == 1
		var p := positions[i] * zoom + pan
		var r := _radius(i) * zoom
		if (faded and not fade_unconnected) or not screen_rect.has_point(p):
			for buffer: PackedFloat32Array in [shadow, disc, inner, ring]:
				buffer[at] = 0.0
				buffer[at + 5] = 0.0
			continue
		var alpha := 0.3 if faded else 1.0
		if focusing and not _focus_people.has(i):
			alpha *= dim
		var color := _colors[i]
		var detailed := r >= detail_from and not moving
		_Medallions.write(shadow, at, p + Vector2(0.0, r * 0.2), r * 1.15, Color(0, 0, 0, 0.5 * alpha) if detailed else Color(0, 0, 0, 0))
		_Medallions.write(disc, at, p, r * 1.03, Color(color, alpha))
		var inside := color.darkened(0.62)
		_Medallions.write(inner, at, p, r * 0.82, Color(inside, alpha) if detailed else Color(inside, 0.0))
		_Medallions.write(ring, at, p, r * 0.84, Color(color.lightened(0.2), 0.5 * alpha) if detailed else Color(color, 0.0))
	_medallions.buffers = [shadow, disc, inner, ring]
	_medallions.draw(layer, style.shape("shadow"), style.shape("disc"), style.shape("ring"))
	# Portraits, initials, and the selected and hovered halos: few, drawn one by one.
	for i in count:
		var p := positions[i] * zoom + pan
		var r := _radius(i) * zoom
		if not screen_rect.has_point(p):
			continue
		var faded := i < _faded.size() and _faded[i] == 1
		if faded and not fade_unconnected:
			continue
		var alpha := 0.3 if faded else 1.0
		if focusing and not _focus_people.has(i):
			alpha *= dim
		var selected := i == _selected_person or (_selected_pair >= 0 and (i == _pa[_selected_pair] or i == _pb[_selected_pair]))
		if selected or i == _hover:
			var halo := 1.0 if selected else 0.55
			layer.draw_circle(p, r * 1.9, Color(style.accent_color, 0.10 * halo))
			layer.draw_arc(p, r * 1.38, 0.0, TAU, 40, Color(style.accent_color, 0.9 * halo), maxf(2.0, r * 0.12), true)
		if r < detail_from or moving:
			continue
		var icon := _icons[i]
		if icon != null:
			layer.draw_texture_rect(icon, Rect2(p - Vector2(r, r) * 0.78, Vector2(r, r) * 1.56), false, Color(1, 1, 1, alpha))
		elif r >= 9.0:
			var font_size := int(maxf(5.0, r * 0.78))
			var width := bold.get_string_size(_initials[i], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			layer.draw_string(bold, p + Vector2(-width / 2.0, font_size * 0.36), _initials[i], HORIZONTAL_ALIGNMENT_LEFT, -1,
				font_size, Color(_colors[i].lightened(0.55), alpha))
	_draw_labels(layer, moving)
	last_people_usec = Time.get_ticks_usec() - started


## Four [MultiMesh] batches of a unit quad, one per layer of a medallion: every person in one draw call each.
class _Medallions:
	var meshes: Array[MultiMesh] = []
	var buffers: Array[PackedFloat32Array] = []
	var count := -1

	func _init() -> void:
		var quad := RelationshipWebTheme.unit_quad()
		for _k in 4:
			var mesh := MultiMesh.new()
			mesh.transform_format = MultiMesh.TRANSFORM_2D
			mesh.use_colors = true
			mesh.mesh = quad
			meshes.append(mesh)
			buffers.append(PackedFloat32Array())

	func resize(people: int) -> void:
		if people == count:
			return
		count = people
		for k in 4:
			meshes[k].instance_count = people
			var buffer := PackedFloat32Array()
			buffer.resize(people * 12)
			buffers[k] = buffer

	## One instance: a quad [param diameter] wide at [param at], tinted. (12 floats: a 2D transform's two rows,
	## then the colour.)
	static func write(buffer: PackedFloat32Array, at: int, centre: Vector2, radius: float, tint: Color) -> void:
		var d := radius * 2.0
		buffer[at] = d
		buffer[at + 1] = 0.0
		buffer[at + 2] = 0.0
		buffer[at + 3] = centre.x
		buffer[at + 4] = 0.0
		buffer[at + 5] = d
		buffer[at + 6] = 0.0
		buffer[at + 7] = centre.y
		buffer[at + 8] = tint.r
		buffer[at + 9] = tint.g
		buffer[at + 10] = tint.b
		buffer[at + 11] = tint.a

	func draw(layer: Control, shadow: Texture2D, disc: Texture2D, ring: Texture2D) -> void:
		if count <= 0:
			return
		var textures: Array[Texture2D] = [shadow, disc, disc, ring]
		for k in 4:
			meshes[k].buffer = buffers[k]
			layer.draw_multimesh(meshes[k], textures[k])


## Names in screen space, never over each other or over anyone's face: the selected and hovered first, then whoever
## is lit up, then the most connected (up to max_labels in the overview; everyone once zoomed in far enough). Each
## name goes below its person if there is room, else above, right or left.
func _draw_labels(layer: Control, moving: bool) -> void:
	var started := Time.get_ticks_usec()
	var font := style.bold_font()
	var order: Array[int] = []
	var wanted: Dictionary[int, bool] = {}
	for i: int in [_selected_person, _hover]:
		if i >= 0 and not wanted.has(i):
			order.append(i)
			wanted[i] = true
	if _selected_pair >= 0:
		for i: int in [_pa[_selected_pair], _pb[_selected_pair]]:
			if not wanted.has(i):
				order.append(i)
				wanted[i] = true
	for i: int in _focus_people:
		if not wanted.has(i):
			order.append(i)
			wanted[i] = true
	var focusing := not _focus_people.is_empty() and _focus_amount > 0.5
	if not moving and not focusing:
		var everyone := person_radius * zoom >= 14.0
		var budget := _ids.size() if everyone else maxi(0, max_labels - order.size())
		for i in _label_order:
			if budget <= 0:
				break
			if not wanted.has(i) and (i >= _faded.size() or _faded[i] == 0):
				order.append(i)
				budget -= 1
	# Faces are in the way of names (only the lit-up ones while someone is lit up).
	var screen_rect := Rect2(Vector2.ZERO, size)
	var grid: Dictionary[Vector2i, Array] = {}
	var positions := _layout.positions
	for i in _ids.size():
		if (i < _faded.size() and _faded[i] == 1) or (focusing and not _focus_people.has(i)):
			continue
		var r := _radius(i) * zoom
		var face := Rect2(positions[i] * zoom + pan - Vector2(r, r), Vector2(r, r) * 2.0)
		if screen_rect.intersects(face):
			_grid_add(grid, face, i)
	var tall := label_font_size + 4.0
	for i in order:
		var screen := positions[i] * zoom + pan
		var r := _radius(i) * zoom
		if i == _selected_person or i == _hover or (_selected_pair >= 0 and (i == _pa[_selected_pair] or i == _pb[_selected_pair])):
			r *= 1.45          # clear of the selection ring
		var wide := font.get_string_size(_labels[i], HORIZONTAL_ALIGNMENT_LEFT, -1, label_font_size).x + 6.0
		var places: Array[Rect2] = [
			Rect2(screen.x - wide / 2.0, screen.y + r + 3.0, wide, tall),
			Rect2(screen.x - wide / 2.0, screen.y - r - 3.0 - tall, wide, tall),
			Rect2(screen.x + r + 4.0, screen.y - tall / 2.0, wide, tall),
			Rect2(screen.x - r - 4.0 - wide, screen.y - tall / 2.0, wide, tall),
		]
		var chosen := Rect2()
		var found := false
		for place in places:
			if screen_rect.encloses(place) and not _grid_hits(grid, place, i):
				chosen = place
				found = true
				break
		if not found:
			if not wanted.has(i) or not screen_rect.intersects(places[0]):
				continue
			chosen = places[0]       # the lit-up are always named
		_grid_add(grid, chosen, -1)
		var alpha := 1.0
		if not _focus_people.is_empty() and not _focus_people.has(i):
			alpha = lerpf(1.0, 0.25, _focus_amount)
		var baseline := Vector2(chosen.position.x + 3.0, chosen.position.y + label_font_size - 1.0)
		layer.draw_string_outline(font, baseline, _labels[i], HORIZONTAL_ALIGNMENT_LEFT, -1, label_font_size, 5,
			Color(style.text_outline_color, 0.9 * alpha))
		var selected := i == _selected_person or i == _hover
		layer.draw_string(font, baseline, _labels[i], HORIZONTAL_ALIGNMENT_LEFT, -1, label_font_size,
			Color(style.accent_color.lightened(0.4) if selected else style.text_color, alpha))
	last_labels_usec = Time.get_ticks_usec() - started


const _LABEL_CELL := 64.0


func _grid_add(grid: Dictionary[Vector2i, Array], rect: Rect2, who: int) -> void:
	for x in range(floori(rect.position.x / _LABEL_CELL), floori(rect.end.x / _LABEL_CELL) + 1):
		for y in range(floori(rect.position.y / _LABEL_CELL), floori(rect.end.y / _LABEL_CELL) + 1):
			var key := Vector2i(x, y)
			if not grid.has(key):
				grid[key] = []
			grid[key].append([rect, who])


func _grid_hits(grid: Dictionary[Vector2i, Array], rect: Rect2, own: int) -> bool:
	for x in range(floori(rect.position.x / _LABEL_CELL), floori(rect.end.x / _LABEL_CELL) + 1):
		for y in range(floori(rect.position.y / _LABEL_CELL), floori(rect.end.y / _LABEL_CELL) + 1):
			var cell: Array = grid.get(Vector2i(x, y), [])
			for entry: Array in cell:
				var other: Rect2 = entry[0]
				var who: int = entry[1]
				if who != own and other.intersects(rect):
					return true
	return false


# ------------------------------------------------------------------------------------------ input

func _to_world(screen: Vector2) -> Vector2:
	return (screen - pan) / zoom


func _person_at(screen: Vector2) -> int:
	var world := _to_world(screen)
	var best := -1
	var best_distance := INF
	for i in _ids.size():
		if i < _faded.size() and _faded[i] == 1 and not fade_unconnected:
			continue
		var d := _layout.positions[i].distance_to(world)
		if d <= _radius(i) + 4.0 / zoom and d < best_distance:
			best = i
			best_distance = d
	return best


func _pair_at(screen: Vector2) -> int:
	var world := _to_world(screen)
	var best := -1
	var best_distance := 6.0 / zoom
	for pair in _pa.size():
		if pair >= _shown.size() or _shown[pair] == 0:
			continue
		var pa := _layout.positions[_pa[pair]]
		var pb := _layout.positions[_pb[pair]]
		var previous := pa
		for s in _SEGMENTS:
			var next := _curve_point(pa, pb, float(s + 1) / _SEGMENTS)
			var d := Geometry2D.get_closest_point_to_segment(world, previous, next).distance_to(world)
			if d < best_distance:
				best_distance = d
				best = pair
			previous = next
	return best


func _find_pair(a_id: String, b_id: String) -> int:
	if not _index.has(a_id) or not _index.has(b_id):
		return -1
	var a: int = _index[a_id]
	var b: int = _index[b_id]
	return _pair_of.get(mini(a, b) * _ids.size() + maxi(a, b), -1)


func _gui_input(event: InputEvent) -> void:
	_sync()
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		_mouse_button(button)
	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		_mouse_motion(motion)
	elif event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo:
			if key.keycode == KEY_ESCAPE:
				clear_selection()
				selection_cleared.emit()
				accept_event()
			elif key.keycode == KEY_F:
				auto_fit = true
				fit_view()
				accept_event()


func _mouse_button(button: InputEventMouseButton) -> void:
	if button.button_index == MOUSE_BUTTON_WHEEL_UP or button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		if button.pressed:
			var before := _to_world(button.position)
			zoom *= 1.12 if button.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.12
			auto_fit = false
			pan = button.position - before * zoom
		accept_event()
		return
	if button.button_index == MOUSE_BUTTON_LEFT:
		if button.pressed:
			grab_focus()
			_press = button.position
			_moved = false
			if button.double_click:
				var person := _person_at(button.position)
				if person >= 0:
					person_activated.emit(_ids[person])
				_skip_release = true
				accept_event()
				return
			_drag = _person_at(button.position)
			_panning = _drag < 0
		else:
			if _skip_release:
				_skip_release = false
			elif not _moved:
				_click(button.position, button.shift_pressed or button.ctrl_pressed)
			elif _drag >= 0:
				_layout.pinned[_drag] = 1
			_drag = -1
			_panning = false
		accept_event()
	elif button.button_index == MOUSE_BUTTON_MIDDLE or button.button_index == MOUSE_BUTTON_RIGHT:
		_panning = button.pressed
		_press = button.position
		_drag = -1
		_moved = button.pressed
		accept_event()


func _mouse_motion(motion: InputEventMouseMotion) -> void:
	if (_drag >= 0 or _panning) and motion.position.distance_to(_press) > 3.0:
		_moved = true
	if _drag >= 0 and _moved:
		_layout.positions[_drag] = _to_world(motion.position)
		_layout.reheat(0.08)
		_geometry_dirty = true
		_wake()
	elif _panning and _moved:
		pan += motion.relative
		auto_fit = false
	else:
		var hovered := _person_at(motion.position)
		if hovered != _hover:
			_hover = hovered
			tooltip_text = _labels[hovered] if hovered >= 0 else ""
			_update_focus()


func _click(at: Vector2, extend: bool) -> void:
	var person := _person_at(at)
	if person >= 0:
		if extend and _selected_person >= 0 and _selected_person != person:
			var first := _ids[_selected_person]
			if select_pair(first, _ids[person]):
				pair_selected.emit(first, _ids[person])
				return
		_selected_person = person
		_selected_pair = -1
		_selection_moved()
		person_selected.emit(_ids[person])
		return
	var pair := _pair_at(at)
	if pair >= 0:
		_selected_pair = pair
		_selected_person = -1
		_selection_moved()
		pair_selected.emit(_ids[_pa[pair]], _ids[_pb[pair]])
		return
	clear_selection()
	selection_cleared.emit()


# ------------------------------------------------------------------------------------------ defaults

func _default_label(person: RelationshipPerson) -> String:
	var given: Variant = person.data.get("name", null)
	return str(given) if given != null and not str(given).is_empty() else person.id


func _default_color(person: RelationshipPerson) -> Color:
	var group: Variant = person.data.get("group", null)
	return style.palette_color(str(group) if group != null else person.id)
