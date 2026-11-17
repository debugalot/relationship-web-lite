@tool
@icon("res://addons/relationship_web/icon.svg")
class_name RelationshipTuning
extends Resource
## Every number the Relationship Web maths uses, in one resource you can edit in the Inspector and save as a
## [code].tres[/code] file. The defaults are the values the model was tuned with.
##
## Values set from code are not range-checked by the Inspector, so [RelationshipWeb] calls [method get_problems]
## and reports each problem once as a warning. The maths also guards itself: a bad value never turns a kind act
## into a hurtful one or pushes a feeling past its limits.

@export_group("Affinity")
## The part of every affinity change everyone feels. A person's volatility adds
## [code]volatility / volatility_divisor[/code] on top, so with the defaults a calm person (volatility 0) feels a
## change at 0.6× and a volatile one (100) at 1.4×.
@export_range(0.0, 5.0, 0.01) var volatility_base := 0.6
## See [member volatility_base]. Larger values make volatility matter less.
@export_range(1.0, 1000.0, 1.0) var volatility_divisor := 125.0
## Feelings get harder to push further the stronger they already are. A gain at affinity [code]a[/code] keeps
## [code]1 - a / saturation_divisor[/code] of its size, and a loss near −100 likewise: with the default, a gain at
## +100 keeps 20%. Must be at least 100, or gains near the top would turn into losses; lower values are treated
## as 100.
@export_range(100.0, 1000.0, 1.0) var saturation_divisor := 125.0
## Familiarity every contact adds on its own, on top of any familiarity change in the event.
@export_range(0.0, 100.0, 0.1) var contact_familiarity := 2.0

@export_group("Trust")
## How much of a trust gain an avoidant person banks (they open up slowly).
@export_range(0.0, 5.0, 0.01) var avoidant_trust_gain := 0.6
## How much harder an anxious person feels a trust loss.
@export_range(0.0, 5.0, 0.01) var anxious_trust_loss := 1.3
## How much of a trust gain a disorganized person banks.
@export_range(0.0, 5.0, 0.01) var disorganized_trust_gain := 0.8
## How much harder a disorganized person feels a trust loss.
@export_range(0.0, 5.0, 0.01) var disorganized_trust_loss := 1.2

@export_group("Grievances")
## People with at least this much pride open every grievance one step more severe (up to 5).
@export_range(0, 101) var proud_threshold := 70
## A grievance older than this many days starts eating into affinity every day.
@export_range(0, 3650) var fester_after_days := 3
## Affinity a grievance costs per day once it is old enough, per point of severity, before pride
## ([code]× (0.5 + pride / 100)[/code]). A festering grievance costs twice as much.
@export_range(0.0, 10.0, 0.01) var fester_rate := 0.15
## An open grievance of at least [member festering_min_severity] turns festering after this many days.
@export_range(0, 3650) var festering_after_days := 10
## The least severity a grievance needs to turn festering.
@export_range(1, 5) var festering_min_severity := 3
## Grievances up to this severity can be let go on their own (0 turns letting go off).
@export_range(0, 5) var let_go_max_severity := 2
## The daily chance of letting a small grievance go is
## [code]forgiveness / let_go_divisor × (6 - severity) / 5[/code]: with the defaults, a forgiving person (100) lets a
## severity-1 grievance go about once a fortnight. Larger values make letting go rarer.
@export_range(1.0, 100000.0, 1.0) var let_go_divisor := 1500.0
## How much a let-go grievance moves the bond's long-term baseline. Negative means it leaves a small scar.
@export_range(-100.0, 100.0, 0.5) var let_go_baseline_shift := -1.0
## Extra tension each festering grievance adds in [method RelationshipWeb.tension].
@export_range(0.0, 100.0, 0.1) var festering_tension_bonus := 2.0
## How many resolved grievances each bond remembers ([method RelationshipWeb.get_past_grievances]); the oldest are
## forgotten first. 0 forgets them at once. Only bonds with history use memory for it.
@export_range(0, 100) var remembered_grievances := 5

