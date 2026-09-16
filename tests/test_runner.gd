extends SceneTree
## Headless test runner. Needs the Aseprite executable in the ASEPRITE_PATH environment variable:
##   ASEPRITE_PATH=<aseprite> godot --headless --path . -s tests/test_runner.gd
## Prints one PASS/FAIL line per check and exits with 1 when any check fails.

const AnimationLibraryStore := preload(
	"res://addons/aseprite_topdown_grid_animations/animation_library_store.gd"
)
const AnimationSync := preload("res://addons/aseprite_topdown_grid_animations/animation_sync.gd")
const AsepriteCli := preload("res://addons/aseprite_topdown_grid_animations/aseprite_cli.gd")
const ExportPlanner := preload("res://addons/aseprite_topdown_grid_animations/export_planner.gd")
const SpriteFramesBuilder := preload(
	"res://addons/aseprite_topdown_grid_animations/sprite_frames_builder.gd"
)

const SOURCE := "res://examples/retro-top-down-character.aseprite"
## Resources are written here: ResourceSaver needs a Godot path, not the native cache directory.
const LIBRARY_DIR := "user://aseprite_topdown_grid_animations_tests"
const LIBRARY_TEMPLATE := "{scene_dir}/{scene}_animations.tres"
const SHEETS_DIR := "res://examples/rpg-type-retro-top-down-playable-character-spritesheett"
const SHEET := SHEETS_DIR + "/16x16-rpg-topdown-playable-character-template.png"
const ATTACK_SHEET := SHEETS_DIR + "/48x48-attack.png"
const SPRITE_SIZE := Vector2i(144, 144)
const CELL_SIZE := Vector2i(48, 48)
const CHARACTER_SIZE := 16
const FRAME_COUNT := 44
## First sheet column of the slash tag, the only one with a sword effect.
const SLASH_FIRST := 32
const EXPECTED_LAYERS: Array[String] = ["character", "weapon"]
const EXPECTED_TAGS: Array[String] = [
	"walk_loop",
	"push_loop",
	"pull_loop",
	"carry_loop",
	"pickup",
	"throw",
	"use",
	"slash",
	"swim_loop",
	"climb_loop",
]
## Sheet row of every direction drawn in the example; its diagonal cells are empty.
const SHEET_ROWS := {"down": 0, "up": 1, "left": 2, "right": 3}
const DEFAULT_OPTIONS := {
	"cell_size": Vector2i.ZERO,
	"layer": "[all]",
	"layer_exclude_pattern": "^_",
	"tag_exclude_pattern": "^_",
	"animation_name": "{tag}_{direction}",
	"loop_suffix": "_loop",
}
const ASSET_HELP := (
	"The example is built from the CC0 sheets of 5yvalia with "
	+ "tests/tools/build_retro_example.lua; see README > Credits."
)

var _failures := 0
var _tmp_dir := OS.get_cache_dir().path_join("aseprite_topdown_grid_animations_tests")


