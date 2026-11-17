@icon("res://addons/relationship_web/icon.svg")
class_name RelationshipGrievance
extends RefCounted
## A wound on one bond: something [member from_id] holds against [member to_id].
##
## Open one with [method RelationshipWeb.open_grievance]. While it lasts, an old grievance eats into affinity
## every day, a severe one turns festering and eats twice as fast, and a small one may be let go. Change it
## through the web ([method RelationshipWeb.escalate], [method RelationshipWeb.soften],
## [method RelationshipWeb.resolve]), which keeps the bond and the signals right.

## Where a grievance is in its life.
enum Status {
	OPEN, ## Fresh. Costs affinity daily once older than [member RelationshipTuning.fester_after_days].
	FESTERING, ## Old and severe: costs twice as much affinity and adds to tension.
	RESOLVED, ## Over. It has left the bond's open grievances; the bond remembers its last few
	## ([method RelationshipWeb.get_past_grievances]).
}

const _STATUS_NAMES: PackedStringArray = ["open", "festering", "resolved"]
## Unique within its web, counting up from 1.
var id := 0
## Who holds the grievance.
var from_id: String
## Who it is held against.
var to_id: String
## 1 (a slight) to 5 (unforgivable). A resolved grievance keeps the severity it had when it ended.
var severity := 1
## Where it is in its life.
var status := Status.OPEN
## Your words for what happened. Saved with it.
var description := ""
## What sort of wrong it is: [code]&""[/code] for anything, or a word of your own. Saved with it; the maths
## treats every kind the same.
var kind := &""
## The day it was opened.
var opened_day := 0
## The day it was resolved, or −1.
var resolved_day := -1
## How it ended ("Let it go", "Softened until nothing was left of it", or what you passed to
## [method RelationshipWeb.resolve]).
var resolution := ""
## Anything of yours to keep with it (JSON-safe values if you save to JSON).
var data := {}


## True while it is open or festering.
func is_active() -> bool:
	return status != Status.RESOLVED


## The status as a lowercase word ("open", "festering" or "resolved").
func get_status_name() -> String:
	return _STATUS_NAMES[status]


## The status for a word ("open", "festering" or "resolved", any case). Returns -1 for anything else.
static func status_from_name(word: String) -> int:
	return _STATUS_NAMES.find(word.strip_edges().to_lower())
