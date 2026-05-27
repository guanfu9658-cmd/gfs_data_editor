@tool
class_name ObjectFormEditor
extends VBoxContainer

const _GAME_CONFIG_SCRIPT := preload("res://addons/gf_data_editor/runtime/game_config.gd")

signal changed

var _type_info: ConfigTypeInfo
var _registry: ConfigTypeRegistry
var _store: JsonTableStore
var _all_tables: Dictionary # table_id -> rows
var _row: Dictionary = {}
var _editors: Dictionary = {} # field_name -> Control
var _omit_id: bool = false
var _suspend_changed: bool = false
var _nested_type_cache: Dictionary = {} # script_path -> ConfigTypeInfo
var _extends_gameconfig_cache: Dictionary = {} # script_path -> bool
var _has_custom_tostring_cache: Dictionary = {} # script_path -> bool


func bind(
	type_info: ConfigTypeInfo,
	row: Dictionary,
	registry: ConfigTypeRegistry,
	store: JsonTableStore,
	all_tables: Dictionary,
	omit_id: bool = false
) -> void:
	_type_info = type_info
	_registry = registry
	_store = store
	_all_tables = all_tables
	_row = row.duplicate(true)
	_omit_id = omit_id
	_suspend_changed = true
	_rebuild()
	_suspend_changed = false


func read_row() -> Dictionary:
	var result := _row.duplicate(true)
	for field_name in _editors.keys():
		var editor: Control = _editors[field_name]
		result[field_name] = _read_editor(field_name, editor)
	return result


func _rebuild() -> void:
	for child in get_children():
		child.queue_free()
	_editors.clear()
	if _type_info == null:
		return
	for field in _type_info.fields:
		if _omit_id and field.name == "id":
			continue
		var label_text: String = field.display_name if field.display_name != "" else field.name
		var row_box := HBoxContainer.new()
		row_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row_box.add_theme_constant_override("separation", 12)
		var label := Label.new()
		label.text = label_text
		label.custom_minimum_size = Vector2(100, 0)
		label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		row_box.add_child(label)
		var editor := _create_editor(field)
		if editor == null:
			editor = Label.new()
			editor.text = "不支持的字段类型"
		editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if not _is_array_field(field):
			editor.custom_minimum_size.y = 28
		row_box.add_child(editor)
		_editors[field.name] = editor
		add_child(row_box)


func _create_editor(field: Dictionary) -> Control:
	if _is_array_field(field):
		var ref_for_array: Dictionary = field.get("config_ref", {})
		if not ref_for_array.is_empty():
			return _create_multi_config_ref_editor(field, ref_for_array)
		if _field_is_gameconfig_ref_array(field):
			return _create_gameconfig_multi_select_editor(field)
		if _field_is_resource_array(field):
			return _create_resource_array_editor(field)

	if field.name == "id":
		var id_readonly := LineEdit.new()
		id_readonly.text = str(int(_row.get("id", 0)))
		id_readonly.editable = false
		id_readonly.selecting_enabled = true
		return id_readonly

	var ref: Dictionary = field.config_ref
	if not ref.is_empty():
		return _create_config_ref_editor(field, ref)
	match field.type:
		TYPE_BOOL:
			var cb := CheckBox.new()
			cb.button_pressed = bool(_row.get(field.name, false))
			cb.toggled.connect(func(_v): _emit_changed())
			return cb
		TYPE_INT:
			var spin := SpinBox.new()
			spin.min_value = -2147483648
			spin.max_value = 2147483647
			spin.step = 1
			spin.value = int(_row.get(field.name, 0))
			spin.value_changed.connect(func(_v): _emit_changed())
			return spin
		TYPE_FLOAT:
			var spin_f := SpinBox.new()
			spin_f.min_value = -1e9
			spin_f.max_value = 1e9
			spin_f.step = 0.01
			spin_f.value = float(_row.get(field.name, 0.0))
			spin_f.value_changed.connect(func(_v): _emit_changed())
			return spin_f
		TYPE_STRING:
			var line := LineEdit.new()
			line.text = str(_row.get(field.name, ""))
			line.text_changed.connect(func(_t): _emit_changed())
			return line
		TYPE_ARRAY:
			var array_text := TextEdit.new()
			array_text.custom_minimum_size = Vector2(0, 96)
			var raw_arr = _row.get(field.name, [])
			array_text.text = JSON.stringify(raw_arr, "\t")
			array_text.text_changed.connect(func(): _emit_changed())
			return array_text
		_:
			if field.hint == PROPERTY_HINT_ENUM and field.hint_string != "":
				return _create_enum_editor(field)
			var fallback := LineEdit.new()
			fallback.text = str(_row.get(field.name, ""))
			fallback.text_changed.connect(func(_t): _emit_changed())
			return fallback


