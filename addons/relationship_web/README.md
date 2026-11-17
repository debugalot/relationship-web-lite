# Relationship Web Lite for Godot

Who feels what about whom: feelings each way between every pair of characters (affinity, trust,
familiarity), personalities that shape them, grudges that fester and get forgiven, days passing, and a
web view to see it. Pure GDScript; there is no plugin to enable.

```gdscript
var web := RelationshipWeb.new()
web.add_person("ana", {"data": {"name": "Ana"}})
web.add_person("bo", {"data": {"name": "Bo"}})
web.link("ana", "bo", &"friend")
web.apply("ana", "bo", {"affinity": 10, "trust": 5})
web.advance_day()

var view := RelationshipWebView.new()
view.set_anchors_preset(Control.PRESET_FULL_RECT)
add_child(view)
view.web = web
```

The view draws the Lite mark (a faint knight and "Relationship Web Lite"), which the license asks
you to keep. The full documentation,
the demo and the tests: https://debugalot.itch.io/relationship-web-lite

The full Relationship Web has the same API and adds romance, jealousy, courtship, couples, marriage,
families, pregnancy, death, abandonment and adoption, the relationship list, the family tree, the
ready-made screen, a look of your own and no mark. Upgrading is replacing this folder:
https://debugalot.itch.io/relationship-web
