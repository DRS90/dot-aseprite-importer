extends RefCounted
## Listing checks of the headless test runner. AsepriteFileReader has to read what Aseprite lists,
## on the example files and on sprites built by tests/tools/build_reader_cases.lua, and refuse a
## damaged file without reading past its end; AsepriteSource, which the importers share, has to
## cache the listing and find the executable without starting it. [param check] is the runner's own
## reporting function, so one run counts every failure.

const AsepriteCli := preload("res://addons/aseprite_topdown_grid_animations/aseprite_cli.gd")
const AsepriteSource := preload("res://addons/aseprite_topdown_grid_animations/aseprite_source.gd")
const AsepriteFileReader := preload(
	"res://addons/aseprite_topdown_grid_animations/aseprite_file_reader.gd"
)

const EXAMPLES: Array[String] = [
	"res://examples/retro-top-down-character.aseprite",
	"res://examples/shadow.aseprite",
	"res://examples/tileset.aseprite",
]
const CASES_SCRIPT := "res://tests/tools/build_reader_cases.lua"
## Built cases whose names are plain ASCII, so Aseprite's listing can be compared as a whole.
const ASCII_CASES: Array[String] = ["tilemap.aseprite", "tiny.aseprite"]
## Built case with non-ASCII names, whose listing through Aseprite garbles them on Windows.
const MIXED_CASE := "layers_and_tags.aseprite"
const ACCENTED_LAYER := "ação ✓"
const SOURCE := "res://examples/retro-top-down-character.aseprite"
const SPRITE_SIZE := Vector2i(144, 144)
const SHADOW := "res://examples/shadow.aseprite"
const SHADOW_SIZE := Vector2i(48, 48)

var _check: Callable
var _folder: String
var _reader := AsepriteFileReader.new()


## [param folder] is an absolute folder of its own, where the cases are built and damaged copies
## written.
func _init(check: Callable, folder: String) -> void:
	_check = check
	_folder = folder


## The checks that need Aseprite.
func run(cli: AsepriteCli) -> void:
	if _build_cases(cli):
		_test_same_as_aseprite(cli)
		_test_mixed_case(cli)
	_test_executable(cli.get_executable())


## The checks that run without Aseprite, so CI covers them whatever it has installed.
func run_without_aseprite() -> void:
	_test_did_not_run()
	_test_missing_script()
	if FileAccess.file_exists(EXAMPLES[0]) and FileAccess.file_exists(SHADOW):
		DirAccess.make_dir_recursive_absolute(_folder)
		_test_damaged()
		_test_source_cache()
		_test_missing_executable()


## Runs build_reader_cases.lua once; false after reporting why it failed.
func _build_cases(cli: AsepriteCli) -> bool:
	DirAccess.make_dir_recursive_absolute(_folder)
	var args := PackedStringArray(
		[
			"-b",
			"--script-param",
			"out=" + _folder,
			"--script",
			ProjectSettings.globalize_path(CASES_SCRIPT),
		]
	)
	var output: Array = []
	var code := OS.execute(cli.get_executable(), args, output, true)
	var built := code == 0 and FileAccess.file_exists(_folder.path_join(MIXED_CASE))
	return _check.call(built, "the reader's test sprites are built", "%d %s" % [code, output])


func _test_same_as_aseprite(cli: AsepriteCli) -> void:
	var paths := PackedStringArray()
	for example: String in EXAMPLES:
		paths.append(ProjectSettings.globalize_path(example))
	for case: String in ASCII_CASES:
		paths.append(_folder.path_join(case))
	var different := PackedStringArray()
	for path: String in paths:
		var read := _reader.read(path)
		var listed := cli.list_contents(path)
		if read.is_empty() or read != listed:
			different.append("%s: %s / %s %s" % [path.get_file(), read, listed, _reader.last_error])
	_check.call(
		different.is_empty(),
		"the file reader lists what Aseprite lists (%d files)" % paths.size(),
		"\n".join(different)
	)


