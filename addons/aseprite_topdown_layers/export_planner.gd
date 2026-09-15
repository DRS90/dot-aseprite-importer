@tool
extends RefCounted
## Turns the layer and tag names of one .aseprite file into export jobs.
##
## Pure: no filesystem, no CLI, no editor. One job is one Aseprite CLI call:
## {"layers": PackedStringArray, "output_name": String, "tag": String, "relative_path": String}
## Problems are collected in [member errors] instead of being printed, so the caller decides how
## to report them and tests can assert on them.

const PNG_EXTENSION := ".png"
const DEFAULT_FILENAME := "{title}_{layer}_{tag}"

## Problems found by the last [method build_jobs] call.
var errors := PackedStringArray()


## [param layers] must be the names reported by Aseprite: user-typed names are validated against
## them, because Aseprite silently exports the wrong thing for unknown names.
## [param options] keys: layer_exclude_pattern, tag_exclude_pattern, output_folder, filename,
## always_include ("a,b": composed into every strip, never exported alone) and combinations
## ("name=a+b;other=c+d": one strip per combination, its layers are not exported alone).
func build_jobs(
	title: String, layers: PackedStringArray, tags: PackedStringArray, options: Dictionary
) -> Array[Dictionary]:
	errors = PackedStringArray()
	var jobs: Array[Dictionary] = []
	var layer_filter := _compile_filter(str(options.get("layer_exclude_pattern", "")), "layer")
	var tag_filter := _compile_filter(str(options.get("tag_exclude_pattern", "")), "tag")
	var folder_template := str(options.get("output_folder", ""))
	var filename_template := str(options.get("filename", DEFAULT_FILENAME))

	var export_tags := _without_excluded(tags, tag_filter)
	if tags.is_empty():
		# No tags at all: the whole timeline becomes one strip per layer.
		export_tags.append("")

	var seen_paths := {}
	for source: Dictionary in _collect_sources(layers, layer_filter, options):
		var output_name: String = source["name"]
		for tag: String in export_tags:
			var relative_path := build_relative_path(
				folder_template, filename_template, title, output_name, tag
			)
			if seen_paths.has(relative_path):
				errors.append(
					(
						"Two outputs resolve to '%s'; skipped the one for '%s'."
						% [relative_path, output_name]
					)
				)
				continue
			seen_paths[relative_path] = true
			var job := {
				"layers": source["layers"],
				"output_name": output_name,
				"tag": tag,
				"relative_path": relative_path,
			}
			jobs.append(job)
	return jobs


## Relative output path (with extension) for one strip. Folder and filename templates accept
## {title}, {layer} and {tag}. An empty tag collapses the separators left around it.
static func build_relative_path(
	folder_template: String, filename_template: String, title: String, layer: String, tag: String
) -> String:
	var folder := apply_template(folder_template, title, layer, tag)
	var file_name := apply_template(filename_template, title, layer, tag)
	if tag == "":
		folder = _collapse_separators(folder)
		file_name = _collapse_separators(file_name)
	var path := file_name + PNG_EXTENSION
	if folder != "":
		path = folder.path_join(path)
	return path.simplify_path()


static func apply_template(template: String, title: String, layer: String, tag: String) -> String:
	return template.replace("{title}", title).replace("{layer}", sanitize(layer)).replace(
		"{tag}", sanitize(tag)
	)


## Makes a layer or tag name safe to use as part of a file name.
static func sanitize(name: String) -> String:
	if name == "":
		return ""
	return name.replace("/", "_").replace(" ", "_").validate_filename()


static func _collapse_separators(text: String) -> String:
	var result := text
	var previous := ""
	while previous != result:
		previous = result
		result = (
			result
			. replace("__", "_")
			. replace("//", "/")
			. replace("_/", "/")
			. replace("/_", "/")
			. replace("_.", ".")
		)
	return result.lstrip("_").rstrip("_/")


## A source is one strip per tag: {"name": String, "layers": PackedStringArray}.
func _collect_sources(
	layers: PackedStringArray, layer_filter: RegEx, options: Dictionary
) -> Array[Dictionary]:
	var always_include := _parse_always_include(str(options.get("always_include", "")), layers)
	var combinations := _parse_combinations(str(options.get("combinations", "")), layers)
	var consumed := always_include.duplicate()
	for combination: Dictionary in combinations:
		var members: PackedStringArray = combination["layers"]
		consumed.append_array(members)

	var sources: Array[Dictionary] = []
	for layer: String in _without_excluded(layers, layer_filter):
		if not consumed.has(layer):
			sources.append(_source(layer, always_include, PackedStringArray([layer])))
	for combination: Dictionary in combinations:
		var combination_name: String = combination["name"]
		var combination_layers: PackedStringArray = combination["layers"]
		sources.append(_source(combination_name, always_include, combination_layers))
	return sources


func _parse_always_include(text: String, layers: PackedStringArray) -> PackedStringArray:
	var names := PackedStringArray()
	for entry: String in text.split(",", false):
		var layer := entry.strip_edges()
		if layer == "" or names.has(layer):
			continue
		if not layers.has(layer):
			errors.append("always_include: unknown layer '%s'; ignored." % layer)
			continue
		names.append(layer)
	return names


func _parse_combinations(text: String, layers: PackedStringArray) -> Array[Dictionary]:
	var combinations: Array[Dictionary] = []
	var names := PackedStringArray()
	for entry: String in text.split(";", false):
		var definition := entry.strip_edges()
		if definition == "":
			continue
		var parts := definition.split("=")
		var name := parts[0].strip_edges() if parts.size() == 2 else ""
		var members := _parse_members(parts[1] if parts.size() == 2 else "")
		if name == "" or members.is_empty():
			errors.append(
				"Combination '%s' must look like name=layerA+layerB; skipped." % definition
			)
			continue
		if names.has(name):
			errors.append("Combination '%s' is defined twice; skipped the second one." % name)
			continue
		var unknown := _unknown_names(members, layers)
		if not unknown.is_empty():
			errors.append(
				"Combination '%s' uses unknown layer(s) %s; skipped." % [name, ", ".join(unknown)]
			)
			continue
		names.append(name)
		combinations.append({"name": name, "layers": members})
	return combinations


static func _parse_members(text: String) -> PackedStringArray:
	var members := PackedStringArray()
	for entry: String in text.split("+", false):
		var member := entry.strip_edges()
		if member != "" and not members.has(member):
			members.append(member)
	return members


static func _unknown_names(names: PackedStringArray, known: PackedStringArray) -> PackedStringArray:
	var unknown := PackedStringArray()
	for name: String in names:
		if not known.has(name):
			unknown.append("'%s'" % name)
	return unknown


static func _source(
	name: String, always_include: PackedStringArray, members: PackedStringArray
) -> Dictionary:
	var composed := always_include.duplicate()
	for member: String in members:
		if not composed.has(member):
			composed.append(member)
	return {"name": name, "layers": composed}


func _compile_filter(pattern: String, label: String) -> RegEx:
	if pattern == "":
		return null
	var regex := RegEx.new()
	if regex.compile(pattern) != OK:
		errors.append("Invalid %s exclude pattern '%s'; nothing excluded." % [label, pattern])
		return null
	return regex


static func _without_excluded(names: PackedStringArray, filter: RegEx) -> PackedStringArray:
	var kept := PackedStringArray()
	for name: String in names:
		if filter == null or filter.search(name) == null:
			kept.append(name)
	return kept
