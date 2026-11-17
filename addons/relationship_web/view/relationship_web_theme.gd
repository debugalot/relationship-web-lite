@tool
@icon("res://addons/relationship_web/icon.svg")
class_name RelationshipWebTheme
extends Resource
## The look of [RelationshipWebView]: colours, fonts and the palette people are coloured from (fixed in Lite). The defaults are a night-time game look. Make one, change what you
## like, save it as a [code].tres[/code] and give it to each part's [code]style[/code] property.

@export_group("Surfaces")
## Behind everything.
@export var background_color := Color("#14162a")
## Panels and cards.
@export var panel_color := Color("#1e2140")
## Panel and card edges.
@export var panel_border_color := Color("#2d3160")
## The faint grid behind the web (transparent turns it off).
@export var grid_color := Color(0.18, 0.77, 0.71, 0.05)

@export_group("Text")
## Names and headings.
@export var text_color := Color("#ebe9f3")
## Details and captions.
@export var muted_text_color := Color("#9a98b4")
## Outlines behind names drawn over the web, so they read over lines.
@export var text_outline_color := Color("#14162a")
## The font everything uses. A variable font (like the bundled Nunito) gets its weights from [member regular_weight]
## and [member bold_weight].
@export var font: Font = preload("res://addons/relationship_web/fonts/Nunito-Variable.ttf"):
	set(value):
		font = value
		_fonts.clear()
		emit_changed()
## The weight of ordinary text, for variable fonts.
@export_range(100, 1000, 50) var regular_weight := 600
## The weight of names and headings, for variable fonts.
@export_range(100, 1000, 50) var bold_weight := 800

@export_group("Feelings")
## Affinity +100.
@export var warm_color := Color("#2ec4b6")
## Affinity 0.
@export var neutral_color := Color("#8a88a6")
## Affinity −100.
@export var cold_color := Color("#ef6b5b")
## Grudges.
@export var grudge_color := Color("#f4b544")
## Selection, hover and focus.
@export var accent_color := Color("#2ec4b6")

@export_group("People")
## Colours handed out to groups (or to people, when there are no groups), in order.
@export var people_palette: PackedColorArray = [
	Color("#e0a96d"), Color("#8fb3e8"), Color("#b99be0"), Color("#7fcf9f"), Color("#e88fa9"), Color("#d9c76a"),
	Color("#6fc7d9"), Color("#c99a7a"),
]

var _fonts: Dictionary[int, Font] = {}
var _shapes: Dictionary[String, Texture2D] = {}


## The colour for an affinity (−100 to 100) on the cold–neutral–warm scale.
func feeling_color(affinity: float) -> Color:
	var t := clampf(affinity / 100.0, -1.0, 1.0)
	return neutral_color.lerp(warm_color, t) if t >= 0.0 else neutral_color.lerp(cold_color, -t)


## [member font] at a weight (for variable fonts; other fonts are returned as they are).
func font_at(weight: int) -> Font:
	if font == null:
		return ThemeDB.fallback_font
	if not _fonts.has(weight):
		var variation := FontVariation.new()
		variation.base_font = font
		variation.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
		_fonts[weight] = variation
	return _fonts[weight]


## Regular text.
func regular_font() -> Font:
	return font_at(regular_weight)


## Names and headings.
func bold_font() -> Font:
	return font_at(bold_weight)


## White shapes baked once for drawing many at a time, tinted on the way (a [MultiMesh] of discs for every person,
## a quad per ember): [code]"disc"[/code] (a filled circle), [code]"ring"[/code] (its outline), [code]"shadow"[/code]
## (a soft dark disc), [code]"glow"[/code] (a soft halo) and [code]"ember"[/code] (a disc with a bright centre). 48×48, smooth-edged, centred.
func shape(key: String) -> Texture2D:
	if _shapes.has(key):
		return _shapes[key]
	var side := 48
	var image := Image.create(side, side, false, Image.FORMAT_RGBA8)
	var centre := (side - 1) / 2.0
	var radius := side * 0.5 - 1.5
	for y in side:
		for x in side:
			var cover := 0.0
			# Four samples per pixel for smooth edges.
			for sy in 2:
				for sx in 2:
					var p := Vector2(x + 0.25 + sx * 0.5 - centre, y + 0.25 + sy * 0.5 - centre) / radius
					var d := p.length()
					match key:
						"disc":
							cover += 1.0 if d <= 1.0 else 0.0
						"ring":
							cover += 1.0 if d <= 1.0 and d >= 0.78 else 0.0
						"shadow":
							cover += clampf(1.0 - d, 0.0, 1.0) * 0.7 + (0.3 if d <= 0.9 else 0.0)
						"glow":
							cover += pow(clampf(1.0 - d, 0.0, 1.0), 1.6)
						"ember":
							cover += 1.0 if d <= 1.0 else 0.0
			cover /= 4.0
			var value := 1.0
			if key == "ember":
				var d := Vector2(x - centre, y - centre).length() / radius
				value = 1.0 if d > 0.45 else 1.55        # the centre is brighter than white: lit from within
			image.set_pixel(x, y, Color(minf(value, 1.0), minf(value, 1.0), minf(value, 1.0), cover))
	var texture := ImageTexture.create_from_image(image)
	_shapes[key] = texture
	return texture


## A unit quad for drawing baked shapes in batches ([MultiMesh] in a [CanvasItem]), with its texture the right way
## up in 2D. A [QuadMesh] won't do: it is laid out for 3D, where up is the other way, so its texture comes out flipped.
static func unit_quad() -> ArrayMesh:
	if _quad != null:
		return _quad
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(-0.5, -0.5, 0), Vector3(0.5, -0.5, 0), Vector3(0.5, 0.5, 0), Vector3(-0.5, 0.5, 0),
	])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	_quad = ArrayMesh.new()
	_quad.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return _quad


static var _quad: ArrayMesh


## A colour from [member people_palette] for any key (a group name, or an id), the same every run.
func palette_color(key: String) -> Color:
	if people_palette.is_empty():
		return neutral_color
	var h := 0
	for i in key.length():
		h = (h * 31 + key.unicode_at(i)) & 0x7FFFFFFF
	return people_palette[h % people_palette.size()]
