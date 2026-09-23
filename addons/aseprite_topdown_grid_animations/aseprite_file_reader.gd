@tool
extends RefCounted
## Reads what an .aseprite/.ase file holds straight from its bytes, without starting Aseprite.
##
## Has no editor dependency, so headless tests can use it. Only the header, the frame headers, the
## layer chunks and the tags chunk are read; every other chunk (cels, palettes, user data) is
## skipped by its size, so nothing is decompressed and even a big file reads in a few milliseconds,
## where starting Aseprite to list it costs 200 ms plus the time it takes to open the file. The
## layout is the one of Aseprite's docs/ase-file-specs.md, and frames and chunks are walked by the
## same rules as Aseprite's own decoder. The result has the shape of AsepriteCli.list_contents(),
## which lists the same through Aseprite and is what the tests compare this with.

const AsepriteCli := preload("aseprite_cli.gd")

const HEADER_SIZE := 128
const FRAME_HEADER_SIZE := 16
const CHUNK_HEADER_SIZE := 6
const FILE_MAGIC := 0xA5E0
const FRAME_MAGIC := 0xF1FA
const LAYER_CHUNK := 0x2004
const TAGS_CHUNK := 0x2018
const LAYER_VISIBLE := 1
## The frame header's old chunk count, when the real count is in its new field.
const MANY_CHUNKS := 0xFFFF
## Byte offsets in the file header.
const HEADER_FRAMES := 6
const HEADER_WIDTH := 8
const HEADER_HEIGHT := 10
## Duration of a frame whose own duration is 0 (files older than per-frame durations). It follows
## the color depth (a WORD at 12) and the flags (a DWORD at 14).
const HEADER_SPEED := 18
## Tag loop directions in file order, named as AsepriteCli.list_contents() names them.
const TAG_DIRECTIONS: Array[String] = ["forward", "reverse", "pingpong", "pingpong_reverse"]
## Bytes of a layer chunk before its name: flags, type, child level, width, height, blend mode
## (a WORD each), opacity (a BYTE) and 3 reserved bytes.
const LAYER_NAME_OFFSET := 16
const LAYER_CHILD_LEVEL := 4
## Bytes of a tag before its name: from, to (a WORD each), direction (a BYTE), repeat (a WORD),
## 6 reserved bytes, the RGB color and one extra byte.
const TAG_NAME_OFFSET := 17
const TAG_DIRECTION := 4
## Bytes of the tags chunk before its first tag: the count (a WORD) and 8 reserved bytes.
const TAGS_OFFSET := 10

## Why the last [method read] call returned an empty dictionary.
var last_error := ""


## What [param path] holds, as AsepriteCli.list_contents() describes it, or an empty dictionary
## with [member last_error] set when the file cannot be read or is not an Aseprite file.
func read(path: String) -> Dictionary:
	last_error = ""
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		var open_error := FileAccess.get_open_error()
		last_error = "cannot read '%s' (%s)." % [path, error_string(open_error)]
		if open_error == OK:
			last_error = "'%s' is empty." % path
		return {}
	if bytes.size() < HEADER_SIZE or bytes.decode_u16(4) != FILE_MAGIC:
		last_error = "'%s' is not an Aseprite file." % path
		return {}
	var contents := {
		"size": Vector2i(bytes.decode_u16(HEADER_WIDTH), bytes.decode_u16(HEADER_HEIGHT)),
		"layers": PackedStringArray(),
		"visible_layers": PackedStringArray(),
		"tags": PackedStringArray(),
		"tag_ranges": {},
		"frame_durations": PackedInt32Array(),
	}
	var default_duration := bytes.decode_u16(HEADER_SPEED)
	var durations := PackedInt32Array()
	var frame_start := HEADER_SIZE
	for frame: int in bytes.decode_u16(HEADER_FRAMES):
		if frame_start + FRAME_HEADER_SIZE > bytes.size():
			return _fail(path, "frame %d starts past the end of the file" % frame, frame_start)
		var frame_end := frame_start + bytes.decode_u32(frame_start)
		if frame_end < frame_start + FRAME_HEADER_SIZE or frame_end > bytes.size():
			return _fail(path, "frame %d does not fit in the file" % frame, frame_start)
		var duration := bytes.decode_u16(frame_start + 8)
		durations.append(duration if duration > 0 else default_duration)
		# Like Aseprite, a frame without its magic number keeps its place but gives no chunks.
		if bytes.decode_u16(frame_start + 4) == FRAME_MAGIC:
			var problem := _read_chunks(bytes, frame_start, frame_end, contents)
			if problem != "":
				return _fail(path, "frame %d: %s" % [frame, problem], frame_start)
		frame_start = frame_end
	contents["frame_durations"] = durations
	return contents


