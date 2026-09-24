extends RefCounted
## AnimationPlayer sync and animation library checks of the headless test runner.
##
## They build their nodes by hand and never touch Aseprite, so they live apart from the import
## checks. [param check] is the runner's own reporting function, so one run counts every failure.

const AnimationLibraryStore := preload(
	"res://addons/dot_aseprite_importer/animation_library_store.gd"
)
const AnimationSync := preload("res://addons/dot_aseprite_importer/animation_sync.gd")
const ExportPlanner := preload("res://addons/dot_aseprite_importer/export_planner.gd")

## Resources are written here: ResourceSaver needs a Godot path, not the native cache directory.
const LIBRARY_DIR := "user://dot_aseprite_importer_tests"
const LIBRARY_TEMPLATE := "{scene_dir}/{scene}_animations.tres"

var _check: Callable
var _scene_root: Node


func _init(check: Callable, scene_root: Node) -> void:
	_check = check
	_scene_root = scene_root


func run() -> void:
	_test_animation_sync()
	_test_animation_library_store()


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
	_scene_root.add_child(root)

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
	_check.call(
		sync.errors.is_empty() and written == PackedStringArray(["hit_down", "idle_down"]),
		"sync writes one animation per SpriteFrames animation",
		"%s %s" % [written, sync.errors]
	)
	_check_synced_idle(library)
	_check.call(
		not library.has_animation(&"old_down"),
		"an animation left with only this sprite's old tracks is removed",
		str(library.get_animation_list())
	)
	var hit := library.get_animation(&"hit_down")
	_check.call(
		hit.loop_mode == Animation.LOOP_NONE and is_equal_approx(hit.length, 0.2),
		"a non-looping animation does not loop and lasts its frames",
		"%s %s" % [hit.loop_mode, hit.length]
	)

	player.play(&"idle_down")
	player.seek(0.15, true)
	_check.call(
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
	_check.call(
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
	_check.call(
		not sync.sync_linked(sprite, false), "sync_linked does nothing without a linked player"
	)
	AnimationSync.link(sprite, player)
	_check.call(
		AnimationSync.linked_player(sprite) == player and sync.sync_linked(sprite, false),
		"a linked player is synced the first time"
	)
	_check.call(not sync.sync_linked(sprite, false), "sync_linked skips an unchanged SpriteFrames")
	sprite.sprite_frames.set_frame(&"idle_down", 1, PlaceholderTexture2D.new(), 3.0)
	_check.call(sync.sync_linked(sprite, false), "sync_linked syncs again when a duration changes")
	_check.call(
		(
			is_equal_approx(library.get_animation(&"idle_down").length, 0.5)
			and library.get_animation(&"idle_down").get_track_count() == 3
		),
		"a second sync replaces its tracks instead of adding more",
		str(library.get_animation(&"idle_down").get_track_count())
	)
	_check.call(sync.sync_linked(sprite, true), "force syncs even when nothing changed")


func _test_animation_library_store() -> void:
	_check.call(
		(
			AnimationLibraryStore.resolve_path(LIBRARY_TEMPLATE, "res://examples/main.tscn")
			== "res://examples/main_animations.tres"
		),
		"resolve_path replaces {scene_dir} and {scene}"
	)
	_check.call(
		AnimationLibraryStore.resolve_path("", "res://examples/main.tscn") == "",
		"an empty template keeps the library built in"
	)
	_check.call(
		AnimationLibraryStore.resolve_path(LIBRARY_TEMPLATE, "") == "",
		"a scene that was never saved keeps the library built in"
	)
	_test_library_switch()
	DirAccess.make_dir_recursive_absolute(LIBRARY_DIR)
	_test_library_created()
	_test_library_converted()
	_test_library_keeps_work()
	_test_sync_linked_writes_the_file()
	_remove_library_dir()


## The switch decides; the path only says where.
func _test_library_switch() -> void:
	var key := AnimationLibraryStore.LIBRARY_ENABLED_KEY
	var previous: Variant = ProjectSettings.get_setting(key, true)
	ProjectSettings.set_setting(key, false)
	_check.call(
		AnimationLibraryStore.configured_template() == "",
		"the switch turned off keeps the library built in, whatever the path says"
	)
	ProjectSettings.set_setting(key, true)
	_check.call(
		AnimationLibraryStore.configured_template() == AnimationLibraryStore.DEFAULT_LIBRARY_PATH,
		"the switch turned on uses the path template",
		AnimationLibraryStore.configured_template()
	)
	ProjectSettings.set_setting(key, previous)


func _test_library_created() -> void:
	var store := AnimationLibraryStore.new()
	var player := AnimationPlayer.new()
	var built_in := store.library_for(player, "")
	_check.call(
		built_in.is_built_in() and player.has_animation_library(&"") and store.errors.is_empty(),
		"an empty path leaves the library built in",
		str(store.errors)
	)
	var path := LIBRARY_DIR + "/created.tres"
	var created := store.library_for(player, path)
	_check.call(
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
	_check.call(
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
	_check.call(
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
	_check.call(
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
	_check.call(
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
	# A second sprite on the same player, with the same animation name (a body and its weapon).
	var weapon := AnimatedSprite2D.new()
	weapon.name = "Weapon"
	root.add_child(weapon)
	weapon.owner = root
	weapon.sprite_frames = frames.duplicate() as SpriteFrames
	AnimationSync.link(weapon, player)

	var path := LIBRARY_DIR + "/scene_animations.tres"
	var sync := AnimationSync.new()
	_check.call(
		sync.sync_linked(sprite, false) and FileAccess.file_exists(path),
		"sync_linked writes the library named by the setting",
		str(sync.errors)
	)
	_check.call(sync.sync_linked(weapon, false), "a second sprite syncs into the same library")
	var tracks := _saved_idle_tracks(path)
	_check.call(
		tracks.has("Body:frame") and tracks.has("Weapon:frame"),
		"the synced animations are saved to the library file, not only held in memory",
		str(tracks)
	)
	_test_empty_library_file_is_resynced(sync, sprite, weapon, player, path)
	_test_rejected_name_is_not_resynced(sync, sprite)
	DirAccess.remove_absolute(path)
	_check.call(
		not sync.sync_linked(sprite, false) and not FileAccess.file_exists(path),
		"a sync that is skipped never touches the file system"
	)
	player.root_node = NodePath("Missing")
	sprite.remove_meta(AnimationSync.META_SYNC_KEY)
	_check.call(
		(
			not sync.sync_linked(sprite, true)
			and not sync.errors.is_empty()
			and not sprite.has_meta(AnimationSync.META_SYNC_KEY)
			and not FileAccess.file_exists(path)
		),
		"a player without a valid root node reports it and writes neither the file nor the key",
		str(sync.errors)
	)
	ProjectSettings.set_setting(AnimationLibraryStore.LIBRARY_PATH_KEY, previous)
	root.queue_free()


## 0.1.0 saved the library file empty and stored the sync key anyway, so reopening the scene
## loaded an empty library under a key that still matched. The sync must notice the missing
## tracks instead of trusting the key, for each sprite: once the body wrote "idle_down" again, the
## weapon's tracks are still missing from it.
func _test_empty_library_file_is_resynced(
	sync: AnimationSync,
	sprite: AnimatedSprite2D,
	weapon: AnimatedSprite2D,
	player: AnimationPlayer,
	path: String
) -> void:
	# What reopening the scene gave: the player holds the file's library, and the file is empty.
	var library := player.get_animation_library(&"")
	for animation_name: StringName in library.get_animation_list():
		library.remove_animation(animation_name)
	ResourceSaver.save(library, path)
	var synced := sync.sync_linked(sprite, false)
	var weapon_synced := sync.sync_linked(weapon, false)
	var tracks := _saved_idle_tracks(path)
	_check.call(
		synced and weapon_synced and tracks.has("Body:frame") and tracks.has("Weapon:frame"),
		"a library that lost a sprite's tracks is synced again although the key matches",
		"%s %s %s" % [synced, weapon_synced, tracks]
	)


## A name AnimationPlayer rejects is never written, so it must not count as missing: otherwise
## every scene change would sync and write the library file again.
func _test_rejected_name_is_not_resynced(sync: AnimationSync, sprite: AnimatedSprite2D) -> void:
	sprite.sprite_frames.add_animation(&"bad/name")
	sprite.sprite_frames.add_frame(&"bad/name", PlaceholderTexture2D.new(), 1.0)
	var synced := sync.sync_linked(sprite, false)
	_check.call(
		synced and not sync.errors.is_empty() and not sync.sync_linked(sprite, false),
		"an animation name AnimationPlayer rejects does not make every sync run again",
		str(sync.errors)
	)


## The track paths of "idle_down" in the library file, read from disk and not from the player:
## a run of the game only sees what the file holds.
func _saved_idle_tracks(path: String) -> PackedStringArray:
	var tracks := PackedStringArray()
	var saved := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as AnimationLibrary
	if saved == null or not saved.has_animation(&"idle_down"):
		return tracks
	var idle := saved.get_animation(&"idle_down")
	for track: int in idle.get_track_count():
		tracks.append(str(idle.track_get_path(track)))
	return tracks


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
