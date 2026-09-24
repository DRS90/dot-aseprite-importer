@tool
extends RefCounted
## Turns the size, layer and tag names of one .aseprite file into export jobs.
##
## In [constant MODE_NONE], the default, the frame is one nameless cell: a sprite with no
## direction. In the [constant MODE_3X3] grid, every frame is 3x3 cells named after the direction
## they face and the center cell is not exported. Pure: no filesystem, no CLI, no editor.
## One job is one animation, exported as one strip: {"direction": String, "tag": String,
## "animation": String, "loop": bool, "relative_path": String}, where relative_path names the strip
## file inside the export folder. Problems are collected in [member errors] instead of being
## printed, so the caller decides how to report them and tests can assert on them.

const DEFAULT_ANIMATION_NAME := "{tag}_{direction}"
const DEFAULT_LOOP_SUFFIX := "_loop"
## Name of the only animation of a file that has neither tags nor directions to name it after.
const DEFAULT_ANIMATION := "default"
## Grid of 3x3 cells, one per facing direction.
const MODE_3X3 := "3x3"
## Grid of one cell: the whole frame, with no direction.
const MODE_NONE := "none"
## Grid of a file whose import options do not name one. Top-down projects that draw every sprite
## as a grid set 3x3 in Project Settings > Import Defaults instead of changing this.
const DEFAULT_DIRECTIONS := MODE_NONE
## Grid cells in reading order, center excluded. aseprite_batch.lua maps each name to its cell.
const DIRECTIONS: Array[String] = [
	"left_up", "up", "right_up", "left", "right", "left_down", "down", "right_down"
]
## The only cell of [constant MODE_NONE]: the top left corner, with no name.
const NO_DIRECTIONS: Array[String] = [""]
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
## Cell size of the last [method build_jobs] call, or [constant Vector2i.ZERO] when the grid does
## not fit the sprite.
var cell_size := Vector2i.ZERO
## Cells per axis of the last [method build_jobs] call: 3 for [constant MODE_3X3], 1 for
## [constant MODE_NONE], 0 when the mode is unknown.
var cells_per_axis := 0


## [param layer_names] must be the names reported by Aseprite: user-typed names are validated
## against them. [param options] keys: directions ([constant MODE_3X3] or [constant MODE_NONE]),
## cell_size (Vector2i; 0 on an axis is the sprite divided by [member cells_per_axis]), layer (the
## top-level layer or group composed into every strip, or [constant ALL_LAYERS] for every layer not
## matched by layer_exclude_pattern), layer_exclude_pattern, tag_exclude_pattern, animation_name
## ({tag} and {direction}) and loop_suffix (a tag ending with it loops and loses it in {tag}; empty
## means no animation loops).
func build_jobs(
	sprite_size: Vector2i,
	layer_names: PackedStringArray,
	tags: PackedStringArray,
	options: Dictionary
) -> Array[Dictionary]:
	errors = PackedStringArray()
	failed = false
	cell_size = Vector2i.ZERO
	cells_per_axis = 0
	composed_layers = PackedStringArray()
	var jobs: Array[Dictionary] = []

	# Nothing else can be validated without knowing how many cells a frame holds.
	var directions := _directions_for(str(options.get("directions", DEFAULT_DIRECTIONS)))
	if directions.is_empty():
		failed = true
		return jobs

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
		# No tags at all: the whole timeline becomes one animation per cell.
		export_tags.append("")

	# Every name is checked before anything is exported: a partial import would replace the
	# animations that still worked with a resource missing the ones that collided.
	var seen_names := {}
	for direction: String in directions:
		for tag: String in export_tags:
			var animation := animation_name(name_template, tag, direction, loop_suffix)
			if animation == "":
				errors.append("%s gives an empty animation name." % _job_label(tag, direction))
				failed = true
				continue
			if seen_names.has(animation):
				var claimed_by: String = seen_names[animation]
				errors.append(
					(
						"%s gives the animation name '%s', already used by %s."
						% [_job_label(tag, direction), animation, claimed_by]
					)
				)
				failed = true
				continue
			seen_names[animation] = _job_label(tag, direction)
			var job := {
				"direction": direction,
				"tag": tag,
				"animation": animation,
				"loop": is_loop(tag, loop_suffix),
				"relative_path": "strip_%03d.png" % jobs.size(),
			}
			jobs.append(job)
	if failed:
		jobs.clear()
	return jobs


