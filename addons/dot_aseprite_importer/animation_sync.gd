@tool
extends RefCounted
## Writes the animations of an AnimatedSprite2D's SpriteFrames into an AnimationPlayer.
##
## Has no editor dependency, so headless tests can use it. Each SpriteFrames animation becomes an
## Animation of the same name in the player's global library, with two discrete value tracks on the
## sprite: "animation", keyed once at 0, and "frame", keyed when each frame starts, following the
## SpriteFrames speed and relative frame durations. A sync replaces only those two tracks, so tracks
## added to the same animations are kept. The linked player and the state of the last sync are
## stored in the sprite's metadata, which is saved with the scene. Both names start with "_", which
## only hides them from the inspector's Metadata list (they are still saved): the panel's
## Assign/Clear buttons are the interface for them, not a raw NodePath the user has to type.

const AnimationLibraryStore := preload("animation_library_store.gd")
const ExportPlanner := preload("export_planner.gd")

## NodePath from the sprite to its AnimationPlayer.
const META_PLAYER := &"_dot_aseprite_importer_player"
## What the last sync wrote, see [method sync_key].
const META_SYNC_KEY := &"_dot_aseprite_importer_sync_key"
const ANIMATION_PROPERTY := "animation"
const FRAME_PROPERTY := "frame"
const GLOBAL_LIBRARY := &""
## Part of every sync key. Raised when a sync writes something an earlier version did not, so that
## every linked sprite syncs once again when its scene is opened: 2 rewrites the library files
## 0.1.0 left empty or stale.
const SYNC_KEY_VERSION := 2
const NO_ROOT_ERROR := "%s needs SpriteFrames and a valid AnimationPlayer root node."

## Problems found by the last [method sync] or [method sync_linked] call.
var errors := PackedStringArray()


## The AnimationPlayer linked to [param sprite], or null.
static func linked_player(sprite: AnimatedSprite2D) -> AnimationPlayer:
	var path: Variant = sprite.get_meta(META_PLAYER, NodePath())
	if not path is NodePath or (path as NodePath).is_empty():
		return null
	return sprite.get_node_or_null(path as NodePath) as AnimationPlayer


## Links [param player] to [param sprite], or unlinks it when [param player] is null.
static func link(sprite: AnimatedSprite2D, player: AnimationPlayer) -> void:
	if player == null:
		sprite.remove_meta(META_PLAYER)
	else:
		sprite.set_meta(META_PLAYER, sprite.get_path_to(player))
	sprite.remove_meta(META_SYNC_KEY)


## Changes whenever a sync of [param sprite] into [param player] would write something different:
## animation names, speeds, loops, frame durations, where the sprite is relative to the player, or
## where the library is stored ([param library_path], empty when it is built into the scene).
static func sync_key(
	sprite: AnimatedSprite2D, player: AnimationPlayer, library_path: String
) -> String:
	var parts := PackedStringArray(
		[str(SYNC_KEY_VERSION), str(player.get_path_to(sprite)), library_path]
	)
	var frames := sprite.sprite_frames
	if frames != null:
		for animation: StringName in frames.get_animation_names():
			var durations := PackedStringArray()
			for index: int in frames.get_frame_count(animation):
				durations.append(str(frames.get_frame_duration(animation, index)))
			var speed := frames.get_animation_speed(animation)
			var loops := frames.get_animation_loop(animation)
			parts.append("%s|%s|%s|%s" % [animation, speed, loops, ",".join(durations)])
	return "\n".join(parts).md5_text()


## Syncs [param sprite] into its linked AnimationPlayer when something changed since the last sync,
## or always with [param force]. Returns true when it wrote the animations.
func sync_linked(sprite: AnimatedSprite2D, force: bool) -> bool:
	errors = PackedStringArray()
	var player := linked_player(sprite)
	if player == null or sprite.sprite_frames == null:
		return false
	var root := player.get_node_or_null(player.root_node)
	if root == null:
		# Nothing can be written: no key and no save, so it syncs once the root is fixed.
		errors.append(NO_ROOT_ERROR % sprite.name)
		return false
	# Resolved first because it is part of the key, and it writes nothing: a sync that is skipped
	# must not create the library file nor touch the scene.
	var path := AnimationLibraryStore.resolve_path(
		AnimationLibraryStore.configured_template(), AnimationLibraryStore.scene_path(sprite)
	)
	var key := sync_key(sprite, player, path)
	if (
		not force
		and str(sprite.get_meta(META_SYNC_KEY, "")) == key
		and _has_every_animation(sprite, player, root)
	):
		return false
	var store := AnimationLibraryStore.new()
	var library := store.library_for(player, path)
	sync(sprite, player)
	# After sync(), which clears the errors of the previous run.
	errors.append_array(store.errors)
	var failure := AnimationLibraryStore.save_external(library)
	if failure != "":
		# No key: the next sync tries to save again instead of trusting a file that was not written.
		errors.append(failure)
		return true
	sprite.set_meta(META_SYNC_KEY, key)
	return true


