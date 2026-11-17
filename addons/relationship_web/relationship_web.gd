@icon("res://addons/relationship_web/icon.svg")
class_name RelationshipWeb
extends RefCounted
## Who feels what about whom.
##
## A web of people and the bonds between them. Every bond is one direction: how one person feels about another,
## as affinity (−100 to 100), trust (0 to 100) and familiarity (0 to 100). The other direction is its own bond,
## so feelings can be lopsided.[br][br]
## Personality shapes the maths. Volatile people swing harder. Proud people open grievances one step more severe
## and stew on them longer. Forgiving people let small grievances go. Loyal people hold their feelings longer.
## Attachment style changes how trust is won and lost.[br][br]
## Between events, [method advance_day] lets affinity drift back toward each bond's long-term baseline, lets old
## grievances eat into affinity (and severe ones fester), lets small ones be let go, and lets familiarity fade
## without contact. Trust never drifts: only events move it.[br][br]
## Everything is deterministic: the same [member random_seed] and the same calls give the same web on any machine,
## and a web saved with [method save_binary] (or [method to_dict]) and loaded back carries on exactly as if it had
## never stopped.[br][br]
## People remember: each bond keeps its last few resolved grievances ([member RelationshipTuning.remembered_grievances],
## see [method get_past_grievances]), so a game can bring up an old wrong long after it was forgiven.[br][br]
## This is [b]Relationship Web Lite[/b], the free edition. The full Relationship Web adds romance and attraction,
## jealousy, courtship that can be turned down, couples, marriage and divorce, affairs, family roles and trees,
## pregnancy, death, abandonment and adoption, the relationship list, the family tree and the ready-made screen,
## with the same API: code written for Lite runs unchanged on it. https://debugalot.itch.io/relationship-web
## [br][br]
## [b]Note:[/b] a web is a [RefCounted]. A signal handler written as a lambda that uses the web keeps the web alive
## (each holds the other), so disconnect such handlers when you are done, or connect a method of a [Node] instead.
## A web isn't thread-safe: use it from one thread at a time.
## [codeblock]
## var web := RelationshipWeb.new()
## web.add_person("ana", {"volatility": 70, "attachment": "anxious"})
## web.add_person("bo")
## web.link("ana", "bo", &"friend")
## web.apply("ana", "bo", {"affinity": 10, "trust": 5})   # bo helped ana: ana likes and trusts bo more
## web.open_grievance("bo", "ana", 2, "She told everyone about the debt.")
## web.advance_day()
## print(web.get_bond("ana", "bo").affinity)
## [/codeblock]

## A person joined the web.
signal person_added(id: String)
## A person left the web, with every bond to and from them.
signal person_removed(id: String)
## A bond was created ([method link], or the first [method apply] between two people).
signal bond_added(from_id: String, to_id: String)
## A bond was removed ([method unlink], or one of its people left).
signal bond_removed(from_id: String, to_id: String)
## A bond's affinity, trust, familiarity or baseline changed.
signal bond_changed(from_id: String, to_id: String)
## A bond's affinity crossed into another band ([code]&"warm"[/code], [code]&"neutral"[/code] or
## [code]&"cold"[/code]). Fires after [signal bond_changed].
signal band_changed(from_id: String, to_id: String, old_band: StringName, new_band: StringName)
## A grievance was opened.
signal grievance_opened(grievance: RelationshipGrievance)
## A grievance got worse, softened, or turned festering.
signal grievance_changed(grievance: RelationshipGrievance)
## A grievance ended. It leaves the bond's open grievances and joins its remembered ones
## ([method get_past_grievances]).
signal grievance_resolved(grievance: RelationshipGrievance)
## A day ended; [param new_day] is the day that starts. Fires after every change the day made.
signal day_advanced(new_day: int)

## The save format [method to_dict] writes.
const FORMAT := 1
## The band of affinity at or above [member RelationshipTuning.warm_at].
const WARM := &"warm"
## The band between cold and warm.
const NEUTRAL := &"neutral"
## The band of affinity at or below [member RelationshipTuning.cold_at].
const COLD := &"cold"
## The presets every web starts with (see [member presets]).
const DEFAULT_PRESETS: Dictionary[StringName, Dictionary] = {
	&"stranger": {"affinity": 0.0, "trust": 20.0, "familiarity": 0.0, "baseline": 0.0},
	&"acquaintance": {"affinity": 0.0, "trust": 30.0, "familiarity": 5.0, "baseline": 0.0},
	&"friend": {"affinity": 40.0, "trust": 50.0, "familiarity": 50.0, "baseline": 30.0, "floor": 10.0},
	&"ally": {"affinity": 15.0, "trust": 40.0, "familiarity": 30.0, "baseline": 10.0},
	&"rival": {"affinity": -25.0, "trust": 20.0, "familiarity": 40.0, "baseline": -15.0},
	&"enemy": {"affinity": -60.0, "trust": 5.0, "familiarity": 40.0, "baseline": -40.0},
	&"partner": {"affinity": 60.0, "trust": 65.0, "familiarity": 80.0, "baseline": 50.0, "floor": 40.0},
	&"family": {"affinity": 25.0, "trust": 50.0, "familiarity": 60.0, "baseline": 20.0, "floor": 30.0, "kin": true},
}

const _PRESET_KEYS: PackedStringArray = ["affinity", "trust", "familiarity", "baseline", "floor", "kin", "tags"]
const _CHANGE_KEYS: PackedStringArray = ["affinity", "trust", "familiarity"]
const _FEELING_KEYS: PackedStringArray = ["affinity", "trust", "familiarity", "baseline"]
const _TRAIT_KEYS: PackedStringArray = ["volatility", "pride", "forgiveness", "loyalty", "attachment", "data"]
const _BANDS: Array[StringName] = [&"warm", &"neutral", &"cold"]
const _BASE := {"affinity": 0.0, "trust": 30.0, "familiarity": 5.0, "baseline": 0.0, "floor": 0.0, "kin": false, "tags": []}

## The numbers the maths uses. Share one [RelationshipTuning] between webs, or save it as a [code].tres[/code].
## Never null: setting null restores the defaults. Problems in it ([method RelationshipTuning.get_problems]) are
## reported once as warnings, and the maths stays safe whatever the values.
var tuning: RelationshipTuning = RelationshipTuning.new():
	set(value):
		tuning = value if value != null else RelationshipTuning.new()
		_check_tuning()
