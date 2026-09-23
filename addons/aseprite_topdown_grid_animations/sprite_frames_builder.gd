@tool
extends RefCounted
## Builds the SpriteFrames of an import from the strips Aseprite exported.
##
## Has no editor dependency, so headless tests can use it. Each strip holds its tag's frames left to
## right in timeline order, one cell per frame. SheetPacker packs the strips into one sheet, trimmed
## per animation, which becomes one lossless texture embedded in the SpriteFrames: every frame is an
## AtlasTexture region of it, with a margin that gives back the trimmed space, so frames keep the
## cell size and every sprite using the file draws the same texture. Timing follows Aseprite:
## the animation speed is 1 / the shortest frame duration, and each frame keeps its duration
## relative to it. Reverse and ping-pong tags reorder the frames.

const SheetPacker := preload("sheet_packer.gd")

const DEFAULT_DURATION_MS := 100

## Problems found by the last [method build] call.
var errors := PackedStringArray()


## The strip written at [param path] as a lossless texture, or null when the file cannot be read.
## [param keep_buffer] keeps the compressed bytes in memory: a texture that loses them survives
## being embedded in an imported resource but comes back empty from Make Unique or Save As, so a
## texture handed to the user as a resource of its own asks for it.
static func load_strip_texture(path: String, keep_buffer := false) -> PortableCompressedTexture2D:
	var image := Image.load_from_file(path)
	if image == null:
		return null
	return _lossless_texture(image, keep_buffer)


## Timeline frames (0-based) that a tag spanning [param first] to [param last] plays, in order.
## [param direction] is forward, reverse, pingpong or pingpong_reverse; ping-pong does not repeat
## the frames at both ends, so the sequence loops smoothly.
static func frame_sequence(first: int, last: int, direction: String) -> PackedInt32Array:
	var forward := PackedInt32Array()
	for frame: int in range(first, last + 1):
		forward.append(frame)
	var backward := forward.duplicate()
	backward.reverse()
	match direction:
		"reverse":
			return backward
		"pingpong":
			return forward + _without_ends(backward)
		"pingpong_reverse":
			return backward + _without_ends(forward)
	return forward


## {"speed": float (frames per second), "durations": PackedFloat32Array (relative)} for frames that
## last [param durations_ms] milliseconds each.
static func timing(durations_ms: PackedInt32Array) -> Dictionary:
	var shortest := 0
	for duration: int in durations_ms:
		if duration > 0 and (shortest == 0 or duration < shortest):
			shortest = duration
	if shortest == 0:
		shortest = DEFAULT_DURATION_MS
	var relative := PackedFloat32Array()
	for duration: int in durations_ms:
		relative.append(maxi(duration, 1) / float(shortest))
	return {"speed": 1000.0 / shortest, "durations": relative}


## [param jobs] come from ExportPlanner.build_jobs() and [param written] lists the strips the export
## wrote (relative to [param strips_dir]); jobs without a strip get no animation. [param contents]
## comes from AsepriteCli.list_contents() and gives the tag ranges and frame durations.
func build(
	jobs: Array[Dictionary],
	written: PackedStringArray,
	strips_dir: String,
	contents: Dictionary,
	cell_size: Vector2i
) -> SpriteFrames:
	errors = PackedStringArray()
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	var durations: PackedInt32Array = contents.get("frame_durations", PackedInt32Array())
	var ranges: Dictionary = contents.get("tag_ranges", {})
	var strips: Array[Dictionary] = []
	var built_jobs: Array[Dictionary] = []
	for job: Dictionary in jobs:
		var relative_path: String = job["relative_path"]
		if not written.has(relative_path):
			continue
		var image := Image.load_from_file(strips_dir.path_join(relative_path))
		if image == null:
			errors.append("Cannot read the exported strip '%s'." % relative_path)
			continue
		strips.append({"key": relative_path, "image": image})
		built_jobs.append(job)
	var packer := SheetPacker.new()
	var packed := packer.pack(strips, cell_size)
	errors.append_array(packer.errors)
	if not errors.is_empty() or built_jobs.is_empty():
		return frames
	# One texture for the whole file, shared by every frame of every animation.
	var texture := _lossless_texture(packed["sheet"], false)
	var cells: Dictionary = packed["cells"]
	for job: Dictionary in built_jobs:
		var tag: String = job["tag"]
		var whole_timeline := {"from": 0, "to": durations.size() - 1, "direction": "forward"}
		var tag_range: Dictionary = ranges.get(tag, whole_timeline)
		var strip_cells: Array[Dictionary] = cells[job["relative_path"]]
		var cell_count: int = tag_range["to"] - tag_range["from"] + 1
		if strip_cells.size() != cell_count:
			errors.append(
				(
					"The strip '%s' has %d frames, but its tag spans %d."
					% [job["relative_path"], strip_cells.size(), cell_count]
				)
			)
			continue
		_add_animation(frames, job, texture, strip_cells, tag_range, durations)
	return frames


## [param frames] without its first and last entries; empty when nothing is left between them.
static func _without_ends(frames: PackedInt32Array) -> PackedInt32Array:
	if frames.size() < 3:
		return PackedInt32Array()
	return frames.slice(1, frames.size() - 1)


static func _add_animation(
	frames: SpriteFrames,
	job: Dictionary,
	texture: Texture2D,
	cells: Array[Dictionary],
	tag_range: Dictionary,
	durations: PackedInt32Array
) -> void:
	var first: int = tag_range["from"]
	var last: int = tag_range["to"]
	var direction: String = tag_range["direction"]
	var sequence := frame_sequence(first, last, direction)
	var sequence_durations := PackedInt32Array()
	for frame: int in sequence:
		sequence_durations.append(
			durations[frame] if frame < durations.size() else DEFAULT_DURATION_MS
		)
	var frame_timing := timing(sequence_durations)
	var relative: PackedFloat32Array = frame_timing["durations"]
	var speed: float = frame_timing["speed"]
	var loop: bool = job["loop"]
	var animation := StringName(str(job["animation"]))
	frames.add_animation(animation)
	frames.set_animation_speed(animation, speed)
	frames.set_animation_loop(animation, loop)
	# Ping-pong plays some cells twice: they share one region.
	var regions := {}
	for index: int in sequence.size():
		var frame := sequence[index]
		if not regions.has(frame):
			var cell: Dictionary = cells[frame - first]
			var region := AtlasTexture.new()
			region.atlas = texture
			region.region = Rect2(cell["region"])
			region.margin = Rect2(cell["margin"])
			# Trimmed frames touch their neighbours in the sheet: a linear filter would bleed them.
			region.filter_clip = true
			regions[frame] = region
		var atlas: AtlasTexture = regions[frame]
		frames.add_frame(animation, atlas, relative[index])


static func _lossless_texture(image: Image, keep_buffer: bool) -> PortableCompressedTexture2D:
	var texture := PortableCompressedTexture2D.new()
	texture.keep_compressed_buffer = keep_buffer
	texture.create_from_image(image, PortableCompressedTexture2D.COMPRESSION_MODE_LOSSLESS)
	return texture
