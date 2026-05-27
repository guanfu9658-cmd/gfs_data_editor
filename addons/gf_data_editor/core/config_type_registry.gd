class_name ConfigTypeRegistry
extends RefCounted

const _GAME_CONFIG_SCRIPT := preload("res://addons/gf_data_editor/runtime/game_config.gd")

var _types: Dictionary = {} # class_name -> ConfigTypeInfo


func scan(config_dir: String = GfPaths.CONFIG_DEFS_DIR) -> void:
	_types.clear()
	_ensure_game_config_loaded()

	var dir := DirAccess.open(config_dir)
	if dir == null:
		push_warning("ConfigTypeRegistry: cannot open %s" % config_dir)
		return

	for file_name in dir.get_files():
		if file_name.ends_with(".gd"):
			_register_script(config_dir.path_join(file_name))


func get_all() -> Array[ConfigTypeInfo]:
	var list: Array[ConfigTypeInfo] = []
	for k in _types.keys():
		list.append(_types[k])
	list.sort_custom(func(a: ConfigTypeInfo, b: ConfigTypeInfo) -> bool:
		return a.class_name_id < b.class_name_id
	)
	return list


func get_type(type_id: String) -> ConfigTypeInfo:
	return _types.get(type_id, null)


func get_by_categories() -> Array:
	var groups: Dictionary = {}
	for info: ConfigTypeInfo in get_all():
		var key := "%04d|%s" % [info.tab_order, info.tab_category]
		if not groups.has(key):
			groups[key] = {
				"order": info.tab_order,
				"name": info.tab_category,
				"types": [],
			}
		(groups[key].types as Array).append(info)
	var keys: Array = groups.keys()
	keys.sort()
	var result: Array = []
	for k in keys:
		var g: Dictionary = groups[k]
		var types: Array = g.types
		types.sort_custom(func(a: ConfigTypeInfo, b: ConfigTypeInfo) -> bool:
			return a.get_display_title() < b.get_display_title()
		)
		result.append(g)
	return result


func get_default_open_type() -> ConfigTypeInfo:
	var candidates: Array[ConfigTypeInfo] = []
	for info: ConfigTypeInfo in get_all():
		if info.default_open_tab:
			candidates.append(info)
	if candidates.is_empty():
		var all := get_all()
		return all[0] if all.size() > 0 else null
	candidates.sort_custom(func(a: ConfigTypeInfo, b: ConfigTypeInfo) -> bool:
		if a.default_open_priority != b.default_open_priority:
			return a.default_open_priority < b.default_open_priority
		return a.class_name_id < b.class_name_id
	)
	return candidates[0]


func _ensure_game_config_loaded() -> void:
	if ClassDB.class_exists(&"GameConfig"):
		return
	var _dummy = _GAME_CONFIG_SCRIPT


func _register_script(path: String) -> void:
	var script: Script = load(path) as Script
	if script == null:
		push_warning("ConfigTypeRegistry: failed to load %s" % path)
		return
	var global_name: String = script.get_global_name()
	if global_name == "":
		# 允许没有 class_name 的脚本；用文件名兜底，这样用户只管数据结构即可。
		global_name = _fallback_type_id_from_path(path)
	if not _extends_game_config(script):
		# data_configs 目录下允许存在 Array[Resource] 的元素定义等辅助脚本。
		# 只有继承 GameConfig 的脚本才作为“顶层可编辑表”注册。
		return
	var source := FileAccess.get_file_as_string(path)
	var class_ann := ConfigAnnotationParser.parse_class_annotations(source)
	var info := ConfigTypeInfo.new()
	info.class_name_id = global_name
	info.script_path = path
	info.config_script = script
	info.tab_category = class_ann.tab_category
	info.tab_order = class_ann.tab_order
	info.display_name = class_ann.display_name
	info.default_open_tab = class_ann.default_open_tab
	info.default_open_priority = class_ann.default_open_priority
	info.fields = _collect_fields(script, source)
	_types[global_name] = info


func _fallback_type_id_from_path(path: String) -> String:
	var file_name := path.get_file().trim_suffix(".gd")
	if file_name == "":
		return "UnnamedConfig"
	# 兜底名统一首字母大写，避免 UI 展示太奇怪。
	return file_name.left(1).to_upper() + file_name.substr(1)


func _extends_game_config(script: Script) -> bool:
	var base: Script = script.get_base_script()
	while base:
		if base.get_global_name() == &"GameConfig":
			return true
		if base == _GAME_CONFIG_SCRIPT:
			return true
		base = base.get_base_script()
	return false