## Animation name for one tag and direction. [param template] accepts {tag} and {direction}; the
## loop suffix is removed from the tag, and a placeholder with nothing to put in it leaves the
## template with one adjacent separator. A file with neither tags nor directions to name its only
## animation after gets [constant DEFAULT_ANIMATION].
static func animation_name(
	template: String, tag: String, direction: String, loop_suffix: String
) -> String:
	var tag_name := tag.trim_suffix(loop_suffix) if is_loop(tag, loop_suffix) else tag
	var resolved := template
	if tag_name == "":
		resolved = _without_placeholder(resolved, "{tag}")
	if direction == "":
		resolved = _without_placeholder(resolved, "{direction}")
	var name := resolved.replace("{tag}", tag_name).replace("{direction}", direction)
	# Only MODE_NONE has an empty direction, so this never renames a cell of a 3x3 grid.
	if name == "" and direction == "":
		name = DEFAULT_ANIMATION
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


## How a job is named in an error message: its tag, and its direction when the grid has directions.
static func _job_label(tag: String, direction: String) -> String:
	if direction == "":
		return "tag '%s'" % tag
	return "tag '%s' (%s)" % [tag, direction]


## [param template] without [param placeholder], taking one separator next to it along so an empty
## value leaves no dangling "_". Only the template is touched: a tag named "run__fast" keeps its
## name.
static func _without_placeholder(template: String, placeholder: String) -> String:
	if template.contains("_" + placeholder):
		return template.replace("_" + placeholder, "")
	if template.contains(placeholder + "_"):
		return template.replace(placeholder + "_", "")
	return template.replace(placeholder, "")


## The cells to export for [param mode], setting [member cells_per_axis]. Empty, with an error,
## when the mode is unknown: an .import file edited by hand must not silently fall back to a grid
## that would crop the wrong pixels.
func _directions_for(mode: String) -> Array[String]:
	var directions: Array[String] = []
	match mode:
		MODE_3X3:
			cells_per_axis = 3
			directions = DIRECTIONS
		MODE_NONE:
			cells_per_axis = 1
			directions = NO_DIRECTIONS
		_:
			var problem := "grid/directions: unknown value '%s'; use '%s' or '%s'."
			errors.append(problem % [mode, MODE_3X3, MODE_NONE])
	return directions


## [param requested] with each 0 axis replaced by [param sprite_size] divided by
## [member cells_per_axis], or [constant Vector2i.ZERO] (and an error) when the cells do not fit
## the sprite on an axis.
func _resolve_cell_size(requested: Vector2i, sprite_size: Vector2i) -> Vector2i:
	var cell := requested
	var problem := ""
	for axis: int in 2:
		if requested[axis] == 0 and sprite_size[axis] % cells_per_axis == 0:
			cell[axis] = int(sprite_size[axis] / float(cells_per_axis))
		elif requested[axis] == 0:
			problem = _split_problem()
		if problem == "" and (cell[axis] < 1 or cell[axis] * cells_per_axis > sprite_size[axis]):
			problem = _cell_problem(requested)
	if problem == "":
		return cell
	errors.append("The %dx%d sprite %s." % [sprite_size.x, sprite_size.y, problem])
	return Vector2i.ZERO


## Why a 0 axis cannot be resolved, naming both ways out: a cell size, or no grid at all. A project
## that sets 3x3 in Import Defaults still has sprites without directions (a run dust puff, a hit
## spark), and one of those is the usual reason a sprite is not a multiple of 3, so a message about
## grid/cell_size alone would send the user to the wrong fix.
func _split_problem() -> String:
	var fix := "set grid/cell_size, or grid/directions to '%s' if it has no directions" % MODE_NONE
	return "cannot be split in %d equal cells: %s" % [cells_per_axis, fix]


## Why [param requested] does not fit, worded for the grid in use: a 3x3 grid has to hold nine of
## them, while a grid without directions only has to be at least as big as the one cell.
func _cell_problem(requested: Vector2i) -> String:
	if cells_per_axis == 1:
		return "is smaller than the requested %dx%d cell" % [requested.x, requested.y]
	return (
		"cannot hold %dx%d cells of %dx%d"
		% [cells_per_axis, cells_per_axis, requested.x, requested.y]
	)


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
