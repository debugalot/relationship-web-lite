@icon("res://addons/relationship_web/icon.svg")
class_name RelationshipPerson
extends RefCounted
## One person in a [RelationshipWeb]: an id and the personality traits the maths reads.
##
## Get people from [method RelationshipWeb.add_person] or [method RelationshipWeb.get_person]; don't create them
## yourself. Traits are clamped to 0..100 when set. Changing a trait affects every later calculation.

## How a person forms trust. See [member attachment].
enum Attachment {
	SECURE, ## Trust moves exactly as events say.
	ANXIOUS, ## Feels trust losses harder ([member RelationshipTuning.anxious_trust_loss]).
	AVOIDANT, ## Banks trust gains slowly ([member RelationshipTuning.avoidant_trust_gain]).
	DISORGANIZED, ## Both: smaller gains, harder losses.
}

const _ATTACHMENT_NAMES: PackedStringArray = ["secure", "anxious", "avoidant", "disorganized"]

## The person's id in the web. It can't change once the person is in a web.
var id: String:
	set(value):
		if not id.is_empty() and value != id:
			push_error("RelationshipPerson: an id can't change once set (\"%s\")." % id)
			return
		id = value
## How hard changes in affinity land: 0 is calm, 100 volatile. See [member RelationshipTuning.volatility_base].
var volatility := 50.0:
	set(value):
		volatility = _trait("volatility", value, volatility)
## Proud people open grievances one step more severe and stew on them harder.
var pride := 50.0:
	set(value):
		pride = _trait("pride", value, pride)
## Forgiving people let small grievances go sooner. See [member RelationshipTuning.let_go_divisor].
var forgiveness := 50.0:
	set(value):
		forgiveness = _trait("forgiveness", value, forgiveness)
## Loyal people hold their feelings longer: affinity drifts back toward its baseline more slowly.
var loyalty := 50.0:
	set(value):
		loyalty = _trait("loyalty", value, loyalty)
## How this person forms trust.
var attachment := Attachment.SECURE
## Anything of yours to keep with the person, saved by [method RelationshipWeb.to_dict]. Keep it to values JSON
## can hold (strings, numbers, booleans, arrays and dictionaries) if you save to JSON.
var data := {}


## The attachment style as a lowercase word ("secure", "anxious", "avoidant" or "disorganized").
func get_attachment_name() -> String:
	return _ATTACHMENT_NAMES[attachment]


## The attachment style for a word ("secure", "anxious", "avoidant" or "disorganized", any case). Returns -1
## for anything else.
static func attachment_from_name(word: String) -> int:
	return _ATTACHMENT_NAMES.find(word.strip_edges().to_lower())


func _trait(trait_name: String, value: float, current: float) -> float:
	if not is_finite(value):
		push_error("RelationshipPerson \"%s\": %s must be a finite number, not %s." % [id, trait_name, value])
		return current
	return clampf(value, 0.0, 100.0)