## Starting values for [method link], by name: [code]&"stranger"[/code], [code]&"acquaintance"[/code],
## [code]&"friend"[/code], [code]&"ally"[/code], [code]&"rival"[/code], [code]&"enemy"[/code], [code]&"partner"[/code]
## and [code]&"family"[/code] to begin with. Each can set [code]affinity[/code], [code]trust[/code],
## [code]familiarity[/code], [code]baseline[/code] (where affinity settles over time), [code]floor[/code]
## (familiarity never fades below it), [code]kin[/code] and [code]tags[/code]; anything left out comes from
## [code]&"acquaintance"[/code], which is also what two people become on first contact. Add your own or change these:
## [codeblock]
## web.presets[&"mentor"] = {"affinity": 30, "trust": 70, "familiarity": 40, "baseline": 25, "tags": ["mentor"]}
## web.link("old_tom", "pip", &"mentor", &"acquaintance")
## [/codeblock]
var presets: Dictionary[StringName, Dictionary] = DEFAULT_PRESETS.duplicate(true)
## The seed for the one chance in the model: whether someone lets a small grievance go on a given day.
var random_seed := 0
## The current day. [method advance_day] ends it and starts the next. Events happen on the current day.
var day := 0

var _people: Dictionary[String, RelationshipPerson] = {}
var _out: Dictionary[String, Dictionary] = {}              # from id → {to id → RelationshipBond}
var _in: Dictionary[String, Dictionary] = {}               # to id → {from id → RelationshipBond}
var _grievances: Dictionary[int, RelationshipGrievance] = {}   # open and festering only
var _past: Dictionary[RelationshipBond, Array] = {}            # bond → its remembered resolved grievances, oldest first
var _next_grievance_id := 1
var _list: Array[RelationshipBond] = []
var _list_dirty := false
# Bonds the daily tick still has to visit. A bond at rest (on its baseline, no grievances, nothing left to fade)
# can't change until something touches it, so it leaves the list (bond._resting) and _wake() puts it back.
var _active: Array[RelationshipBond] = []
var _reported_problems := ""
var _preset_cache: Dictionary[StringName, Array] = {}   # name → [hash of its source and the acquaintance, values]


# ------------------------------------------------------------------------------------------ people

## Adds a person and returns them. [param traits] can set [code]volatility[/code], [code]pride[/code],
## [code]forgiveness[/code] and [code]loyalty[/code] (0 to 100, default 50), [code]attachment[/code]
## ([code]"secure"[/code], [code]"anxious"[/code], [code]"avoidant"[/code] or [code]"disorganized"[/code], or a
## [enum RelationshipPerson.Attachment] value) and [code]data[/code] (a dictionary of your own, copied in). Adding an
## id that is already in the web is an error and returns the person already there, unchanged.
func add_person(id: String, traits: Dictionary = {}) -> RelationshipPerson:
	if id.is_empty():
		push_error("RelationshipWeb.add_person: the id can't be empty.")
		return null
	if _people.has(id):
		push_error("RelationshipWeb.add_person: \"%s\" is already in the web." % id)
		return _people[id]
	var person := RelationshipPerson.new()
	person.id = id
	_apply_traits(person, traits, "add_person")
	_people[id] = person
	_out[id] = {}
	_in[id] = {}
	person_added.emit(id)
	return person


## Removes a person and every bond to and from them (their open grievances end with "Bond removed"). Returns
## false if there was no such person.
func remove_person(id: String) -> bool:
	if not _people.has(id):
		push_error("RelationshipWeb.remove_person: there is no person \"%s\"." % id)
		return false
	for to_id: String in (_out[id] as Dictionary).keys():
		_remove_bond(id, to_id)
	for from_id: String in (_in[id] as Dictionary).keys():
		_remove_bond(from_id, id)
	_people.erase(id)
	_out.erase(id)
	_in.erase(id)
	person_removed.emit(id)
	return true


## True if the person is in the web.
func has_person(id: String) -> bool:
	return _people.has(id)


## The person with this id, or null.
func get_person(id: String) -> RelationshipPerson:
	return _people.get(id, null)


## Every person's id, in the order they were added.
func get_person_ids() -> PackedStringArray:
	return PackedStringArray(_people.keys())


## How many people are in the web.
func get_person_count() -> int:
	return _people.size()


# ------------------------------------------------------------------------------------------ bonds

## Links two people both ways and returns true. [param preset] is a name from [member presets] or a dictionary of
## starting values (see [member presets] for the keys); [param reverse] sets how [param b] feels about [param a]
## the same way, and defaults to [param preset]. Linking people who are already linked resets their bonds to the new
## values (grievances stay).
func link(a: String, b: String, preset: Variant = &"acquaintance", reverse: Variant = null) -> bool:
	if not _check_pair(a, b, "link"):
		return false
	var forward := _resolve_preset(preset, "link")
	var backward := forward if reverse == null else _resolve_preset(reverse, "link")
	_set_from_preset(a, b, forward)
	_set_from_preset(b, a, backward)
	return true


## Links one direction only: how [param from_id] feels about [param to_id]. See [method link].
func link_one_way(from_id: String, to_id: String, preset: Variant = &"acquaintance") -> bool:
	if not _check_pair(from_id, to_id, "link_one_way"):
		return false
	_set_from_preset(from_id, to_id, _resolve_preset(preset, "link_one_way"))
	return true


## Removes both bonds between two people. Returns true if there was at least one.
func unlink(a: String, b: String) -> bool:
	var removed := _remove_bond(a, b)
	return _remove_bond(b, a) or removed


## Removes one direction. Returns true if it existed.
func unlink_one_way(from_id: String, to_id: String) -> bool:
	return _remove_bond(from_id, to_id)


## True if [param from_id] has feelings about [param to_id].
func has_bond(from_id: String, to_id: String) -> bool:
	return _out.has(from_id) and (_out[from_id] as Dictionary).has(to_id)


## How [param from_id] feels about [param to_id], or null if they have no bond.
func get_bond(from_id: String, to_id: String) -> RelationshipBond:
	if not _out.has(from_id):
		return null
	return (_out[from_id] as Dictionary).get(to_id, null)


## How [param id] feels about everyone they have a bond with.
func get_bonds_from(id: String) -> Array[RelationshipBond]:
	var bonds: Array[RelationshipBond] = []
	if _out.has(id):
		bonds.assign((_out[id] as Dictionary).values())
	return bonds


## How everyone with a bond to [param id] feels about them.
func get_bonds_to(id: String) -> Array[RelationshipBond]:
	var bonds: Array[RelationshipBond] = []
	if _in.has(id):
		bonds.assign((_in[id] as Dictionary).values())
	return bonds


## Every bond in the web, in a stable order. The array is yours to keep.
func get_all_bonds() -> Array[RelationshipBond]:
	return _bond_list().duplicate()


## How many bonds there are (each direction counts once).
func get_bond_count() -> int:
	return _bond_list().size()


# ------------------------------------------------------------------------------------------ events