## False when the player's library lacks one of this sprite's animations or its tracks in it: the
## key alone cannot tell, because it describes the last sync and not what the library holds now
## (0.1.0 left library files empty under a matching key). Tracks are checked, not only names,
## because sprites sharing a player share animation names: once one of them wrote "idle_down",
## the name alone would hide that the other's tracks are still missing.
static func _has_every_animation(
	sprite: AnimatedSprite2D, player: AnimationPlayer, root: Node
) -> bool:
	if not player.has_animation_library(GLOBAL_LIBRARY):
		return false
	var library := player.get_animation_library(GLOBAL_LIBRARY)
	var own_paths := _own_paths(root, sprite)
	for animation_name: StringName in sprite.sprite_frames.get_animation_names():
		# Names sync() rejects are never written, so they cannot be missing.
		if ExportPlanner.sanitize_animation_name(animation_name) != String(animation_name):
			continue
		if not library.has_animation(animation_name):
			return false
		var animation := library.get_animation(animation_name)
		for path: NodePath in own_paths:
			if animation.find_track(path, Animation.TYPE_VALUE) == -1:
				return false
	return true


## Writes every animation of [param sprite]'s SpriteFrames into [param player]'s global library and
## removes this sprite's tracks from the animations the SpriteFrames no longer has (an animation
## left without tracks is removed). Returns the names of the animations written.
func sync(sprite: AnimatedSprite2D, player: AnimationPlayer) -> PackedStringArray:
	errors = PackedStringArray()
	var written := PackedStringArray()
	var frames := sprite.sprite_frames
	var root := player.get_node_or_null(player.root_node)
	if frames == null or root == null:
		errors.append(NO_ROOT_ERROR % sprite.name)
		return written
	var own_paths := _own_paths(root, sprite)
	if not player.has_animation_library(GLOBAL_LIBRARY):
		player.add_animation_library(GLOBAL_LIBRARY, AnimationLibrary.new())
	var library := player.get_animation_library(GLOBAL_LIBRARY)

	for animation_name: StringName in frames.get_animation_names():
		if ExportPlanner.sanitize_animation_name(animation_name) != String(animation_name):
			errors.append("Animation '%s' has a name AnimationPlayer rejects." % animation_name)
			continue
		if not library.has_animation(animation_name):
			library.add_animation(animation_name, Animation.new())
		var animation := library.get_animation(animation_name)
		_remove_tracks(animation, own_paths)
		_add_tracks(animation, frames, animation_name, own_paths)
		written.append(animation_name)

	for animation_name: StringName in library.get_animation_list():
		if written.has(animation_name):
			continue
		var animation := library.get_animation(animation_name)
		if _remove_tracks(animation, own_paths) and animation.get_track_count() == 0:
			library.remove_animation(animation_name)
	return written


## The paths of the two tracks a sync writes for [param sprite], relative to the player's
## [param root]: "animation" first, then "frame".
static func _own_paths(root: Node, sprite: AnimatedSprite2D) -> Array[NodePath]:
	var sprite_path := str(root.get_path_to(sprite))
	return [
		NodePath("%s:%s" % [sprite_path, ANIMATION_PROPERTY]),
		NodePath("%s:%s" % [sprite_path, FRAME_PROPERTY]),
	]


## Removes the tracks animating one of [param paths]; true when any was removed.
static func _remove_tracks(animation: Animation, paths: Array[NodePath]) -> bool:
	var removed := false
	for track: int in range(animation.get_track_count() - 1, -1, -1):
		if paths.has(animation.track_get_path(track)):
			animation.remove_track(track)
			removed = true
	return removed


static func _add_tracks(
	animation: Animation, frames: SpriteFrames, animation_name: StringName, paths: Array[NodePath]
) -> void:
	# The animation track comes first: setting the animation resets the frame to 0.
	var animation_track := _add_discrete_track(animation, paths[0])
	animation.track_insert_key(animation_track, 0.0, animation_name)
	var frame_track := _add_discrete_track(animation, paths[1])
	var speed := frames.get_animation_speed(animation_name)
	var time := 0.0
	for index: int in frames.get_frame_count(animation_name):
		animation.track_insert_key(frame_track, time, index)
		if speed > 0.0:
			time += frames.get_frame_duration(animation_name, index) / speed
	animation.length = time
	var loops := frames.get_animation_loop(animation_name)
	animation.loop_mode = Animation.LOOP_LINEAR if loops else Animation.LOOP_NONE


static func _add_discrete_track(animation: Animation, path: NodePath) -> int:
	var track := animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(track, path)
	animation.value_track_set_update_mode(track, Animation.UPDATE_DISCRETE)
	animation.track_set_interpolation_type(track, Animation.INTERPOLATION_NEAREST)
	animation.track_set_interpolation_loop_wrap(track, false)
	return track