func _create_enum_editor(field: Dictionary) -> Control:
	var opt := OptionButton.new()
	var names: PackedStringArray = field.hint_string.split(",")
	var current := str(_row.get(field.name, names[0] if names.size() > 0 else ""))
	var select_idx := 0
	for i in names.size():
		opt.add_item(names[i])
		if names[i] == current:
			select_idx = i
	opt.selected = select_idx
	opt.item_selected.connect(func(_i): _emit_changed())
	return opt


func _create_config_ref_editor(field: Dictionary, ref: Dictionary) -> Control:
	var opt := OptionButton.new()
	opt.add_item("(无)", 0)
	var target_id: String = ref.target
	var rows: Dictionary = _all_tables.get(target_id, {})
	var display_field: String = ref.get("display_field", "name")
	var sorted_keys: Array = rows.keys()
	sorted_keys.sort_custom(func(a, b): return int(a) < int(b))
	var current_id := int(_row.get(field.name, 0))
	var select_idx := 0
	var idx := 1
	for key in sorted_keys:
		var target_row: Dictionary = rows[key]
		var id_val := int(target_row.get("id", int(key)))
		var label := str(id_val)
		if target_row.has(display_field):
			label = "%d - %s" % [id_val, str(target_row[display_field])]
		opt.add_item(label, idx)
		opt.set_item_metadata(idx, id_val)
		if id_val == current_id:
			select_idx = idx
		idx += 1
	opt.selected = select_idx
	opt.item_selected.connect(func(_i): _emit_changed())
	return opt


func _emit_changed() -> void:
	if _suspend_changed:
		return
	changed.emit()


func _field_is_resource_array(field: Dictionary) -> bool:
	if _field_is_gameconfig_ref_array(field):
		return false
	if not _is_array_field(field):
		return false
	return str(field.get("array_element_script_path", "")) != "" or str(field.get("array_element_class_name", "")) != ""


func _is_array_field(field: Dictionary) -> bool:
	if int(field.get("type", TYPE_NIL)) == TYPE_ARRAY:
		return true
	if int(field.get("hint", -1)) == PROPERTY_HINT_ARRAY_TYPE:
		return true
	return typeof(field.get("default", null)) == TYPE_ARRAY


func _field_is_int_array(field: Dictionary) -> bool:
	if not _is_array_field(field):
		return false
	var builtin_type := int(field.get("array_element_builtin_type", TYPE_NIL))
	if builtin_type == TYPE_INT:
		return true
	var decl_name := str(field.get("array_element_decl_name", "")).to_lower()
	return decl_name == "int"


