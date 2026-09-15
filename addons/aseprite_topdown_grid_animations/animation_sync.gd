@tool
extends RefCounted
## Writes the animations of an AnimatedSprite2D's SpriteFrames into an AnimationPlayer.
##
## Has no editor dependency, so headless tests can use it. Each SpriteFrames animation becomes an
## Animation of the same name in the player's global library, with two discrete value tracks on the
## sprite: "animation", keyed once at 0, and "frame", keyed when each frame starts, following the
## SpriteFrames speed and relative frame durations. A sync replaces only those two tracks, so tracks
## added to the same animations are kept. The linked player and the state of the last sync are
## stored in the sprite's metadata, which is saved with the scene.

const ExportPlanner := preload("export_planner.gd")

## NodePath from the sprite to its AnimationPlayer.
const META_PLAYER := &"aseprite_topdown_grid_animations_player"
## What the last sync wrote, see [method sync_key].
const META_SYNC_KEY := &"aseprite_topdown_grid_animations_sync_key"
const ANIMATION_PROPERTY := "animation"
const FRAME_PROPERTY := "frame"
const GLOBAL_LIBRARY := &""

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
## animation names, speeds, loops, frame durations, or where the sprite is relative to the player.
static func sync_key(sprite: AnimatedSprite2D, player: AnimationPlayer) -> String:
	var parts := PackedStringArray([str(player.get_path_to(sprite))])
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
	var key := sync_key(sprite, player)
	if not force and str(sprite.get_meta(META_SYNC_KEY, "")) == key:
		return false
	sync(sprite, player)
	sprite.set_meta(META_SYNC_KEY, key)
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
		errors.append("%s needs SpriteFrames and a valid AnimationPlayer root node." % sprite.name)
		return written
	var sprite_path := str(root.get_path_to(sprite))
	var own_paths: Array[NodePath] = [
		NodePath("%s:%s" % [sprite_path, ANIMATION_PROPERTY]),
		NodePath("%s:%s" % [sprite_path, FRAME_PROPERTY]),
	]
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
