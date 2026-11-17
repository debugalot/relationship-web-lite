extends Control
## Thornbury, the Lite way: 24 villagers, their friendships, feuds and grudges, drawn by the Lite web view. Click
## someone, Shift-click a second person (or click a line) for the pair, and act: help, insult, betray, make up, or
## let a day pass (Space). The full Relationship Web adds romance, families, jealousy, the relationship list, the
## family tree and the ready-made screen: https://debugalot.itch.io/relationship-web
##
## Run with [code]-- --shots <folder>[/code] to save screenshots, then quit.

const KNIGHT := preload("res://demo/knight.png")

## [id, name, group]
const PEOPLE: Array[Array] = [
	["aldric", "Sir Aldric", "Keep"], ["brenna", "Captain Brenna", "Keep"], ["garrick", "Garrick", "Keep"],
	["wyn", "Wyn", "Keep"], ["hugh", "Hugh Miller", "Millers"], ["edda", "Edda Miller", "Millers"],
	["pip", "Pip Miller", "Millers"], ["bram", "Bram Smith", "Smiths"], ["maud", "Maud Smith", "Smiths"],
	["agathe", "Mother Agathe", "Temple"], ["linus", "Brother Linus", "Temple"], ["fenwick", "Fenwick", "Traders"],
	["jory", "Jory", "Traders"], ["nell", "Nell Barrow", "Tavern"], ["wat", "Wat Barrow", "Tavern"],
	["lark", "Lark", "Tavern"], ["ansel", "Ansel Thorne", "Thornes"], ["bess", "Bess Thorne", "Thornes"],
	["kit", "Kit Thorne", "Thornes"], ["rook", "Rook", "Outlaws"], ["sable", "Sable", "Outlaws"],
	["eustace", "Lord Eustace", "Hall"], ["gage", "Gage", "Woods"], ["yara", "Yara", "Woods"],
]

var web := RelationshipWeb.new()
var view := RelationshipWebView.new()
var _card: Label
var _who: Label
var _buttons: Array[Button] = []


func _ready() -> void:
	_build()
	view.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(view)
	view.icon_for = func(person: RelationshipPerson) -> Texture2D:
		return KNIGHT if person.id == "aldric" else null
	view.web = web
	_build_panel()
	view.selection_changed.connect(_refresh)
	web.bond_changed.connect(func(_a: String, _b: String) -> void: _refresh())
	_refresh()
	var args := OS.get_cmdline_user_args()
	var at := args.find("--shots")
	if at >= 0 and at + 1 < args.size():
		await _shots(args[at + 1])


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and key.keycode == KEY_SPACE:
		_act("day")


func _build() -> void:
	web.random_seed = 7
	for person: Array in PEOPLE:
		web.add_person(str(person[0]), {"data": {"name": str(person[1]), "group": str(person[2])}})
	web.get_person("hugh").pride = 85.0
	web.get_person("hugh").forgiveness = 10.0
	web.get_person("agathe").forgiveness = 95.0
	web.get_person("rook").volatility = 90.0
	for family: Array in [["hugh", "edda", "pip"], ["bram", "maud"], ["nell", "wat"], ["ansel", "bess", "kit"]]:
		for i in family.size():
			for j in range(i + 1, family.size()):
				web.link(str(family[i]), str(family[j]), &"family")
	for link: Array in [
		["brenna", "aldric", &"friend"], ["brenna", "garrick", &"rival"], ["aldric", "garrick", &"ally"],
		["aldric", "wyn", &"friend"], ["wyn", "garrick", &"friend"], ["aldric", "eustace", &"ally"],
		["brenna", "eustace", &"ally"], ["eustace", "fenwick", &"ally"], ["rook", "eustace", &"enemy"],
		["hugh", "ansel", &"enemy"], ["edda", "bess", &"rival"], ["pip", "kit", &"friend"], ["bram", "fenwick", &"rival"],
		["bram", "aldric", &"friend"], ["fenwick", "jory", &"ally"], ["wat", "fenwick", &"rival"], ["maud", "nell", &"friend"],
		["nell", "lark", &"friend"], ["wat", "lark", &"ally"], ["nell", "ansel", &"friend"], ["agathe", "linus", &"friend"],
		["agathe", "yara", &"friend"], ["gage", "rook", &"ally"], ["gage", "yara", &"friend"], ["rook", "sable", &"partner"],
		["rook", "aldric", &"enemy"], ["sable", "brenna", &"enemy"], ["jory", "lark", &"friend"], ["yara", "kit", &"ally"],
	]:
		web.link(str(link[0]), str(link[1]), link[2])
	web.open_grievance("hugh", "ansel", 4, "dammed the stream in the dry month")
	web.open_grievance("ansel", "hugh", 3, "called him a thief at market")
	web.open_grievance("rook", "eustace", 5, "hanged his brother")
	web.open_grievance("wat", "fenwick", 2, "charges interest on interest")
	web.open_grievance("garrick", "brenna", 2, "passed him over for sergeant")
	web.open_grievance("sable", "brenna", 4, "put a price on her head")
	for d in 20:
		web.interact("nell", "lark", {"affinity": 2})
		web.interact("aldric", "wyn", {"affinity": 2, "trust": 1})
		if d % 3 == 0:
			web.interact("hugh", "ansel", {"affinity": -6}, {"affinity": -5})
		web.advance_day()


