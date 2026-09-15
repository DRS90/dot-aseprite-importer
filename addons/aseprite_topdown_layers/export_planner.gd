@tool
extends RefCounted
## Turns the size, layer and tag names of one .aseprite file into export jobs.
##
## Every frame is a 3x3 grid of cells named after the direction they face; the center cell is not
## exported. Pure: no filesystem, no CLI, no editor. One job is one animation, exported as one
## strip: {"direction": String, "tag": String, "animation": String, "loop": bool,
## "relative_path": String}, where relative_path names the strip file inside the export folder.
## Problems are collected in [member errors] instead of being printed, so the caller decides how
## to report them and tests can assert on them.

const DEFAULT_ANIMATION_NAME := "{tag}_{direction}"
const DEFAULT_LOOP_SUFFIX := "_loop"
## Grid cells in reading order, center excluded. aseprite_batch.lua maps each name to its cell.
const DIRECTIONS: Array[String] = [
	"left_up", "up", "right_up", "left", "right", "left_down", "down", "right_down"
]
## Layer choice that composes every layer not matched by the exclude pattern.
const ALL_LAYERS := "[all]"
## Characters an AnimationLibrary does not accept in animation names.
const INVALID_NAME_CHARACTERS: Array[String] = ["/", ":", ",", "["]

## Problems found by the last [method build_jobs] call.
var errors := PackedStringArray()
## True when the last [method build_jobs] call found a problem that prevents any export.
var failed := false
## Layers composed into every strip by the last [method build_jobs] call.
var composed_layers := PackedStringArray()
## Cell size of the last [method build_jobs] call, or [constant Vector2i.ZERO] when the 3x3 grid
## does not fit the sprite.
var cell_size := Vector2i.ZERO


## [param layer_names] must be the names reported by Aseprite: user-typed names are validated
## against them. [param options] keys: cell_size (Vector2i; 0 on an axis is a third of the sprite),
## layer (the top-level layer or group composed into every strip, or [constant ALL_LAYERS] for
## every layer not matched by layer_exclude_pattern), layer_exclude_pattern, tag_exclude_pattern,
## animation_name ({tag} and {direction}) and loop_suffix (a tag ending with it loops and loses it
## in {tag}; empty means no animation loops).
func build_jobs(
	sprite_size: Vector2i,
	layer_names: PackedStringArray,
	tags: PackedStringArray,
	options: Dictionary
) -> Array[Dictionary]:
	errors = PackedStringArray()
	var jobs: Array[Dictionary] = []
	var requested_cell := Vector2i.ZERO
	var cell_option: Variant = options.get("cell_size", Vector2i.ZERO)
	if cell_option is Vector2i:
		requested_cell = cell_option
	cell_size = _resolve_cell_size(requested_cell, sprite_size)
	var layer_filter := _compile_filter(str(options.get("layer_exclude_pattern", "")), "layer")
	var layer_choice := str(options.get("layer", ALL_LAYERS))
	composed_layers = _select_layers(layer_choice, layer_names, layer_filter)
	var tag_filter := _compile_filter(str(options.get("tag_exclude_pattern", "")), "tag")
	var name_template := str(options.get("animation_name", DEFAULT_ANIMATION_NAME))
	var loop_suffix := str(options.get("loop_suffix", DEFAULT_LOOP_SUFFIX))

	failed = cell_size == Vector2i.ZERO or composed_layers.is_empty()
	if failed:
		return jobs

	var export_tags := _without_excluded(tags, tag_filter)
	if tags.is_empty():
		# No tags at all: the whole timeline becomes one animation per direction.
		export_tags.append("")

	var seen_names := {}
	for direction: String in DIRECTIONS:
		for tag: String in export_tags:
			var animation := animation_name(name_template, tag, direction, loop_suffix)
			if animation == "" or seen_names.has(animation):
				var problem := "Tag '%s' (%s) gives the animation name '%s', empty or already used."
				errors.append(problem % [tag, direction, animation])
				continue
			seen_names[animation] = true
			var job := {
				"direction": direction,
				"tag": tag,
				"animation": animation,
				"loop": is_loop(tag, loop_suffix),
				"relative_path": "strip_%03d.png" % jobs.size(),
			}
			jobs.append(job)
	return jobs


## Animation name for one tag and direction. [param template] accepts {tag} and {direction}; the
## loop suffix is removed from the tag, and an empty tag collapses the separators left around it.
static func animation_name(
	template: String, tag: String, direction: String, loop_suffix: String
) -> String:
	var tag_name := tag.trim_suffix(loop_suffix) if is_loop(tag, loop_suffix) else tag
	var name := template.replace("{tag}", tag_name).replace("{direction}", direction)
	if tag_name == "":
		name = _collapse_separators(name)
	return sanitize_animation_name(name)


## True when [param tag] ends with a non-empty [param loop_suffix].
static func is_loop(tag: String, loop_suffix: String) -> bool:
	return loop_suffix != "" and tag.ends_with(loop_suffix)


## Replaces the characters an AnimationLibrary does not accept in animation names with "_".
static func sanitize_animation_name(text: String) -> String:
	var result := text
	for character: String in INVALID_NAME_CHARACTERS:
		result = result.replace(character, "_")
	return result


static func _collapse_separators(text: String) -> String:
	var result := text
	var previous := ""
	while previous != result:
		previous = result
		result = result.replace("__", "_")
	return result.lstrip("_").rstrip("_")


## [param requested] with each 0 axis replaced by a third of [param sprite_size], or
## [constant Vector2i.ZERO] (and an error) when three cells do not fit the sprite on an axis.
func _resolve_cell_size(requested: Vector2i, sprite_size: Vector2i) -> Vector2i:
	var cell := requested
	var problem := ""
	for axis: int in 2:
		if requested[axis] == 0 and sprite_size[axis] % 3 == 0:
			cell[axis] = int(sprite_size[axis] / 3.0)
		elif requested[axis] == 0:
			problem = "cannot be split in 3 equal cells: set grid/cell_size"
		if problem == "" and (cell[axis] < 1 or cell[axis] * 3 > sprite_size[axis]):
			problem = "cannot hold 3x3 cells of %dx%d" % [requested.x, requested.y]
	if problem == "":
		return cell
	errors.append("The %dx%d sprite %s." % [sprite_size.x, sprite_size.y, problem])
	return Vector2i.ZERO


## [param choice] alone when it is one of [param layer_names] (it may match [param exclude]), or
## every layer not matched by [param exclude] for [constant ALL_LAYERS] or an empty choice.
func _select_layers(
	choice: String, layer_names: PackedStringArray, exclude: RegEx
) -> PackedStringArray:
	var selected := PackedStringArray()
	if choice == ALL_LAYERS or choice == "":
		selected = _without_excluded(layer_names, exclude)
	elif layer_names.has(choice):
		selected.append(choice)
	else:
		errors.append("layers/layer: unknown layer '%s'." % choice)
	if selected.is_empty():
		errors.append("No layers to export.")
	return selected


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