## Something happened that changes how [param from_id] feels about [param to_id]; returns the bond.
## [param changes] holds any of [code]affinity[/code], [code]trust[/code] and [code]familiarity[/code], as
## amounts to add (negative to take away). Personality shapes them: volatility scales affinity, the feeling's
## strength damps pushing it further, and attachment style scales trust. [param contact] means the two met,
## which adds [member RelationshipTuning.contact_familiarity] and stops familiarity fading today.
## [br][br]If the two have no bond yet, an [code]&"acquaintance"[/code] bond is made first. Returns null if either
## person isn't in the web.
func apply(from_id: String, to_id: String, changes: Dictionary, contact: bool = true) -> RelationshipBond:
	var bond := _ensure_bond(from_id, to_id, "apply")
	if bond == null:
		return null
	_check_keys(changes, _CHANGE_KEYS, "apply")
	var da := _number(changes, "affinity", "apply")
	var dt := _number(changes, "trust", "apply")
	var df := _number(changes, "familiarity", "apply")
	var owner := bond._owner
	var affinity_before := bond.affinity
	var trust_before := bond.trust
	var familiarity_before := bond.familiarity
	if da != 0.0:
		var divisor := _safe(tuning.volatility_divisor, 125.0)
		var k_vol := maxf(0.0, _safe(tuning.volatility_base, 0.6)) + (owner.volatility / divisor if divisor > 0.0 else 0.0)
		var k_sat := maxf(0.0, 1.0 - maxf(0.0, signf(da) * bond.affinity) / maxf(_safe(tuning.saturation_divisor, 125.0), 100.0))
		bond.affinity = clampf(bond.affinity + da * k_vol * k_sat, -100.0, 100.0)
	if dt != 0.0:
		bond.trust = clampf(bond.trust + dt * _trust_factor(owner.attachment, dt), 0.0, 100.0)
	if contact:
		df += maxf(0.0, _safe(tuning.contact_familiarity, 2.0))
		bond.last_contact_day = day
	if df != 0.0:
		bond.familiarity = clampf(bond.familiarity + df, 0.0, 100.0)
	_wake(bond)
	if bond.affinity != affinity_before or bond.trust != trust_before or bond.familiarity != familiarity_before:
		_changed(bond)
	return bond


## [method apply] both ways at once: [param a_changes] to how [param a] feels about [param b], and
## [param b_changes] (the same as [param a_changes] if left out) to how [param b] feels about [param a].
## Returns false if either person isn't in the web.
func interact(a: String, b: String, a_changes: Dictionary, b_changes: Variant = null, contact: bool = true) -> bool:
	if not _check_pair(a, b, "interact"):
		return false
	var back: Dictionary = a_changes
	if b_changes is Dictionary:
		back = b_changes
	elif b_changes != null:
		push_error("RelationshipWeb.interact: b_changes must be a Dictionary or null.")
		return false
	apply(a, b, a_changes, contact)
	apply(b, a, back, contact)
	return true


## Sets feelings outright, with no personality maths: any of [code]affinity[/code], [code]trust[/code],
## [code]familiarity[/code] and [code]baseline[/code] (which also becomes the point the baseline can drift
## around). Values are clamped to their ranges. Makes an [code]&"acquaintance"[/code] bond first if there is none.
## Returns the bond, or null if either person isn't in the web.
func set_feelings(from_id: String, to_id: String, values: Dictionary) -> RelationshipBond:
	var bond := _ensure_bond(from_id, to_id, "set_feelings")
	if bond == null:
		return null
	_check_keys(values, _FEELING_KEYS, "set_feelings")
	var before := [bond.affinity, bond.trust, bond.familiarity, bond.baseline]
	if values.has("affinity"):
		bond.affinity = clampf(_number(values, "affinity", "set_feelings", bond.affinity), -100.0, 100.0)
	if values.has("trust"):
		bond.trust = clampf(_number(values, "trust", "set_feelings", bond.trust), 0.0, 100.0)
	if values.has("familiarity"):
		bond.familiarity = clampf(_number(values, "familiarity", "set_feelings", bond.familiarity), 0.0, 100.0)
	if values.has("baseline"):
		bond.baseline = clampf(_number(values, "baseline", "set_feelings", bond.baseline), -100.0, 100.0)
		bond.anchor = bond.baseline
	_wake(bond)
	if before != [bond.affinity, bond.trust, bond.familiarity, bond.baseline]:
		_changed(bond)
	return bond


## Moves a bond's long-term baseline (where affinity settles over time): positive heals, negative scars. It stays
## within [member RelationshipTuning.baseline_band] of where the bond started. Returns the bond, or null if there
## is no bond.
func shift_baseline(from_id: String, to_id: String, amount: float) -> RelationshipBond:
	var bond := get_bond(from_id, to_id)
	if bond == null:
		push_error("RelationshipWeb.shift_baseline: \"%s\" has no bond with \"%s\"." % [from_id, to_id])
		return null
	if not is_finite(amount):
		push_error("RelationshipWeb.shift_baseline: amount must be a finite number, not %s." % amount)
		return bond
	if _move_baseline(bond, amount):
		_wake(bond)
		_changed(bond)
	return bond


# ------------------------------------------------------------------------------------------ grievances

## [param from_id] now holds something against [param to_id]. [param severity] runs from 1 (a slight) to 5
## (unforgivable); a proud holder ([member RelationshipTuning.proud_threshold]) takes it one step harder. Makes
## an [code]&"acquaintance"[/code] bond first if there is none. [param kind] says what sort of wrong it is (see
## [member RelationshipGrievance.kind]). Returns the grievance, or null if either person isn't in the web.
func open_grievance(from_id: String, to_id: String, severity: int, description: String = "",
		kind: StringName = &"") -> RelationshipGrievance:
	var bond := _ensure_bond(from_id, to_id, "open_grievance")
	if bond == null:
		return null
	if severity < 1 or severity > 5:
		push_warning("RelationshipWeb.open_grievance: severity %d is outside 1..5; using %d." % [severity, clampi(severity, 1, 5)])
	var grievance := RelationshipGrievance.new()
	grievance.id = _next_grievance_id
	_next_grievance_id += 1
	grievance.from_id = from_id
	grievance.to_id = to_id
	var proud := 1 if bond._owner.pride >= tuning.proud_threshold else 0
	grievance.severity = clampi(clampi(severity, 1, 5) + proud, 1, 5)
	grievance.description = description
	grievance.kind = kind
	grievance.opened_day = day
	bond.grievances.append(grievance)
	_grievances[grievance.id] = grievance
	_wake(bond)
	grievance_opened.emit(grievance)
	return grievance


## Makes a grievance one step more severe (up to 5). Returns false if it is already resolved or not in this web.
func escalate(grievance: RelationshipGrievance) -> bool:
	if not _owns(grievance, "escalate"):
		return false
	if grievance.severity < 5:
		grievance.severity += 1
		grievance_changed.emit(grievance)
	return true


## Makes a grievance one step less severe. Softening a severity-1 grievance resolves it ("Softened until nothing
## was left of it"), keeping severity 1. Returns true if this resolved it.
func soften(grievance: RelationshipGrievance) -> bool:
	if not _owns(grievance, "soften"):
		return false
	if grievance.severity <= 1:
		_end_grievance(grievance, "Softened until nothing was left of it", true)
		grievance_resolved.emit(grievance)
		return true
	grievance.severity -= 1
	grievance_changed.emit(grievance)
	return false