func _collect_fields(script: Script, source: String) -> Array[Dictionary]:
	var fields: Array[Dictionary] = []
	var inst = script.new()
	if inst == null:
		return fields
	for prop in inst.get_property_list():
		if not (prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and prop.usage & PROPERTY_USAGE_STORAGE):
			continue
		if prop.name.begins_with("_"):
			continue
		var default_value = prop.get("value", null)
		var array_element_script_path := ""
		var array_element_class_name := ""
		var array_element_decl_name := ""
		var array_element_builtin_type := TYPE_NIL
		var is_array_field := int(prop.type) == TYPE_ARRAY or int(prop.hint) == PROPERTY_HINT_ARRAY_TYPE
		if is_array_field and typeof(default_value) == TYPE_ARRAY:
			var typed_array: Array = default_value
			var typed_script: Script = typed_array.get_typed_script()
			if typed_script != null:
				array_element_script_path = typed_script.resource_path
				array_element_class_name = typed_script.get_global_name()
			if array_element_class_name == "":
				array_element_class_name = str(typed_array.get_typed_class_name())
			array_element_builtin_type = int(typed_array.get_typed_builtin())
		if is_array_field and (array_element_script_path == "" and array_element_class_name != ""):
			array_element_script_path = _resolve_script_path_from_global_class(array_element_class_name)
		if is_array_field and (array_element_class_name == "" or array_element_script_path == ""):
			var inferred := _infer_array_element_from_hint(str(prop.get("hint_string", "")))
			if array_element_class_name == "":
				array_element_class_name = inferred.get("class_name", "")
			if array_element_script_path == "":
				array_element_script_path = inferred.get("script_path", "")
		# 源码声明优先：@export var xxx: Array[item_resource]
		# 运行时 typed_script 在某些情况下会错误指向当前脚本（如 item.gd）。
		if is_array_field:
			var inferred_src := _infer_array_element_from_source(source, str(prop.name))
			var src_class := str(inferred_src.get("class_name", ""))
			var src_path := str(inferred_src.get("script_path", ""))
			var src_decl := str(inferred_src.get("decl_name", ""))
			if src_class != "":
				array_element_class_name = src_class
			if src_path != "":
				array_element_script_path = src_path
			if src_decl != "":
				array_element_decl_name = src_decl
				if array_element_builtin_type == TYPE_NIL:
					array_element_builtin_type = _builtin_type_from_name(src_decl)
		var ann := ConfigAnnotationParser.parse_field_annotations(source, prop.name)
		fields.append({
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
			"array_element_decl_name": array_element_decl_name,
			"array_element_builtin_type": array_element_builtin_type,
		})
	# 统一把主键 id 放在第一位，其他字段维持原有顺序。
	fields.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var an := str(a.get("name", ""))
		var bn := str(b.get("name", ""))
		if an == "id" and bn != "id":
			return true
		if bn == "id" and an != "id":
			return false
		return false
	)
	return fields


func _resolve_script_path_from_global_class(class_name_id: String) -> String:
	if class_name_id == "":
		return ""
	for c in ProjectSettings.get_global_class_list():
		if str(c.get("class", "")) == class_name_id:
			return str(c.get("path", ""))
	return ""


func _infer_array_element_from_hint(hint_string: String) -> Dictionary:
	if hint_string == "":
		return {}
	for c in ProjectSettings.get_global_class_list():
		var class_name_id := str(c.get("class", ""))
		if class_name_id == "":
			continue
		if hint_string.find(class_name_id) >= 0:
			return {
				"class_name": class_name_id,
				"script_path": str(c.get("path", "")),
			}
	return {}


func _infer_array_element_from_source(source: String, field_name: String) -> Dictionary:
	if source == "" or field_name == "":
		return {}
	var lines := source.split("\n")
	var class_name_id := ""
	for raw_line in lines:
		var line := String(raw_line).strip_edges()
		if not line.begins_with("@export"):
			continue
		if line.find("var %s" % field_name) < 0:
			continue
		var arr_pos := line.find("Array[")
		if arr_pos < 0:
			continue
		var start := arr_pos + "Array[".length()
		var end := line.find("]", start)
		if end < 0:
			continue
		class_name_id = line.substr(start, end - start).strip_edges()
		break
	if class_name_id == "":
		return {}
	var builtin_type := _builtin_type_from_name(class_name_id)
	return {
		"class_name": class_name_id if builtin_type == TYPE_NIL else "",
		"script_path": _resolve_script_path_from_global_class(class_name_id),
		"decl_name": class_name_id,
		"builtin_type": builtin_type,
	}


func _builtin_type_from_name(type_name: String) -> int:
	match type_name.to_lower():
		"int":
			return TYPE_INT
		"float":
			return TYPE_FLOAT
		"bool":
			return TYPE_BOOL
		"string":
			return TYPE_STRING
		_:
			return TYPE_NIL
