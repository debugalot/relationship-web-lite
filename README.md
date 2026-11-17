# Relationship Web Lite for Godot

[![ExcaliBug](https://img.shields.io/badge/Website-ExcaliBug.com-F4B544?style=flat-square)](https://excalibug.com/addons/relationship-web/)
[![Godot 4.7](https://img.shields.io/badge/Godot-4.7-478CBF?style=flat-square&logo=godotengine&logoColor=white)](https://godotengine.org)
[![Relationship Web](https://img.shields.io/badge/itch.io-Relationship%20Web%20(full)-FA5C5C?style=flat-square&logo=itch.io&logoColor=white)](https://debugalot.itch.io/relationship-web)
[![Ko-fi](https://img.shields.io/badge/Ko--fi-Support-FF5E5B?style=flat-square&logo=kofi&logoColor=white)](https://ko-fi.com/debugalot)
[![License: free](https://img.shields.io/badge/License-Free%2C%20commercial%20OK-43D1C6?style=flat-square)](LICENSE)

Who feels what about whom. Every pair of characters has feelings each way (affinity, trust and how
well they know each other), personalities that shape how those feelings move, grudges that fester
and get forgiven, and days that pass between events. A web view draws it. Pure GDScript, nothing to
enable. This is the free edition of **[Relationship Web](https://debugalot.itch.io/relationship-web)**,
with the same API.

```gdscript
var web := RelationshipWeb.new()
web.add_person("ana", {"volatility": 70, "attachment": "anxious", "data": {"name": "Ana"}})
web.add_person("bo", {"data": {"name": "Bo"}})
web.link("ana", "bo", &"friend")
web.apply("ana", "bo", {"affinity": 10, "trust": 5})      # Bo helped Ana
web.open_grievance("bo", "ana", 2, "She told everyone about the debt.")
web.advance_day()

var view := RelationshipWebView.new()
view.set_anchors_preset(Control.PRESET_FULL_RECT)
add_child(view)
view.web = web
```

- **Feelings each way.** How Ana feels about Bo and how Bo feels about Ana are separate, so trust and
  grudges can be one-sided.
- **Personality does the maths.** Volatile people swing harder, proud people hold grudges harder,
  forgiving people let them go, loyal people's feelings last, and attachment style changes how trust
  is won and lost.
- **Time.** Between events feelings drift back toward a long-term baseline, grudges eat at affinity
  and fester, small ones are let go, and familiarity fades without contact.
- **Deterministic.** The same seed and the same calls give the same web on every machine, and a web
  saved and loaded carries on exactly.
- **The web view.** Lines that fade from one side's feeling into the other's, embers for grudges,
  people sized by how strongly they're felt about, names that never overlap, filters, pan and zoom.

## Lite or Relationship Web?

| | Relationship Web Lite (free) | [Relationship Web](https://debugalot.itch.io/relationship-web) ($5) |
|---|---|---|
| People, personalities, feelings each way, presets, events | Yes | Yes |
| Grudges that fester and get let go; days passing; saves | Yes | Yes |
| The web view | Yes, with the Lite mark | Yes, no mark |
| Your own look (colours, fonts, palette), glowing lines, flowing dots | | Yes |
| Romance and attraction; crushes; asking out, with a chance of a no | | Yes |
| Couples, marriage, break-ups, divorce, affairs, infidelity | | Yes |
| Jealousy: rivals, guarding a partner, insecurity | | Yes |
| Family roles, pregnancy (in and out of wedlock), births, death, abandonment, adoption | | Yes |
| Gender and who each person can be drawn to | | Yes |
| The relationship list, the family tree, the ready-made screen | | Yes |
| A playable demo village with every life event | | Yes |

**The Lite mark:** the web view draws a large, faint knight across the middle and "Relationship Web
Lite" in the corner. The data, the maths and the saves carry no mark.

**Upgrading** is replacing `addons/relationship_web/` with the full version's folder: code written
for Lite keeps working, and saves made with Lite load in the full version. `tools/check_upgrade.py`
proves it by running this repository's tests and demo on the full version. Don't then update Lite
from the Asset Library, which would put Lite back.

## Requirements

Godot 4.7, tested on 4.7.2. Pure GDScript.

## Install

From the editor's **AssetLib** tab, search for *Relationship Web Lite*. Or copy
`addons/relationship_web/` into your project's `addons/` folder. There is no plugin to enable:
`RelationshipWeb` and `RelationshipWebView` are available everywhere.

## People

`add_person(id, traits)`. Traits, 0 to 100: `volatility` (how hard changes in affinity land),
`pride` (grudges open a step harder and stew longer), `forgiveness` (small grudges get let go
sooner), `loyalty` (feelings drift back more slowly), plus `attachment` (`"secure"`, `"anxious"`,
`"avoidant"` or `"disorganized"`: how trust is won and lost) and `data` (a dictionary of your own;
`name` and `group` are what the view reads). `get_person(id)`, `remove_person(id)`.

## Bonds

A bond is one direction: `get_bond("ana", "bo")` is how Ana feels about Bo. Fields: `affinity`
(−100 to 100), `trust` and `familiarity` (0 to 100), `baseline` (where affinity settles over time),
`familiarity_floor`, `kin`, `tags`, `band` (`&"warm"`, `&"neutral"` or `&"cold"`), `grievances`.

`link(a, b, preset, reverse)` makes a bond each way; `link_one_way(from, to, preset)` makes one.
Presets: `stranger`, `acquaintance`, `friend`, `ally`, `rival`, `enemy`, `partner`, `family`, or a
dictionary of starting values (`affinity`, `trust`, `familiarity`, `baseline`, `floor`, `kin`,
`tags`). Add your own in `web.presets`.

## Events and grudges

| | |
|---|---|
| `apply(from, to, changes, contact := true)` | Something happened: amounts to add to `affinity`, `trust`, `familiarity`. Personality shapes them. |
| `interact(a, b, a_changes, b_changes := null)` | `apply` both ways. |
| `set_feelings(from, to, values)` | Set values outright. |
| `shift_baseline(from, to, amount)` | Heal or scar the long-term baseline. |
| `open_grievance(from, to, severity 1–5, description)` | A grudge. `escalate`, `soften`, `resolve`. |
| `get_grievances`, `get_grievances_held_by`, `get_grievances_against`, `get_past_grievances`, `tension` | |

## Days

`advance_day(days := 1)`: affinity drifts toward its baseline, grudges cost affinity and may fester
or be let go, familiarity fades without contact. Trust moves only when something happens. Bonds with
nothing left to do rest, so a web of thousands costs almost nothing on a quiet day. Signals:
`person_added`, `person_removed`, `bond_added`, `bond_removed`, `bond_changed`, `band_changed`,
`grievance_opened`, `grievance_changed`, `grievance_resolved`, `day_advanced`.

## Saving

`save_binary(path)` / `load_binary(path)`: exact, a reloaded web carries on bit for bit.
`save_json` / `load_json` for files people read. `to_dict()` / `from_dict(data)` underneath.

## Tuning

Every number lives in a `RelationshipTuning` resource (`web.tuning`), with Inspector ranges and a doc
on each. `tuning.get_problems()` lists anything out of range in plain words.

## The web view

`RelationshipWebView` draws one curve per pair, fading from one side's feeling into the other's
(cold coral, neutral grey, warm teal), thicker the better they know each other, broken where trust is
low, with a gold ember at the grudge-holder's end. Drag to pan (or drag a person to pin them), scroll
to zoom, click a person or a line, Shift-click a second person for the pair, Escape, F to fit.
Filters: `min_affinity` / `max_affinity`, `show_family`, `show_others`, `only_grudges`, `only_tags`,
`focus_person` + `focus_depth`, `custom_filter`. `label_for`, `color_for` and `icon_for` decide how
each person is shown.

## Performance

2,000 people and 40,000 bonds: `apply()` 11 µs, a busy day under 0.1 s, a quiet day 6 ms. The view at
500 people holds 60 fps.

## Demo

`demo/lite_demo.tscn` (the main scene): Thornbury, 24 villagers with their friendships, feuds and
grudges. Click someone, Shift-click a second person, and help, insult, betray or make up; Space passes
a day.

The Godot Asset Library download contains only `addons/relationship_web/`. The demo and the tests are
in this repository and on [itch.io](https://debugalot.itch.io/relationship-web-lite).

## Tests

```
godot --headless --path . res://tests/test_web.tscn
godot --headless --path . res://tests/test_view.tscn
```

244 checks of the core and 71 of the view. `python tools/check_upgrade.py <godot> <full
addons/relationship_web>` runs the core tests and the demo on the full version.

## License

Free to use in any number of your own projects, commercial ones included. Wherever the web view is
shown, the Lite mark stays. Don't redistribute the add-on itself, changed or unchanged. The full terms
are in [LICENSE](LICENSE).

## Support

If Relationship Web Lite saved you time, consider [buying me a coffee on Ko-fi](https://ko-fi.com/debugalot),
getting [Relationship Web](https://debugalot.itch.io/relationship-web), or checking out more Godot
tools on [ExcaliBug](https://excalibug.com).

## Credits

- **Font:** Nunito, copyright 2014 The Nunito Project Authors, SIL Open Font License
  (`addons/relationship_web/fonts/Nunito-OFL.txt`).
- **The mark and the demo portrait:** the Sir Debugalot knight, from the KayKit Adventurers knight by
  Kay Lousberg (CC0).