func _initialize() -> void:
	var missing := _missing_example_files()
	if missing.is_empty():
		_test_with_example_asset()
	else:
		print("SKIP: Aseprite checks, example files not found: %s" % ", ".join(missing))
		print("SKIP: " + ASSET_HELP)
	_test_planner_edge_cases()
	_test_builder()
	_test_animation_sync()
	_test_animation_library_store()
	print("%s: %d failure(s)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(0 if _failures == 0 else 1)


func _missing_example_files() -> PackedStringArray:
	var missing := PackedStringArray()
	for path: String in [SOURCE, SHEET, ATTACK_SHEET]:
		if not FileAccess.file_exists(path):
			missing.append(path)
	return missing


func _test_with_example_asset() -> void:
	var cli := AsepriteCli.new(OS.get_environment("ASEPRITE_PATH"))
	_check(cli.is_available(), "Aseprite executable available", cli.get_executable())
	if not cli.is_available():
		return
	var contents := _test_listing(cli)
	var planner := ExportPlanner.new()
	var jobs := _test_planner(planner, contents)
	_test_sprite_frames(cli, planner, jobs, contents)
	_test_export_rejects_bad_input(cli)


func _test_listing(cli: AsepriteCli) -> Dictionary:
	var contents := cli.list_contents(ProjectSettings.globalize_path(SOURCE))
	var size: Vector2i = contents.get("size", Vector2i.ZERO)
	_check(size == SPRITE_SIZE, "list_contents returns the size", "%s %s" % [size, cli.last_error])
	var layers: PackedStringArray = contents.get("layers", PackedStringArray())
	_check(
		layers == PackedStringArray(EXPECTED_LAYERS), "list_contents returns layers", str(layers)
	)
	var visible: PackedStringArray = contents.get("visible_layers", PackedStringArray())
	_check(
		visible == PackedStringArray(EXPECTED_LAYERS),
		"list_contents returns visible layers",
		str(visible)
	)
	var tags: PackedStringArray = contents.get("tags", PackedStringArray())
	_check(tags == PackedStringArray(EXPECTED_TAGS), "list_contents returns 10 tags", str(tags))
	var ranges: Dictionary = contents.get("tag_ranges", {})
	_check(
		ranges.get("walk_loop", {}) == {"from": 0, "to": 3, "direction": "forward"},
		"list_contents returns tag ranges and directions",
		str(ranges)
	)
	var durations: PackedInt32Array = contents.get("frame_durations", PackedInt32Array())
	_check(
		durations.size() == FRAME_COUNT and durations.count(100) == FRAME_COUNT,
		"list_contents returns 44 frame durations of 100 ms",
		str(durations)
	)
	return contents


func _test_planner(planner: ExportPlanner, contents: Dictionary) -> Array[Dictionary]:
	var size: Vector2i = contents.get("size", Vector2i.ZERO)
	var layers: PackedStringArray = contents.get("layers", PackedStringArray())
	var tags: PackedStringArray = contents.get("tags", PackedStringArray())
	var jobs := planner.build_jobs(size, layers, tags, DEFAULT_OPTIONS)
	_check(jobs.size() == 80, "planner builds 8 directions x 10 tags", str(jobs.size()))
	_check(
		not planner.failed and planner.errors.is_empty(),
		"planner reports no errors",
		str(planner.errors)
	)
	_check(planner.cell_size == CELL_SIZE, "cell is a third of the sprite", str(planner.cell_size))
	_check(
		planner.composed_layers == PackedStringArray(EXPECTED_LAYERS),
		"every layer is composed",
		str(planner.composed_layers)
	)
	var walk := _find_job(jobs, "walk_down")
	_check(
		walk.get("tag") == "walk_loop" and walk.get("loop") == true,
		"walk_loop becomes the looping animation walk_down",
		str(walk)
	)
	var slash := _find_job(jobs, "slash_left")
	_check(
		slash.get("tag") == "slash" and slash.get("loop") == false,
		"slash keeps its name and does not loop",
		str(slash)
	)
	return jobs


## All 80 jobs in one Aseprite process, then the SpriteFrames: the diagonals and the sides of climb
## give no animation, and every frame matches the CC0 sheets the example was built from.
func _test_sprite_frames(
	cli: AsepriteCli, planner: ExportPlanner, jobs: Array[Dictionary], contents: Dictionary
) -> void:
	var strips_dir := _tmp_dir.path_join("strips")
	var code := cli.export_strips(
		ProjectSettings.globalize_path(SOURCE),
		jobs,
		planner.composed_layers,
		planner.cell_size,
		strips_dir
	)
	_check(
		code == OK and cli.last_written.size() == 38,
		"export_strips writes 38 of 80 strips",
		"%d written, %s" % [cli.last_written.size(), cli.last_error]
	)
	var builder := SpriteFramesBuilder.new()
	var frames := builder.build(jobs, cli.last_written, strips_dir, contents, planner.cell_size)
	var names := frames.get_animation_names()
	_check(
		(
			builder.errors.is_empty()
			and names.size() == 38
			and not frames.has_animation(&"walk_left_up")
			and not frames.has_animation(&"climb_left")
		),
		"SpriteFrames has 38 animations, none for the empty cells",
		"%s %s" % [names, builder.errors]
	)
	if not frames.has_animation(&"walk_down"):
		_check(false, "SpriteFrames has walk_down", str(names))
		return
	_check(
		(
			frames.get_frame_count(&"walk_down") == 4
			and is_equal_approx(frames.get_animation_speed(&"walk_down"), 10.0)
			and frames.get_frame_duration(&"walk_down", 3) == 1.0
			and frames.get_animation_loop(&"walk_down")
			and frames.get_frame_count(&"use_left") == 8
			and not frames.get_animation_loop(&"slash_right")
		),
		"walk_down loops with 4 frames at 10 fps, use_left has 8, slash_right does not loop"
	)
	_test_frames_match_sheets(frames, jobs, contents)


func _test_frames_match_sheets(
	frames: SpriteFrames, jobs: Array[Dictionary], contents: Dictionary
) -> void:
	var sheet := Image.load_from_file(ProjectSettings.globalize_path(SHEET))
	var attack := Image.load_from_file(ProjectSettings.globalize_path(ATTACK_SHEET))
	sheet.convert(Image.FORMAT_RGBA8)
	attack.convert(Image.FORMAT_RGBA8)
	var ranges: Dictionary = contents.get("tag_ranges", {})
	var checked := 0
	var matching := 0
	for job: Dictionary in jobs:
		var animation := StringName(str(job["animation"]))
		var direction: String = job["direction"]
		if not frames.has_animation(animation) or not SHEET_ROWS.has(direction):
			continue
		var tag_range: Dictionary = ranges[job["tag"]]
		var first: int = tag_range["from"]
		var row: int = SHEET_ROWS[direction]
		for index: int in frames.get_frame_count(animation):
			var frame := frames.get_frame_texture(animation, index).get_image()
			frame.convert(Image.FORMAT_RGBA8)
			checked += 1
			if frame.get_data() == _expected_frame(sheet, attack, first + index, row).get_data():
				matching += 1
	_check(
		checked == 168 and matching == checked,
		"every frame matches the sheets the example was built from",
		"%d of %d" % [matching, checked]
	)


## The cell the example should hold for one sheet column and row: the character centered, plus the
## sword effect of the slash columns.
func _expected_frame(sheet: Image, attack: Image, column: int, row: int) -> Image:
	var expected := Image.create_empty(CELL_SIZE.x, CELL_SIZE.y, false, Image.FORMAT_RGBA8)
	var character := sheet.get_region(
		Rect2i(column * CHARACTER_SIZE, row * CHARACTER_SIZE, CHARACTER_SIZE, CHARACTER_SIZE)
	)
	var offset := (CELL_SIZE.x - CHARACTER_SIZE) / 2
	expected.blit_rect(
		character, Rect2i(0, 0, CHARACTER_SIZE, CHARACTER_SIZE), Vector2i(offset, offset)
	)
	var effect_column := column - SLASH_FIRST
	if effect_column >= 0 and (effect_column + 1) * CELL_SIZE.x <= attack.get_width():
		var effect := attack.get_region(
			Rect2i(effect_column * CELL_SIZE.x, row * CELL_SIZE.y, CELL_SIZE.x, CELL_SIZE.y)
		)
		expected.blend_rect(effect, Rect2i(Vector2i.ZERO, CELL_SIZE), Vector2i.ZERO)
	return expected


func _test_export_rejects_bad_input(cli: AsepriteCli) -> void:
	var layers := PackedStringArray(["character"])
	var ghost := PackedStringArray(["ghost"])
	_expect_rejected(
		cli, "an unknown layer", ghost, CELL_SIZE, "walk_loop", "up", "unknown layer 'ghost'"
	)
	_expect_rejected(cli, "an unknown tag", layers, CELL_SIZE, "nope", "up", "unknown tag 'nope'")
	_expect_rejected(
		cli, "an unknown direction", layers, CELL_SIZE, "walk_loop", "center", "unknown direction"
	)
	_expect_rejected(
		cli, "a cell too big", layers, Vector2i(50, 48), "walk_loop", "up", "does not fit"
	)


func _expect_rejected(
	cli: AsepriteCli,
	description: String,
	layers: PackedStringArray,
	cell: Vector2i,
	tag: String,
	direction: String,
	expected_error: String
) -> void:
	var jobs: Array[Dictionary] = [
		{
			"direction": direction,
			"tag": tag,
			"animation": "rejected",
			"loop": false,
			"relative_path": "rejected.png",
		}
	]
	var code := cli.export_strips(
		ProjectSettings.globalize_path(SOURCE), jobs, layers, cell, _tmp_dir.path_join("rejected")
	)
	_check(
		code != OK and cli.last_error.contains(expected_error),
		"export_strips rejects " + description,
		cli.last_error
	)


func _test_planner_edge_cases() -> void:
	var planner := ExportPlanner.new()
	var layers := PackedStringArray(["body", "_guide", "fx"])
	var tags := PackedStringArray(EXPECTED_TAGS)

	var jobs := planner.build_jobs(SPRITE_SIZE, layers, tags, DEFAULT_OPTIONS)
	_check(
		jobs.size() == 80 and planner.composed_layers == PackedStringArray(["body", "fx"]),
		"[all] composes every layer not excluded",
		str(planner.composed_layers)
	)

	var options := DEFAULT_OPTIONS.duplicate()
	options["tag_exclude_pattern"] = "^(push_loop|pull_loop)$"
	jobs = planner.build_jobs(SPRITE_SIZE, layers, tags, options)
	_check(jobs.size() == 64, "tag exclude pattern removes 2 tags", str(jobs.size()))

	jobs = planner.build_jobs(SPRITE_SIZE, layers, PackedStringArray(), DEFAULT_OPTIONS)
	_check(
		jobs.size() == 8 and _find_job(jobs, "up").get("tag") == "",
		"no tags: one animation per direction named after it",
		str(jobs.map(func(job: Dictionary) -> String: return job["animation"]))
	)

	options = DEFAULT_OPTIONS.duplicate()
	options["animation_name"] = "{direction}"
	jobs = planner.build_jobs(SPRITE_SIZE, layers, tags, options)
	_check(
		jobs.size() == 8 and planner.errors.size() == 72,
		"animation names used twice are skipped and reported",
		"%d jobs, %d errors" % [jobs.size(), planner.errors.size()]
	)

	var same_names := PackedStringArray(["idle", "idle_loop"])
	jobs = planner.build_jobs(SPRITE_SIZE, layers, same_names, DEFAULT_OPTIONS)
	_check(
		jobs.size() == 8 and planner.errors.size() == 8,
		"idle and idle_loop give the same names: the second is reported",
		str(planner.errors)
	)

	jobs = planner.build_jobs(
		SPRITE_SIZE, layers, PackedStringArray(["attack/heavy"]), DEFAULT_OPTIONS
	)
	_check(
		not _find_job(jobs, "attack_heavy_up").is_empty(),
		"characters invalid in animation names become _",
		str(jobs.map(func(job: Dictionary) -> String: return job["animation"]))
	)
	_test_loop_suffix(planner, layers)
	_test_layer_choice(planner, layers, tags)
	_test_cell_size(planner, layers, tags)


func _test_loop_suffix(planner: ExportPlanner, layers: PackedStringArray) -> void:
	var options := DEFAULT_OPTIONS.duplicate()
	options["loop_suffix"] = "_repeat"
	var tags := PackedStringArray(["idle_repeat", "run_loop"])
	var jobs := planner.build_jobs(SPRITE_SIZE, layers, tags, options)
	var idle := _find_job(jobs, "idle_up")
	var run := _find_job(jobs, "run_loop_up")
	_check(
		idle.get("loop") == true and run.get("loop") == false,
		"a custom loop suffix decides the loop and leaves other suffixes in the name",
		"%s %s" % [idle, run]
	)

	options["loop_suffix"] = ""
	jobs = planner.build_jobs(SPRITE_SIZE, layers, tags, options)
	var plain := _find_job(jobs, "idle_repeat_up")
	_check(
		plain.get("loop") == false and _find_job(jobs, "run_loop_up").get("loop") == false,
		"an empty loop suffix loops nothing and keeps the tag names",
		str(plain)
	)


func _test_layer_choice(
	planner: ExportPlanner, layers: PackedStringArray, tags: PackedStringArray
) -> void:
	var options := DEFAULT_OPTIONS.duplicate()
	options["layer"] = ""
	var jobs := planner.build_jobs(SPRITE_SIZE, layers, tags, options)
	_check(
		jobs.size() == 80 and planner.composed_layers == PackedStringArray(["body", "fx"]),
		"an empty layer choice means [all]",
		str(planner.composed_layers)
	)

	options["layer"] = "fx"
	jobs = planner.build_jobs(SPRITE_SIZE, layers, tags, options)
	_check(
		(
			jobs.size() == 80
			and planner.errors.is_empty()
			and planner.composed_layers == PackedStringArray(["fx"])
		),
		"a chosen layer is composed alone",
		str(planner.composed_layers)
	)

	options["layer"] = "_guide"
	jobs = planner.build_jobs(SPRITE_SIZE, layers, tags, options)
	_check(
		jobs.size() == 80 and planner.composed_layers == PackedStringArray(["_guide"]),
		"an excluded layer can still be chosen",
		str(planner.composed_layers)
	)

	options["layer"] = "ghost"
	jobs = planner.build_jobs(SPRITE_SIZE, layers, tags, options)
	_check(
		jobs.is_empty() and planner.failed and planner.errors.size() == 2,
		"an unknown chosen layer fails",
		str(planner.errors)
	)

	options["layer"] = "[all]"
	options["layer_exclude_pattern"] = "."
	jobs = planner.build_jobs(SPRITE_SIZE, layers, tags, options)
	_check(jobs.is_empty() and planner.failed, "every layer excluded fails", str(planner.errors))


func _test_cell_size(
	planner: ExportPlanner, layers: PackedStringArray, tags: PackedStringArray
) -> void:
	var options := DEFAULT_OPTIONS.duplicate()
	options["cell_size"] = CELL_SIZE
	var jobs := planner.build_jobs(SPRITE_SIZE, layers, tags, options)
	_check(
		jobs.size() == 80 and planner.cell_size == CELL_SIZE,
		"explicit cell size equal to the default",
		str(planner.cell_size)
	)

	options["cell_size"] = Vector2i(40, 0)
	jobs = planner.build_jobs(SPRITE_SIZE, layers, tags, options)
	_check(
		jobs.size() == 80 and planner.cell_size == Vector2i(40, 48),
		"smaller cell width, 0 height is a third",
		str(planner.cell_size)
	)

	for cell: Vector2i in [Vector2i(50, 48), Vector2i(-1, 48), Vector2i(48, 49)]:
		options["cell_size"] = cell
		jobs = planner.build_jobs(SPRITE_SIZE, layers, tags, options)
		_check(
			jobs.is_empty() and planner.failed and planner.cell_size == Vector2i.ZERO,
			"cell size %s does not fit" % cell,
			str(planner.errors)
		)

	jobs = planner.build_jobs(Vector2i(145, 144), layers, tags, DEFAULT_OPTIONS)
	_check(
		jobs.is_empty() and planner.failed,
		"default cell needs a size multiple of 3",
		str(planner.errors)
	)


func _test_builder() -> void:
	var sequences := {
		"forward": PackedInt32Array([2, 3, 4, 5]),
		"reverse": PackedInt32Array([5, 4, 3, 2]),
		"pingpong": PackedInt32Array([2, 3, 4, 5, 4, 3]),
		"pingpong_reverse": PackedInt32Array([5, 4, 3, 2, 3, 4]),
	}
	for direction: String in sequences:
		var sequence := SpriteFramesBuilder.frame_sequence(2, 5, direction)
		_check(sequence == sequences[direction], direction + " frame sequence", str(sequence))
	var single := SpriteFramesBuilder.frame_sequence(3, 3, "pingpong")
	_check(single == PackedInt32Array([3]), "ping-pong of one frame plays it once", str(single))

	var timing := SpriteFramesBuilder.timing(PackedInt32Array([150, 50, 100]))
	var speed: float = timing["speed"]
	_check(
		is_equal_approx(speed, 20.0) and timing["durations"] == PackedFloat32Array([3.0, 1.0, 2.0]),
		"timing: speed is 1 / the shortest duration, durations are relative to it",
		str(timing)
	)
	_test_builder_ping_pong()


## A ping-pong tag over timeline frames 1 to 3 of a synthetic strip: cells are reused in the
## sequence 1 2 3 2, each frame keeps its Aseprite duration relative to the shortest one.
func _test_builder_ping_pong() -> void:
	var strips_dir := _tmp_dir.path_join("synthetic")
	DirAccess.make_dir_recursive_absolute(strips_dir)
	var strip := Image.create_empty(12, 4, false, Image.FORMAT_RGBA8)
	for index: int in 3:
		strip.fill_rect(Rect2i(index * 4, 0, 4, 4), Color(index / 2.0, 0.0, 0.0))
	strip.save_png(strips_dir.path_join("strip_000.png"))
	var jobs: Array[Dictionary] = [
		{
			"direction": "up",
			"tag": "bounce_loop",
			"animation": "bounce_up",
			"loop": true,
			"relative_path": "strip_000.png",
		}
	]
	var contents := {
		"tag_ranges": {"bounce_loop": {"from": 1, "to": 3, "direction": "pingpong"}},
		"frame_durations": PackedInt32Array([100, 100, 100, 200]),
	}
	var builder := SpriteFramesBuilder.new()
	var written := PackedStringArray(["strip_000.png"])
	var frames := builder.build(jobs, written, strips_dir, contents, Vector2i(4, 4))
	var regions: Array[float] = []
	var durations: Array[float] = []
	for index: int in frames.get_frame_count(&"bounce_up"):
		var atlas := frames.get_frame_texture(&"bounce_up", index) as AtlasTexture
		regions.append(atlas.region.position.x)
		durations.append(frames.get_frame_duration(&"bounce_up", index))
	_check(
		(
			builder.errors.is_empty()
			and regions == [0.0, 4.0, 8.0, 4.0]
			and durations == [1.0, 1.0, 2.0, 1.0]
			and frames.get_animation_loop(&"bounce_up")
			and is_equal_approx(frames.get_animation_speed(&"bounce_up"), 10.0)
		),
		"ping-pong animation reuses cells with Aseprite durations",
		"%s %s %s" % [regions, durations, builder.errors]
	)


## A sprite and an AnimationPlayer side by side under one root in the scene tree. The player's
## "idle_down" already has a user track on the sprite's modulate, and "old_down" only this sprite's
## tracks from an earlier sync.
func _test_animation_sync() -> void:
	var root := Node2D.new()
	var sprite := AnimatedSprite2D.new()
	sprite.name = "Body"
	root.add_child(sprite)
	var player := AnimationPlayer.new()
	root.add_child(player)
	get_root().add_child(root)

	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	for animation: StringName in [&"idle_down", &"hit_down"]:
		frames.add_animation(animation)
		frames.set_animation_speed(animation, 10.0)
		frames.set_animation_loop(animation, animation == &"idle_down")
	var texture := PlaceholderTexture2D.new()
	for duration: float in [1.0, 2.0, 1.0]:
		frames.add_frame(&"idle_down", texture, duration)
	for duration: float in [1.0, 1.0]:
		frames.add_frame(&"hit_down", texture, duration)
	sprite.sprite_frames = frames

	var library := AnimationLibrary.new()
	var user_animation := Animation.new()
	var user_track := user_animation.add_track(Animation.TYPE_VALUE)
	user_animation.track_set_path(user_track, "Body:modulate")
	user_animation.track_insert_key(user_track, 0.0, Color.WHITE)
	library.add_animation(&"idle_down", user_animation)
	var old_animation := Animation.new()
	var old_track := old_animation.add_track(Animation.TYPE_VALUE)
	old_animation.track_set_path(old_track, "Body:frame")
	library.add_animation(&"old_down", old_animation)
	player.add_animation_library(&"", library)

	var sync := AnimationSync.new()
	var written := sync.sync(sprite, player)
	written.sort()
	_check(
		sync.errors.is_empty() and written == PackedStringArray(["hit_down", "idle_down"]),
		"sync writes one animation per SpriteFrames animation",
		"%s %s" % [written, sync.errors]
	)
	_check_synced_idle(library)
	_check(
		not library.has_animation(&"old_down"),
		"an animation left with only this sprite's old tracks is removed",
		str(library.get_animation_list())
	)
	var hit := library.get_animation(&"hit_down")
	_check(
		hit.loop_mode == Animation.LOOP_NONE and is_equal_approx(hit.length, 0.2),
		"a non-looping animation does not loop and lasts its frames",
		"%s %s" % [hit.loop_mode, hit.length]
	)

	player.play(&"idle_down")
	player.seek(0.15, true)
	_check(
		sprite.animation == &"idle_down" and sprite.frame == 1,
		"the AnimationPlayer drives the sprite's animation and frame",
		"%s %d" % [sprite.animation, sprite.frame]
	)
	player.stop()
	_test_sync_linked(sync, sprite, player, library)
	root.queue_free()


func _check_synced_idle(library: AnimationLibrary) -> void:
	var idle := library.get_animation(&"idle_down")
	var frame_track := idle.find_track("Body:frame", Animation.TYPE_VALUE)
	var times: Array[float] = []
	var values: Array[int] = []
	for key: int in idle.track_get_key_count(frame_track):
		times.append(snappedf(idle.track_get_key_time(frame_track, key), 0.0001))
		values.append(idle.track_get_key_value(frame_track, key))
	var animation_track := idle.find_track("Body:animation", Animation.TYPE_VALUE)
	_check(
		(
			idle.get_track_count() == 3
			and idle.track_get_path(0) == NodePath("Body:modulate")
			and animation_track == 1
			and idle.track_get_key_value(animation_track, 0) == &"idle_down"
			and times == [0.0, 0.1, 0.3]
			and values == [0, 1, 2]
			and is_equal_approx(idle.length, 0.4)
			and idle.loop_mode == Animation.LOOP_LINEAR
		),
		"idle_down keeps the user track and gets frame keys at the Aseprite times",
		(
			"%d tracks, times %s, values %s, length %s"
			% [idle.get_track_count(), times, values, idle.length]
		)
	)


func _test_sync_linked(
	sync: AnimationSync,
	sprite: AnimatedSprite2D,
	player: AnimationPlayer,
	library: AnimationLibrary
) -> void:
	_check(not sync.sync_linked(sprite, false), "sync_linked does nothing without a linked player")
	AnimationSync.link(sprite, player)
	_check(
		AnimationSync.linked_player(sprite) == player and sync.sync_linked(sprite, false),
		"a linked player is synced the first time"
	)
	_check(not sync.sync_linked(sprite, false), "sync_linked skips an unchanged SpriteFrames")
	sprite.sprite_frames.set_frame(&"idle_down", 1, PlaceholderTexture2D.new(), 3.0)
	_check(sync.sync_linked(sprite, false), "sync_linked syncs again when a duration changes")
	_check(
		(
			is_equal_approx(library.get_animation(&"idle_down").length, 0.5)
			and library.get_animation(&"idle_down").get_track_count() == 3
		),
		"a second sync replaces its tracks instead of adding more",
		str(library.get_animation(&"idle_down").get_track_count())
	)
	_check(sync.sync_linked(sprite, true), "force syncs even when nothing changed")


func _test_animation_library_store() -> void:
	_check(
		(
			AnimationLibraryStore.resolve_path(LIBRARY_TEMPLATE, "res://examples/main.tscn")
			== "res://examples/main_animations.tres"
		),
		"resolve_path replaces {scene_dir} and {scene}"
	)
	_check(
		AnimationLibraryStore.resolve_path("", "res://examples/main.tscn") == "",
		"an empty template keeps the library built in"
	)
	_check(
		AnimationLibraryStore.resolve_path(LIBRARY_TEMPLATE, "") == "",
		"a scene that was never saved keeps the library built in"
	)
	DirAccess.make_dir_recursive_absolute(LIBRARY_DIR)
	_test_library_created()
	_test_library_converted()
	_test_library_keeps_work()
	_test_sync_linked_writes_the_file()
	_remove_library_dir()


func _test_library_created() -> void:
	var store := AnimationLibraryStore.new()
	var player := AnimationPlayer.new()
	var built_in := store.library_for(player, "")
	_check(
		built_in.is_built_in() and player.has_animation_library(&"") and store.errors.is_empty(),
		"an empty path leaves the library built in",
		str(store.errors)
	)
	var path := LIBRARY_DIR + "/created.tres"
	var created := store.library_for(player, path)
	_check(
		(
			FileAccess.file_exists(path)
			and not created.is_built_in()
			and created.resource_path == path
			and player.get_animation_library(&"") == created
		),
		"a missing library file is created and assigned to the player",
		"%s %s" % [created.resource_path, store.errors]
	)
	var elsewhere := LIBRARY_DIR + "/elsewhere.tres"
	var kept := store.library_for(player, elsewhere)
	_check(
		kept == created and not FileAccess.file_exists(elsewhere),
		"a library that is already external is not moved",
		kept.resource_path
	)
	player.free()


func _test_library_converted() -> void:
	var player := AnimationPlayer.new()
	player.add_animation_library(&"", _library_with(&"idle_down", "Body:modulate"))
	var path := LIBRARY_DIR + "/converted.tres"
	var store := AnimationLibraryStore.new()
	store.library_for(player, path)
	# Fetched from the player: loading the saved file gives a different object.
	var converted := player.get_animation_library(&"")
	_check(
		(
			not converted.is_built_in()
			and converted.has_animation(&"idle_down")
			and converted.get_animation(&"idle_down").get_track_count() == 1
			and FileAccess.file_exists(path)
		),
		"a built-in library moves to the file with its animations and tracks",
		"%s %s" % [converted.resource_path, store.errors]
	)
	player.free()


## The user must not lose work: adopting a file that already exists keeps what only the built-in
## library had, and writes it, instead of dropping those animations.
func _test_library_keeps_work() -> void:
	var path := LIBRARY_DIR + "/converted.tres"
	var player := AnimationPlayer.new()
	player.add_animation_library(&"", _library_with(&"only_built_in", "Body:visible"))
	var store := AnimationLibraryStore.new()
	store.library_for(player, path)
	var merged := player.get_animation_library(&"")
	_check(
		(
			merged.has_animation(&"only_built_in")
			and merged.has_animation(&"idle_down")
			and store.errors.is_empty()
		),
		"animations only the built-in library had survive adopting an existing file",
		"%s %s" % [merged.get_animation_list(), store.errors]
	)
	var from_disk := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	var reloaded := from_disk as AnimationLibrary
	_check(
		reloaded != null and reloaded.has_animation(&"only_built_in"),
		"the kept animations are written to the file, not only held in memory",
		"" if reloaded == null else str(reloaded.get_animation_list())
	)
	player.free()


## A skipped sync must not create the file: the path is resolved before the key is compared.
func _test_sync_linked_writes_the_file() -> void:
	var previous: Variant = ProjectSettings.get_setting(
		AnimationLibraryStore.LIBRARY_PATH_KEY, AnimationLibraryStore.DEFAULT_LIBRARY_PATH
	)
	ProjectSettings.set_setting(AnimationLibraryStore.LIBRARY_PATH_KEY, LIBRARY_TEMPLATE)
	var root := Node2D.new()
	root.scene_file_path = LIBRARY_DIR + "/scene.tscn"
	var sprite := AnimatedSprite2D.new()
	sprite.name = "Body"
	root.add_child(sprite)
	sprite.owner = root
	var player := AnimationPlayer.new()
	root.add_child(player)
	player.owner = root
	player.root_node = player.get_path_to(root)
	var frames := SpriteFrames.new()
	frames.add_animation(&"idle_down")
	frames.add_frame(&"idle_down", PlaceholderTexture2D.new(), 1.0)
	sprite.sprite_frames = frames
	AnimationSync.link(sprite, player)

	var path := LIBRARY_DIR + "/scene_animations.tres"
	var sync := AnimationSync.new()
	_check(
		sync.sync_linked(sprite, false) and FileAccess.file_exists(path),
		"sync_linked writes the library named by the setting",
		str(sync.errors)
	)
	DirAccess.remove_absolute(path)
	_check(
		not sync.sync_linked(sprite, false) and not FileAccess.file_exists(path),
		"a sync that is skipped never touches the file system"
	)
	ProjectSettings.set_setting(AnimationLibraryStore.LIBRARY_PATH_KEY, previous)
	root.queue_free()


func _library_with(animation_name: StringName, track_path: String) -> AnimationLibrary:
	var library := AnimationLibrary.new()
	var animation := Animation.new()
	var track := animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(track, track_path)
	animation.track_insert_key(track, 0.0, true)
	library.add_animation(animation_name, animation)
	return library


func _remove_library_dir() -> void:
	var directory := DirAccess.open(LIBRARY_DIR)
	if directory == null:
		return
	for file: String in directory.get_files():
		directory.remove(file)
	DirAccess.remove_absolute(LIBRARY_DIR)


func _find_job(jobs: Array[Dictionary], animation: String) -> Dictionary:
	for job: Dictionary in jobs:
		if job["animation"] == animation:
			return job
	return {}


func _check(condition: bool, description: String, detail: String = "") -> void:
	if condition:
		print("PASS: " + description)
		return
	_failures += 1
	print("FAIL: %s (%s)" % [description, detail])