func _create_multi_config_ref_editor(field: Dictionary, ref: Dictionary) -> Control:
	var root := HBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	root.set_meta("selected_ids", _to_int_array(_row.get(field.name, [])))

	var menu_btn := MenuButton.new()
	menu_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	menu_btn.custom_minimum_size.y = 28
	menu_btn.set_meta("selected_ids", root.get_meta("selected_ids", []))
	root.add_child(menu_btn)

	var clear_btn := Button.new()
	clear_btn.text = "清空"
	clear_btn.custom_minimum_size.y = 28
	root.add_child(clear_btn)

	var popup := menu_btn.get_popup()
	popup.hide_on_checkable_item_selection = false
	var target_id: String = str(ref.get("target", ""))
	var rows: Dictionary = _all_tables.get(target_id, {})
	var display_field: String = str(ref.get("display_field", "name"))
	var sorted_keys: Array = rows.keys()
	sorted_keys.sort_custom(func(a, b): return int(a) < int(b))

	var selected_ids: Array = menu_btn.get_meta("selected_ids", [])
	for key in sorted_keys:
		var target_row: Dictionary = rows[key]
		var id_val := int(target_row.get("id", int(key)))
		var label := str(id_val)
		if target_row.has(display_field):
			label = "%d - %s" % [id_val, str(target_row[display_field])]
		popup.add_check_item(label, id_val)
		var idx := popup.item_count - 1
		popup.set_item_checked(idx, selected_ids.has(id_val))

	_refresh_multi_ref_text(menu_btn)
	popup.id_pressed.connect(func(id: int):
		var idx := popup.get_item_index(id)
		if idx < 0:
			return
		popup.set_item_checked(idx, not popup.is_item_checked(idx))
		var selected := _collect_checked_ids(popup)
		menu_btn.set_meta("selected_ids", selected)
		root.set_meta("selected_ids", selected)
		_refresh_multi_ref_text(menu_btn)
		_emit_changed()
	)
	clear_btn.pressed.connect(func():
		for i in popup.item_count:
			popup.set_item_checked(i, false)
		menu_btn.set_meta("selected_ids", [])
		root.set_meta("selected_ids", [])
		_refresh_multi_ref_text(menu_btn)
		_emit_changed()
	)
	return root


func _collect_checked_ids(popup: PopupMenu) -> Array:
	var result: Array = []
	for i in popup.item_count:
		if popup.is_item_checked(i):
			result.append(int(popup.get_item_id(i)))
	result.sort()
	return result


func _refresh_multi_ref_text(menu_btn: MenuButton) -> void:
	var ids: Array = menu_btn.get_meta("selected_ids", [])
	var popup := menu_btn.get_popup()
	if ids.is_empty():
		menu_btn.text = "未选择"
		return
	var labels: Array[String] = []
	for id_val in ids:
		var idx := popup.get_item_index(int(id_val))
		if idx >= 0:
			labels.append(popup.get_item_text(idx))
		else:
			labels.append(str(id_val))
	if labels.size() <= 2:
		menu_btn.text = ", ".join(labels)
		return
	menu_btn.text = "%s, %s 等%d项" % [labels[0], labels[1], labels.size()]


func _to_int_array(value: Variant) -> Array:
	var result: Array = []
	if typeof(value) != TYPE_ARRAY:
		return result
	for v in value:
		result.append(int(v))
	result.sort()
	return result


func _field_is_gameconfig_ref_array(field: Dictionary) -> bool:
	if not _is_array_field(field):
		return false
	return _array_element_extends_game_config(field)


func _array_element_extends_game_config(field: Dictionary) -> bool:
	var script_path := str(field.get("array_element_script_path", ""))
	if script_path == "":
		var cls := str(field.get("array_element_class_name", ""))
		if cls != "" and cls != "GameConfig":
			return true
		return cls == "GameConfig"
	if _extends_gameconfig_cache.has(script_path):
		return bool(_extends_gameconfig_cache[script_path])
	var script: Script = load(script_path) as Script
	if script == null:
		_extends_gameconfig_cache[script_path] = false
		return false
	var base: Script = script
	while base != null:
		if base == _GAME_CONFIG_SCRIPT or base.get_global_name() == "GameConfig":
			_extends_gameconfig_cache[script_path] = true
			return true
		base = base.get_base_script()
	_extends_gameconfig_cache[script_path] = false
	return false