@export_group("Daily drift")
## How far a bond's long-term baseline can move from where it started ([member RelationshipBond.anchor]),
## either way. Healing and scarring happen within this band.
@export_range(0.0, 200.0, 0.5) var baseline_band := 30.0
## Share of the gap between affinity and its baseline that closes each day, before loyalty and familiarity
## slow it ([code]× (1 - loyalty / 200) × (1 - familiarity / 200)[/code]).
@export_range(0.0, 1.0, 0.001) var decay_rate := 0.03
## Familiarity lost on each day without contact, down to the bond's floor.
@export_range(0.0, 100.0, 0.01) var familiarity_fade_per_day := 0.4
## A bond this close to its baseline, with no grievances and nothing left to fade, snaps onto the baseline and
## rests. Resting bonds cost almost nothing on [method RelationshipWeb.advance_day].
@export_range(0.0, 10.0, 0.001) var rest_epsilon := 0.05

@export_group("Bands")
## Affinity at or above this is [code]&"warm"[/code].
@export_range(-100.0, 100.0, 0.5) var warm_at := 35.0
## Affinity at or below this is [code]&"cold"[/code]. Must be below [member warm_at].
@export_range(-100.0, 100.0, 0.5) var cold_at := -15.0


## Every problem with the current values, in plain words. Empty when all is well.
func get_problems() -> PackedStringArray:
	var problems := PackedStringArray()
	var finite := {
		"volatility_base": volatility_base, "volatility_divisor": volatility_divisor,
		"saturation_divisor": saturation_divisor, "contact_familiarity": contact_familiarity,
		"avoidant_trust_gain": avoidant_trust_gain, "anxious_trust_loss": anxious_trust_loss,
		"disorganized_trust_gain": disorganized_trust_gain, "disorganized_trust_loss": disorganized_trust_loss,
		"fester_rate": fester_rate, "let_go_divisor": let_go_divisor, "let_go_baseline_shift": let_go_baseline_shift,
		"festering_tension_bonus": festering_tension_bonus, "baseline_band": baseline_band, "decay_rate": decay_rate,
		"familiarity_fade_per_day": familiarity_fade_per_day, "rest_epsilon": rest_epsilon,
		"warm_at": warm_at, "cold_at": cold_at,
	}
	for key: String in finite:
		var value: float = finite[key]
		if not is_finite(value):
			problems.append("%s is %s; it must be a finite number." % [key, finite[key]])
	if not problems.is_empty():
		return problems
	for key: String in ["volatility_base", "contact_familiarity", "avoidant_trust_gain", "anxious_trust_loss",
			"disorganized_trust_gain", "disorganized_trust_loss", "fester_rate", "festering_tension_bonus",
			"baseline_band", "familiarity_fade_per_day", "rest_epsilon"]:
		var value: float = finite[key]
		if value < 0.0:
			problems.append("%s is %s; it can't be negative." % [key, finite[key]])
	if volatility_divisor <= 0.0:
		problems.append("volatility_divisor is %s; it must be above 0 (volatility is ignored)." % volatility_divisor)
	if saturation_divisor < 100.0:
		problems.append("saturation_divisor is %s; below 100, gains near the top would turn into losses, so 100 is used." % saturation_divisor)
	if let_go_divisor <= 0.0:
		problems.append("let_go_divisor is %s; it must be above 0 (letting go is turned off)." % let_go_divisor)
	if decay_rate > 1.0:
		problems.append("decay_rate is %s; above 1 affinity would overshoot its baseline, so 1 is used." % decay_rate)
	if fester_after_days < 0 or festering_after_days < 0:
		problems.append("fester_after_days and festering_after_days can't be negative.")
	if festering_min_severity < 1 or festering_min_severity > 5:
		problems.append("festering_min_severity is %d; it must be 1 to 5." % festering_min_severity)
	if remembered_grievances < 0:
		problems.append("remembered_grievances is %d; it can't be negative (nothing is remembered)." % remembered_grievances)
	if let_go_max_severity < 0 or let_go_max_severity > 5:
		problems.append("let_go_max_severity is %d; it must be 0 to 5." % let_go_max_severity)
	if cold_at >= warm_at:
		problems.append("cold_at (%s) must be below warm_at (%s)." % [cold_at, warm_at])
	return problems