## Groups, hidden layers, every tag direction, a repeat count, a tag name used twice and a duration
## per frame, checked against the values the build script set, since Aseprite's listing garbles the
## non-ASCII name on Windows. Everything but the names is also compared with that listing.
func _test_mixed_case(cli: AsepriteCli) -> void:
	var path := _folder.path_join(MIXED_CASE)
	var read := _reader.read(path)
	var expected := {
		"size": Vector2i(20, 10),
		"layers":
		PackedStringArray(["base", "armor, plate", "hidden:fx", ACCENTED_LAYER, "_guide"]),
		"visible_layers": PackedStringArray(["base", "armor, plate", ACCENTED_LAYER]),
		"tags": PackedStringArray(["t1", "t2", "t3", "t4", "t1", "single frame"]),
		"tag_ranges":
		{
			"t1": {"from": 0, "to": 1, "direction": "forward"},
			"t2": {"from": 1, "to": 2, "direction": "reverse"},
			"t3": {"from": 2, "to": 3, "direction": "pingpong"},
			"t4": {"from": 3, "to": 4, "direction": "pingpong_reverse"},
			"single frame": {"from": 8, "to": 8, "direction": "forward"},
		},
		"frame_durations": PackedInt32Array([17, 34, 51, 68, 85, 102, 119, 136, 153]),
	}
	_check.call(
		read == expected,
		"the reader lists nested groups, hidden layers, non-ASCII names and every tag direction",
		"%s %s" % [read, _reader.last_error]
	)
	var listed := cli.list_contents(path)
	var mismatched := PackedStringArray()
	for key: String in ["size", "tags", "tag_ranges", "frame_durations"]:
		if read.get(key) != listed.get(key):
			mismatched.append("%s: %s / %s" % [key, read.get(key), listed.get(key)])
	_check.call(
		mismatched.is_empty(),
		"tag ranges, directions and durations match Aseprite's listing",
		"\n".join(mismatched)
	)

	# The name read from the file is the one the export script finds in the sprite.
	var job := {
		"direction": "",
		"tag": "t1",
		"animation": "t1",
		"loop": false,
		"relative_path": "accented.png",
	}
	var jobs: Array[Dictionary] = [job]
	var layers := PackedStringArray([ACCENTED_LAYER])
	var strips_dir := _folder.path_join("accented")
	var error := cli.export_strips(path, jobs, layers, Vector2i(20, 10), 1, strips_dir)
	_check.call(
		error == OK and cli.last_written == PackedStringArray(["accented.png"]),
		"a non-ASCII layer name read from the file exports its layer",
		"%s %s %s" % [error_string(error), cli.last_written, cli.last_error]
	)


## Damaged copies of the example: every one is refused with a message, and the frame fields the
## reader falls back on behave like Aseprite's decoder.
func _test_damaged() -> void:
	var bytes := FileAccess.get_file_as_bytes(EXAMPLES[0])
	var original := _reader.read(EXAMPLES[0])
	var refused := PackedStringArray()
	var cuts := [0, 100, 128, 150, bytes.size() / 2, bytes.size() - 1]
	for size: int in cuts:
		if not _read_copy(bytes.slice(0, size)).is_empty() or _reader.last_error == "":
			refused.append("cut at %d" % size)
	var wrong_magic := bytes.duplicate()
	wrong_magic.encode_u16(4, 0x1234)
	if not _read_copy(wrong_magic).is_empty():
		refused.append("file magic")
	var empty_chunk := bytes.duplicate()
	empty_chunk.encode_u32(AsepriteFileReader.HEADER_SIZE + AsepriteFileReader.FRAME_HEADER_SIZE, 0)
	if not _read_copy(empty_chunk).is_empty():
		refused.append("chunk of size 0")
	_check.call(refused.is_empty(), "damaged files are refused with a message", ", ".join(refused))

	# A frame duration of 0 means the header's, and so does a frame without its magic number, which
	# keeps its place. The header's speed is set apart from the example's 100 ms to tell them apart.
	var old_style := bytes.duplicate()
	var header_speed := 77
	old_style.encode_u16(AsepriteFileReader.HEADER_SPEED, header_speed)
	var first_frame := AsepriteFileReader.HEADER_SIZE
	old_style.encode_u16(first_frame + 8, 0)
	var second_frame := first_frame + old_style.decode_u32(first_frame)
	old_style.encode_u16(second_frame + 4, 0)
	var read := _read_copy(old_style)
	var durations: PackedInt32Array = read.get("frame_durations", PackedInt32Array())
	var expected := (
		(original.get("frame_durations", PackedInt32Array()) as PackedInt32Array).duplicate()
	)
	expected[0] = header_speed
	expected[1] = header_speed
	_check.call(
		durations == expected and read.get("layers") == original.get("layers"),
		"a frame of 0 ms takes the header's duration, and a frame without its magic is skipped",
		"%s (header %d) %s" % [durations, header_speed, _reader.last_error]
	)


## The source shared by the importers: it finds the executable without starting it, reads and
## caches a listing by file content and hands out the layer dropdown. Headless, so the executable
## arrives as a Callable instead of from the Editor Settings.
func _test_executable(executable: String) -> void:
	var source := AsepriteSource.new(func() -> String: return executable)
	_check.call(
		source.verified_cli() != null, "the shared source finds the executable", source.last_error
	)
	_test_path_lookup(executable)