## Reads the layer and tag chunks of the frame between [param frame_start] and [param frame_end],
## returning what is wrong with them, or "".
func _read_chunks(
	bytes: PackedByteArray, frame_start: int, frame_end: int, contents: Dictionary
) -> String:
	var old_count := bytes.decode_u16(frame_start + 6)
	var new_count := bytes.decode_u32(frame_start + 12)
	# The count rule of Aseprite's decoder: the new field only when the old one is saturated.
	var count := new_count if old_count == MANY_CHUNKS and old_count < new_count else old_count
	var chunk := frame_start + FRAME_HEADER_SIZE
	for index: int in count:
		if chunk + CHUNK_HEADER_SIZE > frame_end:
			return "chunk %d starts past the end of the frame" % index
		var chunk_end := chunk + bytes.decode_u32(chunk)
		if chunk_end < chunk + CHUNK_HEADER_SIZE or chunk_end > frame_end:
			return "chunk %d does not fit in the frame" % index
		var data := chunk + CHUNK_HEADER_SIZE
		var chunk_type := bytes.decode_u16(chunk + 4)
		var complete := true
		if chunk_type == LAYER_CHUNK:
			complete = _read_layer(bytes, data, chunk_end, contents)
		elif chunk_type == TAGS_CHUNK:
			complete = _read_tags(bytes, data, chunk_end, contents)
		if not complete:
			return "chunk %d is cut short" % index
		chunk = chunk_end
	return ""


func _read_layer(bytes: PackedByteArray, data: int, data_end: int, contents: Dictionary) -> bool:
	var name: Variant = _string_at(bytes, data + LAYER_NAME_OFFSET, data_end)
	if name == null:
		return false
	# A layer inside a group follows the group with a higher child level; only the top level is
	# listed, like Aseprite's sprite.layers. Groups, tilemaps and reference layers are layers here.
	if bytes.decode_u16(data + LAYER_CHILD_LEVEL) == 0:
		var visible := bytes.decode_u16(data) & LAYER_VISIBLE != 0
		AsepriteCli.add_layer(contents, str(name), visible)
	return true


func _read_tags(bytes: PackedByteArray, data: int, data_end: int, contents: Dictionary) -> bool:
	if data + TAGS_OFFSET > data_end:
		return false
	var tag := data + TAGS_OFFSET
	for index: int in bytes.decode_u16(data):
		var name: Variant = _string_at(bytes, tag + TAG_NAME_OFFSET, data_end)
		if name == null:
			return false
		var code := bytes.decode_u8(tag + TAG_DIRECTION)
		# An unknown direction plays forward, as the Lua listing reports it.
		var direction := TAG_DIRECTIONS[code] if code < TAG_DIRECTIONS.size() else TAG_DIRECTIONS[0]
		AsepriteCli.add_tag(
			contents, str(name), bytes.decode_u16(tag), bytes.decode_u16(tag + 2), direction
		)
		tag += TAG_NAME_OFFSET + 2 + bytes.decode_u16(tag + TAG_NAME_OFFSET)
	return true


## The STRING at [param offset] (a WORD byte length, then that many bytes of UTF-8), or null when
## it runs past [param limit].
static func _string_at(bytes: PackedByteArray, offset: int, limit: int) -> Variant:
	if offset + 2 > limit:
		return null
	var end := offset + 2 + bytes.decode_u16(offset)
	if end > limit:
		return null
	return bytes.slice(offset + 2, end).get_string_from_utf8()


func _fail(path: String, problem: String, offset: int) -> Dictionary:
	last_error = "'%s' is damaged: %s (byte %d)." % [path, problem, offset]
	return {}
