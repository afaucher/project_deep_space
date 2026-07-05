class_name DMThemeValues extends RefCounted


var scale: float = 1
var background_color: Color = Color.WHITE
var current_line_color: Color = Color.WHITE
var error_line_color: Color = Color.WHITE

var critical_color: Color = Color.WHITE
var notice_color: Color = Color.WHITE

var cues_color: Color = Color.WHITE
var text_color: Color = Color.WHITE
var tags_color: Color = Color.WHITE
var conditions_color: Color = Color.WHITE
var mutations_color: Color = Color.WHITE
var mutations_line_color: Color = Color.WHITE
var members_color: Color = Color.WHITE
var strings_color: Color = Color.WHITE
var numbers_color: Color = Color.WHITE
var symbols_color: Color = Color.WHITE
var comments_color: Color = Color.WHITE
var jumps_color: Color = Color.WHITE

var font_size: int = 16


func _init(values: Dictionary) -> void:
	scale = values.scale

	background_color = values.background_color
	current_line_color = values.current_line_color
	error_line_color = values.error_line_color

	critical_color = values.critical_color
	notice_color = values.notice_color

	cues_color = values.cues_color
	text_color = values.text_color
	tags_color = values.tags_color
	conditions_color = values.conditions_color
	mutations_color = values.mutations_color
	mutations_line_color = values.mutations_line_color
	members_color = values.members_color
	strings_color = values.strings_color
	numbers_color = values.numbers_color
	symbols_color = values.symbols_color
	comments_color = values.comments_color
	jumps_color = values.jumps_color

	font_size = values.font_size


## Some Godot versions don't expose every text_editor/theme/highlighting/*
## setting this addon was written against (renamed/removed), in which case
## EditorSettings.get_setting returns null -- assigning that straight into a
## typed Color field throws "Nil -> Color" at editor/export load. Fall back to
## white (matches every field's own default above) instead of erroring.
static func _get_color_setting(editor_settings: EditorSettings, setting_name: String) -> Color:
	var value = editor_settings.get_setting(setting_name)
	if value == null:
		return Color.WHITE
	return value

## Get size and colour values used for setting themes.
static func get_values_from_editor() -> DMThemeValues:
	var editor_settings: EditorSettings = EditorInterface.get_editor_settings()
	return DMThemeValues.new({
		scale = EditorInterface.get_editor_scale(),

		background_color = Color(_get_color_setting(editor_settings, "interface/theme/base_color").blend(_get_color_setting(editor_settings, "text_editor/theme/highlighting/background_color")), 1),
		current_line_color = _get_color_setting(editor_settings, "text_editor/theme/highlighting/current_line_color"),
		error_line_color = _get_color_setting(editor_settings, "text_editor/theme/highlighting/mark_color"),

		critical_color = _get_color_setting(editor_settings, "text_editor/theme/highlighting/comment_markers/critical_color"),
		notice_color = _get_color_setting(editor_settings, "text_editor/theme/highlighting/comment_markers/notice_color"),

		cues_color = _get_color_setting(editor_settings, "text_editor/theme/highlighting/gdscript/node_reference_color"),
		text_color = _get_color_setting(editor_settings, "text_editor/theme/highlighting/text_color"),
		tags_color = _get_color_setting(editor_settings, "text_editor/theme/highlighting/string_placeholder_color"),
		conditions_color = _get_color_setting(editor_settings, "text_editor/theme/highlighting/keyword_color"),
		mutations_color = _get_color_setting(editor_settings, "text_editor/theme/highlighting/function_color"),
		mutations_line_color = Color(_get_color_setting(editor_settings, "text_editor/theme/highlighting/function_color"), 0.6),
		members_color = _get_color_setting(editor_settings, "text_editor/theme/highlighting/member_variable_color"),
		strings_color = _get_color_setting(editor_settings, "text_editor/theme/highlighting/string_color"),
		numbers_color = _get_color_setting(editor_settings, "text_editor/theme/highlighting/number_color"),
		symbols_color = _get_color_setting(editor_settings, "text_editor/theme/highlighting/symbol_color"),
		comments_color = _get_color_setting(editor_settings, "text_editor/theme/highlighting/comment_color"),
		jumps_color = Color(_get_color_setting(editor_settings, "text_editor/theme/highlighting/gdscript/node_reference_color"), 0.6),

		font_size = editor_settings.get_setting("interface/editor/code_font_size")
	})


## Return a copy of a texture with a tint applied.
static func get_icon_with_color(icon: Texture2D, color: Color) -> ImageTexture:
	var image: Image = icon.get_image().duplicate()
	for x: int in image.get_width():
		for y: int in image.get_height():
			var pixel: Color = image.get_pixel(x, y)
			pixel *= color
			image.set_pixel(x, y, pixel)
	return ImageTexture.create_from_image(image)
