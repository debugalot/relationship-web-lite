extends SceneTree
## Checks that every public class, signal, method, property, constant and enum in the addon has a doc comment
## (the [code]##[/code] lines Godot's help reads). Run:
##   godot --headless --path . -s res://tools/check_docs.gd
## Exit code 0 when nothing is missing. Private members (a leading underscore) and the members of private inner
## classes are skipped; a public member inside a public inner class is not. Only class-level declarations count.

const ROOT := "res://addons/relationship_web"


func _init() -> void:
	var missing := PackedStringArray()
	var members := 0
	for path in _scripts(ROOT):
		var lines := FileAccess.get_file_as_string(path).split("\n")
		var private_class_indent := -1
		var public_class_indent := -1
		var in_enum := false
		for n in lines.size():
			var raw := lines[n]
			var line := raw.strip_edges()
			if line.is_empty() or line.begins_with("#"):
				continue
			var indent := raw.length() - raw.lstrip("\t").length()
			if private_class_indent >= 0 and indent <= private_class_indent:
				private_class_indent = -1
			if public_class_indent >= 0 and indent <= public_class_indent:
				public_class_indent = -1
			if line.begins_with("class ") and line.ends_with(":"):
				var class_word := line.substr(6).split(" ")[0]
				if class_word.begins_with("_"):
					private_class_indent = indent
				else:
					public_class_indent = indent
					members += 1
					if not _documented(lines, n):
						missing.append("%s:%d  %s" % [path, n + 1, line])
				continue
			if private_class_indent >= 0:
				continue
			var class_level := indent == 0 or (public_class_indent >= 0 and indent == public_class_indent + 1)
			if in_enum:
				if line.begins_with("}"):
					in_enum = false
				else:
					members += 1
					if not ("##" in line or _documented(lines, n)):
						missing.append("%s:%d  enum value %s" % [path, n + 1, line])
				continue
			if not class_level:
				continue
			if line.begins_with("class_name "):
				members += 1
				if not _class_documented(lines, n):
					missing.append("%s:%d  %s (no ## block after extends)" % [path, n + 1, line])
				continue
			var kind := _public_kind(line)
			if kind.is_empty():
				continue
			members += 1
			if not _documented(lines, n):
				missing.append("%s:%d  %s" % [path, n + 1, line.left(80)])
			if kind == "enum" and line.ends_with("{"):
				in_enum = true
	print("%d public members checked, %d without a doc comment" % [members, missing.size()])
	for m in missing:
		print("  ", m)
	quit(0 if missing.is_empty() else 1)


## "signal", "func", "var", "const" or "enum" for a public declaration, else "".
func _public_kind(line: String) -> String:
	var rest := _without_annotations(line)
	var words := rest.split(" ", false)
	if words.size() < 2:
		return ""
	var keyword := words[0]
	if not keyword in ["signal", "func", "var", "const", "enum"]:
		return ""
	var given := words[1].split("(")[0].split(":")[0].split("=")[0].strip_edges()
	if given.begins_with("_") or given.is_empty():
		return ""
	return keyword


## The line without its leading annotations (arguments and all, so [code]@export_range(0, 10, 1)[/code] goes as
## one) and without [code]static[/code].
func _without_annotations(line: String) -> String:
	var rest := line.strip_edges()
	while rest.begins_with("@") or rest.begins_with("static "):
		if rest.begins_with("static "):
			rest = rest.substr(7).strip_edges()
			continue
		var space := rest.find(" ")
		var paren := rest.find("(")
		if paren >= 0 and (space < 0 or paren < space):
			var close := rest.find(")", paren)
			if close < 0:
				return ""
			rest = rest.substr(close + 1).strip_edges()
		elif space >= 0:
			rest = rest.substr(space + 1).strip_edges()
		else:
			return ""
	return rest


## True if a doc comment follows the class_name / extends lines (where Godot reads a class's own description).
func _class_documented(lines: PackedStringArray, n: int) -> bool:
	for k in range(n + 1, mini(n + 6, lines.size())):
		var below := lines[k].strip_edges()
		if below.begins_with("##"):
			return true
		if not (below.begins_with("extends ") or below.begins_with("@") or below.is_empty()):
			return false
	return false


## True if the lines just above (skipping annotation lines) are a doc comment.
func _documented(lines: PackedStringArray, n: int) -> bool:
	var k := n - 1
	while k >= 0:
		var above := lines[k].strip_edges()
		if above.begins_with("##"):
			return true
		if above.begins_with("@") and not " var " in above:
			k -= 1
			continue
		return false
	return false


func _scripts(folder: String) -> PackedStringArray:
	var found := PackedStringArray()
	for file in DirAccess.get_files_at(folder):
		if file.ends_with(".gd"):
			found.append(folder.path_join(file))
	for sub in DirAccess.get_directories_at(folder):
		found.append_array(_scripts(folder.path_join(sub)))
	return found