## Ends a grievance now, with your own words for how. It leaves its bond. Returns false if it is already resolved
## or not in this web.
func resolve(grievance: RelationshipGrievance, resolution: String = "Resolved") -> bool:
	if not _owns(grievance, "resolve"):
		return false
	_end_grievance(grievance, resolution, true)
	grievance_resolved.emit(grievance)
	return true


## The open or festering grievance with this id, or null.
func get_grievance(id: int) -> RelationshipGrievance:
	return _grievances.get(id, null)


## What [param from_id] holds against [param to_id], oldest first. The array is yours to keep.
func get_grievances(from_id: String, to_id: String) -> Array[RelationshipGrievance]:
	var bond := get_bond(from_id, to_id)
	if bond == null:
		return []
	return bond.grievances.duplicate()


## Every open or festering grievance [param id] holds, against anyone. The array is yours to keep.
func get_grievances_held_by(id: String) -> Array[RelationshipGrievance]:
	var held: Array[RelationshipGrievance] = []
	for bond in get_bonds_from(id):
		held.append_array(bond.grievances)
	return held


## Every open or festering grievance held against [param id], by anyone. The array is yours to keep.
func get_grievances_against(id: String) -> Array[RelationshipGrievance]:
	var against: Array[RelationshipGrievance] = []
	for bond in get_bonds_to(id):
		against.append_array(bond.grievances)
	return against


## The grievances [param from_id] once held against [param to_id] and has since resolved, oldest first: the last
## [member RelationshipTuning.remembered_grievances] of them. Each keeps how and when it ended
## ([member RelationshipGrievance.resolution], [member RelationshipGrievance.resolved_day]). The array is yours to keep.
func get_past_grievances(from_id: String, to_id: String) -> Array[RelationshipGrievance]:
	var past: Array[RelationshipGrievance] = []
	var bond := get_bond(from_id, to_id)
	if bond != null and _past.has(bond):
		past.assign(_past[bond])
	return past


## How tense [param from_id] is about [param to_id]: each grievance adds its severity, more when trust is low
## ([code]× (1 + (100 - trust) / 100)[/code]), and each festering one adds
## [member RelationshipTuning.festering_tension_bonus]. 0 with no grievances or no bond.
func tension(from_id: String, to_id: String) -> float:
	var bond := get_bond(from_id, to_id)
	if bond == null:
		return 0.0
	var bonus := maxf(0.0, _safe(tuning.festering_tension_bonus, 2.0))
	var total := 0.0
	for g in bond.grievances:
		total += g.severity * (1.0 + (100.0 - bond.trust) / 100.0)
		if g.status == RelationshipGrievance.Status.FESTERING:
			total += bonus
	return total


## True if [param from_id] holds an open or festering grievance against [param to_id] and [param to_id] holds none
## back.
func has_one_sided_grudge(from_id: String, to_id: String) -> bool:
	var bond := get_bond(from_id, to_id)
	if bond == null or not bond.has_active_grievance():
		return false
	var back := get_bond(to_id, from_id)
	return back == null or not back.has_active_grievance()


# ------------------------------------------------------------------------------------------ time

## Ends the current day (or [param days] of them) and starts the next. Each bond's affinity drifts toward its
## baseline (slower for loyal people and close bonds); grievances older than
## [member RelationshipTuning.fester_after_days] cost affinity (severe, old ones turn festering and cost double);
## small ones may be let go, leaving a small scar on the baseline; and familiarity fades on bonds without contact
## today. Trust never drifts.[br][br]
## Signals for the day's changes fire after the whole day is worked out, so handlers can change the web freely.
func advance_day(days: int = 1) -> void:
	if days < 1:
		push_error("RelationshipWeb.advance_day: days must be at least 1, not %d." % days)
		return
	for _i: int in days:
		_check_tuning()
		_end_day()
		day += 1
		day_advanced.emit(day)


## The band for an affinity: [constant WARM], [constant NEUTRAL] or [constant COLD].
func band_of(affinity: float) -> StringName:
	var warm := _safe(tuning.warm_at, 35.0)
	var cold := minf(_safe(tuning.cold_at, -15.0), warm)
	if affinity >= warm:
		return WARM
	if affinity <= cold:
		return COLD
	return NEUTRAL


# ------------------------------------------------------------------------------------------ saving

## The whole web as plain data (dictionaries, arrays, strings, numbers and booleans) ready for
## [method JSON.stringify] or [method FileAccess.store_var]. The tuning is not included: it is a resource of yours.
func to_dict() -> Dictionary:
	var people := []
	for person: RelationshipPerson in _people.values():
		people.append({
			"id": person.id, "volatility": person.volatility, "pride": person.pride,
			"forgiveness": person.forgiveness, "loyalty": person.loyalty,
			"attachment": person.get_attachment_name(), "data": person.data.duplicate(true),
		})
	var bonds := []
	for bond in _bond_list():
		var grievances := []
		for g in bond.grievances:
			grievances.append({
				"id": g.id, "severity": g.severity, "status": g.get_status_name(), "description": g.description,
				"kind": String(g.kind),
				"opened_day": g.opened_day, "data": g.data.duplicate(true),
			})
		var row := {
			"from": bond.from_id, "to": bond.to_id, "affinity": bond.affinity, "trust": bond.trust,
			"familiarity": bond.familiarity, "baseline": bond.baseline, "anchor": bond.anchor,
			"floor": bond.familiarity_floor, "kin": bond.kin, "tags": Array(bond.tags), "band": String(bond.band),
			"last_contact_day": bond.last_contact_day, "grievances": grievances,
		}
		if _past.has(bond):
			var past := []
			for g: RelationshipGrievance in _past[bond]:
				past.append({
					"id": g.id, "severity": g.severity, "description": g.description, "kind": String(g.kind),
					"opened_day": g.opened_day,
					"resolved_day": g.resolved_day, "resolution": g.resolution, "data": g.data.duplicate(true),
				})
			row["past"] = past
		bonds.append(row)
	return {
		"format": FORMAT, "random_seed": str(random_seed), "day": day, "next_grievance_id": _next_grievance_id,
		"people": people, "bonds": bonds,
	}


## Replaces the whole web with data from [method to_dict] (copied in: changing [param data] afterwards doesn't touch
## the web). Returns false and changes nothing if the data is broken (each problem is reported as an error). No
## signals fire; the tuning and [member presets] stay as they are.
func from_dict(data: Dictionary) -> bool:
	var loader := _Loader.new()
	var web := loader.build(data)
	if web == null:
		for problem in loader.problems:
			push_error("RelationshipWeb.from_dict: " + problem)
		return false
	random_seed = web.random_seed
	day = web.day
	_people = web._people
	_out = web._out
	_in = web._in
	_grievances = web._grievances
	_past = web._past
	_next_grievance_id = web._next_grievance_id
	_list_dirty = true
	_active = _bond_list().duplicate()
	for bond in _active:
		bond._resting = false
		if bond.band == &"":
			bond.band = band_of(bond.affinity)      # saved without a band: work it out with this web's tuning
	return true


