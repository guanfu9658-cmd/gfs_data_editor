@tool
extends EditorPlugin

const DataEditorPanelScene := preload("res://addons/gf_data_editor/data_editor_panel.tscn")

var _main_panel: Control


func _enter_tree() -> void:
	_main_panel = DataEditorPanelScene.instantiate()
	_main_panel.name = "GFDataEditorMainScreen"
	_main_panel.hide()
	_main_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var main_screen := EditorInterface.get_editor_main_screen()
	main_screen.add_child(_main_panel)
	_fit_main_screen_panel()
	_make_visible(false)


func _exit_tree() -> void:
	if _main_panel:
		_main_panel.queue_free()
		_main_panel = null


func _has_main_screen() -> bool:
	return true


func _make_visible(visible: bool) -> void:
	if _main_panel == null:
		return
	_main_panel.visible = visible
	_main_panel.mouse_filter = (
		Control.MOUSE_FILTER_STOP if visible else Control.MOUSE_FILTER_IGNORE
	)
	if visible:
		_fit_main_screen_panel()


func _fit_main_screen_panel() -> void:
	if _main_panel == null:
		return
	_main_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_main_panel.offset_left = 0
	_main_panel.offset_top = 0
	_main_panel.offset_right = 0
	_main_panel.offset_bottom = 0
	_main_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_main_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_main_panel.queue_sort()


func _get_plugin_name() -> String:
	return "数据编辑器"


func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_editor_theme().get_icon("Grid", "EditorIcons")
