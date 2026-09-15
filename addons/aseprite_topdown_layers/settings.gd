@tool
extends RefCounted
## Editor and project settings of the addon.
##
## The executable path is per machine (EditorSettings); output defaults are per project
## (ProjectSettings) and can still be overridden per file in the Import dock.

const EXECUTABLE_KEY := "aseprite_topdown_layers/general/executable_path"
const EXECUTABLE_ENV := "ASEPRITE_PATH"
const DEFAULT_OUTPUT_FOLDER_KEY := "aseprite_topdown_layers/defaults/output_folder"
const DEFAULT_FILENAME_KEY := "aseprite_topdown_layers/defaults/filename"
const DEFAULT_LAYER_EXCLUDE_KEY := "aseprite_topdown_layers/defaults/layer_exclude_pattern"
const DEFAULT_TAG_EXCLUDE_KEY := "aseprite_topdown_layers/defaults/tag_exclude_pattern"
const PROJECT_DEFAULTS := {
	DEFAULT_OUTPUT_FOLDER_KEY: "assets/{tag}",
	DEFAULT_FILENAME_KEY: "{title}_{layer}_{tag}",
	DEFAULT_LAYER_EXCLUDE_KEY: "^_",
	DEFAULT_TAG_EXCLUDE_KEY: "^_",
}


func register() -> void:
	var editor_settings := EditorInterface.get_editor_settings()
	# Empty by default so the ASEPRITE_PATH variable and the OS default still apply.
	if not editor_settings.has_setting(EXECUTABLE_KEY):
		editor_settings.set_setting(EXECUTABLE_KEY, "")
	editor_settings.set_initial_value(EXECUTABLE_KEY, "", false)
	editor_settings.add_property_info(
		{"name": EXECUTABLE_KEY, "type": TYPE_STRING, "hint": PROPERTY_HINT_GLOBAL_FILE}
	)
	for key: String in PROJECT_DEFAULTS:
		var value: String = PROJECT_DEFAULTS[key]
		if not ProjectSettings.has_setting(key):
			ProjectSettings.set_setting(key, value)
		# Equal to the initial value means it is not written to project.godot.
		ProjectSettings.set_initial_value(key, value)
		ProjectSettings.add_property_info({"name": key, "type": TYPE_STRING})


## EditorSettings first, then the ASEPRITE_PATH environment variable, then the OS default.
func get_executable_path() -> String:
	var editor_settings := EditorInterface.get_editor_settings()
	if editor_settings.has_setting(EXECUTABLE_KEY):
		var configured := str(editor_settings.get_setting(EXECUTABLE_KEY)).strip_edges()
		if configured != "":
			return configured
	var from_environment := OS.get_environment(EXECUTABLE_ENV).strip_edges()
	if from_environment != "":
		return from_environment
	return default_executable_path()


func get_project_default(key: String, fallback: String) -> String:
	if not ProjectSettings.has_setting(key):
		return fallback
	return str(ProjectSettings.get_setting(key, fallback))


static func default_executable_path() -> String:
	match OS.get_name():
		"Windows":
			return "C:\\Program Files\\Aseprite\\Aseprite.exe"
		"macOS":
			return "/Applications/Aseprite.app/Contents/MacOS/aseprite"
	return "aseprite"