## Saves the web exactly, in Godot's binary format ([method FileAccess.store_var] of [method to_dict]). This is the
## one for game saves: a reloaded web carries on exactly as if it had never stopped. Returns OK or the file error.
func save_binary(path: String) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_var(to_dict())
	return file.get_error()


## Loads a file written by [method save_binary]. Returns OK, the file error, or [constant ERR_INVALID_DATA] (the
## web is then unchanged).
func load_binary(path: String) -> Error:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return FileAccess.get_open_error()
	var stored: Variant = file.get_var()
	if not stored is Dictionary:
		push_error("RelationshipWeb.load_binary: %s doesn't hold a saved web." % path)
		return ERR_INVALID_DATA
	var data: Dictionary = stored
	return OK if from_dict(data) else ERR_INVALID_DATA


## Saves [method to_dict] as readable JSON, for looking at or sharing. Godot's JSON reader can get the last binary
## digit of a number wrong (about 1 number in 12 in Godot 4.7), so a web reloaded from JSON can differ in the 17th
## significant digit; use [method save_binary] for saves that must carry on exactly. Returns OK or the file error.
func save_json(path: String) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(to_dict(), "\t", false, true))
	return file.get_error()


## Loads a file written by [method save_json]. Returns OK, the file error, or [constant ERR_PARSE_ERROR] /
## [constant ERR_INVALID_DATA] (the web is then unchanged).
func load_json(path: String) -> Error:
	if not FileAccess.file_exists(path):
		return ERR_FILE_NOT_FOUND
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		push_error("RelationshipWeb.load_json: %s line %d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return ERR_PARSE_ERROR
	if not json.data is Dictionary:
		push_error("RelationshipWeb.load_json: %s doesn't hold a saved web." % path)
		return ERR_INVALID_DATA
	var data: Dictionary = json.data
	return OK if from_dict(data) else ERR_INVALID_DATA


# ------------------------------------------------------------------------------------------ internals

func _end_day() -> void:
	var decay := clampf(_safe(tuning.decay_rate, 0.03), 0.0, 1.0)
	var fester_after := tuning.fester_after_days
	var fester_rate := maxf(0.0, _safe(tuning.fester_rate, 0.15))
	var festering_after := tuning.festering_after_days
	var festering_min := tuning.festering_min_severity
	var let_go_max := tuning.let_go_max_severity
	var let_go_divisor := _safe(tuning.let_go_divisor, 1500.0)
	var let_go_shift := _safe(tuning.let_go_baseline_shift, -1.0)
	var fade := maxf(0.0, _safe(tuning.familiarity_fade_per_day, 0.4))
	var rest := maxf(0.0, _safe(tuning.rest_epsilon, 0.05))
	# Queuing a signal nobody listens to is most of a big day's cost, so ask once.
	var tell_changed := not bond_changed.get_connections().is_empty()
	var tell_band := not band_changed.get_connections().is_empty()
	var warm := _safe(tuning.warm_at, 35.0)
	var cold := minf(_safe(tuning.cold_at, -15.0), warm)
	var queued: Array[Callable] = []
	var visiting := _active
	_active = []
	for bond in visiting:
		if bond._resting or not bond._in_web:
			continue      # put to rest twice, or removed, since it was queued
		var owner := bond._owner
		var diff := bond.baseline - bond.affinity
		var fading := bond.last_contact_day != day and bond.familiarity > bond.familiarity_floor
		var wounded := not bond.grievances.is_empty()
		# A bond at rest snaps onto its baseline and leaves the list until something touches it: most bonds
		# settle there, so a long run is mostly such bonds and costs almost nothing.
		if not wounded and not fading and absf(diff) < rest:
			bond._resting = true
			if diff != 0.0:
				bond.affinity = bond.baseline
				_settle_band(queued, bond, warm, cold, tell_changed, tell_band)
			continue
		_active.append(bond)
		var affinity_before := bond.affinity
		var familiarity_before := bond.familiarity
		var baseline_before := bond.baseline
		if diff != 0.0:
			bond.affinity += diff * decay * (1.0 - owner.loyalty / 200.0) * (1.0 - bond.familiarity / 200.0)
		if wounded:
			for g: RelationshipGrievance in bond.grievances.duplicate():
				var age := day - g.opened_day
				var festering := g.status == RelationshipGrievance.Status.FESTERING
				if age >= fester_after:
					bond.affinity -= fester_rate * g.severity * (0.5 + owner.pride / 100.0) * (2.0 if festering else 1.0)
				if not festering and age >= festering_after and g.severity >= festering_min:
					g.status = RelationshipGrievance.Status.FESTERING
					queued.append(grievance_changed.emit.bind(g))
				if g.severity <= let_go_max and let_go_divisor > 0.0 \
						and _unit(random_seed, day, g.id) < owner.forgiveness / let_go_divisor * (6 - g.severity) / 5.0:
					_end_grievance(g, "Let it go", true)
					_move_baseline(bond, let_go_shift)
					queued.append(grievance_resolved.emit.bind(g))
		bond.affinity = clampf(bond.affinity, -100.0, 100.0)
		if fading:
			bond.familiarity = maxf(bond.familiarity_floor, bond.familiarity - fade)
		if bond.affinity != affinity_before or bond.familiarity != familiarity_before or bond.baseline != baseline_before:
			_settle_band(queued, bond, warm, cold, tell_changed, tell_band)
	for deferred in queued:
		deferred.call()


## The day's version of _changed(): the band from thresholds worked out once, signals queued only if heard.
func _settle_band(queued: Array[Callable], bond: RelationshipBond, warm: float, cold: float, tell_changed: bool,
		tell_band: bool) -> void:
	var a := bond.affinity
	var new_band := WARM if a >= warm else (COLD if a <= cold else NEUTRAL)
	if tell_changed:
		queued.append(bond_changed.emit.bind(bond.from_id, bond.to_id))
	if new_band != bond.band:
		var old_band := bond.band
		bond.band = new_band
		if tell_band:
			queued.append(band_changed.emit.bind(bond.from_id, bond.to_id, old_band, new_band))


## Puts a bond back on the daily tick's list (anything that changes a bond calls this).
func _wake(bond: RelationshipBond) -> void:
	if bond._resting:
		bond._resting = false
		_active.append(bond)


## Emits bond_changed, then band_changed if the band moved.
func _changed(bond: RelationshipBond) -> void:
	var old_band := bond.band
	bond.band = band_of(bond.affinity)
	bond_changed.emit(bond.from_id, bond.to_id)
	if bond.band != old_band:
		band_changed.emit(bond.from_id, bond.to_id, old_band, bond.band)


func _move_baseline(bond: RelationshipBond, amount: float) -> bool:
	var band := maxf(0.0, _safe(tuning.baseline_band, 30.0))
	var before := bond.baseline
	bond.baseline = clampf(bond.baseline + amount, maxf(-100.0, bond.anchor - band), minf(100.0, bond.anchor + band))
	return bond.baseline != before


func _trust_factor(attachment: RelationshipPerson.Attachment, change: float) -> float:
	match attachment:
		RelationshipPerson.Attachment.AVOIDANT:
			return maxf(0.0, _safe(tuning.avoidant_trust_gain, 0.6)) if change > 0.0 else 1.0
		RelationshipPerson.Attachment.ANXIOUS:
			return maxf(0.0, _safe(tuning.anxious_trust_loss, 1.3)) if change < 0.0 else 1.0
		RelationshipPerson.Attachment.DISORGANIZED:
			if change > 0.0:
				return maxf(0.0, _safe(tuning.disorganized_trust_gain, 0.8))
			return maxf(0.0, _safe(tuning.disorganized_trust_loss, 1.2))
	return 1.0


func _end_grievance(grievance: RelationshipGrievance, resolution: String, remember: bool) -> void:
	grievance.status = RelationshipGrievance.Status.RESOLVED
	grievance.resolved_day = day
	grievance.resolution = resolution
	_grievances.erase(grievance.id)
	var bond := get_bond(grievance.from_id, grievance.to_id)
	if bond == null:
		return
	bond.grievances.erase(grievance)
	var keep := tuning.remembered_grievances
	if not remember or keep <= 0:
		return
	var past: Array = _past.get(bond, [])
	past.append(grievance)
	while past.size() > keep:
		past.pop_front()
	_past[bond] = past


func _owns(grievance: RelationshipGrievance, where: String) -> bool:
	if grievance == null:
		push_error("RelationshipWeb.%s: the grievance is null." % where)
		return false
	if _grievances.get(grievance.id, null) != grievance:
		push_error("RelationshipWeb.%s: grievance %d is resolved or belongs to another web." % [where, grievance.id])
		return false
	return true


func _check_pair(a: String, b: String, where: String) -> bool:
	if a == b:
		push_error("RelationshipWeb.%s: \"%s\" can't have a bond with themselves." % [where, a])
		return false
	var ok := true
	for id: String in [a, b]:
		if not _people.has(id):
			push_error("RelationshipWeb.%s: there is no person \"%s\"." % [where, id])
			ok = false
	return ok


func _ensure_bond(from_id: String, to_id: String, where: String) -> RelationshipBond:
	var bond := get_bond(from_id, to_id)
	if bond != null:
		return bond
	if not _check_pair(from_id, to_id, where):
		return null
	_set_from_preset(from_id, to_id, _resolve_preset(&"acquaintance", where))
	return get_bond(from_id, to_id)


func _set_from_preset(from_id: String, to_id: String, values: Dictionary) -> void:
	var bond := get_bond(from_id, to_id)
	var is_new := bond == null
	if is_new:
		bond = RelationshipBond.new()
		bond.from_id = from_id
		bond.to_id = to_id
		bond._owner = _people[from_id]
	var before := [bond.affinity, bond.trust, bond.familiarity, bond.baseline, bond.anchor, bond.familiarity_floor,
		bond.kin, bond.tags]
	# values come from _resolve_preset, so every key is there with the right type.
	var affinity: float = values.get("affinity", 0.0)
	var trust: float = values.get("trust", 30.0)
	var familiarity: float = values.get("familiarity", 5.0)
	var baseline: float = values.get("baseline", 0.0)
	var familiarity_floor: float = values.get("floor", 0.0)
	var kin: bool = values.get("kin", false)
	bond.affinity = clampf(affinity, -100.0, 100.0)
	bond.trust = clampf(trust, 0.0, 100.0)
	bond.familiarity = clampf(familiarity, 0.0, 100.0)
	bond.baseline = clampf(baseline, -100.0, 100.0)
	bond.anchor = bond.baseline
	bond.familiarity_floor = clampf(familiarity_floor, 0.0, 100.0)
	bond.kin = kin
	bond.tags = _strings(values.get("tags", PackedStringArray()))
	_wake(bond)
	if is_new:
		bond.band = band_of(bond.affinity)
		(_out[from_id] as Dictionary)[to_id] = bond
		(_in[to_id] as Dictionary)[from_id] = bond
		_list_dirty = true
		bond_added.emit(from_id, to_id)
	elif before != [bond.affinity, bond.trust, bond.familiarity, bond.baseline, bond.anchor, bond.familiarity_floor,
			bond.kin, bond.tags]:
		_changed(bond)


func _remove_bond(from_id: String, to_id: String) -> bool:
	var bond := get_bond(from_id, to_id)
	if bond == null:
		return false
	var ended: Array[RelationshipGrievance] = bond.grievances.duplicate()
	for g in ended:
		_end_grievance(g, "Bond removed", false)
	(_out[from_id] as Dictionary).erase(to_id)
	(_in[to_id] as Dictionary).erase(from_id)
	_past.erase(bond)
	bond._in_web = false
	_list_dirty = true
	for g in ended:
		grievance_resolved.emit(g)
	bond_removed.emit(from_id, to_id)
	return true


## Starting values for a preset name or dictionary, on top of the acquaintance preset, every value checked. A named
## preset is checked once and cached until it (or the acquaintance preset) changes: linking a big web calls this
## tens of thousands of times. The values returned are read, never changed.
func _resolve_preset(preset: Variant, where: String) -> Dictionary:
	if not (preset is StringName or preset is String):
		return _resolve_uncached(preset, where)
	var preset_name := StringName(str(preset))
	if not presets.has(preset_name):
		return _resolve_uncached(preset, where)
	var key := [presets.get(&"acquaintance", null), presets[preset_name]].hash()
	var cached: Array = _preset_cache.get(preset_name, [])
	if not cached.is_empty() and cached[0] == key:
		return cached[1]
	var values := _resolve_uncached(preset, where)
	_preset_cache[preset_name] = [key, values]
	return values


func _resolve_uncached(preset: Variant, where: String) -> Dictionary:
	var values: Dictionary = _BASE.duplicate()
	values["tags"] = PackedStringArray()
	_merge_preset(values, presets.get(&"acquaintance", DEFAULT_PRESETS[&"acquaintance"]), where)
	if preset is StringName or preset is String:
		var preset_name := StringName(str(preset))
		if preset_name == &"acquaintance":
			return values
		if not presets.has(preset_name):
			push_error("RelationshipWeb.%s: there is no preset \"%s\" (there are %s); using acquaintance." % [where, preset_name, ", ".join(PackedStringArray(presets.keys()))])
			return values
		_merge_preset(values, presets[preset_name], where)
		return values
	if not preset is Dictionary:
		push_error("RelationshipWeb.%s: a preset is a name or a Dictionary, not %s; using acquaintance." % [where, type_string(typeof(preset))])
		return values
	_merge_preset(values, preset, where)
	return values


func _merge_preset(values: Dictionary, preset: Variant, where: String) -> void:
	if not preset is Dictionary:
		push_error("RelationshipWeb.%s: a preset must be a Dictionary." % where)
		return
	var custom: Dictionary = preset
	_check_keys(custom, _PRESET_KEYS, where)
	for key: String in ["affinity", "trust", "familiarity", "baseline", "floor"]:
		if custom.has(key):
			var fallback: float = values[key]
			values[key] = _number(custom, key, where, fallback)
	if custom.has("kin"):
		if custom["kin"] is bool:
			values["kin"] = custom["kin"]
		else:
			push_error("RelationshipWeb.%s: kin must be true or false." % where)
	if custom.has("tags"):
		var tags: Variant = custom["tags"]
		if tags is PackedStringArray or tags is Array:
			values["tags"] = _strings(tags)
		else:
			push_error("RelationshipWeb.%s: tags must be an Array of Strings." % where)


func _apply_traits(person: RelationshipPerson, traits: Dictionary, where: String) -> void:
	_check_keys(traits, _TRAIT_KEYS, where)
	person.volatility = _number(traits, "volatility", where, person.volatility)
	person.pride = _number(traits, "pride", where, person.pride)
	person.forgiveness = _number(traits, "forgiveness", where, person.forgiveness)
	person.loyalty = _number(traits, "loyalty", where, person.loyalty)
	if traits.has("attachment"):
		var value: Variant = traits["attachment"]
		var style := -1
		if value is String or value is StringName:
			style = RelationshipPerson.attachment_from_name(str(value))
		elif value is int:
			var number: int = value
			if number >= 0 and number <= RelationshipPerson.Attachment.DISORGANIZED:
				style = number
		if style < 0:
			push_error("RelationshipWeb.%s: attachment \"%s\" isn't secure, anxious, avoidant or disorganized; keeping secure." % [where, value])
		else:
			person.attachment = style as RelationshipPerson.Attachment
	if traits.has("data"):
		if traits["data"] is Dictionary:
			var data: Dictionary = traits["data"]
			person.data = data.duplicate(true)
		else:
			push_error("RelationshipWeb.%s: data must be a Dictionary." % where)


func _check_keys(values: Dictionary, allowed: PackedStringArray, where: String) -> void:
	for key: Variant in values:
		if not (key is String or key is StringName) or not allowed.has(str(key)):
			push_warning("RelationshipWeb.%s: ignoring \"%s\" (expected %s)." % [where, key, ", ".join(allowed)])


func _number(values: Dictionary, key: String, where: String, fallback: float = 0.0) -> float:
	if not values.has(key):
		return fallback
	var value: Variant = values[key]
	if value is int or value is float:
		var number: float = value
		if is_finite(number):
			return number
	push_error("RelationshipWeb.%s: %s must be a finite number, not %s." % [where, key, value])
	return fallback


func _check_tuning() -> void:
	var problems := tuning.get_problems()
	var key := "\n".join(problems)
	if key == _reported_problems:
		return
	_reported_problems = key
	for problem in problems:
		push_warning("RelationshipWeb: tuning: " + problem)


func _bond_list() -> Array[RelationshipBond]:
	if _list_dirty:
		_list.clear()
		for from_id: String in _out:
			_list.append_array((_out[from_id] as Dictionary).values())
		_list_dirty = false
	return _list


## Any Array or PackedStringArray as a PackedStringArray of its items as text.
static func _strings(value: Variant) -> PackedStringArray:
	if value is PackedStringArray:
		return value
	var out := PackedStringArray()
	if value is Array:
		var items: Array = value
		for item: Variant in items:
			out.append(str(item))
	return out


static func _safe(value: float, fallback: float) -> float:
	return value if is_finite(value) else fallback


## A number in [0, 1) from the seed, the day and a grievance id, the same on every machine and Godot version
## (MurmurHash3's finalizer on 32-bit words; no engine RNG, whose algorithm could change).
static func _unit(seed_value: int, on_day: int, grievance_id: int) -> float:
	var h := _mix(0x9747B28C, seed_value)
	h = _mix(h, seed_value >> 32)
	h = _mix(h, on_day)
	h = _mix(h, grievance_id)
	return h / 4294967296.0


static func _mix(h: int, value: int) -> int:
	h = (h ^ (value & 0xFFFFFFFF)) & 0xFFFFFFFF
	h = _mul32(h ^ (h >> 16), 0x85EBCA6B)
	h = _mul32(h ^ (h >> 13), 0xC2B2AE35)
	return (h ^ (h >> 16)) & 0xFFFFFFFF


## (a × b) mod 2³² without 64-bit overflow.
static func _mul32(a: int, b: int) -> int:
	return ((a * (b & 0xFFFF)) + (((a * (b >> 16)) & 0xFFFF) << 16)) & 0xFFFFFFFF


## Builds a web from saved data, collecting every problem instead of stopping at the first.
class _Loader:
	var problems := PackedStringArray()
	# The bond being read, for messages. Messages are only built when there is a problem: formatting a context
	# string for every bond was a large share of loading a big web.
	var _from := ""
	var _to := ""
	var _ids := {}        # every grievance id seen, open or remembered

	func build(data: Dictionary) -> RelationshipWeb:
		if int(_num(data.get("format", -1))) != FORMAT:
			problems.append("format is %s; this version reads format %d." % [data.get("format", "missing"), FORMAT])
			return null
		var web := RelationshipWeb.new()
		var seed_text := str(data.get("random_seed", "0"))
		if not seed_text.is_valid_int():
			problems.append("random_seed \"%s\" isn't a whole number." % seed_text)
		web.random_seed = seed_text.to_int()
		web.day = _int(data, "day", 0, "the save")
		web._next_grievance_id = _int(data, "next_grievance_id", 1, "the save")
		var people_ok := problems.size()
		for row: Variant in _array(data, "people"):
			_person(web, row)
		if problems.size() > people_ok:
			return null      # every bond would also fail; the people problem is the one worth reading
		for row: Variant in _array(data, "bonds"):
			_bond(web, row)
		if web._next_grievance_id <= _largest_grievance():
			problems.append("next_grievance_id %d isn't above every grievance id." % web._next_grievance_id)
		return web if problems.is_empty() else null

	func _person(web: RelationshipWeb, row: Variant) -> void:
		if not row is Dictionary:
			problems.append("a person isn't a Dictionary.")
			return
		var d: Dictionary = row
		var id := str(d.get("id", ""))
		if id.is_empty() or web._people.has(id):
			problems.append("person id \"%s\" is empty or repeated." % id)
			return
		var person := RelationshipPerson.new()
		person.id = id
		person.volatility = _float(d, "volatility", 50.0, "person %s" % id)
		person.pride = _float(d, "pride", 50.0, "person %s" % id)
		person.forgiveness = _float(d, "forgiveness", 50.0, "person %s" % id)
		person.loyalty = _float(d, "loyalty", 50.0, "person %s" % id)
		var style := RelationshipPerson.attachment_from_name(str(d.get("attachment", "secure")))
		if style < 0:
			problems.append("person %s has attachment \"%s\"." % [id, d.get("attachment")])
		else:
			person.attachment = style as RelationshipPerson.Attachment
		person.data = _dict(d, "data").duplicate(true)
		web._people[id] = person
		web._out[id] = {}
		web._in[id] = {}

	func _bond(web: RelationshipWeb, row: Variant) -> void:
		if not row is Dictionary:
			problems.append("a bond isn't a Dictionary.")
			return
		var d: Dictionary = row
		var from_id := str(d.get("from", ""))
		var to_id := str(d.get("to", ""))
		_from = from_id
		_to = to_id
		var where := ""       # "" means the current bond; see _here()
		if not web._people.has(from_id) or not web._people.has(to_id) or from_id == to_id:
			problems.append("%s names someone not in the web, or the same person twice." % _here(where))
			return
		if (web._out[from_id] as Dictionary).has(to_id):
			problems.append("%s appears twice." % _here(where))
			return
		var bond := RelationshipBond.new()
		bond.from_id = from_id
		bond.to_id = to_id
		bond._owner = web._people[from_id]
		bond.affinity = clampf(_float(d, "affinity", 0.0, where), -100.0, 100.0)
		bond.trust = clampf(_float(d, "trust", 30.0, where), 0.0, 100.0)
		bond.familiarity = clampf(_float(d, "familiarity", 5.0, where), 0.0, 100.0)
		bond.baseline = clampf(_float(d, "baseline", 0.0, where), -100.0, 100.0)
		bond.anchor = clampf(_float(d, "anchor", bond.baseline, where), -100.0, 100.0)
		bond.familiarity_floor = clampf(_float(d, "floor", 0.0, where), 0.0, 100.0)
		var kin: Variant = d.get("kin", false)
		if not kin is bool:
			problems.append("%s: kin isn't true or false." % _here(where))
		bond.kin = kin == true
		bond.tags = RelationshipWeb._strings(d.get("tags", []))
		var band: Variant = d.get("band", null)
		bond.band = &"" if band == null else StringName(str(band))     # from_dict works out a missing band
		if band != null and not _BANDS.has(bond.band):
			problems.append("%s has band \"%s\"." % [_here(where), bond.band])
		bond.last_contact_day = _int(d, "last_contact_day", -1, where)
		for g_row: Variant in _array(d, "grievances"):
			_grievance(web, bond, g_row, where)
		if d.has("past"):
			var past := []
			for p_row: Variant in _array(d, "past"):
				var old := _past_grievance(bond, p_row)
				if old != null:
					past.append(old)
			if not past.is_empty():
				web._past[bond] = past
		(web._out[from_id] as Dictionary)[to_id] = bond
		(web._in[to_id] as Dictionary)[from_id] = bond
		web._list_dirty = true

	func _grievance(web: RelationshipWeb, bond: RelationshipBond, row: Variant, where: String) -> void:
		if not row is Dictionary:
			problems.append("a grievance on %s isn't a Dictionary." % _here(where))
			return
		var d: Dictionary = row
		var g := RelationshipGrievance.new()
		g.id = _int(d, "id", 0, _here(where) + " grievance id")
		if g.id < 1 or _ids.has(g.id):
			problems.append("grievance id %d on %s is missing or repeated." % [g.id, _here(where)])
			return
		g.from_id = bond.from_id
		g.to_id = bond.to_id
		g.severity = _int(d, "severity", 1, _here(where) + " severity")
		if g.severity < 1 or g.severity > 5:
			problems.append("grievance %d has severity %d." % [g.id, g.severity])
		var status := RelationshipGrievance.status_from_name(str(d.get("status", "open")))
		if status < 0 or status == RelationshipGrievance.Status.RESOLVED:
			problems.append("grievance %d has status \"%s\"; only open and festering are saved." % [g.id, d.get("status")])
			return
		g.status = status as RelationshipGrievance.Status
		g.description = str(d.get("description", ""))
		g.kind = StringName(str(d.get("kind", "")))
		g.opened_day = _int(d, "opened_day", 0, _here(where) + " opened_day")
		g.data = _dict(d, "data").duplicate(true)
		bond.grievances.append(g)
		web._grievances[g.id] = g
		_ids[g.id] = true

	func _past_grievance(bond: RelationshipBond, row: Variant) -> RelationshipGrievance:
		if not row is Dictionary:
			problems.append("a remembered grievance on %s isn't a Dictionary." % _here(""))
			return null
		var d: Dictionary = row
		var g := RelationshipGrievance.new()
		g.id = _int(d, "id", 0, _here("") + " remembered grievance id")
		if g.id < 1 or _ids.has(g.id):
			problems.append("remembered grievance id %d on %s is missing or repeated." % [g.id, _here("")])
			return null
		_ids[g.id] = true
		g.from_id = bond.from_id
		g.to_id = bond.to_id
		g.status = RelationshipGrievance.Status.RESOLVED
		g.severity = _int(d, "severity", 1, _here("") + " severity")
		if g.severity < 1 or g.severity > 5:
			problems.append("remembered grievance %d has severity %d." % [g.id, g.severity])
		g.description = str(d.get("description", ""))
		g.kind = StringName(str(d.get("kind", "")))
		g.opened_day = _int(d, "opened_day", 0, _here("") + " opened_day")
		g.resolved_day = _int(d, "resolved_day", 0, _here("") + " resolved_day")
		g.resolution = str(d.get("resolution", ""))
		g.data = _dict(d, "data").duplicate(true)
		return g

	func _here(where: String) -> String:
		return where if not where.is_empty() else "bond %s→%s" % [_from, _to]

	func _largest_grievance() -> int:
		var largest := 0
		for id: int in _ids:
			largest = maxi(largest, id)
		return largest

	func _dict(d: Dictionary, key: String) -> Dictionary:
		var value: Variant = d.get(key, {})
		if value is Dictionary:
			return value
		problems.append("%s isn't a Dictionary." % key)
		return {}

	func _array(d: Dictionary, key: String) -> Array:
		var value: Variant = d.get(key, [])
		if value is Array:
			return value
		problems.append("%s isn't an Array." % key)
		return []

	func _float(d: Dictionary, key: String, fallback: float, where: String) -> float:
		var raw: Variant = d.get(key, null)
		if raw == null:
			return fallback
		if raw is float:
			var quick: float = raw
			if is_finite(quick):
				return quick
		var value := _num(raw)
		if is_nan(value):
			problems.append("%s: %s isn't a number." % [_here(where), key])
			return fallback
		return value

	func _int(d: Dictionary, key: String, fallback: int, where: String) -> int:
		var raw: Variant = d.get(key, null)
		if raw == null:
			return fallback
		if raw is int:
			return raw
		var value := _num(raw)
		if is_nan(value) or value != floorf(value):
			problems.append("%s: %s isn't a whole number." % [_here(where), key])
			return fallback
		return int(value)

	func _num(value: Variant) -> float:
		if value is int or value is float:
			var number: float = value
			if is_finite(number):
				return number
		return NAN
