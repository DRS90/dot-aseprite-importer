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


## [param options] keys: layer_exclude_pattern, tag_exclude_pattern, output_folder, filename.
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
	for source: Dictionary in _collect_sources(layers, layer_filter):
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


func _collect_sources(layers: PackedStringArray, layer_filter: RegEx) -> Array[Dictionary]:
	var sources: Array[Dictionary] = []
	for layer: String in _without_excluded(layers, layer_filter):
		sources.append({"name": layer, "layers": PackedStringArray([layer])})
	return sources


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