func _build_panel() -> void:
	var style := view.style
	var panel := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color(style.panel_color, 0.94)
	box.border_color = style.panel_border_color
	box.set_border_width_all(1)
	box.set_corner_radius_all(12)
	box.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", box)
	panel.position = Vector2(16, 16)
	panel.custom_minimum_size = Vector2(340, 0)
	add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)
	var title := _label("Thornbury", 20, style.bold_font(), style.text_color)
	column.add_child(title)
	_who = _label("", 14, style.bold_font(), style.accent_color.lightened(0.3))
	column.add_child(_who)
	_card = _label("", 13, style.regular_font(), style.muted_text_color)
	_card.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_card)
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 6)
	row.add_theme_constant_override("v_separation", 6)
	column.add_child(row)
	for action: Array in [["Help", "help"], ["Insult", "insult"], ["Betray", "betray"], ["Make up", "make_up"], ["A day", "day"]]:
		var button := Button.new()
		button.text = str(action[0])
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_act.bind(str(action[1])))
		var normal := StyleBoxFlat.new()
		normal.bg_color = style.panel_color.lightened(0.07)
		normal.border_color = style.panel_border_color
		normal.set_border_width_all(1)
		normal.set_corner_radius_all(12)
		normal.content_margin_left = 12
		normal.content_margin_right = 12
		normal.content_margin_top = 4
		normal.content_margin_bottom = 4
		button.add_theme_stylebox_override("normal", normal)
		button.add_theme_stylebox_override("hover", normal)
		button.add_theme_stylebox_override("pressed", normal)
		button.add_theme_stylebox_override("disabled", normal)
		button.add_theme_font_override("font", style.bold_font())
		button.add_theme_font_size_override("font_size", 12)
		button.add_theme_color_override("font_color", style.text_color)
		button.add_theme_color_override("font_disabled_color", Color(style.muted_text_color, 0.4))
		row.add_child(button)
		_buttons.append(button)


func _label(text: String, font_size: int, font: Font, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


## Who the buttons act on: the selected pair, first to second.
func _pair() -> PackedStringArray:
	return view.get_selected_pair()


func _act(what: String) -> void:
	var pair := _pair()
	if what == "day":
		web.advance_day()
	elif pair.size() == 2:
		var a := pair[0]
		var b := pair[1]
		match what:
			"help":
				web.apply(b, a, {"affinity": 8, "trust": 6})
			"insult":
				web.apply(b, a, {"affinity": -12, "trust": -5})
			"betray":
				web.apply(b, a, {"affinity": -20, "trust": -30})
				web.open_grievance(b, a, 4, "betrayed them")
			"make_up":
				for g in web.get_grievances(b, a) + web.get_grievances(a, b):
					web.resolve(g, "Made up")
				web.interact(a, b, {"affinity": 6, "trust": 4})
	_refresh()


func _refresh() -> void:
	var pair := _pair()
	var person := view.get_selected_person()
	var lines := PackedStringArray()
	if pair.size() == 2:
		_who.text = "%s and %s" % [view.get_label(pair[0]), view.get_label(pair[1])]
		for side: Array in [[pair[0], pair[1]], [pair[1], pair[0]]]:
			var bond := web.get_bond(str(side[0]), str(side[1]))
			var from := view.get_label(str(side[0]))
			var to := view.get_label(str(side[1]))
			if bond == null:
				lines.append("%s → %s: no feelings yet" % [from, to])
				continue
			lines.append("%s → %s: affinity %+d, trust %d, knows %d" % [from, to, roundi(bond.affinity), roundi(bond.trust),
				roundi(bond.familiarity)])
			for g in bond.grievances:
				lines.append("   holds a grudge: %s (%d/5)" % [g.description if not g.description.is_empty() else "something", g.severity])
	elif not person.is_empty():
		_who.text = view.get_label(person)
		lines.append("Knows %d people. Shift-click someone else (or click a line) to act on the pair." % web.get_bonds_from(person).size())
	else:
		_who.text = "Day %d" % web.day
		lines.append("Click someone, then Shift-click a second person, or click a line between two people.")
	_card.text = "\n".join(lines)
	for k in _buttons.size():
		_buttons[k].disabled = k < 4 and pair.size() != 2


func _shots(folder: String) -> void:
	DirAccess.make_dir_recursive_absolute(folder)
	await get_tree().process_frame
	await get_tree().process_frame
	view.settle()
	await get_tree().create_timer(0.6).timeout
	await _shot(folder.path_join("lite_overview.png"))
	view.select_pair("hugh", "ansel")
	_refresh()
	await get_tree().create_timer(0.8).timeout
	await _shot(folder.path_join("lite_pair.png"))
	get_tree().quit()


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)