func _create_gameconfig_multi_select_editor(field: Dictionary) -> Control:
	var root := HBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	root.set_meta("editor_kind", "gameconfig_multi")

	var button := MenuButton.new()
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.text = "选择..."
	root.add_child(button)

	var clear_btn := Button.new()
	clear_btn.text = "清空"
	root.add_child(clear_btn)

	var popup := button.get_popup()
	popup.hide_on_checkable_item_selection = false
	popup.hide_on_item_selection = false

	var target_table := _resolve_gameconfig_array_target_table(field)
	var rows: Dictionary = _all_tables.get(target_table, {})
	var sorted_keys: Array = rows.keys()
	sorted_keys.sort_custom(func(a, b): return int(a) < int(b))
	var selected_ids := _normalize_id_array(_row.get(field.name, []))
	for key in sorted_keys:
		var row: Dictionary = rows[key]
		var id_val := int(row.get("id", int(key)))
		var label := str(id_val)
		if row.has("name"):
			label = "%d - %s" % [id_val, str(row["name"])]
		elif row.has("title"):
			label = "%d - %s" % [id_val, str(row["title"])]
		popup.add_check_item(label, id_val)
		var idx := popup.item_count - 1
		popup.set_item_checked(idx, selected_ids.has(id_val))

	root.set_meta("selected_ids", selected_ids)
	root.set_meta("popup", popup)
	_update_multi_select_button_text(root)

	popup.id_pressed.connect(func(id: int):
		var idx := popup.get_item_index(id)
		if idx < 0:
			return
		popup.set_item_checked(idx, not popup.is_item_checked(idx))
		_sync_selected_ids_from_popup(root)
		_update_multi_select_button_text(root)
		_emit_changed()
	)
	clear_btn.pressed.connect(func():
		for i in popup.item_count:
			popup.set_item_checked(i, false)
		root.set_meta("selected_ids", [])
		_update_multi_select_button_text(root)
		_emit_changed()
	)

	return root


func _resolve_gameconfig_array_target_table(field: Dictionary) -> String:
	var ref: Dictionary = field.get("config_ref", {})
	if not ref.is_empty():
		return str(ref.get("target", ""))
	var cls := str(field.get("array_element_class_name", ""))
	if cls != "" and cls != "GameConfig":
		return cls
	var path := str(field.get("array_element_script_path", ""))
	if path != "":
		var script: Script = load(path) as Script
		if script != null and script.get_global_name() != "" and script.get_global_name() != "GameConfig":
			return script.get_global_name()
	return ""


func _normalize_id_array(raw: Variant) -> Array:
	var result: Array = []
	if typeof(raw) != TYPE_ARRAY:
		return result
	for v in raw:
		result.append(int(v))
	return result


func _sync_selected_ids_from_popup(root: Control) -> void:
	var popup: PopupMenu = root.get_meta("popup", null)
	if popup == null:
		root.set_meta("selected_ids", [])
		return
	var ids: Array = []
	for i in popup.item_count:
		if popup.is_item_checked(i):
			ids.append(int(popup.get_item_id(i)))
	root.set_meta("selected_ids", ids)


func _update_multi_select_button_text(root: Control) -> void:
	if root.get_child_count() == 0:
		return
	var btn := root.get_child(0) as MenuButton
	if btn == null:
		return
	var ids: Array = root.get_meta("selected_ids", [])
	if ids.is_empty():
		btn.text = "未选择"
	else:
		btn.text = "已选择 %d 项" % ids.size()


