@icon("res://addons/relationship_web/icon.svg")
class_name RelationshipBond
extends RefCounted
## How one person feels about another, in one direction: [member from_id]'s feelings about [member to_id].
## The other direction is a separate bond, so feelings can be lopsided.
##
## Read bonds freely. Change them through [RelationshipWeb] ([method RelationshipWeb.apply],
## [method RelationshipWeb.set_feelings], [method RelationshipWeb.shift_baseline] and the grievance methods):
## those keep every value in range, update [member band], emit the web's signals and wake a bond that had come to
## rest. Writing the fields directly skips all of that.

## Whose feelings these are.
var from_id: String
## Who they are about.
var to_id: String
## How much [member from_id] likes [member to_id], −100 to 100.
var affinity := 0.0
## How much [member from_id] trusts [member to_id], 0 to 100. Only events move trust; it never drifts.
var trust := 30.0
## How well [member from_id] knows [member to_id], 0 to 100. Contact raises it; days without contact fade it
## down to [member familiarity_floor].
var familiarity := 5.0
## Where affinity settles over time: the long-term memory of the bond. Events don't move it;
## [method RelationshipWeb.shift_baseline] and letting grievances go do, within
## [member RelationshipTuning.baseline_band] of [member anchor].
var baseline := 0.0
## The baseline the bond started with. [member baseline] can only move so far from it.
var anchor := 0.0
## Familiarity never fades below this (family and partners don't become strangers).
var familiarity_floor := 0.0
## Family. Your own flag: the maths treats it like any other bond, and the web view draws family closer.
var kin := false
## Labels of your own ("mentor", "crush", "debt"...). Saved with the bond.
var tags := PackedStringArray()
## The affinity band this bond is in: [code]&"warm"[/code], [code]&"neutral"[/code] or [code]&"cold"[/code]
## (see [member RelationshipTuning.warm_at]). [signal RelationshipWeb.band_changed] fires when it changes.
var band := &"neutral"
## The last day these two were in contact, or −1. No contact on a day lets familiarity fade at the end of it.
var last_contact_day := -1
## Open and festering grievances, oldest first. Resolved ones leave the list.
var grievances: Array[RelationshipGrievance] = []

var _owner: RelationshipPerson
var _resting := true          # off the daily tick's list (new bonds join it when the web wakes them)
var _in_web := true


## The person whose feelings these are (the [RelationshipPerson] for [member from_id]).
func get_owner_person() -> RelationshipPerson:
	return _owner


## True while the bond is at rest: on its baseline, with no grievances and nothing left to fade.
## [method RelationshipWeb.advance_day] skips resting bonds, and anything that changes the bond wakes it.
func is_at_rest() -> bool:
	return _resting


## False once the bond has been removed from its web ([method RelationshipWeb.unlink], or one of its people left).
func is_in_web() -> bool:
	return _in_web


## True if any grievance is still open or festering.
func has_active_grievance() -> bool:
	return not grievances.is_empty()


## The most severe grievance (the oldest of equals), or null.
func worst_grievance() -> RelationshipGrievance:
	var worst: RelationshipGrievance = null
	for g in grievances:
		if worst == null or g.severity > worst.severity:
			worst = g
	return worst


## How many grievances are festering.
func festering_count() -> int:
	var n := 0
	for g in grievances:
		if g.status == RelationshipGrievance.Status.FESTERING:
			n += 1
	return n