## The listing cache and the dropdown, which need no Aseprite. A hit compares the MD5 streamed from
## the file with the one hashed from the bytes parsed on the miss, so a cached dictionary coming
## back proves both are spelled alike.
func _test_source_cache() -> void:
	var source := AsepriteSource.new(func() -> String: return "")
	var first := source.list(SOURCE)
	var second := source.list(SOURCE)
	_check.call(
		is_same(first, second) and first.get("size", Vector2i.ZERO) == SPRITE_SIZE,
		"listing the same file twice returns the cached dictionary",
		"%s %s" % [first.get("size", Vector2i.ZERO), source.last_error]
	)

	# Keyed by content, not by path: a file replaced under the same name has to be listed again.
	var copy := "user://aseprite_source_copy.aseprite"
	DirAccess.copy_absolute(SOURCE, copy)
	var before: Vector2i = source.list(copy).get("size", Vector2i.ZERO)
	DirAccess.copy_absolute(SHADOW, copy)
	var after: Vector2i = source.list(copy).get("size", Vector2i.ZERO)
	DirAccess.remove_absolute(copy)
	_check.call(
		before == SPRITE_SIZE and after == SHADOW_SIZE,
		"a file replaced under the same path is listed again",
		"%s then %s" % [before, after]
	)

	_check.call(
		source.layer_choices(SOURCE) == "[all],character,weapon",
		"the layer dropdown offers [all] and the file's layers",
		source.layer_choices(SOURCE)
	)
	_check.call(
		source.layer_choices("") == "[all]",
		"without a file the dropdown offers [all] alone",
		source.layer_choices("")
	)


## A missing executable is found out without starting a process, and the file is still read.
func _test_missing_executable() -> void:
	var missing_name := "no-such-aseprite-anywhere"
	var bare := AsepriteSource.new(func() -> String: return missing_name)
	var absent_path := _folder.path_join("missing/Aseprite.exe")
	var absent := AsepriteSource.new(func() -> String: return absent_path)
	_check.call(
		(
			bare.verified_cli() == null
			and bare.last_error.contains(missing_name)
			and absent.verified_cli() == null
			and absent.last_error.contains("ASEPRITE_PATH")
		),
		"a name missing from the PATH or a path to nothing is reported, with where to set it",
		"%s | %s" % [bare.last_error, absent.last_error]
	)
	_check.call(
		bare.layer_choices(SOURCE) == "[all],character,weapon",
		"the layer dropdown reads the file without Aseprite",
		bare.layer_choices(SOURCE)
	)


## A bare name is looked up in the PATH, as the OS would.
func _test_path_lookup(executable: String) -> void:
	var resolved := AsepriteCli.find_executable(executable)
	var saved_path := OS.get_environment("PATH")
	OS.set_environment("PATH", resolved.get_base_dir())
	# Only a Windows extension goes: a Linux build may be named aseprite-1.3.18.
	var bare_name := resolved.get_file()
	if OS.get_name() == "Windows":
		bare_name = bare_name.get_basename()
	var found := AsepriteCli.find_executable(bare_name)
	OS.set_environment("PATH", saved_path)
	_check.call(
		found != "" and FileAccess.file_exists(found),
		"a bare name is found in the PATH",
		"%s in %s" % [found, resolved.get_base_dir()]
	)


## Aseprite exits without a word for a script that is not there, so the wrapper checks for it
## first and names it, instead of blaming the executable. Nothing is started.
func _test_missing_script() -> void:
	var cli := AsepriteCli.new("unused")
	cli._batch_script = _folder.path_join("moved/aseprite_batch.lua")
	var job := {
		"direction": "", "tag": "", "animation": "a", "loop": false, "relative_path": "a.png"
	}
	var jobs: Array[Dictionary] = [job]
	var layers := PackedStringArray(["layer"])
	var error := cli.export_strips("x.aseprite", jobs, layers, Vector2i.ONE, 1, _folder)
	_check.call(
		error != OK and cli.last_error.contains("moved/aseprite_batch.lua"),
		"a missing batch script is named instead of the executable being blamed",
		cli.last_error
	)


## A run that never started is told from a Lua error by its output, on each platform. Checked on
## made-up outputs: a real failed start prints an engine error on Windows.
func _test_did_not_run() -> void:
	var lua_error := "batch.lua:1: unknown layer 'x'"
	# [exit code, output, on Windows, expected]
	var cases := [
		[-1, "", true, true],
		[0, "", true, true],
		[-1, lua_error, true, false],
		[127, "sh: 1: aseprite: not found", false, true],
		[126, "sh: 1: ./aseprite: Permission denied", false, true],
		[127, lua_error, false, false],
		[1, "sh: not the shell's own failure", false, false],
	]
	var wrong := PackedStringArray()
	for case: Array in cases:
		if AsepriteCli.did_not_run(case[0], case[1], case[2]) != case[3]:
			wrong.append(str(case))
	_check.call(
		wrong.is_empty(),
		"a run that never started is told from a script error by its output",
		", ".join(wrong)
	)


func _read_copy(bytes: PackedByteArray) -> Dictionary:
	var path := _folder.path_join("damaged.aseprite")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()
	return _reader.read(path)