func _create_resource_array_editor(field: Dictionary) -> Control:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)

	var title := Label.new()
	title.text = "数组元素"
	root.add_child(title)

	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 8)
	var add_btn := Button.new()
	add_btn.text = "添加元素"
	var del_btn := Button.new()
	del_btn.text = "删除元素"
	toolbar.add_child(add_btn)
	toolbar.add_child(del_btn)
	root.add_child(toolbar)

	var list := ItemList.new()
	list.custom_minimum_size = Vector2(0, 120)
	root.add_child(list)

	var detail := VBoxContainer.new()
	detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail.add_theme_constant_override("separation", 6)
	root.add_child(detail)

	var items := _normalize_resource_array_items(field, _row.get(field.name, []))
	root.set_meta("items", items)
	root.set_meta("list", list)
	root.set_meta("detail", detail)
	root.set_meta("field", field)
	root.set_meta("active_index", -1)
	root.set_meta("active_form", null)

	_array_rebuild_list(root)

	list.item_selected.connect(func(index: int):
		_array_select_item(root, index)
	)
	add_btn.pressed.connect(func():
		_array_commit_active_form(root)
		var arr: Array = root.get_meta("items", [])
		arr.append(_create_default_resource_item(field))
		root.set_meta("items", arr)
		_array_rebuild_list(root)
		if list.item_count > 0:
			list.select(list.item_count - 1)
			_array_select_item(root, list.item_count - 1)
		_emit_changed()
	)
	del_btn.pressed.connect(func():
		_array_commit_active_form(root)
		var idx := list.get_selected_items()[0] if list.get_selected_items().size() > 0 else -1
		if idx < 0:
			return
		var arr: Array = root.get_meta("items", [])
		if idx >= 0 and idx < arr.size():
			arr.remove_at(idx)
		root.set_meta("items", arr)
		_array_rebuild_list(root)
		if list.item_count > 0:
			var next_idx := mini(idx, list.item_count - 1)
			list.select(next_idx)
			_array_select_item(root, next_idx)
		else:
			_array_clear_detail(root, "暂无元素。")
		_emit_changed()
	)

	if list.item_count > 0:
		list.select(0)
		_array_select_item(root, 0)
	else:
		_array_clear_detail(root, "暂无元素。点击“添加元素”创建。")

	return root


func _array_rebuild_list(root: VBoxContainer) -> void:
	var list: ItemList = root.get_meta("list", null)
	if list == null:
		return
	list.clear()
	var arr: Array = root.get_meta("items", [])
	for i in arr.size():
		var item = arr[i]
		var text := _array_item_preview_text(root, item, i)
		list.add_item(text)


func _array_clear_detail(root: VBoxContainer, message: String) -> void:
	var detail: VBoxContainer = root.get_meta("detail", null)
	if detail == null:
		return
	for child in detail.get_children():
		child.queue_free()
	var label := Label.new()
	label.text = message
	label.modulate = Color(0.55, 0.55, 0.55)
	detail.add_child(label)
	root.set_meta("active_form", null)
	root.set_meta("active_index", -1)


func _array_select_item(root: VBoxContainer, index: int) -> void:
	_array_commit_active_form(root)
	var arr: Array = root.get_meta("items", [])
	if index < 0 or index >= arr.size():
		_array_clear_detail(root, "未选择元素。")
		return
	var item = arr[index]
	var row_dict: Dictionary = item if typeof(item) == TYPE_DICTIONARY else {}
	var field: Dictionary = root.get_meta("field", {})
	var nested_info := _build_nested_type_info(field)
	if nested_info == null:
		_array_clear_detail(root, "无法解析数组元素类型。")
		return

	var detail: VBoxContainer = root.get_meta("detail", null)
	for child in detail.get_children():
		child.queue_free()

	var nested_form := ObjectFormEditor.new()
	nested_form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nested_form.bind(nested_info, row_dict, _registry, _store, _all_tables, false)
	nested_form.changed.connect(func():
		var cur_arr: Array = root.get_meta("items", [])
		if index >= 0 and index < cur_arr.size():
			cur_arr[index] = nested_form.read_row()
			root.set_meta("items", cur_arr)
		_emit_changed()
	)
	detail.add_child(nested_form)
	root.set_meta("active_form", nested_form)
	root.set_meta("active_index", index)


