@tool
class_name ConfigTableEditor
extends HSplitContainer

signal table_dirty_changed(is_dirty: bool)
signal table_saved(table_id: String)

var _type_info: ConfigTypeInfo
var _registry: ConfigTypeRegistry
var _store: JsonTableStore
var _all_tables: Dictionary
var _rows: Dictionary = {}
var _selected_key: String = ""
var _dirty: bool = false

var _list: ItemList
var _btn_add: Button
var _btn_delete: Button
var _btn_save: Button
var _btn_discard: Button
var _txt_state: Label
var _form_host: VBoxContainer


func setup(
	type_info: ConfigTypeInfo,
	registry: ConfigTypeRegistry,
	store: JsonTableStore,
	all_tables: Dictionary
) -> void:
	_type_info = type_info
	_registry = registry
	_store = store
	_all_tables = all_tables
	_reload_from_store()
	call_deferred("_refresh_list")


func _ready() -> void:
	_bind_nodes()
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	split_offset = 260
	if _btn_add:
		_btn_add.pressed.connect(_on_add)
	if _btn_delete:
		_btn_delete.pressed.connect(_on_delete)
	if _btn_save:
		_btn_save.pressed.connect(_on_save)
	if _btn_discard:
		_btn_discard.pressed.connect(_on_discard)
	if _list:
		_list.item_selected.connect(_on_list_selected)
	_update_state_ui()
	if _type_info:
		call_deferred("_refresh_list")


func _bind_nodes() -> void:
	_list = get_node_or_null("%ListItems") as ItemList
	_btn_add = get_node_or_null("%BtnAdd") as Button
	_btn_delete = get_node_or_null("%BtnDelete") as Button
	_btn_save = get_node_or_null("%BtnSave") as Button
	_btn_discard = get_node_or_null("%BtnDiscard") as Button
	_txt_state = get_node_or_null("%TxtEditState") as Label
	_form_host = get_node_or_null("%FormHost") as VBoxContainer


func _reload_from_store() -> void:
	if _type_info == null or _store == null:
		return
	_rows = _store.load_table(_type_info.class_name_id, _type_info)
	_dirty = false
	_update_state_ui()
	table_dirty_changed.emit(false)


func _refresh_list() -> void:
	_bind_nodes()
	if _list == null:
		push_warning("ConfigTableEditor: ListItems node missing.")
		return
	_list.clear()
	var keys: Array = _rows.keys()
	keys.sort_custom(func(a, b): return int(a) < int(b))
	var select_idx := 0
	for i in keys.size():
		var key: String = str(keys[i])
		var row: Dictionary = _rows[key]
		_list.add_item(_format_list_label(row))
		_list.set_item_metadata(i, key)
		if key == _selected_key:
			select_idx = i
	if keys.is_empty():
		_selected_key = ""
		_clear_form("暂无数据，点击「添加」创建条目。")
	else:
		if _selected_key == "" or not _rows.has(_selected_key):
			_selected_key = str(keys[0])
		_list.select(select_idx)
		_render_form()


func _format_list_label(row: Dictionary) -> String:
	var id_val := int(row.get("id", 0))
	if row.has("name"):
		return "%d - %s" % [id_val, str(row["name"])]
	if row.has("title"):
		return "%d - %s" % [id_val, str(row["title"])]
	return str(id_val)


func _on_list_selected(index: int) -> void:
	var key: String = str(_list.get_item_metadata(index))
	if key == _selected_key:
		return
	_selected_key = key
	_render_form()


func _render_form() -> void:
	_bind_nodes()
	if _form_host == null:
		return
	for child in _form_host.get_children():
		child.queue_free()
	if _selected_key == "" or not _rows.has(_selected_key):
		_clear_form("未选择条目。")
		return
	var form := ObjectFormEditor.new()
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.bind(_type_info, _rows[_selected_key], _registry, _store, _all_tables, false)
	form.changed.connect(_on_form_changed)
	_form_host.add_child(form)


func _clear_form(message: String) -> void:
	if _form_host == null:
		return
	for child in _form_host.get_children():
		child.queue_free()
	var label := Label.new()
	label.text = message
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.modulate = Color(0.55, 0.55, 0.55)
	_form_host.add_child(label)


func _on_form_changed() -> void:
	if not _dirty:
		_dirty = true
		_update_state_ui()
		table_dirty_changed.emit(true)


func _commit_form_to_row() -> void:
	if _form_host == null or _form_host.get_child_count() == 0:
		return
	var form := _form_host.get_child(0)
	if form is ObjectFormEditor:
		_rows[_selected_key] = (form as ObjectFormEditor).read_row()


func _on_add() -> void:
	var next_id := _store.compute_next_id(_rows)
	var row := GameConfig.make_default_row(_type_info.config_script)
	row["id"] = next_id
	var key := str(next_id)
	_rows[key] = row
	_selected_key = key
	_dirty = true
	_update_state_ui()
	table_dirty_changed.emit(true)
	_refresh_list()


func _on_delete() -> void:
	if _selected_key == "":
		return
	_rows.erase(_selected_key)
	_selected_key = ""
	_dirty = true
	_update_state_ui()
	table_dirty_changed.emit(true)
	_refresh_list()


func _on_save() -> void:
	_commit_form_to_row()
	var err := _store.save_table(_type_info.class_name_id, _rows)
	if err != OK:
		push_warning("保存失败: %s" % error_string(err))
		return
	_all_tables[_type_info.class_name_id] = _rows.duplicate(true)
	_dirty = false
	_update_state_ui()
	# 保存后重绘左侧列表，保证名称/标题变化能立即可见。
	_refresh_list()
	table_dirty_changed.emit(false)
	table_saved.emit(_type_info.class_name_id)


func _on_discard() -> void:
	_reload_from_store()
	_refresh_list()


func _update_state_ui() -> void:
	if _txt_state == null:
		return
	_txt_state.text = "已修改 *" if _dirty else "未修改"
	if _btn_save:
		_btn_save.disabled = not _dirty
	if _btn_discard:
		_btn_discard.disabled = not _dirty


func save_if_dirty() -> bool:
	if not _dirty:
		return true
	_on_save()
	return not _dirty


func get_rows() -> Dictionary:
	_commit_form_to_row()
	return _rows


func get_table_id() -> String:
	return _type_info.class_name_id if _type_info else ""


func update_all_tables_cache(all_tables: Dictionary) -> void:
	_all_tables = all_tables
	if _selected_key != "" and _rows.has(_selected_key):
		_render_form()
