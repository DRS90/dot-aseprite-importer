@tool
extends RefCounted
## Decides where an AnimationPlayer's global AnimationLibrary lives: built into the scene, or an
## external resource named by a path template in Project Settings.
##
## Has no editor dependency, so headless tests can use it. An empty template, or a scene that was
## never saved, keeps the library built in, which is what Godot does on its own. A library that is
## already external is never moved, and a library that is replaced by an existing file keeps the
## animations that only it had: the file wins, but nothing is dropped.

## Path template of the external library, empty to keep it built in.
const LIBRARY_PATH_KEY := "aseprite_topdown_grid_animations/animation_player/library_path"
const DEFAULT_LIBRARY_PATH := "{scene_dir}/{scene}_animations.tres"
const GLOBAL_LIBRARY := &""

## Problems found by the last [method library_for] call.
var errors := PackedStringArray()


## The template from Project Settings, or its default where the setting is not registered.
static func configured_template() -> String:
	return str(ProjectSettings.get_setting(LIBRARY_PATH_KEY, DEFAULT_LIBRARY_PATH))


## Path of the scene [param node] belongs to, empty while that scene has never been saved.
static func scene_path(node: Node) -> String:
	var root: Node = node.owner if node.owner != null else node
	return root.scene_file_path


## Where the library of [param scene_file] belongs. [param template] accepts {scene_dir} and
## {scene}; an empty template or an unsaved scene gives "", which keeps the library built in.
static func resolve_path(template: String, scene_file: String) -> String:
	if template.strip_edges() == "" or scene_file == "":
		return ""
	var directory := scene_file.get_base_dir()
	var name := scene_file.get_file().get_basename()
	return template.replace("{scene_dir}", directory).replace("{scene}", name)


## The library [param player] should use, creating [param path] and moving a built-in library into
## it when needed. An empty [param path] keeps the library built in. Never returns null: on any
## problem it reports in [member errors] and leaves the built-in library in place.
func library_for(player: AnimationPlayer, path: String) -> AnimationLibrary:
	errors = PackedStringArray()
	var current := _current_library(player)
	var external: AnimationLibrary = null
	if path != "":
		if current != null and not current.is_built_in():
			# Already external, possibly somewhere else: where it lives is the user's choice.
			return current
		if FileAccess.file_exists(path):
			external = _merge_into(_load(path), current)
		else:
			external = _create(path, current)
	if external != null:
		_assign(player, external)
		return external
	if current == null:
		current = AnimationLibrary.new()
		player.add_animation_library(GLOBAL_LIBRARY, current)
	return current


## Loads the library at [param path], or reports that the file is something else.
func _load(path: String) -> AnimationLibrary:
	# Without a type hint: loading with one prints an engine error when the type does not match.
	var library := ResourceLoader.load(path) as AnimationLibrary
	if library == null:
		errors.append("'%s' is not an AnimationLibrary. The library stays built in." % path)
	return library


## Writes [param library] (or a new one) to [param path] and returns it loaded from there, so that
## it carries a resource path: without one it would be saved into the scene again.
func _create(path: String, library: AnimationLibrary) -> AnimationLibrary:
	var directory := path.get_base_dir()
	if directory != "" and not DirAccess.dir_exists_absolute(directory):
		if DirAccess.make_dir_recursive_absolute(directory) != OK:
			errors.append("Cannot create '%s'. The library stays built in." % directory)
			return null
	var saved: AnimationLibrary = library if library != null else AnimationLibrary.new()
	var error := ResourceSaver.save(saved, path)
	if error != OK:
		errors.append(
			(
				"Cannot write the animation library to '%s' (%s). It stays built in."
				% [path, error_string(error)]
			)
		)
		return null
	return _load(path)


## Adds to [param library] the animations only [param built_in] has, so that replacing a built-in
## library with an existing file keeps the tracks made against those animations.
func _merge_into(library: AnimationLibrary, built_in: AnimationLibrary) -> AnimationLibrary:
	if library == null or built_in == null:
		return library
	var moved := false
	for name: StringName in built_in.get_animation_list():
		if not library.has_animation(name):
			library.add_animation(name, built_in.get_animation(name))
			moved = true
	if not moved:
		return library
	# Saved right away: otherwise they would live only in memory until something saves the file.
	var error := ResourceSaver.save(library, library.resource_path)
	if error != OK:
		errors.append(
			(
				"Animations of the built-in library were kept in memory only: '%s' failed (%s)."
				% [library.resource_path, error_string(error)]
			)
		)
	return library


static func _assign(player: AnimationPlayer, library: AnimationLibrary) -> void:
	if player.has_animation_library(GLOBAL_LIBRARY):
		player.remove_animation_library(GLOBAL_LIBRARY)
	player.add_animation_library(GLOBAL_LIBRARY, library)


static func _current_library(player: AnimationPlayer) -> AnimationLibrary:
	if not player.has_animation_library(GLOBAL_LIBRARY):
		return null
	return player.get_animation_library(GLOBAL_LIBRARY)