func _array_commit_active_form(root: VBoxContainer) -> void:
	if root == null:
		return
	if not root.has_meta("active_form") or not root.has_meta("active_index") or not root.has_meta("items"):
		return
	var form = root.get_meta("active_form")
	var idx := int(root.get_meta("active_index"))
	if form is ObjectFormEditor and idx >= 0:
		var arr: Array = root.get_meta("items", [])
		if idx < arr.size():
			arr[idx] = (form as ObjectFormEditor).read_row()
			root.set_meta("items", arr)


func _normalize_resource_array_items(field: Dictionary, raw_value: Variant) -> Array:
	if typeof(raw_value) != TYPE_ARRAY:
		return []
	var result: Array = []
	var src: Array = raw_value
	for item in src:
		if typeof(item) == TYPE_DICTIONARY:
			result.append((item as Dictionary).duplicate(true))
			continue
		if item is GameConfig:
			result.append((item as GameConfig).to_row_dict())
			continue
		result.append({})
	return result


func _create_default_resource_item(field: Dictionary) -> Dictionary:
	var nested_info := _build_nested_type_info(field)
	if nested_info == null or nested_info.config_script == null:
		return {}
	return GameConfig.make_default_row(nested_info.config_script)


func _build_nested_type_info(field: Dictionary) -> ConfigTypeInfo:
	var script_path := str(field.get("array_element_script_path", ""))
	if script_path == "":
		script_path = _resolve_script_path_from_global_class(str(field.get("array_element_class_name", "")))
	if script_path == "":
		return null
	if _nested_type_cache.has(script_path):
		return _nested_type_cache[script_path]

	var script: Script = load(script_path) as Script
	if script == null:
		return null
	var source := FileAccess.get_file_as_string(script_path)
	var class_ann := ConfigAnnotationParser.parse_class_annotations(source)
	var info := ConfigTypeInfo.new()
	info.class_name_id = script.get_global_name() if script.get_global_name() != "" else script_path.get_file().trim_suffix(".gd")
	info.script_path = script_path
	info.config_script = script
	info.tab_category = class_ann.tab_category
	info.tab_order = class_ann.tab_order
	info.display_name = class_ann.display_name
	info.default_open_tab = false
	info.default_open_priority = 9999

	var inst = script.new()
	var nested_fields: Array[Dictionary] = []
	if inst != null:
		for prop in inst.get_property_list():
			if not (prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and prop.usage & PROPERTY_USAGE_STORAGE):
				continue
			if str(prop.name).begins_with("_"):
				continue
			var default_value = prop.get("value", null)
			var array_element_script_path := ""
			var array_element_class_name := ""
			if typeof(default_value) == TYPE_ARRAY:
				var typed_array: Array = default_value
				var typed_script: Script = typed_array.get_typed_script()
				if typed_script != null:
					array_element_script_path = typed_script.resource_path
					array_element_class_name = typed_script.get_global_name()
				if array_element_class_name == "":
					array_element_class_name = str(typed_array.get_typed_class_name())
			var ann := ConfigAnnotationParser.parse_field_annotations(source, prop.name)
			nested_fields.append({
				"name": prop.name,
				"type": prop.type,
				"type_name": str(prop.get("class_name", "")),
				"hint": prop.hint,
				"hint_string": prop.hint_string,
				"display_name": ann.display_name,
				"config_ref": ann.config_ref,
				"default": default_value,
				"array_element_script_path": array_element_script_path,
				"array_element_class_name": array_element_class_name,
			})
	nested_fields.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var an := str(a.get("name", ""))
		var bn := str(b.get("name", ""))
		if an == "id" and bn != "id":
			return true
		if bn == "id" and an != "id":
			return false
		return false
	)
	info.fields = nested_fields
	_nested_type_cache[script_path] = info
	return info


func _array_item_preview_text(root: VBoxContainer, item: Variant, index: int) -> String:
	var fallback := "元素 %d" % index
	if typeof(item) != TYPE_DICTIONARY:
		return fallback
	var row_dict: Dictionary = item

	var field: Dictionary = root.get_meta("field", {})
	var nested_info := _build_nested_type_info(field)
	if nested_info != null:
		var ts := _try_game_struct_tostring(nested_info, row_dict)
		if ts != "":
			return "%d - %s" % [index, ts]

	if row_dict.has("name"):
		return "%d - %s" % [index, str(row_dict["name"])]
	if row_dict.has("title"):
		return "%d - %s" % [index, str(row_dict["title"])]
	if row_dict.has("id"):
		return "%d - #%d" % [index, int(row_dict["id"])]
	return fallback


func _try_game_struct_tostring(nested_info: ConfigTypeInfo, row_dict: Dictionary) -> String:
	if nested_info == null or nested_info.config_script == null:
		return ""
	if not _script_has_custom_tostring(nested_info.script_path):
		return ""
	var obj = _deserialize_for_preview(nested_info.config_script, row_dict)
	if obj == null:
		return ""
	var text := str(obj).strip_edges()
	return text


func _script_has_custom_tostring(script_path: String) -> bool:
	if script_path == "":
		return false
	if _has_custom_tostring_cache.has(script_path):
		return bool(_has_custom_tostring_cache[script_path])
	var source := FileAccess.get_file_as_string(script_path)
	var has_ts := source.find("func _to_string") >= 0
	_has_custom_tostring_cache[script_path] = has_ts
	return has_ts


func _deserialize_for_preview(script: Script, row_dict: Dictionary) -> Variant:
	if script == null:
		return null
	var obj = script.new()
	if obj == null:
		return null
	for p in obj.get_property_list():
		if not (p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and p.usage & PROPERTY_USAGE_STORAGE):
			continue
		var prop_name := str(p.name)
		if not row_dict.has(prop_name):
			continue
		obj.set(prop_name, row_dict[prop_name])
	return obj


func _resolve_script_path_from_global_class(class_name_id: String) -> String:
	if class_name_id == "":
		return ""
	for c in ProjectSettings.get_global_class_list():
		if str(c.get("class", "")) == class_name_id:
			return str(c.get("path", ""))
	return ""


func _read_editor(field_name: String, editor: Control) -> Variant:
	if field_name == "id":
		return int(_row.get("id", 0))
	var field := _type_info.find_field(field_name)
	if field.is_empty():
		return _row.get(field_name)
	if _is_array_field(field):
		if not field.config_ref.is_empty():
			if editor is MenuButton:
				return _to_int_array((editor as MenuButton).get_meta("selected_ids", []))
			if editor != null and editor.has_meta("selected_ids"):
				return _to_int_array(editor.get_meta("selected_ids", []))
		if _field_is_gameconfig_ref_array(field):
			return editor.get_meta("selected_ids", []) if editor else []
		if _field_is_resource_array(field) and editor is VBoxContainer and editor.has_meta("items"):
			_array_commit_active_form(editor as VBoxContainer)
			return (editor as VBoxContainer).get_meta("items", [])
		if editor is TextEdit:
			var parsed = JSON.parse_string((editor as TextEdit).text)
			return parsed if typeof(parsed) == TYPE_ARRAY else []
		return _row.get(field_name, [])
	if not field.config_ref.is_empty():
		var opt: OptionButton = editor as OptionButton
		if opt.selected <= 0:
			return 0
		return opt.get_item_metadata(opt.selected)
	match field.type:
		TYPE_BOOL:
			return (editor as CheckBox).button_pressed
		TYPE_INT:
			return int((editor as SpinBox).value)
		TYPE_FLOAT:
			return float((editor as SpinBox).value)
		TYPE_STRING:
			return (editor as LineEdit).text
		_:
			if field.hint == PROPERTY_HINT_ENUM:
				var opt_e: OptionButton = editor as OptionButton
				return opt_e.get_item_text(opt_e.selected)
			return (editor as LineEdit).text
